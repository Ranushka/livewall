# LiveWall

Live wallpaper maker + partner notes on the Lock Screen.

- `worker/` — Cloudflare Worker + D1 backend (pairing, notes, APNs push). `cd worker && pnpm install && pnpm test`
- `ios/` — Swift app, widget and notification extension (see ios/README.md)
- `docs/` — privacy policy and support pages (host on GitHub Pages or Cloudflare Pages; fill in [DATE] and [SUPPORT EMAIL])

## Backend API
All routes except `/register` need `Authorization: Bearer <userId>.<secret>`.

| Route | Purpose |
|---|---|
| `POST /register` | Create anonymous user → `{userId, secret}` (store in Keychain) |
| `PUT /me/push-token` | Save APNs device token |
| `POST /pair/code` | Get a 6-digit code (valid 10 min) |
| `POST /pair/join` | Join with a code (5 wrong tries/hour) |
| `POST /notes` / `GET /notes` | Send a note (≤100 chars, pushes partner) / history |
| `DELETE /pair` | Unpair (deletes notes) |
| `DELETE /me` | Delete my data |

## Deploy (after Apple push key exists)
```
cd worker
npx wrangler d1 create livewall        # paste database_id into wrangler.jsonc
pnpm migrate:remote
npx wrangler secret put APNS_KEY       # contents of the .p8 file
npx wrangler secret put APNS_KEY_ID
npx wrangler secret put APNS_TEAM_ID
pnpm deploy
```
Set `APNS_TOPIC` (bundle id) and `APNS_HOST` (sandbox vs production) in `wrangler.jsonc`.
