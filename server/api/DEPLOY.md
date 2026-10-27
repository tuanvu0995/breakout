# breakout-api: deploy

Cloudflare Worker + D1 (accounts, leaderboards) + R2 (OTA patches).
Same setup as drivedrive's `dd-api`.

## First deploy

```bash
cd server/api
npm install
npx wrangler login
npx wrangler d1 create breakout-db          # copy the database_id into wrangler.jsonc
npx wrangler r2 bucket create breakout-store
openssl rand -hex 32                        # keep it: this is ADMIN_TOKEN
npx wrangler secret put ADMIN_TOKEN
npm run migrate:remote
npm run deploy
curl https://breakout-api.<your-subdomain>.workers.dev/v1/health
```

Then set the URL in the game, `project.godot`:

```ini
[breakout]
api_url="https://breakout-api.<your-subdomain>.workers.dev/v1"
```

Empty `api_url` = the game runs fully offline (no leaderboard, no OTA).

Optional: a custom domain (add `routes` in `wrangler.jsonc`), and a public R2 domain
for patch downloads (set `STORE_PUBLIC_URL`, e.g. `https://breakout-store.example.com`).

## Local dev

```bash
echo "ADMIN_TOKEN=dev-admin" > .dev.vars
npm run migrate:local
npm run dev            # http://localhost:8787/v1
```

## API

| Method | Path | Notes |
|---|---|---|
| GET | `/v1/health` | |
| POST | `/v1/auth/guest` | `{token, account}`; 10 per IP per hour |
| GET / PATCH | `/v1/me` | PATCH `{handle}`: 3-16 chars `A-Z a-z 0-9 _` |
| POST | `/v1/runs/start` | `{level}` -> `{nonce}` (one use, 2 h) |
| POST | `/v1/runs` | `{client_run_id, nonce, level, time_ms, score, skin, build_version}` |
| GET | `/v1/boards/:level` | `limit, offset, period=all\|week\|day, q=<name part>`; ranks stay global |
| GET | `/v1/ota/manifest` | |
| GET | `/v1/ota/files/:name` | |
| PUT | `/v1/admin/ota/files/:name` | Bearer ADMIN_TOKEN, `X-Sha256` |
| PUT | `/v1/admin/ota/manifest` | refused until each named file is uploaded |
| POST | `/v1/admin/accounts/:id/ban` | |

Anti-cheat: a run needs a nonce from `runs/start`; the claimed time can't exceed the
real time since that nonce was issued; times under 4 s are stored as `flagged` and hidden.
Ceiling: a client can still under-report its time inside that window. Add input replays
(like drivedrive) if cheating shows up.

## OTA patches

Patches are Godot patch PCKs against the shipped build (`tools/build_patch.sh`).

```bash
# once, on the exact commit you released:
PLATFORMS="macos web android" tools/build_patch.sh snapshot

# later, for a content/script fix (config/version stays the same):
API=https://.../v1 ADMIN_TOKEN=... PLATFORMS="macos web android" tools/build_patch.sh 0.1.1 --upload

# pull a bad patch / announce a new store build
tools/build_patch.sh revoke 0.1.1
FULL_DOWNLOAD_URL=https://... tools/build_patch.sh announce --upload
```

The game checks for a patch on the main menu, downloads it, verifies its SHA-256 and
applies it on the next launch (web: page reload).
A patch can't change the engine version or native code - that needs a new full build.
iOS: App Store rules forbid downloading new code; don't ship OTA patches to iOS.
