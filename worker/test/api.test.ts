import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";
import { handle } from "../src/index";
import type { PushMessage } from "../src/apns";

const sent: PushMessage[] = [];
const ctx = { waitUntil: (p: Promise<unknown>) => void p };
const fakePush = async (_e: unknown, m: PushMessage) => { sent.push(m); };

type Auth = { userId: string; secret: string };
async function call(method: string, path: string, auth?: Auth, body?: unknown) {
  const headers: Record<string, string> = {};
  if (auth) headers.authorization = `Bearer ${auth.userId}.${auth.secret}`;
  const res = await handle(new Request(`https://x${path}`, { method, headers, body: body ? JSON.stringify(body) : undefined }), env as any, ctx, fakePush);
  return { status: res.status, body: (await res.json()) as any };
}
const register = async (): Promise<Auth> => (await call("POST", "/register")).body;
async function pairedUsers() {
  const a = await register(), b = await register();
  const { body } = await call("POST", "/pair/code", a);
  expect((await call("POST", "/pair/join", b, { code: body.code })).status).toBe(201);
  return { a, b };
}

describe("auth", () => {
  it("rejects missing or wrong secret", async () => {
    const a = await register();
    expect((await call("GET", "/me")).status).toBe(401);
    expect((await call("GET", "/me", { ...a, secret: "0".repeat(64) })).status).toBe(401);
    expect((await call("GET", "/me", a)).status).toBe(200);
  });
});

describe("pairing", () => {
  it("pairs two users with a code, and the code is single-use", async () => {
    const a = await register(), b = await register(), c = await register();
    const { body } = await call("POST", "/pair/code", a);
    expect(body.code).toMatch(/^\d{6}$/);
    expect((await call("POST", "/pair/join", b, { code: body.code })).status).toBe(201);
    expect((await call("GET", "/me", a)).body.paired).toBe(true);
    expect((await call("POST", "/pair/join", c, { code: body.code })).status).toBe(404);
  });
  it("cannot join your own code", async () => {
    const a = await register();
    const { body } = await call("POST", "/pair/code", a);
    expect((await call("POST", "/pair/join", a, { code: body.code })).status).toBe(404);
  });
  it("rejects expired codes", async () => {
    const a = await register(), b = await register();
    const { body } = await call("POST", "/pair/code", a);
    await (env as any).DB.prepare("UPDATE pair_codes SET expires_at = 1").run();
    expect((await call("POST", "/pair/join", b, { code: body.code })).status).toBe(404);
  });
  it("rate-limits wrong guesses", async () => {
    const b = await register();
    for (let i = 0; i < 5; i++) expect((await call("POST", "/pair/join", b, { code: "000000" })).status).toBe(404);
    expect((await call("POST", "/pair/join", b, { code: "000000" })).status).toBe(429);
  });
});

describe("notes", () => {
  it("delivers a note to the partner with a push, and shows it in both histories", async () => {
    const { a, b } = await pairedUsers();
    await call("PUT", "/me/push-token", b, { token: "ab".repeat(32) });
    sent.length = 0;
    const r = await call("POST", "/notes", a, { text: "  miss you  " });
    expect(r.status).toBe(201);
    expect(sent).toHaveLength(1);
    expect(sent[0]).toMatchObject({ token: "ab".repeat(32), text: "miss you" });
    expect((await call("GET", "/notes", b)).body.notes[0]).toMatchObject({ text: "miss you", mine: false });
    expect((await call("GET", "/notes", a)).body.notes[0].mine).toBe(true);
  });
  it("validates length and pairing", async () => {
    const { a } = await pairedUsers();
    expect((await call("POST", "/notes", a, { text: "" })).status).toBe(400);
    expect((await call("POST", "/notes", a, { text: "x".repeat(101) })).status).toBe(400);
    expect((await call("POST", "/notes", a, { text: "x".repeat(100) })).status).toBe(201);
    const loner = await register();
    expect((await call("POST", "/notes", loner, { text: "hi" })).status).toBe(409);
  });
  it("outsiders cannot read a pair's notes", async () => {
    await pairedUsers();
    const outsider = await register();
    expect((await call("GET", "/notes", outsider)).status).toBe(409);
  });
});

describe("unpair and delete", () => {
  it("unpairing clears notes for both", async () => {
    const { a, b } = await pairedUsers();
    await call("POST", "/notes", a, { text: "hi" });
    await call("DELETE", "/pair", a);
    expect((await call("GET", "/me", b)).body.paired).toBe(false);
    expect((await call("GET", "/notes", b)).status).toBe(409);
  });
  it("DELETE /me removes the account", async () => {
    const { a, b } = await pairedUsers();
    expect((await call("DELETE", "/me", a)).status).toBe(200);
    expect((await call("GET", "/me", a)).status).toBe(401);
    expect((await call("GET", "/me", b)).body.paired).toBe(false);
  });
});

describe("block and report", () => {
  it("blocking unpairs, stores a report, and prevents re-pairing", async () => {
    const { a, b } = await pairedUsers();
    await call("POST", "/notes", b, { text: "rude" });
    expect((await call("POST", "/block", a, { report: true, reason: "abuse" })).status).toBe(200);
    expect((await call("GET", "/me", b)).body.paired).toBe(false);
    const row = await (env as any).DB.prepare("SELECT last_notes FROM reports ORDER BY created_at DESC LIMIT 1").first();
    expect(JSON.parse(row.last_notes)).toEqual(["rude"]);
    const { body } = await call("POST", "/pair/code", b);
    expect((await call("POST", "/pair/join", a, { code: body.code })).status).toBe(404);
  });
});
