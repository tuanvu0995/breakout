CREATE TABLE accounts (
  id TEXT PRIMARY KEY,
  handle TEXT NOT NULL UNIQUE COLLATE NOCASE,
  banned INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL
);

CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY,
  account_id TEXT NOT NULL REFERENCES accounts(id),
  expires_at INTEGER NOT NULL
);

CREATE TABLE throttle_events (
  bucket TEXT NOT NULL,
  at INTEGER NOT NULL
);
CREATE INDEX throttle_bucket_at ON throttle_events(bucket, at);

-- One-use ticket issued when a level starts; the server clock bounds the claimed time.
CREATE TABLE nonces (
  nonce TEXT PRIMARY KEY,
  account_id TEXT NOT NULL,
  level INTEGER NOT NULL,
  issued_at_ms INTEGER NOT NULL,
  expires_at INTEGER NOT NULL,
  used_at INTEGER
);

CREATE TABLE runs (
  id TEXT PRIMARY KEY,               -- client_run_id (idempotent retries)
  account_id TEXT NOT NULL,
  level INTEGER NOT NULL,
  time_ms INTEGER NOT NULL,
  score INTEGER NOT NULL,
  skin TEXT,
  build_version TEXT,
  status TEXT NOT NULL,              -- verified | flagged
  reason TEXT,
  received_at INTEGER NOT NULL
);
CREATE INDEX runs_account ON runs(account_id, received_at);

-- Leaderboard: each player's best (lowest) clear time per level.
CREATE TABLE best (
  level INTEGER NOT NULL,
  account_id TEXT NOT NULL,
  run_id TEXT NOT NULL,
  time_ms INTEGER NOT NULL,
  score INTEGER NOT NULL,
  flagged INTEGER NOT NULL DEFAULT 0,
  achieved_at INTEGER NOT NULL,
  PRIMARY KEY (level, account_id)
);
CREATE INDEX best_board ON best(level, flagged, time_ms);
