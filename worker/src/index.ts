import { sendApns, type PushEnv, type PushSender } from "./apns";

export interface Env extends PushEnv { DB: D1Database }

const MAX_NOTE = 100;
const CODE_TTL_MS = 10 * 60 * 1000;
const MAX_FAILED_JOINS = 5;
const JOIN_WINDOW_MS = 60 * 60 * 1000;

const json = (data: unknown, status = 200) => Response.json(data, { status });
const err = (status: number, message: string) => json({ error: message }, status);

const hex = (buf: ArrayBuffer | Uint8Array) => [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
const sha256 = async (s: string) => hex(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)));
const randomHex = (bytes: number) => hex(crypto.getRandomValues(new Uint8Array(bytes)));
const randomCode = () => String(crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000).padStart(6, "0");

function timingSafeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

interface User { id: string; push_token: string | null; pair_id: string | null }

async function authenticate(req: Request, env: Env): Promise<User | null> {
  const m = /^Bearer ([0-9a-f]{32})\.([0-9a-f]{64})$/.exec(req.headers.get("authorization") ?? "");
  if (!m) return null;
  const row = await env.DB.prepare("SELECT id, secret_hash, push_token, pair_id FROM users WHERE id = ?")
    .bind(m[1]).first<User & { secret_hash: string }>();
  if (!row || !timingSafeEqual(row.secret_hash, await sha256(m[2]))) return null;
  return { id: row.id, push_token: row.push_token, pair_id: row.pair_id };
}

async function readJson(req: Request): Promise<Record<string, unknown>> {
  try { const v = await req.json(); return v && typeof v === "object" ? (v as Record<string, unknown>) : {}; }
  catch { return {}; }
}

async function partnerOf(env: Env, user: User) {
  if (!user.pair_id) return null;
  const pair = await env.DB.prepare("SELECT user_a, user_b FROM pairs WHERE id = ?").bind(user.pair_id).first<{ user_a: string; user_b: string }>();
  if (!pair) return null;
  return pair.user_a === user.id ? pair.user_b : pair.user_a;
}

async function dissolvePair(env: Env, pairId: string) {
  await env.DB.batch([
    env.DB.prepare("UPDATE users SET pair_id = NULL WHERE pair_id = ?").bind(pairId),
    env.DB.prepare("DELETE FROM notes WHERE pair_id = ?").bind(pairId),
    env.DB.prepare("DELETE FROM pairs WHERE id = ?").bind(pairId),
  ]);
}

export async function handle(req: Request, env: Env, ctx: Pick<ExecutionContext, "waitUntil">, push: PushSender = sendApns): Promise<Response> {
  const { pathname, searchParams } = new URL(req.url);
  const route = `${req.method} ${pathname}`;

  if (route === "POST /register") {
    const id = randomHex(16), secret = randomHex(32);
    await env.DB.prepare("INSERT INTO users (id, secret_hash, created_at) VALUES (?, ?, ?)")
      .bind(id, await sha256(secret), Date.now()).run();
    return json({ userId: id, secret }, 201);
  }

  const user = await authenticate(req, env);
  if (!user) return err(401, "unauthorized");

  switch (route) {
    case "GET /me":
      return json({ userId: user.id, paired: !!user.pair_id });

    case "PUT /me/push-token": {
      const token = (await readJson(req)).token;
      if (typeof token !== "string" || !/^[0-9a-fA-F]{32,200}$/.test(token)) return err(400, "invalid token");
      await env.DB.prepare("UPDATE users SET push_token = ? WHERE id = ?").bind(token, user.id).run();
      return json({ ok: true });
    }

    case "POST /pair/code": {
      if (user.pair_id) return err(409, "already paired");
      await env.DB.prepare("DELETE FROM pair_codes WHERE owner_id = ? OR expires_at < ?").bind(user.id, Date.now()).run();
      for (let i = 0; i < 5; i++) {
        const code = randomCode(), expiresAt = Date.now() + CODE_TTL_MS;
        const r = await env.DB.prepare("INSERT OR IGNORE INTO pair_codes (code, owner_id, expires_at) VALUES (?, ?, ?)")
          .bind(code, user.id, expiresAt).run();
        if (r.meta.changes === 1) return json({ code, expiresAt }, 201);
      }
      return err(503, "try again");
    }

    case "POST /pair/join": {
      if (user.pair_id) return err(409, "already paired");
      const code = (await readJson(req)).code;
      if (typeof code !== "string" || !/^\d{6}$/.test(code)) return err(400, "invalid code");
      const now = Date.now();
      const failed = await env.DB.prepare("SELECT COUNT(*) AS n FROM join_attempts WHERE user_id = ? AND at > ?")
        .bind(user.id, now - JOIN_WINDOW_MS).first<{ n: number }>();
      if ((failed?.n ?? 0) >= MAX_FAILED_JOINS) return err(429, "too many attempts, try later");

      const row = await env.DB.prepare("SELECT owner_id FROM pair_codes WHERE code = ? AND expires_at > ?")
        .bind(code, now).first<{ owner_id: string }>();
      const owner = row && row.owner_id !== user.id
        ? await env.DB.prepare("SELECT id, pair_id FROM users WHERE id = ?").bind(row.owner_id).first<{ id: string; pair_id: string | null }>()
        : null;
      if (!owner || owner.pair_id) {
        await env.DB.prepare("INSERT INTO join_attempts (user_id, at) VALUES (?, ?)").bind(user.id, now).run();
        return err(404, "code not found or expired");
      }
      const pairId = randomHex(16);
      await env.DB.batch([
        env.DB.prepare("INSERT INTO pairs (id, user_a, user_b, created_at) VALUES (?, ?, ?, ?)").bind(pairId, owner.id, user.id, now),
        env.DB.prepare("UPDATE users SET pair_id = ? WHERE id IN (?, ?)").bind(pairId, owner.id, user.id),
        env.DB.prepare("DELETE FROM pair_codes WHERE owner_id = ?").bind(owner.id),
        env.DB.prepare("DELETE FROM join_attempts WHERE user_id = ?").bind(user.id),
      ]);
      return json({ paired: true }, 201);
    }

    case "DELETE /pair": {
      if (user.pair_id) await dissolvePair(env, user.pair_id);
      return json({ ok: true });
    }

    case "POST /notes": {
      const text = (await readJson(req)).text;
      if (typeof text !== "string") return err(400, "text required");
      const trimmed = text.trim();
      if (!trimmed || [...trimmed].length > MAX_NOTE) return err(400, `text must be 1-${MAX_NOTE} characters`);
      const partnerId = await partnerOf(env, user);
      if (!user.pair_id || !partnerId) return err(409, "not paired");

      const noteId = randomHex(16), createdAt = Date.now();
      await env.DB.prepare("INSERT INTO notes (id, pair_id, sender_id, text, created_at) VALUES (?, ?, ?, ?, ?)")
        .bind(noteId, user.pair_id, user.id, trimmed, createdAt).run();
      const partner = await env.DB.prepare("SELECT push_token FROM users WHERE id = ?").bind(partnerId).first<{ push_token: string | null }>();
      if (partner?.push_token) ctx.waitUntil(push(env, { token: partner.push_token, text: trimmed, noteId }).catch((e) => console.warn("push error", e)));
      return json({ id: noteId, createdAt }, 201);
    }

    case "GET /notes": {
      if (!user.pair_id) return err(409, "not paired");
      const limit = Math.min(Math.max(parseInt(searchParams.get("limit") ?? "50", 10) || 50, 1), 200);
      const { results } = await env.DB.prepare(
        "SELECT id, sender_id, text, created_at FROM notes WHERE pair_id = ? ORDER BY created_at DESC LIMIT ?")
        .bind(user.pair_id, limit).all<{ id: string; sender_id: string; text: string; created_at: number }>();
      return json({ notes: results.map((n) => ({ id: n.id, mine: n.sender_id === user.id, text: n.text, createdAt: n.created_at })) });
    }

    case "DELETE /me": {
      if (user.pair_id) await dissolvePair(env, user.pair_id);
      await env.DB.batch([
        env.DB.prepare("DELETE FROM pair_codes WHERE owner_id = ?").bind(user.id),
        env.DB.prepare("DELETE FROM join_attempts WHERE user_id = ?").bind(user.id),
        env.DB.prepare("DELETE FROM users WHERE id = ?").bind(user.id),
      ]);
      return json({ ok: true });
    }
  }
  return err(404, "not found");
}

export default {
  fetch: (req: Request, env: Env, ctx: ExecutionContext) => handle(req, env, ctx),
} satisfies ExportedHandler<Env>;
