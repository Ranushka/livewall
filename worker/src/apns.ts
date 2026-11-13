export interface PushEnv {
  APNS_KEY: string; APNS_KEY_ID: string; APNS_TEAM_ID: string; APNS_TOPIC: string; APNS_HOST: string;
}
export interface PushMessage { token: string; text: string; noteId: string }
export type PushSender = (env: PushEnv, msg: PushMessage) => Promise<void>;

const b64url = (buf: ArrayBuffer | Uint8Array) =>
  btoa(String.fromCharCode(...new Uint8Array(buf))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

let cached: { jwt: string; at: number } | null = null;

async function providerToken(env: PushEnv): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && now - cached.at < 50 * 60) return cached.jwt;
  const pem = env.APNS_KEY.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const enc = new TextEncoder();
  const head = b64url(enc.encode(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID })));
  const body = b64url(enc.encode(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: now })));
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(`${head}.${body}`));
  cached = { jwt: `${head}.${body}.${b64url(sig)}`, at: now };
  return cached.jwt;
}

/** Sends an alert push. mutable-content lets the app's notification extension save the note for the widget. */
export const sendApns: PushSender = async (env, msg) => {
  const res = await fetch(`${env.APNS_HOST}/3/device/${msg.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${await providerToken(env)}`,
      "apns-topic": env.APNS_TOPIC,
      "apns-push-type": "alert",
      "apns-priority": "10",
    },
    body: JSON.stringify({
      aps: { alert: { title: "New note", body: msg.text }, sound: "default", "mutable-content": 1 },
      noteId: msg.noteId,
      text: msg.text,
    }),
  });
  if (!res.ok) console.warn("APNs failed", res.status, await res.text());
};
