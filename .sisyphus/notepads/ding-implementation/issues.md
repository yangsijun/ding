# Issues & Gotchas

## Known Gotchas (from research)
- JWT iat MUST be rounded to 20-min boundary or APNs returns TooManyProviderTokenUpdates
- PEM import for .p8: strip headers, decode base64, pass as pkcs8 ArrayBuffer
- Process pipe deadlock: call readDataToEndOfFile() BEFORE waitUntilExit()
- Keychain CLI prompt: first-time access shows system dialog (expected, sign binary to dismiss)
- apns-push-type: "alert" is REQUIRED since iOS 13 — omit = silent drops
- QR code: use .interpolation(.none) or it renders blurry
- Sandbox vs production: device tokens are environment-specific
- Guideline 4.2: need QR + copy + share + notification list minimum for App Store

## Session Log
