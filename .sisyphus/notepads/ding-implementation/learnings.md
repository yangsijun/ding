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

## Task 9: iOS App Store Features (COMPLETED)

### New Files Created
- `DingApp/DingApp/Views/QRCodeView.swift` — CoreImage QR code generator, .interpolation(.none), 200x200 frame
- `DingApp/DingApp/Views/NotificationListView.swift` — List with color-coded status circles, Clear All button
- `DingApp/DingApp/Models/NotificationRecord.swift` — Codable struct with id/title/body/status/timestamp
- `DingApp/DingApp/Models/NotificationStore.swift` — @MainActor ObservableObject, max 20 records in UserDefaults

### Key Implementation Patterns

#### QR Code Generation
- Use `CIFilter.qrCodeGenerator()` from CoreImage.CIFilterBuiltins
- Set `filter.message = Data(string.utf8)` and `filter.correctionLevel = "M"`
- Scale output by 10x with `CGAffineTransform(scaleX: 10, y: 10)` for crisp rendering
- Apply `.interpolation(.none)` on Image to prevent blurring
- Wrap in white background with 8pt padding and 8pt corner radius

#### ShareLink Integration
- `ShareLink(item: tokenStore.deviceToken, subject: Text("ding Device Token")) { Label(...) }`
- Works natively in iOS 16.1+ — no additional dependencies needed
- Pair with Copy button for dual sharing options

#### Notification Storage
- NotificationStore: @MainActor ObservableObject with @Published records array
- Max 20 records enforced: `if records.count > maxRecords { records = Array(records.prefix(maxRecords)) }`
- Persist to UserDefaults with JSONEncoder/JSONDecoder using iso8601 date strategy
- Load on init, save after every add/clearAll operation

#### Notification Parsing from APNs
- In `willPresent` delegate: `userInfo["ding"] as? [String: Any]` to extract custom payload
- Fallback to notification.request.content.title/body if ding payload missing
- Also handle `didReceiveRemoteNotification` for background/terminated app receipt
- Use `Task { @MainActor in }` to call NotificationStore from nonisolated delegate method

#### Tab Bar Navigation
- `TabView { ... }` with `.tabItem { Label(..., systemImage: "...") }` for each tab
- Token tab: NavigationView wrapping VStack with 4 states
- Notifications tab: NotificationListView() directly
- Both tabs receive environment objects via .environmentObject()

#### Project Structure
- `project.yml` sources must use `"**/*.swift"` (not `"*.swift"`) to include Views/ and Models/ subdirectories
- After adding new files, re-run `xcodegen generate` to update .xcodeproj
- All new files automatically included in build target

### Build Verification
- `xcodebuild -scheme DingApp -destination 'platform=iOS Simulator,name=iPhone 17' build` → BUILD SUCCEEDED
- Evidence saved to .sisyphus/evidence/task-9-qr-share.txt and task-9-notification-list.txt
- Git commit: `feat(ios): add QR code, share, notification list`

## Task 10: Homebrew Tap + Release Automation (COMPLETED)

### Files Created
- `scripts/release.sh` — builds arm64 + x86_64, lipo universal binary, zip + SHA256
- `homebrew-tap/Formula/ding.rb` — Homebrew formula (PLACEHOLDER_SHA256 until real release)
- `homebrew-tap/README.md` — installation instructions

### Key Patterns
- lipo command: `lipo -create .build/arm64-apple-macosx/release/ding .build/x86_64-apple-macosx/release/ding -output .build/release-artifacts/ding`
- Archive: `ditto -c -k --keepParent ding ding-VERSION-macos.zip`
- SHA256: `shasum -a 256 file.zip | awk '{print $1}'`
- Formula sha256 is PLACEHOLDER until real GitHub release is created
- brew install requires actual GitHub release URL with real binary

## Task 12: Shell Auto-Hook (COMPLETED)

### Files Created
- `Sources/DingCore/Commands/InstallHookCommand.swift` — detects shell, writes hook script, appends to RC
- `Sources/DingCore/Commands/UninstallHookCommand.swift` — removes hook script + RC source line
- `Sources/DingCore/Resources/hook.zsh` — zsh hook using preexec/precmd + add-zsh-hook
- `Sources/DingCore/Resources/hook.bash` — bash hook using trap DEBUG + PROMPT_COMMAND

### Key Patterns
- Shell detection: `ProcessInfo.processInfo.environment["SHELL"]`
- Hook dir: `~/.config/ding/hook.{zsh,bash}`
- RC guard: `# Added by ding` comment prevents duplicate installation
- Inline hook script as fallback (Resources/ files may not be bundled in debug builds)
- zsh: `add-zsh-hook preexec __ding_preexec` + `add-zsh-hook precmd __ding_precmd`
- bash: `trap '__ding_debug' DEBUG` + `PROMPT_COMMAND="__ding_precmd;..."`
- Notification is non-blocking: `ding notify ... 2>/dev/null & disown`
- `__ding_hooks_loaded` guard prevents duplicate hook registration

## Task 13: Relay Multi-Device KV Token Management (COMPLETED)

### KV Data Model
- Device list key: `devices:{apiKey}` → `{ devices: string[], registeredAt: string, lastSeenAt: string }`
- Rate limit key: `ratelimit:{apiKey}:{Math.floor(Date.now()/60000)}` → count string, TTL 120s
- JWT cache key: `apns-jwt` → JWT string, TTL 2700s (unchanged)

### New Endpoints
- POST /register: `{ device_token: string }` → stores in KV under API key
- POST /deregister: `{ device_token: string }` → removes from KV
- POST /push: fan-out to ALL devices for API key, returns `{ sent, failed, tokens_removed }`

### Rate Limiting
- 10 pushes per minute per API key
- KV key uses minute bucket: `Math.floor(Date.now() / 60000)`
- TTL 120s (2 minutes) to handle clock skew
- 11th request returns 429

### Auth
- `extractApiKey()` helper: strips "Bearer " prefix from Authorization header
- Same Bearer token used for all endpoints (register, deregister, push)
- Legacy DEVICE_TOKEN env var still supported as fallback

### BadDeviceToken Handling
- Try production APNs first
- On BadDeviceToken: try sandbox fallback
- If sandbox also fails: mark token for removal, remove from KV after all sends
