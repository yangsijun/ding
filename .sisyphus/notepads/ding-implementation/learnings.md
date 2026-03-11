# Learnings & Conventions

## Project Structure (Decided)
- Monorepo: `Sources/` (CLI), `relay/` (CF Workers), `DingApp/` (iOS), `DingWatch/` (watchOS)
- CLI: Swift Package, executable target `ding` + library `DingCore`
- Bundle ID: `dev.sijun.ding`
- iOS deployment target: iOS 16.0

## PoC References
- PoC CLI: `~/coding/lab/WatchTaskPoC/WatchTaskCLI/`
- PoC relay: `~/coding/lab/WatchTaskPoC/watchtask-relay/`
- PoC iOS: `~/coding/lab/WatchTaskPoC/WatchTaskPoC/`
- PoC Watch: `~/coding/lab/WatchTaskPoC/WatchTaskPoCWatch/`

## Key Patterns
- Root command: `@main struct Ding: AsyncParsableCommand` (not ParsableCommand)
- Keychain service: "dev.sijun.ding", kSecClassGenericPassword
- APNs JWT: ES256 via Web Crypto, iat rounded to 20-min windows
- Process spawning: /usr/bin/env with inherited FileHandle.standard*

## Conventions
- Error handling: notification failure is NON-FATAL (log to stderr, preserve exit code)
- No third-party Swift deps beyond ArgumentParser
- All credentials in Keychain, never config files

## Task 2: Cloudflare Workers Scaffolding

### Env Interface Pattern
- KVNamespace binding: `STORE: KVNamespace`
- APNs credentials: APPLE_KEYID, APPLE_TEAMID, APPLE_AUTHKEY (base64 .p8)
- Relay auth: RELAY_SECRET (shared secret for Bearer token)
- APNs config: APNS_TOPIC (bundle ID), DEVICE_TOKEN (hardcoded for Phase 1)

### Workers Fetch Handler
- Export: `export default { async fetch(request: Request, env: Env): Promise<Response> { ... } }`
- CORS headers: Allow POST, OPTIONS, GET with Content-Type and Authorization
- /health endpoint: Returns `{ status: "ok", timestamp: ISO8601 }`
- /push endpoint: Returns 405 for non-POST, 401 for missing Bearer auth (stub for Task 5)

### TypeScript Configuration
- Target: ES2020, Module: ES2020
- Workers types: @cloudflare/workers-types
- Strict mode enabled
- tsconfig includes src/** and excludes node_modules, dist

### Development Setup
- wrangler dev runs on localhost:8787
- .dev.vars.example documents all required secrets with placeholders
- package.json scripts: dev (wrangler dev), deploy, test
- KV namespace binding uses placeholder ID in wrangler.toml (PLACEHOLDER_KV_ID)

### Testing Verification
- GET /health returns 200 with JSON response
- GET /push returns 405 Method Not Allowed
- TypeScript compiles without errors (npx tsc --noEmit)
