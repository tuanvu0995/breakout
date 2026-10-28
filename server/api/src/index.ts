// Brickstellar API (bs-api): guest accounts, per-level clear-time leaderboards, OTA patch hosting.
// Plain fetch handler, no framework. Same shape as drivedrive's dd-api, trimmed down.

export interface Env {
  DB: D1Database;
  STORE: R2Bucket;
  ADMIN_TOKEN?: string;
  ALLOWED_BUILD_MIN?: string;
  SESSION_TTL_DAYS?: string;
  RUNS_PER_HOUR?: string;
  STORE_PUBLIC_URL?: string;
}

const LEVEL_COUNT = 120;
const MIN_TIME_MS = 2_000;        // nobody clears a level faster than this
const FLAG_TIME_MS = 4_000;       // suspiciously fast: kept but hidden from boards
const CLOCK_SLACK_MS = 3_000;     // network + timer drift allowed vs. server clock
const NONCE_TTL_S = 2 * 60 * 60;  // a level attempt can last up to 2 hours
const OTA_FILE_RE = /^patch-\d+\.\d+\.\d+-(windows|macos|linux|android)\.pck$/;
const OTA_MAX_BYTES = 95 * 1024 * 1024;

// ---------------------------------------------------------------- helpers

class ApiError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "Authorization, Content-Type, X-Sha256",
  "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, OPTIONS",
};

const nowS = () => Math.floor(Date.now() / 1000);

function json(data: unknown, status = 200, extra: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...CORS, ...extra },
  });
}

async function body(req: Request, max = 16_000): Promise<Record<string, unknown>> {
  const text = await req.text();
  if (text.length > max) throw new ApiError(413, "TOO_BIG", "Body too large.");
  try {
    const data = JSON.parse(text);
    if (data && typeof data === "object" && !Array.isArray(data)) return data;
  } catch {}
  throw new ApiError(400, "BAD_JSON", "Body must be a JSON object.");
}

function int(v: unknown, name: string, min: number, max: number): number {
  if (typeof v !== "number" || !Number.isInteger(v) || v < min || v > max)
    throw new ApiError(400, "BAD_FIELD", `${name} must be an integer in [${min}, ${max}].`);
  return v;
}

function str(v: unknown, name: string, re: RegExp): string {
  if (typeof v !== "string" || !re.test(v)) throw new ApiError(400, "BAD_FIELD", `${name} is invalid.`);
  return v;
}

function randomHex(bytes: number): string {
  const b = crypto.getRandomValues(new Uint8Array(bytes));
  return [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
}

async function sha256Hex(data: string | ArrayBuffer): Promise<string> {
  const buf = typeof data === "string" ? new TextEncoder().encode(data) : data;
  const h = await crypto.subtle.digest("SHA-256", buf);
  return [...new Uint8Array(h)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

/** -1 / 0 / 1 for dotted numeric versions. */
function cmpVersion(a: string, b: string): number {
  const pa = a.split(".").map(Number), pb = b.split(".").map(Number);
  for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
    const d = (pa[i] ?? 0) - (pb[i] ?? 0);
    if (d) return Math.sign(d);
  }
  return 0;
}

/** Counts events per bucket in a sliding window; throws 429 when over. */
async function throttle(env: Env, bucket: string, windowS: number, limit: number) {
  const t = nowS();
  const row = await env.DB.prepare("SELECT COUNT(*) AS n FROM throttle_events WHERE bucket = ? AND at > ?")
    .bind(bucket, t - windowS).first<{ n: number }>();
  if ((row?.n ?? 0) >= limit) throw new ApiError(429, "RATE_LIMITED", "Too many requests, try later.");
  await env.DB.batch([
    env.DB.prepare("INSERT INTO throttle_events (bucket, at) VALUES (?, ?)").bind(bucket, t),
    env.DB.prepare("DELETE FROM throttle_events WHERE at < ?").bind(t - 86_400),
  ]);
}

const ip = (req: Request) => req.headers.get("CF-Connecting-IP") ?? "local";

interface Account { id: string; handle: string; banned: number }

async function auth(req: Request, env: Env, required = true): Promise<Account | null> {
  const h = req.headers.get("Authorization") ?? "";
  if (!h.startsWith("Bearer ")) {
    if (required) throw new ApiError(401, "NO_AUTH", "Missing bearer token.");
    return null;
  }
  const acc = await env.DB.prepare(
    `SELECT a.id, a.handle, a.banned FROM sessions s JOIN accounts a ON a.id = s.account_id
     WHERE s.token_hash = ? AND s.expires_at > ?`,
  ).bind(await sha256Hex(h.slice(7)), nowS()).first<Account>();
  if (!acc) {
    if (required) throw new ApiError(401, "BAD_TOKEN", "Session expired or unknown.");
    return null;
  }
  if (acc.banned) throw new ApiError(403, "BANNED", "Account banned.");
  return acc;
}

function requireAdmin(req: Request, env: Env) {
  if (!env.ADMIN_TOKEN || req.headers.get("Authorization") !== `Bearer ${env.ADMIN_TOKEN}`)
    throw new ApiError(401, "NOT_ADMIN", "Admin token required.");
}

// ---------------------------------------------------------------- handlers

const HANDLE_RE = /^[A-Za-z0-9_]{3,16}$/;

async function guest(req: Request, env: Env) {
  await throttle(env, `guest:${ip(req)}`, 3600, 10);
  const id = crypto.randomUUID();
  const handle = `Pilot${randomHex(3).toUpperCase()}`;
  const token = randomHex(32);
  const ttl = Number(env.SESSION_TTL_DAYS ?? "365") * 86_400;
  await env.DB.batch([
    env.DB.prepare("INSERT INTO accounts (id, handle, created_at) VALUES (?, ?, ?)").bind(id, handle, nowS()),
    env.DB.prepare("INSERT INTO sessions (token_hash, account_id, expires_at) VALUES (?, ?, ?)")
      .bind(await sha256Hex(token), id, nowS() + ttl),
  ]);
  return json({ token, account: { id, handle } }, 201);
}

async function patchMe(req: Request, env: Env) {
  const acc = (await auth(req, env))!;
  const base = str((await body(req)).handle, "handle", HANDLE_RE);
  // Name taken by someone else: add the smallest free "#n" (Pilot, Pilot#2, Pilot#3...).
  const { results } = await env.DB.prepare(
    "SELECT handle FROM accounts WHERE (handle = ? OR handle LIKE ? ESCAPE '\\') AND id != ?",
  ).bind(base, base.replace(/_/g, "\\_") + "#%", acc.id).all<{ handle: string }>();
  const taken = new Set(results.map((r) => r.handle.toLowerCase()));
  let handle = base;
  for (let n = 2; taken.has(handle.toLowerCase()); n++) handle = `${base}#${n}`;
  try {
    await env.DB.prepare("UPDATE accounts SET handle = ? WHERE id = ?").bind(handle, acc.id).run();
  } catch {
    throw new ApiError(409, "HANDLE_TAKEN", "That name is taken.");
  }
  return json({ account: { id: acc.id, handle } });
}

async function runStart(req: Request, env: Env) {
  const acc = (await auth(req, env))!;
  const level = int((await body(req)).level, "level", 1, LEVEL_COUNT);
  const nonce = randomHex(16);
  const expires = nowS() + NONCE_TTL_S;
  await env.DB.prepare("INSERT INTO nonces (nonce, account_id, level, issued_at_ms, expires_at) VALUES (?, ?, ?, ?, ?)")
    .bind(nonce, acc.id, level, Date.now(), expires).run();
  return json({ nonce, expires_at: expires });
}

async function runSubmit(req: Request, env: Env) {
  const acc = (await auth(req, env))!;
  const b = await body(req);
  const runId = str(b.client_run_id, "client_run_id", /^[A-Za-z0-9-]{8,64}$/);
  const nonce = str(b.nonce, "nonce", /^[0-9a-f]{32}$/);
  const level = int(b.level, "level", 1, LEVEL_COUNT);
  const timeMs = int(b.time_ms, "time_ms", MIN_TIME_MS, NONCE_TTL_S * 1000);
  const score = int(b.score, "score", 0, 1_000_000_000);
  const skin = typeof b.skin === "string" ? b.skin.slice(0, 24) : null;
  const build = str(b.build_version ?? "0.0.0", "build_version", /^\d+\.\d+\.\d+$/);
  if (cmpVersion(build, env.ALLOWED_BUILD_MIN ?? "0.0.0") < 0)
    throw new ApiError(426, "OLD_BUILD", "Please update the game.");

  // Retry of a run we already stored: answer the same way.
  const prev = await env.DB.prepare("SELECT status FROM runs WHERE id = ? AND account_id = ?")
    .bind(runId, acc.id).first<{ status: string }>();
  if (prev) return json({ run_id: runId, status: prev.status, ...(await myRank(env, level, acc.id)) });

  await throttle(env, `runs:${acc.id}`, 3600, Number(env.RUNS_PER_HOUR ?? "120"));

  // Claim the nonce atomically: one submission per level start.
  const claimed = await env.DB.prepare(
    `UPDATE nonces SET used_at = ? WHERE nonce = ? AND account_id = ? AND level = ?
     AND used_at IS NULL AND expires_at > ? RETURNING issued_at_ms`,
  ).bind(nowS(), nonce, acc.id, level, nowS()).first<{ issued_at_ms: number }>();
  if (!claimed) throw new ApiError(409, "BAD_NONCE", "Unknown, used or expired nonce.");

  // The claimed time can't exceed the real time since the level started.
  const elapsed = Date.now() - claimed.issued_at_ms;
  if (timeMs > elapsed + CLOCK_SLACK_MS)
    throw new ApiError(422, "IMPOSSIBLE_TIME", "Time is longer than the attempt itself.");
  const flagged = timeMs < FLAG_TIME_MS;
  const status = flagged ? "flagged" : "verified";

  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO runs (id, account_id, level, time_ms, score, skin, build_version, status, reason, received_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
    ).bind(runId, acc.id, level, timeMs, score, skin, build, status, flagged ? "too_fast" : null, nowS()),
    env.DB.prepare(
      `INSERT INTO best (level, account_id, run_id, time_ms, score, flagged, achieved_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT (level, account_id) DO UPDATE SET
         run_id = excluded.run_id, time_ms = excluded.time_ms, score = excluded.score,
         flagged = excluded.flagged, achieved_at = excluded.achieved_at
       WHERE excluded.flagged <= best.flagged AND (excluded.time_ms < best.time_ms OR best.flagged > excluded.flagged)`,
    ).bind(level, acc.id, runId, timeMs, score, flagged ? 1 : 0, nowS()),
  ]);
  return json({ run_id: runId, status, ...(await myRank(env, level, acc.id)) }, 201);
}

const PERIODS: Record<string, number> = { all: 0, week: 7 * 86_400, day: 86_400 };

/** Ranked view of one level's board (ties broken by who got there first). */
function rankedSql(sinceClause: string) {
  return `SELECT b.account_id, a.handle, b.time_ms, b.score, b.achieved_at,
            RANK() OVER (ORDER BY b.time_ms ASC, b.achieved_at ASC) AS rank
          FROM best b JOIN accounts a ON a.id = b.account_id
          WHERE b.level = ? AND b.flagged = 0 AND a.banned = 0 ${sinceClause}`;
}

async function myRank(env: Env, level: number, accountId: string, since = 0) {
  const me = await env.DB.prepare(
    `SELECT time_ms, rank FROM (${rankedSql("AND b.achieved_at >= ?")}) WHERE account_id = ?`,
  ).bind(level, since, accountId).first<{ time_ms: number; rank: number }>();
  return { best_time_ms: me?.time_ms ?? null, rank: me?.rank ?? null };
}

// GET /v1/boards/:level?limit=&offset=&period=all|week|day&q=<name part>
// Ranks stay global (within the period) even when filtered by name.
async function board(req: Request, env: Env, levelStr: string, url: URL) {
  const level = int(Number(levelStr), "level", 1, LEVEL_COUNT);
  const limit = Math.min(Math.max(Number(url.searchParams.get("limit") ?? "20") | 0, 1), 100);
  const offset = Math.max(Number(url.searchParams.get("offset") ?? "0") | 0, 0);
  const period = url.searchParams.get("period") ?? "all";
  if (!(period in PERIODS)) throw new ApiError(400, "BAD_FIELD", "period must be all, week or day.");
  const since = PERIODS[period] ? nowS() - PERIODS[period] : 0;
  const q = (url.searchParams.get("q") ?? "").trim().slice(0, 16);
  const like = "%" + q.replace(/[\\%_]/g, (c) => "\\" + c) + "%";
  const ranked = rankedSql("AND b.achieved_at >= ?");
  const where = q ? "WHERE handle LIKE ? ESCAPE '\\'" : "";
  const args = q ? [level, since, like] : [level, since];
  const rows = await env.DB.prepare(
    `SELECT rank, handle, time_ms, score, achieved_at FROM (${ranked}) ${where} ORDER BY rank ASC LIMIT ? OFFSET ?`,
  ).bind(...args, limit, offset).all<{ rank: number; handle: string; time_ms: number; score: number; achieved_at: number }>();
  const total = await env.DB.prepare(`SELECT COUNT(*) AS n FROM (${ranked}) ${where}`)
    .bind(...args).first<{ n: number }>();
  const acc = await auth(req, env, false);
  return json(
    {
      level, period, q,
      total: total?.n ?? 0,
      offset,
      entries: rows.results,
      me: acc ? { handle: acc.handle, ...(await myRank(env, level, acc.id, since)) } : null,
    },
    200,
    { "Cache-Control": acc ? "private, no-store" : "public, max-age=15" },
  );
}

// ---------------------------------------------------------------- OTA

async function otaManifest(env: Env, url: URL) {
  const obj = await env.STORE.get("ota/manifest.json");
  if (!obj) return json({ patch: null }, 200, { "Cache-Control": "max-age=60" });
  const m = (await obj.json()) as { patch?: { patch_version: string; sha256: Record<string, string>; urls?: Record<string, string> } };
  if (m.patch && m.patch.patch_version && m.patch.sha256) {
    const base = env.STORE_PUBLIC_URL ? `${env.STORE_PUBLIC_URL}/ota` : `${url.origin}/v1/ota/files`;
    m.patch.urls = Object.fromEntries(
      Object.keys(m.patch.sha256).map((p) => [p, `${base}/patch-${m.patch!.patch_version}-${p}.pck`]),
    );
  }
  return json(m, 200, { "Cache-Control": "max-age=60" });
}

async function otaFile(env: Env, name: string) {
  if (!OTA_FILE_RE.test(name)) throw new ApiError(404, "NOT_FOUND", "No such file.");
  const obj = await env.STORE.get(`ota/${name}`);
  if (!obj) throw new ApiError(404, "NOT_FOUND", "No such file.");
  return new Response(obj.body, {
    headers: { "Content-Type": "application/octet-stream", "Cache-Control": "public, max-age=31536000, immutable", ...CORS },
  });
}

async function adminPutFile(req: Request, env: Env, name: string) {
  const data = await req.arrayBuffer(); // read fully before replying (avoids broken uploads)
  requireAdmin(req, env);
  if (!OTA_FILE_RE.test(name)) throw new ApiError(400, "BAD_NAME", "Expected patch-<x.y.z>-<platform>.pck");
  if (data.byteLength > OTA_MAX_BYTES) throw new ApiError(413, "TOO_BIG", "Patch too large.");
  const sha = await sha256Hex(data);
  const want = req.headers.get("X-Sha256")?.toLowerCase();
  if (want && want !== sha) throw new ApiError(400, "SHA_MISMATCH", "Upload corrupted.");
  await env.STORE.put(`ota/${name}`, data, { customMetadata: { sha256: sha } });
  return json({ name, sha256: sha, bytes: data.byteLength }, 201);
}

async function adminPutManifest(req: Request, env: Env) {
  const m = await body(req, 64_000);
  requireAdmin(req, env);
  const patch = m.patch as { patch_version?: string; base_version?: string; sha256?: Record<string, string> } | null;
  if (patch && Object.keys(patch).length > 0) {
    str(patch.patch_version, "patch.patch_version", /^\d+\.\d+\.\d+$/);
    str(patch.base_version, "patch.base_version", /^\d+\.\d+\.\d+$/);
    for (const [plat, sha] of Object.entries(patch.sha256 ?? {})) {
      const head = await env.STORE.head(`ota/patch-${patch.patch_version}-${plat}.pck`);
      if (head?.customMetadata?.sha256 !== sha)
        throw new ApiError(409, "FILE_MISSING", `Upload patch-${patch.patch_version}-${plat}.pck first.`);
    }
  }
  await env.STORE.put("ota/manifest.json", JSON.stringify(m), { httpMetadata: { contentType: "application/json" } });
  return json({ ok: true });
}

async function adminBan(req: Request, env: Env, id: string) {
  requireAdmin(req, env);
  await env.DB.prepare("UPDATE accounts SET banned = 1 WHERE id = ?").bind(id).run();
  return json({ ok: true });
}

// ---------------------------------------------------------------- router

type Route = [method: string, pattern: RegExp, fn: (req: Request, env: Env, m: RegExpMatchArray, url: URL) => Promise<Response>];

const ROUTES: Route[] = [
  ["GET", /^\/v1\/health$/, async () => json({ ok: true, service: "bs-api", api: "1" })],
  ["POST", /^\/v1\/auth\/guest$/, (r, e) => guest(r, e)],
  ["GET", /^\/v1\/me$/, async (r, e) => json({ account: await auth(r, e) })],
  ["PATCH", /^\/v1\/me$/, (r, e) => patchMe(r, e)],
  ["POST", /^\/v1\/runs\/start$/, (r, e) => runStart(r, e)],
  ["POST", /^\/v1\/runs$/, (r, e) => runSubmit(r, e)],
  ["GET", /^\/v1\/boards\/(\d+)$/, (r, e, m, u) => board(r, e, m[1], u)],
  ["GET", /^\/v1\/ota\/manifest$/, (_r, e, _m, u) => otaManifest(e, u)],
  ["GET", /^\/v1\/ota\/files\/([^/]+)$/, (_r, e, m) => otaFile(e, m[1])],
  ["PUT", /^\/v1\/admin\/ota\/files\/([^/]+)$/, (r, e, m) => adminPutFile(r, e, m[1])],
  ["PUT", /^\/v1\/admin\/ota\/manifest$/, (r, e) => adminPutManifest(r, e)],
  ["POST", /^\/v1\/admin\/accounts\/([^/]+)\/ban$/, (r, e, m) => adminBan(r, e, m[1])],
];

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: CORS });
    const url = new URL(req.url);
    try {
      let pathMatched = false;
      for (const [method, re, fn] of ROUTES) {
        const m = url.pathname.match(re);
        if (!m) continue;
        pathMatched = true;
        if (method === req.method) return await fn(req, env, m, url);
      }
      throw pathMatched ? new ApiError(405, "METHOD", "Method not allowed.") : new ApiError(404, "NOT_FOUND", "No such route.");
    } catch (e) {
      if (e instanceof ApiError) return json({ error: { code: e.code, message: e.message } }, e.status);
      console.error(e);
      return json({ error: { code: "INTERNAL", message: "Server error." } }, 500);
    }
  },
};
