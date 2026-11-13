CREATE TABLE users (
  id TEXT PRIMARY KEY,
  secret_hash TEXT NOT NULL,
  push_token TEXT,
  pair_id TEXT,
  created_at INTEGER NOT NULL
);
CREATE TABLE pair_codes (
  code TEXT PRIMARY KEY,
  owner_id TEXT NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE TABLE pairs (
  id TEXT PRIMARY KEY,
  user_a TEXT NOT NULL,
  user_b TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE TABLE notes (
  id TEXT PRIMARY KEY,
  pair_id TEXT NOT NULL,
  sender_id TEXT NOT NULL,
  text TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX notes_pair_time ON notes (pair_id, created_at DESC);
CREATE TABLE join_attempts (
  user_id TEXT NOT NULL,
  at INTEGER NOT NULL
);
CREATE INDEX join_attempts_user ON join_attempts (user_id, at);
