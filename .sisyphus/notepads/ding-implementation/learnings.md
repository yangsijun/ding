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

## Task 1: Swift Package Scaffolding (COMPLETED)

### Implementation Details
- Package.swift: swift-tools-version 5.9, platforms [.macOS(.v13)]
- Two targets: executable "ding" + library "DingCore"
- ArgumentParser dependency: from 1.5.0
- Root command: `@main struct Ding: AsyncParsableCommand` (critical for async subcommands)
- All command structs must be public with explicit `public init()` to satisfy ParsableArguments protocol

### NotificationPayload Structure
- id: UUID (not String)
- status: enum with CaseIterable + rawValue: String
- All fields match PRD section 6
- Custom encode/decode methods with iso8601 date strategy
- toDictionary/fromDictionary for WatchConnectivity compatibility

### Key Learnings
- Public structs implementing AsyncParsableCommand require explicit public init()
- Commands must be public to be accessible from executable target
- ArgumentParser 1.7.0 resolved (from 1.5.0 constraint)
- Build artifacts in .build/ should be .gitignored (embedded git repo warning)
- All 5 subcommands (wait, notify, setup, status, test) registered and accessible

### Build Verification
- `swift build` succeeds with zero errors
- `.build/debug/ding --help` lists all 5 subcommands
- `.build/debug/ding --version` outputs "0.1.0"
- Evidence saved to .sisyphus/evidence/task-1-*

## Task 3: iOS Xcode Project Scaffolding (COMPLETED)

### Project Structure
- Location: `/Users/sijun/coding/ding/DingApp/`
- Generated with xcodegen from project.yml
- Bundle ID: `dev.sijun.ding`
- Deployment target: iOS 16.0
- Directory structure: DingApp/DingApp/ contains all Swift sources + entitlements + Info.plist

### Key Files Created
- `DingApp.swift`: @main struct with @UIApplicationDelegateAdaptor(AppDelegate.self)
- `AppDelegate.swift`: UIApplicationDelegate with APNs callback stubs
- `TokenStore.swift`: @MainActor ObservableObject with @Published deviceToken
- `ContentView.swift`: Placeholder UI with "ding" title + "Setup required"
- `DingApp.entitlements`: aps-environment = development
- `Info.plist`: Standard SwiftUI app configuration
- `project.yml`: xcodegen configuration with push_notifications capability

### Critical Implementation Details
- TokenStore persists deviceToken to UserDefaults with key "apns_device_token"
- AppDelegate.tokenStore reference set in DingApp.swift onAppear
- ContentView receives tokenStore as @EnvironmentObject
- APNs callbacks (didRegisterForRemoteNotifications, didFailToRegisterForRemoteNotifications) are method stubs with print statements
- Entitlements file properly generated with aps-environment = development

### Build Verification
- `xcodebuild -scheme DingApp -destination 'platform=iOS Simulator,name=iPhone 16,OS=18.6' build` succeeds
- Build output saved to .sisyphus/evidence/task-3-xcode-build.txt
- Entitlements file verified in .sisyphus/evidence/task-3-entitlements.txt

### xcodegen Learnings
- xcodegen generates project.pbxproj from project.yml
- Entitlements properties must be specified in project.yml under target.entitlements.properties
- Sources path must match actual directory structure (DingApp/DingApp/ in this case)
- Resources paths are relative to project root
- Push notifications capability automatically enables aps-environment in entitlements

## Task 6: iOS APNs Registration + Token Display UI (COMPLETED)

### APNs Registration Flow
- `UNUserNotificationCenter.current().requestAuthorization` MUST be called BEFORE `registerForRemoteNotifications()`
- The `requestAuthorization` callback returns `granted: Bool` — only call `registerForRemoteNotifications()` if granted
- On simulator, `didFailToRegisterForRemoteNotificationsWithError` is always called (no APNs on sim)
- `UNUserNotificationCenter.current().delegate = self` must be set in `didFinishLaunchingWithOptions`
- `nonisolated` keyword needed on `willPresent` delegate method when AppDelegate is implicitly @MainActor

### Concurrency / Main Actor
- AppDelegate methods (UIApplicationDelegate) are implicitly @MainActor in modern Swift
- Use `Task { @MainActor in }` for explicit safety when calling @MainActor-isolated TokenStore from delegate callbacks
- NotificationPermissionManager is @MainActor ObservableObject — can use async methods directly

### ContentView States
- 4 states: token received, registration error, permission denied, not determined
- `UIPasteboard.general.string` for clipboard copy
- Copy feedback: `@State var copied = false` + `Task.sleep(nanoseconds:)` for 2-second checkmark

### xcodegen
- New Swift files in sources directory are auto-included when `xcodegen generate` is re-run
- Must regenerate .xcodeproj after adding new files: `cd DingApp && xcodegen generate`
- `includes: ["*.swift"]` in project.yml matches top-level files in the sources directory

### Build
- Build command: `xcodebuild -scheme DingApp -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Simulator name is iPhone 17 (not iPhone 16) with this Xcode version
