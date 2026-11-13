# App Store listing (draft)

## Name / subtitle
- **Name:** LiveWall (check availability in App Store Connect; fallback "LiveWall: Moving Wallpapers")
- **Subtitle (30 chars):** Live wallpapers + love notes

## Promotional text (170 chars)
Turn any video into a Lock Screen wallpaper that actually moves, and get sweet notes from your partner right under the clock.

## Description
LiveWall does two things well.

**1. Wallpapers that actually move**
Pick a video, frame it, and save it as a Live Photo. Press and hold your Lock Screen and it comes alive.
• Works with any video from your library
• Crop and frame it for your Lock Screen
• First 2 wallpapers free, then a one-time unlock. No subscription.

**2. Notes from your partner, on your Lock Screen**
Pair with one person using a 6-digit code. Whatever they write appears on your Lock Screen widget, and the other way round.
• No account, email or phone number
• Notes up to 100 characters
• Lock Screen and Home Screen widgets
• Always free

Your videos stay on your device. Block, unpair and delete your data any time.

## Keywords (100 chars)
live wallpaper,lock screen,widget,couples,partner,love notes,video wallpaper,moving background

## Category
Primary: Photo & Video. Secondary: Lifestyle.

## Age rating
Answer "No" to all content questions, except **User-generated content / messaging** (notes between two paired users): expect 12+ (or 17+ if Apple's questionnaire requires it for unmoderated chat). Have block and report in place (done).

## In-App Purchase
- Type: Non-consumable. Product ID `com.example.livewall.unlock`. Price tier: $2.99.
- Display name: Unlock LiveWall. Description: Unlimited live wallpapers.
- Review screenshot: the paywall screen.

## App Privacy ("nutrition label")
Data collected, **not used for tracking**, linked to the user's (anonymous) ID:
| Type | Purpose |
|---|---|
| User Content → Other User Content (notes) | App Functionality |
| Identifiers → Device ID (push token, anonymous ID) | App Functionality |
| Purchases | App Functionality (handled by Apple) |

No analytics, no advertising, no tracking. Privacy Policy URL: `docs/privacy.html` once hosted. Support URL: `docs/support.html`.

## Review notes (for Apple)
LiveWall is not a generic wallpaper app: it converts the user's own videos to Live Photos and adds a private two-person notes feature. To test notes, install on two devices, tap Partner → Get a code on one, and enter it on the other. Block/report is under Partner → ⋯ → Block…, deletion under ⋯ → Delete my data. Purchases can be tested in sandbox.

## Screenshots (6.9" and 6.5" iPhone sizes required)
1. Lock Screen with a moving wallpaper and a partner note under the clock. Caption: "Wallpapers that actually move"
2. Wallpaper maker framing a video. Caption: "Any video, framed your way"
3. Partner tab with a conversation. Caption: "Notes from your person"
4. Pairing code screen. Caption: "Pair with a 6-digit code"
5. Widget gallery (Lock + Home). Caption: "Right under the clock"
6. Paywall. Caption: "Pay once. No subscription."

## Pre-submission checklist
- [ ] Replace all `com.example` IDs, App Group, Worker URL, support URL
- [ ] Switch `aps-environment` to `production` and `APNS_HOST` to `https://api.push.apple.com` for release
- [ ] Real app icon (1024×1024, no transparency)
- [ ] Privacy policy and support pages hosted; placeholders filled
- [ ] Two-device TestFlight run for several days
- [ ] Confirm the wallpaper maker sets Live Photos correctly on a real device ("Motion Not Available" check)
