# ding — CLI → iPhone/Watch Push Notification System

## TL;DR

> **Quick Summary**: Build a 3-component system (Swift CLI + Cloudflare Workers relay + iOS companion app) that sends push notifications to iPhone/Apple Watch when Mac terminal commands complete. Architecture validated by 5-day PoC with 100% delivery rate and 1-2s latency.
> 
> **Deliverables**:
> - `ding` Swift CLI (Homebrew Tap distribution)
> - Cloudflare Workers APNs relay (production deployment)
> - iOS companion app (App Store via TestFlight)
> - Shell auto-hook for zsh/bash (Phase 2)
> - Webhook endpoint for CI/CD (Phase 2)
> - Dedicated watchOS app with custom haptics (Phase 2)
> 
> **Estimated Effort**: Large (Phase 1 + Phase 2)
> **Parallel Execution**: YES — 6 waves
> **Critical Path**: Task 1 → Task 4 → Task 5 → Task 8 → Task 14 → Task 18 → F1-F4

---

## Context

### Original Request
Build "ding" — a CLI tool for Mac that sends push notifications to iPhone/Apple Watch when long-running terminal commands (builds, tests, deploys, LLM agents) complete or fail. Based on a comprehensive PRD (`docs/prd-ding.md`) and a validated 5-day PoC (`~/coding/lab/WatchTaskPoC`).

### Interview Summary
**Key Discussions**:
- **Scope**: Phase 1 (MVP) + Phase 2 (Expansion) in one plan
- **Token Registration**: Manual paste — iOS app shows token + copy button, user runs `ding setup <token>`
- **Relay Auth**: Per-user API key generated during `ding setup`, stored in Keychain
- **PoC Code**: Available at `~/coding/lab/WatchTaskPoC` — reuse patterns (command structure, payload model, JWT generation, APNs registration), remove PoC-only code (Bonjour, TCP, Mac app, WatchConnectivity)
- **Test Strategy**: Tests after implementation + agent-executed QA scenarios

**Research Findings**:
- **Swift CLI**: ArgumentParser with AsyncParsableCommand, DingCore library target, Keychain via Security framework, Process with inherited file handles, universal binary via lipo
- **CF Workers**: Web Crypto ES256 for JWT, iat rounding to 20-min windows + KV cache (45min TTL), visible push requires `apns-push-type: alert` + `apns-topic` headers
- **iOS App**: AppDelegate + SwiftUI lifecycle for APNs, CoreImage QR code, Guideline 4.2 risk (need QR + copy + share minimum), UNNotificationServiceExtension not needed
- **PoC Inventory**: 30+ files explored, reusable code identified across CLI/relay/iOS, ~360 LOC total production estimate

### Gap Analysis (Self-Conducted)
**Identified Gaps** (addressed in plan):
- **CLI resilience**: Notification failure must not affect wrapped command exit code — handled in WaitCommand error handling
- **Ctrl+C handling**: CLI must forward SIGINT to child process — added signal forwarding requirement
- **Concurrent instances**: Multiple `ding wait` running simultaneously — no conflict since each is independent HTTP POST
- **Token validation**: CLI should validate token format before storing — added validation in setup command
- **Relay input validation**: Must sanitize all incoming payloads — added schema validation requirement
- **APNs error handling**: BadDeviceToken should trigger sandbox fallback — added to relay error handling
- **Offline behavior**: CLI must exit cleanly even if relay is unreachable — added timeout + graceful failure
- **App Store rejection risk**: Guideline 4.2 — mitigated with QR code, copy, share, notification history features

---

## Work Objectives

### Core Objective
Deliver a production-ready notification pipeline: Mac terminal command → 1-3 second push notification to iPhone/Apple Watch. Phase 1 provides core CLI + relay + iOS app. Phase 2 adds shell hooks, webhooks, Watch app, and multi-user support.

### Concrete Deliverables
- `ding` CLI binary (universal arm64+x86_64) published to Homebrew Tap
- Cloudflare Workers relay deployed to production with API key auth
- iOS app on App Store (via TestFlight) with APNs registration + token display
- Shell hook integration for zsh/bash (Phase 2)
- Webhook endpoint for CI/CD integration (Phase 2)
- watchOS companion app with custom haptics (Phase 2)

### Definition of Done
- [ ] `ding wait -- echo hello` sends notification, exit code 0, notification arrives on iPhone within 3s
- [ ] `ding wait -- false` sends failure notification, exit code 1 preserved
- [ ] `ding notify "test" --status success` sends notification with correct status
- [ ] `ding test` sends 4 notifications (success/failure/warning/info), all arrive
- [ ] `ding setup <token>` stores token + API key in Keychain
- [ ] `ding status` reports relay connectivity and token validity
- [ ] `brew install <user>/tap/ding` installs CLI successfully
- [ ] iOS app registers for APNs, displays token, supports copy/QR/share
- [ ] 10 rapid-fire notifications: 10/10 delivered
- [ ] Shell hook auto-notifies on commands >30s (Phase 2)
- [ ] Webhook endpoint accepts curl POST and delivers notification (Phase 2)
- [ ] Watch app shows custom haptics per status type (Phase 2)

### Must Have
- Exit code preservation (wrapped command's exit code returned by `ding wait`)
- Stdout/stderr passthrough (user sees real-time output)
- Notification within 3 seconds of command completion (P50)
- 100% notification delivery (visible push, not silent)
- Keychain storage for sensitive data (token + API key)
- Per-user API key authentication on relay
- JWT caching with 20-min iat rounding (prevents TooManyProviderTokenUpdates)
- iOS notification mirroring to Watch (automatic, no Watch app needed in Phase 1)

### Must NOT Have (Guardrails)
- **No Mac companion app** — CLI sends directly to relay (PoC eliminated this)
- **No silent push** — only visible push (PoC proved silent push unreliable)
- **No WatchConnectivity in Phase 1** — rely on iOS notification mirroring
- **No telemetry/analytics** without explicit user consent
- **No plaintext token storage** — Keychain only, never config files or env vars
- **No blocking on notification failure** — wrapped command exit code always preserved
- **No over-abstraction** — PoC is ~360 LOC, production should stay under ~600 LOC total
- **No third-party Swift dependencies** beyond ArgumentParser — URLSession, Security framework, Foundation are sufficient
- **No plugin/extension system** — Phase 3 scope, not Phase 1 or 2

---

## Verification Strategy

> **ZERO HUMAN INTERVENTION** — ALL verification is agent-executed. No exceptions.

### Test Decision
- **Infrastructure exists**: NO
- **Automated tests**: YES (after implementation)
- **Framework**: Swift Testing (for DingCore library), wrangler test (for relay)
- **Approach**: Build features first, add tests for critical paths afterward

### QA Policy
Every task MUST include agent-executed QA scenarios.
Evidence saved to `.sisyphus/evidence/task-{N}-{scenario-slug}.{ext}`.

- **CLI**: Use Bash — run `ding` commands, verify stdout/stderr/exit codes
- **Relay**: Use Bash (curl) — send HTTP requests, assert status + response JSON
- **iOS App**: Use Xcode build verification — `xcodebuild` for build success, manual device testing noted as post-merge
- **Build/Distribution**: Use Bash — verify `swift build`, `lipo`, `wrangler deploy` succeed

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1 (Start Immediately — foundation + scaffolding):
├── Task 1: Swift Package scaffolding + shared models [quick]
├── Task 2: Cloudflare Workers project scaffolding [quick]
├── Task 3: iOS Xcode project scaffolding [quick]

Wave 2 (After Wave 1 — core modules, MAX PARALLEL):
├── Task 4: CLI core commands (wait/notify) [deep]
├── Task 5: CF Workers relay with APNs + JWT [deep]
├── Task 6: iOS APNs registration + token display [unspecified-high]

Wave 3 (After Wave 2 — integration + remaining CLI):
├── Task 7: CLI setup/test/status commands [unspecified-high]
├── Task 8: E2E integration testing (CLI → relay → APNs) [deep]
├── Task 9: iOS App Store features (QR, share, history) [visual-engineering]

Wave 4 (After Wave 3 — distribution + Phase 2 foundation):
├── Task 10: Homebrew Tap + release automation [quick]
├── Task 11: App Store submission prep [unspecified-high]
├── Task 12: Shell auto-hook (install-hook/uninstall-hook) [unspecified-high]
├── Task 13: Relay multi-device KV support [unspecified-high]

Wave 5 (After Wave 4 — Phase 2 features):
├── Task 14: Webhook endpoint for CI/CD [unspecified-high]
├── Task 15: Custom notification sounds [quick]
├── Task 16: watchOS companion app [deep]
├── Task 17: iOS notification history [visual-engineering]

Wave 6 (After Wave 5 — tests + polish):
├── Task 18: Automated tests (Swift Testing + wrangler) [unspecified-high]
├── Task 19: CLI enhanced status + token refresh [quick]

Wave FINAL (After ALL tasks — independent review, 4 parallel):
├── Task F1: Plan compliance audit (oracle)
├── Task F2: Code quality review (unspecified-high)
├── Task F3: Real QA — full E2E verification (unspecified-high)
├── Task F4: Scope fidelity check (deep)

Critical Path: Task 1 → Task 4 → Task 5 → Task 8 → Task 14 → Task 18 → F1-F4
Parallel Speedup: ~65% faster than sequential
Max Concurrent: 3 (Waves 2, 4, 5)
```

### Dependency Matrix

| Task | Depends On | Blocks | Wave |
|------|-----------|--------|------|
| 1 | — | 4, 6, 7 | 1 |
| 2 | — | 5 | 1 |
| 3 | — | 6, 9, 11 | 1 |
| 4 | 1 | 7, 8, 10 | 2 |
| 5 | 2 | 8, 13, 14 | 2 |
| 6 | 1, 3 | 8, 9, 11 | 2 |
| 7 | 1, 4 | 8, 12 | 3 |
| 8 | 4, 5, 6 | 10, 11, 18 | 3 |
| 9 | 3, 6 | 11, 17 | 3 |
| 10 | 4, 8 | — | 4 |
| 11 | 3, 6, 8, 9 | — | 4 |
| 12 | 4, 7 | — | 4 |
| 13 | 5 | 14 | 4 |
| 14 | 5, 13 | 18 | 5 |
| 15 | 6 | 16 | 5 |
| 16 | 6, 15 | 18 | 5 |
| 17 | 9 | — | 5 |
| 18 | 8, 14, 16 | F1-F4 | 6 |
| 19 | 7 | — | 6 |
| F1-F4 | 18, 19 | — | FINAL |

### Agent Dispatch Summary

- **Wave 1**: 3 tasks — T1 `quick`, T2 `quick`, T3 `quick`
- **Wave 2**: 3 tasks — T4 `deep`, T5 `deep`, T6 `unspecified-high`
- **Wave 3**: 3 tasks — T7 `unspecified-high`, T8 `deep`, T9 `visual-engineering`
- **Wave 4**: 4 tasks — T10 `quick`, T11 `unspecified-high`, T12 `unspecified-high`, T13 `unspecified-high`
- **Wave 5**: 4 tasks — T14 `unspecified-high`, T15 `quick`, T16 `deep`, T17 `visual-engineering`
- **Wave 6**: 2 tasks — T18 `unspecified-high`, T19 `quick`
- **FINAL**: 4 tasks — F1 `oracle`, F2 `unspecified-high`, F3 `unspecified-high`, F4 `deep`

---

## TODOs

> Implementation + Test = ONE Task. Never separate.
> EVERY task MUST have: Recommended Agent Profile + Parallelization info + QA Scenarios.


### Wave 1 — Foundation & Scaffolding

- [ ] 1. Swift Package Scaffolding + Shared Models

  **What to do**:
  - Create `Package.swift` with swift-tools-version:5.9, platforms: [.macOS(.v13)]
  - Add dependency: `swift-argument-parser` from 1.3.0
  - Create executable target `ding` (Sources/ding/Ding.swift) and library target `DingCore` (Sources/DingCore/)
  - Create root `@main struct Ding: AsyncParsableCommand` with `CommandConfiguration` listing all subcommands (placeholder files)
  - Create `NotificationPayload` model in DingCore/Models/ — Codable struct with: id (UUID), title, body, status (enum: success/failure/warning/info), command (optional), exitCode (optional), duration (optional), timestamp (Date)
  - Create `DingError` enum in DingCore/Models/ for typed errors (relayUnreachable, invalidToken, keychainError, httpError)
  - Create `Config` struct for relay URL constant and version string
  - Verify `swift build` succeeds

  **Must NOT do**:
  - Do NOT implement command logic yet — only create empty subcommand files with argument definitions
  - Do NOT add any third-party dependencies besides ArgumentParser
  - Do NOT create test targets yet (Task 18)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Scaffolding with known patterns, no complex logic
  - **Skills**: []
    - No specialized skills needed for package scaffolding

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 2, 3)
  - **Blocks**: Tasks 4, 6, 7
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References** (existing code to follow):
  - `~/coding/lab/WatchTaskPoC/WatchTaskCLI/Package.swift` — PoC Package.swift structure with ArgumentParser dependency and Swift 6.0 tools version
  - `~/coding/lab/WatchTaskPoC/WatchTaskCLI/Sources/watchtask.swift` — Root command with CommandConfiguration and subcommand registration pattern
  - `~/coding/lab/WatchTaskPoC/WatchTaskCLI/Sources/NotificationPayload.swift` — Shared payload model with Codable, Status enum, optional fields

  **API/Type References**:
  - `~/coding/lab/WatchTaskPoC/WatchTaskCLI/Sources/Constants.swift` — Constants pattern (relay URL, app group ID)
  - `~/coding/lab/WatchTaskPoC/Shared/NotificationPayload.swift` — Shared payload struct definition (same model, use as source of truth for field names)

  **External References**:
  - swift-argument-parser docs: https://github.com/apple/swift-argument-parser — AsyncParsableCommand, CommandConfiguration, @Argument/@Option/@Flag

  **WHY Each Reference Matters**:
  - PoC Package.swift shows the exact ArgumentParser dependency version and target structure to replicate
  - PoC watchtask.swift shows how to wire subcommands into CommandConfiguration — copy this pattern exactly
  - NotificationPayload is the core data contract shared between CLI, relay, and iOS app — must match the PoC fields

  **Acceptance Criteria**:
  - [ ] `swift build` succeeds with zero errors
  - [ ] `.build/debug/ding --help` shows all subcommand names (wait, notify, test, setup, status)
  - [ ] `.build/debug/ding --version` outputs `0.1.0`
  - [ ] NotificationPayload encodes to JSON matching the PRD payload format

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Swift Package builds successfully
    Tool: Bash
    Preconditions: Swift 5.9+ installed, Package.swift created
    Steps:
      1. Run `swift build` in project root
      2. Check exit code is 0
      3. Verify binary exists at `.build/debug/ding`
    Expected Result: Build succeeds, binary exists
    Failure Indicators: Compilation errors, missing binary
    Evidence: .sisyphus/evidence/task-1-swift-build.txt

  Scenario: CLI help output lists all subcommands
    Tool: Bash
    Preconditions: Build succeeded
    Steps:
      1. Run `.build/debug/ding --help`
      2. Assert output contains "wait", "notify", "test", "setup", "status"
      3. Run `.build/debug/ding --version`
      4. Assert output contains "0.1.0"
    Expected Result: All 5 subcommands listed, version correct
    Failure Indicators: Missing subcommand name, wrong version
    Evidence: .sisyphus/evidence/task-1-cli-help.txt

  Scenario: NotificationPayload JSON encoding matches PRD format
    Tool: Bash
    Preconditions: Build succeeded
    Steps:
      1. Create a Swift script or test that encodes a NotificationPayload with all fields
      2. Verify JSON output contains keys: id, title, body, status, command, exitCode, duration, timestamp
      3. Verify status encodes as raw string ("success", not enum index)
    Expected Result: JSON matches PRD section 6 payload format
    Failure Indicators: Missing fields, wrong encoding format
    Evidence: .sisyphus/evidence/task-1-payload-json.txt
  ```

  **Commit**: YES
  - Message: `feat(cli): scaffold Swift Package with shared models`
  - Files: `Package.swift, Sources/ding/Ding.swift, Sources/DingCore/Models/NotificationPayload.swift, Sources/DingCore/Models/DingError.swift, Sources/DingCore/Config.swift, Sources/DingCore/Commands/*.swift`
  - Pre-commit: `swift build`

- [ ] 2. Cloudflare Workers Project Scaffolding

  **What to do**:
  - Create `relay/` directory with Cloudflare Workers TypeScript project
  - Create `wrangler.toml` with: name="ding-relay", main="src/index.ts", compatibility_date, KV namespace binding (STORE)
  - Define `Env` interface in `src/index.ts`: STORE (KVNamespace), APPLE_KEYID, APPLE_TEAMID, APPLE_AUTHKEY, RELAY_SECRET, APNS_TOPIC
  - Create minimal `fetch` handler that returns 200 on GET /health with JSON `{status: "ok"}`
  - Create `package.json` with wrangler dev dependency and scripts (dev, deploy, test)
  - Create `tsconfig.json` for Workers TypeScript
  - Add `.dev.vars.example` documenting required secrets (APPLE_AUTHKEY, RELAY_SECRET)
  - Verify `npx wrangler dev` starts successfully

  **Must NOT do**:
  - Do NOT implement APNs logic yet (Task 5)
  - Do NOT set up actual secrets — only document them
  - Do NOT configure rate limiting yet (part of Task 5)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Standard Workers scaffolding, no complex logic
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 3)
  - **Blocks**: Task 5
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - `~/coding/lab/WatchTaskPoC/watchtask-relay/wrangler.toml` — PoC wrangler config with env vars for APNs credentials
  - `~/coding/lab/WatchTaskPoC/watchtask-relay/src/index.ts` — PoC relay structure showing Env interface, fetch handler, and endpoint routing

  **External References**:
  - Cloudflare Workers docs: https://developers.cloudflare.com/workers/ — wrangler.toml format, KV bindings, secrets
  - ruddarr/apns-worker: https://github.com/ruddarr/apns-worker — Production APNs relay reference implementation

  **WHY Each Reference Matters**:
  - PoC wrangler.toml shows the exact env var names for APNs credentials — use the same names
  - PoC index.ts shows the Env interface structure that Task 5 will implement fully

  **Acceptance Criteria**:
  - [ ] `npx wrangler dev` starts local dev server without errors
  - [ ] `curl http://localhost:8787/health` returns `{"status":"ok"}`
  - [ ] wrangler.toml has KV namespace binding configured
  - [ ] TypeScript compiles without errors

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Workers dev server starts and health check responds
    Tool: Bash
    Preconditions: Node.js 18+, wrangler installed
    Steps:
      1. Run `npx wrangler dev` in relay/ directory (background)
      2. Wait 5 seconds for server startup
      3. Run `curl -s http://localhost:8787/health`
      4. Assert response contains `"status":"ok"`
      5. Kill wrangler process
    Expected Result: Health endpoint returns 200 with status ok
    Failure Indicators: Server fails to start, 404 on /health, non-JSON response
    Evidence: .sisyphus/evidence/task-2-workers-health.txt

  Scenario: Non-POST methods return 405
    Tool: Bash
    Preconditions: Dev server running
    Steps:
      1. Run `curl -s -o /dev/null -w "%{http_code}" http://localhost:8787/push`
      2. Assert HTTP status is 405 (GET on push endpoint)
    Expected Result: 405 Method Not Allowed
    Failure Indicators: 200 or 404
    Evidence: .sisyphus/evidence/task-2-method-not-allowed.txt
  ```

  **Commit**: YES
  - Message: `feat(relay): scaffold Cloudflare Workers project`
  - Files: `relay/wrangler.toml, relay/src/index.ts, relay/package.json, relay/tsconfig.json, relay/.dev.vars.example`
  - Pre-commit: `npx wrangler dev --test-scheduled` (dry run)

- [ ] 3. iOS Xcode Project Scaffolding

  **What to do**:
  - Create `DingApp/` directory with Xcode project (or use xcodegen `project.yml`)
  - Set up SwiftUI app with `@main struct DingApp: App` and `WindowGroup`
  - Add `@UIApplicationDelegateAdaptor(AppDelegate.self)` for APNs callback
  - Create empty `AppDelegate.swift` with `UIApplicationDelegate` conformance
  - Create `TokenStore.swift` — `@MainActor ObservableObject` with `@Published deviceToken: String`, persisted to UserDefaults
  - Configure Xcode capabilities: Push Notifications, Background Modes (Remote notifications)
  - Set deployment target: iOS 16.0
  - Set bundle identifier pattern: `dev.sijun.ding` (or user's preferred)
  - Add `aps-environment` entitlement (development)
  - Create placeholder `ContentView` showing "ding" branding and "Setup required" state
  - Copy `NotificationPayload.swift` shared model into project (or create shared Swift Package)

  **Must NOT do**:
  - Do NOT implement APNs registration logic yet (Task 6)
  - Do NOT add QR code or share features (Task 9)
  - Do NOT create watchOS target (Task 16)

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Xcode project creation with known patterns
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Tasks 1, 2)
  - **Blocks**: Tasks 6, 9, 11
  - **Blocked By**: None (can start immediately)

  **References**:

  **Pattern References**:
  - `~/coding/lab/WatchTaskPoC/WatchTaskPoC/WatchTaskPoCApp.swift` — PoC iOS app entry point with UIApplicationDelegateAdaptor pattern
  - `~/coding/lab/WatchTaskPoC/WatchTaskPoC/AppDelegate.swift` — PoC AppDelegate with APNs registration callbacks
  - `~/coding/lab/WatchTaskPoC/WatchTaskPoC/ContentView.swift` — PoC ContentView with device token display
  - `~/coding/lab/WatchTaskPoC/project.yml` — xcodegen config for iOS target (platforms, capabilities, deployment target)

  **External References**:
  - Apple UIApplicationDelegateAdaptor docs: https://developer.apple.com/documentation/swiftui/uiapplicationdelegateadaptor
  - Apple Push Notification entitlements: aps-environment key in .entitlements file

  **WHY Each Reference Matters**:
  - PoC WatchTaskPoCApp.swift shows the exact SwiftUI + AppDelegate bridging pattern needed for APNs
  - PoC AppDelegate.swift has the didRegisterForRemoteNotificationsWithDeviceToken callback structure to copy
  - PoC project.yml shows xcodegen config including Push Notifications capability — replicate for production

  **Acceptance Criteria**:
  - [ ] `xcodebuild -scheme DingApp build` succeeds (or project opens in Xcode without errors)
  - [ ] App has Push Notifications capability enabled
  - [ ] App has Background Modes → Remote notifications enabled
  - [ ] TokenStore persists deviceToken to UserDefaults
  - [ ] App launches in simulator showing placeholder UI

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: iOS project builds without errors
    Tool: Bash
    Preconditions: Xcode installed, project created
    Steps:
      1. Run `xcodebuild -scheme DingApp -destination 'platform=iOS Simulator,name=iPhone 16' build` in DingApp/ directory
      2. Check exit code is 0
    Expected Result: BUILD SUCCEEDED
    Failure Indicators: Compilation errors, missing entitlements
    Evidence: .sisyphus/evidence/task-3-xcode-build.txt

  Scenario: Entitlements include APNs capability
    Tool: Bash
    Preconditions: Project created
    Steps:
      1. Search for `aps-environment` in .entitlements file
      2. Verify value is "development"
    Expected Result: aps-environment entitlement present with value "development"
    Failure Indicators: Missing entitlement, wrong value
    Evidence: .sisyphus/evidence/task-3-entitlements.txt
  ```

  **Commit**: YES
  - Message: `feat(ios): scaffold Xcode project with APNs entitlements`
  - Files: `DingApp/DingApp.swift, DingApp/AppDelegate.swift, DingApp/TokenStore.swift, DingApp/ContentView.swift, DingApp/DingApp.entitlements`
  - Pre-commit: `xcodebuild build`


### Wave 2 — Core Modules (MAX PARALLEL)

- [ ] 4. CLI Core Commands: wait + notify

  **What to do**:
  - Implement `WaitCommand` (AsyncParsableCommand):
    - Accept `@Argument(parsing: .captureForPassthrough)` for the command + args after `--`
    - Optional `--title` flag for custom notification title
    - Spawn child process via `Foundation.Process` with `/usr/bin/env` as executable
    - Inherit `FileHandle.standardInput/Output/Error` for real-time passthrough
    - Forward current environment (`ProcessInfo.processInfo.environment`)
    - Measure duration with `ContinuousClock` or `Date` difference
    - On completion: create `NotificationPayload` with command name, exit code, duration
    - Send via `RelayClient.send()` (async HTTP POST)
    - Handle notification send failure gracefully: print warning to stderr, still exit with original code
    - Forward child exit code via `throw ExitCode(process.terminationStatus)`
    - Set up SIGINT/SIGTERM signal handlers to forward signals to child process
  - Implement `NotifyCommand` (AsyncParsableCommand):
    - Accept `@Argument` message string
    - Optional `--title` (default: "ding")
    - Optional `--status` (enum: success/failure/warning/info, default: info)
    - Create `NotificationPayload` with message as body, no command/exitCode/duration
    - Send via `RelayClient.send()`
  - Implement `RelayClient` (async HTTP POST):
    - Read relay URL from Config, API key from Keychain
    - Build `URLRequest` with POST, JSON body, Authorization header (Bearer token)
    - Use `URLSession.shared.data(for:)` async
    - 10-second timeout
    - Parse response: success (200-299) or throw typed error
  - Implement `KeychainService`:
    - `saveDeviceToken(_ token: String)`, `getDeviceToken() -> String`
    - `saveAPIKey(_ key: String)`, `getAPIKey() -> String`
    - `deleteAll()` for cleanup
    - Use `Security` framework (`kSecClassGenericPassword`)
    - Service: "dev.sijun.ding", separate account keys for token vs API key

  **Must NOT do**:
  - Do NOT implement setup/test/status commands (Task 7)
  - Do NOT add retry logic — single attempt, fail gracefully
  - Do NOT store credentials outside Keychain
  - Do NOT use DispatchSemaphore — use async/await throughout

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Core business logic with process spawning, signal handling, Keychain, HTTP — multiple concerns requiring careful implementation
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 5, 6)
  - **Blocks**: Tasks 7, 8, 10
  - **Blocked By**: Task 1 (needs Package.swift + models)

  **References**:

  **Pattern References**:
  - `~/coding/lab/WatchTaskPoC/WatchTaskCLI/Sources/Commands/WaitCommand.swift` — PoC wait command with Process spawning, exit code forwarding, duration measurement. REWRITE: Use async/await instead of DispatchSemaphore, add signal forwarding
  - `~/coding/lab/WatchTaskPoC/WatchTaskCLI/Sources/Commands/NotifyCommand.swift` — PoC notify command with argument parsing and status enum. REWRITE: Use async RelayClient
  - `~/coding/lab/WatchTaskPoC/WatchTaskCLI/Sources/IPCClient.swift` — PoC HTTP POST client with URLSession and JSON encoding. REWRITE: Switch to async/await, add Bearer auth header
  - `~/coding/lab/WatchTaskPoC/WatchTaskCLI/Sources/NotificationPayload.swift` — Payload model with Codable encoding — use exact same field names and encoding strategy

  **External References**:
  - Foundation.Process: https://developer.apple.com/documentation/foundation/process — Process spawning with inherited file handles, terminationStatus
  - Security framework Keychain: https://developer.apple.com/documentation/security/keychain_services — SecItemAdd/CopyMatching/Update/Delete for kSecClassGenericPassword

  **WHY Each Reference Matters**:
  - PoC WaitCommand has the exact process spawning pattern with /usr/bin/env, inherited file handles, and exit code forwarding — core pattern to replicate
  - PoC IPCClient shows the HTTP POST + JSON encoding pattern — adapt to async/await and add auth header
  - PoC NotificationPayload fields must match exactly since relay and iOS app parse the same JSON

  **Acceptance Criteria**:
  - [ ] `ding wait -- echo hello` prints "hello" to stdout and exits with code 0
  - [ ] `ding wait -- false` exits with code 1
  - [ ] `ding wait -- sh -c 'echo out; echo err >&2'` shows both stdout and stderr
  - [ ] `ding notify "test message"` sends HTTP POST with correct JSON payload
  - [ ] `ding notify "fail" --status failure` includes status "failure" in payload
  - [ ] When relay is unreachable, `ding wait -- echo hello` still exits 0 (prints warning to stderr)
  - [ ] KeychainService saves and retrieves device token correctly

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: wait command preserves exit code and stdout
    Tool: Bash
    Preconditions: CLI built, relay not required for exit code test
    Steps:
      1. Run `.build/debug/ding wait -- echo hello`
      2. Assert stdout contains "hello"
      3. Assert exit code is 0
      4. Run `.build/debug/ding wait -- false`
      5. Assert exit code is 1
      6. Run `.build/debug/ding wait -- sh -c 'exit 42'`
      7. Assert exit code is 42
    Expected Result: Exit codes 0, 1, 42 respectively
    Failure Indicators: Wrong exit code, missing stdout
    Evidence: .sisyphus/evidence/task-4-exit-codes.txt

  Scenario: notify command sends correct JSON payload
    Tool: Bash
    Preconditions: CLI built
    Steps:
      1. Start a local HTTP server (python3 -m http.server or nc -l)
      2. Configure CLI to point to local server (or mock)
      3. Run `.build/debug/ding notify "test message" --status success --title "CI"`
      4. Capture the POST body
      5. Assert JSON contains: title="CI", body="test message", status="success"
    Expected Result: Valid JSON with correct fields
    Failure Indicators: Missing fields, wrong content-type
    Evidence: .sisyphus/evidence/task-4-notify-payload.txt

  Scenario: Graceful failure when relay is unreachable
    Tool: Bash
    Preconditions: CLI built, no relay running
    Steps:
      1. Temporarily set relay URL to unreachable endpoint
      2. Run `.build/debug/ding wait -- echo hello`
      3. Assert stdout still contains "hello"
      4. Assert exit code is 0 (not relay error code)
      5. Assert stderr contains warning about notification failure
    Expected Result: Command succeeds, notification failure is non-fatal
    Failure Indicators: Non-zero exit code, no warning message
    Evidence: .sisyphus/evidence/task-4-graceful-failure.txt
  ```

  **Commit**: YES
  - Message: `feat(cli): implement wait and notify commands`
  - Files: `Sources/DingCore/Commands/WaitCommand.swift, Sources/DingCore/Commands/NotifyCommand.swift, Sources/DingCore/Services/RelayClient.swift, Sources/DingCore/Services/KeychainService.swift`
  - Pre-commit: `swift build`

- [ ] 5. Cloudflare Workers Relay with APNs + JWT + Auth

  **What to do**:
  - Implement POST /push endpoint:
    - Validate Authorization header: `Bearer <RELAY_SECRET>`
    - Parse JSON body: validate required fields (title, body) with explicit checks
    - Get or create APNs JWT (cached, see below)
    - Construct APNs payload: `{ aps: { alert: { title, body }, sound: "default" }, ding: { ...original payload } }`
    - Send to APNs: `POST https://api.push.apple.com/3/device/<token>`
    - Required headers: authorization, apns-topic, apns-push-type ("alert"), apns-priority ("10"), apns-expiration
    - Handle APNs response: 200 → return 204, 400/410 → return error with reason, 429 → return 429
    - On BadDeviceToken: try sandbox endpoint as fallback
  - Implement ES256 JWT generation:
    - Import .p8 key via Web Crypto `importKey('pkcs8', ...)`
    - Sign JWT with ECDSA P-256 + SHA-256
    - Header: `{ alg: 'ES256', kid: keyId, typ: 'JWT' }`
    - Claims: `{ iss: teamId, iat: roundedTimestamp }`
    - Round `iat` to 20-minute boundaries: `Math.floor(Date.now() / 1000 / 1200) * 1200`
  - Implement JWT caching:
    - Check KV store for cached JWT
    - If found and not expired, return cached
    - If not found, generate new, store in KV with expirationTtl: 2700 (45 min)
  - Implement GET /health endpoint (enhance from scaffolding)
  - Add CORS headers for potential web dashboard (future-proofing)

  **Must NOT do**:
  - Do NOT implement multi-device token routing (Task 13)
  - Do NOT implement webhook endpoint (Task 14)
  - Do NOT add rate limiting API (keep simple for MVP, Task 13)
  - Use single DEVICE_TOKEN from env var for now

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: Cryptographic JWT generation with Web Crypto, APNs HTTP/2 integration, error handling, KV caching — multiple complex concerns
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 4, 6)
  - **Blocks**: Tasks 8, 13, 14
  - **Blocked By**: Task 2 (needs Workers scaffolding)

  **References**:

  **Pattern References**:
  - `~/coding/lab/WatchTaskPoC/watchtask-relay/src/index.ts` — PoC relay with complete JWT generation (ES256 via Web Crypto), APNs payload construction, health endpoint. REWRITE: Add auth validation, input sanitization, KV caching, error handling improvements
  - `~/coding/lab/WatchTaskPoC/watchtask-relay/wrangler.toml` — PoC wrangler config with env var names for APNs credentials

  **External References**:
  - ruddarr/apns-worker (GitHub): https://github.com/ruddarr/apns-worker — Production-grade APNs relay showing JWT caching, sandbox fallback, device deregistration patterns
  - APNs HTTP/2 API: https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns — Required headers, payload format, response codes
  - Web Crypto importKey: https://developer.mozilla.org/en-US/docs/Web/API/SubtleCrypto/importKey — PKCS8 format for .p8 key import

  **WHY Each Reference Matters**:
  - PoC index.ts has working JWT generation code — the ES256 signing with Web Crypto is tricky and this is proven to work
  - ruddarr/apns-worker shows the sandbox fallback pattern (retry on BadDeviceToken) and KV caching with TTL
  - APNs docs clarify required vs optional headers (apns-push-type is REQUIRED since iOS 13)

  **Acceptance Criteria**:
  - [ ] `curl -X POST /push -H 'Authorization: Bearer <key>' -d '{"title":"test","body":"hello"}'` returns 204
  - [ ] Missing/wrong auth returns 401
  - [ ] Missing required fields returns 400 with error description
  - [ ] JWT is generated correctly (ES256 with P-256)
  - [ ] Consecutive requests within 20 minutes use the same cached JWT
  - [ ] Health endpoint returns `{"status":"ok"}`

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Authenticated push notification delivery
    Tool: Bash (curl)
    Preconditions: Worker running locally with wrangler dev, secrets configured in .dev.vars
    Steps:
      1. Run `curl -s -w '\n%{http_code}' -X POST http://localhost:8787/push -H 'Content-Type: application/json' -H 'Authorization: Bearer test-secret' -d '{"title":"Test","body":"Hello from curl"}'`
      2. Assert HTTP status is 204 (or 200 with success body)
      3. Check that APNs was called (via response body or logs)
    Expected Result: 204 response, notification delivered to APNs
    Failure Indicators: 4xx/5xx status, JWT generation error in logs
    Evidence: .sisyphus/evidence/task-5-push-delivery.txt

  Scenario: Unauthorized request rejected
    Tool: Bash (curl)
    Preconditions: Worker running locally
    Steps:
      1. Run `curl -s -w '\n%{http_code}' -X POST http://localhost:8787/push -d '{"title":"Test","body":"No auth"}'`
      2. Assert HTTP status is 401
      3. Run `curl -s -w '\n%{http_code}' -X POST http://localhost:8787/push -H 'Authorization: Bearer wrong-key' -d '{"title":"Test","body":"Wrong auth"}'`
      4. Assert HTTP status is 401
    Expected Result: Both requests return 401 Unauthorized
    Failure Indicators: 200/204 without valid auth
    Evidence: .sisyphus/evidence/task-5-auth-rejection.txt

  Scenario: Invalid payload returns 400
    Tool: Bash (curl)
    Preconditions: Worker running locally
    Steps:
      1. Run `curl -s -w '\n%{http_code}' -X POST http://localhost:8787/push -H 'Authorization: Bearer test-secret' -H 'Content-Type: application/json' -d '{}'`
      2. Assert HTTP status is 400
      3. Assert response body contains error about missing fields
    Expected Result: 400 with descriptive error
    Failure Indicators: 500 (unhandled), 204 (accepted empty payload)
    Evidence: .sisyphus/evidence/task-5-validation.txt
  ```

  **Commit**: YES
  - Message: `feat(relay): implement APNs relay with JWT + auth`
  - Files: `relay/src/index.ts`
  - Pre-commit: `npx wrangler dev --test-scheduled` (type-check)

- [ ] 6. iOS APNs Registration + Token Display UI

  **What to do**:
  - Implement `AppDelegate` APNs registration:
    - In `didFinishLaunchingWithOptions`: set `UNUserNotificationCenter.current().delegate = self`
    - Request notification permissions: `.alert, .sound, .badge`
    - Call `UIApplication.shared.registerForRemoteNotifications()` on permission grant
    - In `didRegisterForRemoteNotificationsWithDeviceToken`: convert Data to hex string, store in TokenStore
    - In `didFailToRegisterForRemoteNotificationsWithError`: store error in TokenStore
    - Implement `UNUserNotificationCenterDelegate.willPresent` to show notifications when app is foregrounded
  - Implement `NotificationPermissionManager`:
    - Check current authorization status
    - Request if `.notDetermined`
    - Show settings prompt if `.denied`
    - Re-register on every app launch (token may have rotated)
  - Implement `ContentView` with token display:
    - Show device token in monospaced font (truncated with full text selectable)
    - "Copy Token" button with checkmark feedback animation
    - Status indicators: permission granted, token received, last updated timestamp
    - Empty state when no token yet: prompt to grant notification permission
    - Error state when registration fails: show error + "Open Settings" button
  - Persist token to UserDefaults via TokenStore
  - Call `registerForRemoteNotifications()` on every app launch via `.onAppear`

  **Must NOT do**:
  - Do NOT add QR code, share sheet, or notification history (Task 9)
  - Do NOT implement WatchConnectivity or any Watch-specific code
  - Do NOT add custom notification sounds yet (Task 15)
  - Do NOT add notification categories yet

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: iOS app development with APNs registration, SwiftUI state management, permission flow — moderate complexity
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (with Tasks 4, 5)
  - **Blocks**: Tasks 8, 9, 11
  - **Blocked By**: Tasks 1 (shared models), 3 (Xcode project)

  **References**:

  **Pattern References**:
  - `~/coding/lab/WatchTaskPoC/WatchTaskPoC/AppDelegate.swift` — PoC AppDelegate with APNs registration, token hex conversion, UNUserNotificationCenterDelegate. REWRITE: Remove Bonjour listener startup, WatchBridge forwarding, measurement logging
  - `~/coding/lab/WatchTaskPoC/WatchTaskPoC/ContentView.swift` — PoC ContentView with token display and copy functionality. REWRITE: Remove latency measurements, simplify to token-focused UI
  - `~/coding/lab/WatchTaskPoC/WatchTaskPoC/WatchTaskPoCApp.swift` — PoC app entry point with UIApplicationDelegateAdaptor. Copy this pattern exactly

  **External References**:
  - UNUserNotificationCenter requestAuthorization: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization — Permission request flow and options
  - UIApplication registerForRemoteNotifications: https://developer.apple.com/documentation/uikit/uiapplication/registerforremotenotifications — Must call on main thread

  **WHY Each Reference Matters**:
  - PoC AppDelegate has the exact token hex conversion pattern (`Data.map { String(format: "%02.2hhx", $0) }.joined()`) — this format is what APNs expects
  - PoC ContentView shows the token display + copy UX pattern — adapt for production without measurement clutter
  - PoC App entry shows the UIApplicationDelegateAdaptor wiring — required for APNs callbacks

  **Acceptance Criteria**:
  - [ ] App builds and runs on iOS simulator (APNs registration will fail on simulator — verify error handling)
  - [ ] On physical device: notification permission dialog appears on first launch
  - [ ] Device token displayed after permission grant (physical device only)
  - [ ] "Copy Token" button copies token to clipboard with visual feedback
  - [ ] Token persists across app kills (UserDefaults)
  - [ ] Foreground notifications display as banner (willPresent delegate)
  - [ ] Denied permission state shows "Open Settings" button

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: iOS app builds for simulator
    Tool: Bash
    Preconditions: Xcode project with APNs entitlements
    Steps:
      1. Run `xcodebuild -scheme DingApp -destination 'platform=iOS Simulator,name=iPhone 16' build`
      2. Assert BUILD SUCCEEDED
    Expected Result: Clean build
    Failure Indicators: Compilation errors, missing frameworks
    Evidence: .sisyphus/evidence/task-6-ios-build.txt

  Scenario: Token display and copy functionality
    Tool: Bash (verify code structure)
    Preconditions: App code written
    Steps:
      1. Verify ContentView.swift contains UIPasteboard.general.string assignment
      2. Verify AppDelegate.swift contains didRegisterForRemoteNotificationsWithDeviceToken
      3. Verify TokenStore.swift persists to UserDefaults
      4. Search for monospaced font usage in token display
    Expected Result: All required code patterns present
    Failure Indicators: Missing clipboard code, no UserDefaults persistence
    Evidence: .sisyphus/evidence/task-6-code-review.txt

  Scenario: Error handling for simulator (no APNs)
    Tool: Bash
    Preconditions: App code written
    Steps:
      1. Verify didFailToRegisterForRemoteNotificationsWithError is implemented
      2. Verify TokenStore has @Published registrationError property
      3. Verify ContentView shows error state when registrationError is non-nil
    Expected Result: Graceful error handling for environments without APNs
    Failure Indicators: Missing error handler, crash on simulator
    Evidence: .sisyphus/evidence/task-6-error-handling.txt
  ```

  **Commit**: YES
  - Message: `feat(ios): APNs registration + token display UI`
  - Files: `DingApp/AppDelegate.swift, DingApp/ContentView.swift, DingApp/TokenStore.swift, DingApp/NotificationPermissionManager.swift`
  - Pre-commit: `xcodebuild build`

### Wave 3 — Integration + Remaining CLI + iOS Features

- [ ] 7. CLI Setup, Test, and Status Commands

  **What to do**:
  - Implement `SetupCommand`:
    - Accept `@Argument` device token string (64-char hex)
    - Validate token format (hex characters only, length check)
    - Generate random API key (32-byte hex string via `SecRandomCopyBytes`)
    - Store both in Keychain via KeychainService
    - Print success message with relay URL and next steps ("Run `ding test` to verify")
    - Option: `--api-key <key>` to provide existing API key instead of generating
  - Implement `TestCommand`:
    - Send 4 notifications sequentially with configurable delay (default 1.5s):
      1. success: "Test notification — Success"
      2. failure: "Test notification — Failure"
      3. warning: "Test notification — Warning"
      4. info: "Test notification — Info"
    - Print progress for each ("Sending 1/4... ✓")
    - Summary at end ("4/4 sent successfully" or "N/4 failed")
  - Implement `StatusCommand`:
    - Health check: GET relay /health endpoint, display response
    - Show stored device token (masked: first 8 + last 8 chars)
    - Show relay URL
    - Show API key status (stored/not stored)
    - Overall status: ✓ Ready / ✗ Not configured

  **Must NOT do**:
  - Do NOT implement shell hooks (Task 12)
  - Do NOT add QR code scanning to setup (v1.1+)

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Multiple CLI commands with validation, Keychain interaction, HTTP health checks
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 8, 9)
  - **Blocks**: Tasks 8, 12
  - **Blocked By**: Tasks 1 (models), 4 (RelayClient, KeychainService)

  **References**:

  **Pattern References**:
  - `~/coding/lab/WatchTaskPoC/WatchTaskCLI/Sources/Commands/TestCommand.swift` — PoC test command sending 4 status types with delay. REWRITE: Add progress printing, error counting
  - `~/coding/lab/WatchTaskPoC/WatchTaskCLI/Sources/Commands/StatusCommand.swift` — PoC status with GET /health check
  - `~/coding/lab/WatchTaskPoC/WatchTaskCLI/Sources/Constants.swift` — Relay URL constant

  **WHY Each Reference Matters**:
  - PoC TestCommand has the 4-status sequential send pattern with delay — replicate and enhance with progress output
  - PoC StatusCommand shows the GET /health pattern — extend with token/key status display

  **Acceptance Criteria**:
  - [ ] `ding setup <valid-64-char-hex>` stores token + generates API key in Keychain
  - [ ] `ding setup <invalid-token>` rejects with clear error message
  - [ ] `ding test` sends 4 notifications and prints progress
  - [ ] `ding status` shows token (masked), relay URL, API key status, connectivity
  - [ ] Running `ding test` without prior `ding setup` gives clear error

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Setup stores credentials and test sends notifications
    Tool: Bash
    Preconditions: CLI built, relay running
    Steps:
      1. Run `.build/debug/ding setup aaaa1111bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa1111bbbb2222`
      2. Assert exit code 0 and success message printed
      3. Run `.build/debug/ding status`
      4. Assert output shows token (masked), API key stored, relay URL
      5. Run `.build/debug/ding test`
      6. Assert output shows "Sending 1/4... Sending 2/4..." etc.
    Expected Result: Setup succeeds, status shows config, test sends 4 notifications
    Failure Indicators: Keychain error, missing fields in status, test fails to send
    Evidence: .sisyphus/evidence/task-7-setup-test-status.txt

  Scenario: Invalid token format rejected
    Tool: Bash
    Preconditions: CLI built
    Steps:
      1. Run `.build/debug/ding setup too-short`
      2. Assert non-zero exit code
      3. Assert error message mentions token format
      4. Run `.build/debug/ding setup GGGG1111bbbb2222cccc3333dddd4444eeee5555ffff6666aaaa1111bbbb2222`
      5. Assert non-zero exit code (G is not valid hex)
    Expected Result: Both rejected with descriptive error
    Failure Indicators: Accepts invalid tokens, no error message
    Evidence: .sisyphus/evidence/task-7-validation.txt
  ```

  **Commit**: YES
  - Message: `feat(cli): implement setup, test, status commands`
  - Files: `Sources/DingCore/Commands/SetupCommand.swift, Sources/DingCore/Commands/TestCommand.swift, Sources/DingCore/Commands/StatusCommand.swift`
  - Pre-commit: `swift build`

- [ ] 8. E2E Integration Testing (CLI → Relay → APNs)

  **What to do**:
  - Set up real APNs credentials in relay (sandbox environment)
  - Configure CLI with valid device token from iOS app and API key matching relay secret
  - Run full E2E flow:
    1. `ding setup <real-token>` → verify Keychain storage
    2. `ding test` → verify 4 notifications arrive on device (check relay logs)
    3. `ding wait -- sleep 2` → verify notification arrives with correct duration (~2s)
    4. `ding wait -- false` → verify failure notification with exit code 1
    5. `ding notify "E2E test" --status success` → verify custom message arrives
    6. Rapid fire: 10 notifications in quick succession → verify 10/10 delivered
  - Document relay logs showing APNs 200 responses for each test
  - Verify notification content on device (title, body, status formatting)
  - Test edge cases:
    - Very long command name (>200 chars)
    - Unicode characters in message body
    - Special characters in title (quotes, backslash)

  **Must NOT do**:
  - Do NOT automate iOS device verification (manual check of notification arrival)
  - Do NOT modify relay or CLI code — this is verification only
  - Do NOT deploy to production — use sandbox APNs

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: E2E integration across 3 systems (CLI, relay, APNs) with real credentials, multiple scenarios
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 3 (sequential dependency)
  - **Blocks**: Tasks 10, 11, 18
  - **Blocked By**: Tasks 4 (CLI commands), 5 (relay), 6 (iOS token)

  **References**:

  **Pattern References**:
  - `~/coding/lab/WatchTaskPoC/Scripts/measure-apns.sh` — PoC script for sending N notifications to relay with timing measurement. Adapt for E2E verification
  - `~/coding/lab/WatchTaskPoC/Docs/latency-report.md` — PoC latency results documenting go/no-go criteria and test methodology

  **WHY Each Reference Matters**:
  - measure-apns.sh shows the curl-based approach for sending to relay and capturing APNs response — useful for automated relay log verification
  - Latency report documents the PoC test scenarios and success criteria — replicate for production verification

  **Acceptance Criteria**:
  - [ ] 4 test notifications from `ding test` all return 200/204 from relay
  - [ ] `ding wait -- sleep 2` notification includes duration ~2s
  - [ ] `ding wait -- false` notification includes exit code 1 and "failure" status
  - [ ] 10 rapid-fire notifications: 10/10 relay responses are 200/204
  - [ ] Unicode and special characters preserved in notification body

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Full E2E pipeline verification
    Tool: Bash (curl + CLI)
    Preconditions: Relay deployed to sandbox, iOS app installed on physical device, ding setup completed
    Steps:
      1. Run `.build/debug/ding test` and capture output
      2. Assert output shows 4/4 sent successfully
      3. Check relay logs via `wrangler tail` for 4 APNs 200 responses
      4. Run `.build/debug/ding wait -- sleep 2` and capture output
      5. Assert notification sent (relay 200/204)
      6. Run `.build/debug/ding wait -- false` and capture exit code
      7. Assert exit code is 1 and notification sent
    Expected Result: All notifications delivered via APNs, exit codes preserved
    Failure Indicators: Non-200 APNs response, missing notifications, wrong exit code
    Evidence: .sisyphus/evidence/task-8-e2e-pipeline.txt

  Scenario: Burst delivery — 10 rapid-fire notifications
    Tool: Bash
    Preconditions: Relay running, CLI configured
    Steps:
      1. Run a loop sending 10 `ding notify` in rapid succession (no delay)
      2. Capture relay response for each
      3. Assert all 10 return 200/204
    Expected Result: 10/10 delivered
    Failure Indicators: TooManyProviderTokenUpdates, 429 from APNs
    Evidence: .sisyphus/evidence/task-8-burst-delivery.txt
  ```

  **Commit**: YES
  - Message: `test(e2e): verify CLI → relay → APNs pipeline`
  - Files: `.sisyphus/evidence/task-8-*.txt`
  - Pre-commit: none (evidence files only)

- [ ] 9. iOS App Store Features (QR Code, Share, Notification List)

  **What to do**:
  - Add QR code generation for device token:
    - Use `CoreImage.CIFilter.qrCodeGenerator()` — no third-party dependency
    - Display QR code at 200x200 with `.interpolation(.none)` for sharp rendering
    - White background padding for scan reliability
    - Medium error correction level
  - Add Share button:
    - SwiftUI `ShareLink(item: token)` for native share sheet
    - Subject line: "ding Device Token"
  - Add basic notification list:
    - Store received notifications in UserDefaults (last 20 for now, expanded to 50 in Task 17)
    - List view showing: title, body, status icon, timestamp
    - Color-coded status: green (success), red (failure), orange (warning), blue (info)
    - Parse incoming push payload from `userInfo["ding"]` in `didReceiveRemoteNotification`
  - Polish UI:
    - App icon placeholder
    - "ding" branding on main screen
    - Tab bar: Token | Notifications

  **Must NOT do**:
  - Do NOT add custom notification sounds (Task 15)
  - Do NOT add notification categories or actions
  - Do NOT implement Watch-specific features
  - Do NOT add settings/preferences UI

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: UI-focused task with QR code rendering, share sheet integration, list view design, color coding
  - **Skills**: [`frontend-ui-ux`]
    - `frontend-ui-ux`: SwiftUI UI/UX design and layout decisions

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 3 (with Tasks 7, 8)
  - **Blocks**: Tasks 11, 17
  - **Blocked By**: Tasks 3 (Xcode project), 6 (APNs registration + token)

  **References**:

  **Pattern References**:
  - `~/coding/lab/WatchTaskPoC/WatchTaskPoC/ContentView.swift` — PoC ContentView with token display. REWRITE: Remove latency measurements, add QR code + share + notification list

  **External References**:
  - CoreImage QR generation: `CIFilter.qrCodeGenerator()` — Native iOS QR code creation without third-party deps
  - SwiftUI ShareLink: https://developer.apple.com/documentation/swiftui/sharelink — Native share sheet integration (iOS 16+)

  **WHY Each Reference Matters**:
  - PoC ContentView has the basic token display layout — extend with QR code and share button
  - CoreImage QR is the standard iOS approach — no third-party pods needed, reviewers expect native APIs

  **Acceptance Criteria**:
  - [ ] QR code displays device token and is scannable by any QR reader
  - [ ] Share button opens system share sheet with token text
  - [ ] Received notifications appear in list with correct status colors
  - [ ] Tab bar switches between Token and Notifications views
  - [ ] App builds without new third-party dependencies

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: QR code generation and share functionality
    Tool: Bash (code verification)
    Preconditions: iOS app with token display
    Steps:
      1. Verify QR code uses CoreImage CIFilter.qrCodeGenerator()
      2. Verify .interpolation(.none) is set on QR Image view
      3. Verify ShareLink exists with item binding to device token
      4. Build app: `xcodebuild -scheme DingApp build`
    Expected Result: QR + share code present, app builds cleanly
    Failure Indicators: Third-party QR dependency, missing interpolation (blurry QR)
    Evidence: .sisyphus/evidence/task-9-qr-share.txt

  Scenario: Notification list with status color coding
    Tool: Bash (code verification)
    Preconditions: iOS app code written
    Steps:
      1. Verify notification storage uses UserDefaults
      2. Verify list view has color mapping: success=green, failure=red, warning=orange, info=blue
      3. Verify didReceiveRemoteNotification parses ding payload from userInfo
    Expected Result: Color-coded notification list with proper payload parsing
    Failure Indicators: Missing color mapping, no payload parsing
    Evidence: .sisyphus/evidence/task-9-notification-list.txt
  ```

  **Commit**: YES
  - Message: `feat(ios): add QR code, share, notification list`
  - Files: `DingApp/Views/QRCodeView.swift, DingApp/Views/NotificationListView.swift, DingApp/ContentView.swift`
  - Pre-commit: `xcodebuild build`

### Wave 4 — Distribution + Phase 2 Foundation

- [ ] 10. Homebrew Tap + Release Automation

  **What to do**:
  - Create `scripts/release.sh`:
    - Build for both architectures: `swift build -c release --triple x86_64-apple-macosx`, `swift build -c release --triple arm64-apple-macosx`
    - Combine via `lipo -create -output .build/ding ...`
    - Verify with `lipo -info .build/ding`
    - Compress: `ditto -c -k --keepParent .build/ding ding-macos.zip`
    - Compute SHA256: `shasum -a 256 ding-macos.zip`
    - Create GitHub release with `gh release create`
  - Create Homebrew Tap repository structure:
    - `homebrew-tap/Formula/ding.rb` with: desc, homepage, url (GitHub release), sha256, license
    - `install` block: `bin.install "ding"`
    - `test` block: `assert_match version.to_s, shell_output("#{bin}/ding --version")`
  - Document installation: `brew install <user>/tap/ding`
  - Add GitHub Actions workflow for automated release on tag push

  **Must NOT do**:
  - Do NOT submit to homebrew-core (use personal Tap for now)
  - Do NOT add auto-update mechanism

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Shell scripting and Homebrew formula creation — well-documented patterns
  - **Skills**: [`git-master`]
    - `git-master`: GitHub release creation and tag management

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Tasks 11, 12, 13)
  - **Blocks**: None
  - **Blocked By**: Tasks 4 (CLI implemented), 8 (E2E verified)

  **References**:

  **External References**:
  - SwiftFormat Homebrew formula: https://github.com/Homebrew/homebrew-core/blob/master/Formula/s/swiftformat.rb — Gold standard Swift CLI formula
  - Homebrew Tap docs: https://docs.brew.sh/Taps — How to create and publish a Tap

  **Acceptance Criteria**:
  - [ ] `scripts/release.sh 0.1.0` builds universal binary and creates GitHub release
  - [ ] `brew install <user>/tap/ding` installs successfully
  - [ ] `ding --version` after Homebrew install outputs `0.1.0`
  - [ ] Binary is universal: `lipo -info $(which ding)` shows x86_64 + arm64

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Universal binary build
    Tool: Bash
    Preconditions: Swift toolchain installed
    Steps:
      1. Run `scripts/release.sh 0.1.0` (or manual build steps)
      2. Run `lipo -info .build/ding`
      3. Assert output contains both "x86_64" and "arm64"
      4. Run `.build/ding --version`
      5. Assert output is "0.1.0"
    Expected Result: Universal binary with both architectures
    Failure Indicators: Single architecture only, build failure
    Evidence: .sisyphus/evidence/task-10-universal-binary.txt

  Scenario: Homebrew formula validity
    Tool: Bash
    Preconditions: Formula file created
    Steps:
      1. Run `brew audit --strict Formula/ding.rb` (if Tap repo exists)
      2. Verify formula contains: desc, homepage, url, sha256, version
      3. Verify test block exists
    Expected Result: Formula passes audit or contains required fields
    Failure Indicators: Missing required fields, audit warnings
    Evidence: .sisyphus/evidence/task-10-homebrew-formula.txt
  ```

  **Commit**: YES
  - Message: `feat(dist): Homebrew Tap + release script`
  - Files: `scripts/release.sh, homebrew-tap/Formula/ding.rb`
  - Pre-commit: `swift build -c release`

- [ ] 11. App Store Submission Prep

  **What to do**:
  - Switch `aps-environment` from "development" to "production" in release build config
  - Create App Store Connect entry:
    - App name: "ding — Command Notifier" (or similar)
    - Bundle ID: `dev.sijun.ding`
    - Category: Developer Tools
    - Privacy Policy URL (create minimal privacy policy page)
  - Prepare metadata:
    - App description explaining developer tool use case
    - Keywords: push notification, APNs, developer, CLI, terminal, command
    - Screenshots (3-4): token display, QR code, notification list, notification on lock screen
    - App Review Notes: explain this is a developer tool companion for a CLI, describe the use case
  - Create app icon (1024x1024 for App Store, @2x/@3x for device)
  - Prepare for Guideline 4.2 defense:
    - Ensure QR code, copy, share, notification list are all present
    - Review notes explaining native iOS features used
  - Archive and upload to TestFlight
  - Test on TestFlight with production APNs (different from sandbox tokens)

  **Must NOT do**:
  - Do NOT submit to App Store review yet (TestFlight beta first)
  - Do NOT add in-app purchases or subscriptions (free for v1)
  - Do NOT add analytics SDK

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: App Store prep involves entitlements, metadata, icon creation, TestFlight — multiple non-code concerns
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Tasks 10, 12, 13)
  - **Blocks**: None
  - **Blocked By**: Tasks 3 (Xcode project), 6 (APNs registration), 8 (E2E verified), 9 (App Store features)

  **References**:

  **External References**:
  - App Store Review Guidelines 4.2: https://developer.apple.com/app-store/review/guidelines/#minimum-functionality
  - App Store Connect: https://appstoreconnect.apple.com — App submission portal

  **Acceptance Criteria**:
  - [ ] Archive builds successfully with production entitlements
  - [ ] TestFlight build uploads and installs on test device
  - [ ] Production APNs token is different from sandbox token (verified)
  - [ ] Push notification arrives via production APNs path
  - [ ] App icon displays correctly on device and in App Store Connect

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Production build with correct entitlements
    Tool: Bash
    Preconditions: Xcode project with all features
    Steps:
      1. Build archive: `xcodebuild -scheme DingApp -configuration Release archive`
      2. Verify .entitlements has aps-environment = "production"
      3. Verify app icon asset catalog has all required sizes
    Expected Result: Archive builds, entitlements correct
    Failure Indicators: Build failure, sandbox entitlement in release, missing icon sizes
    Evidence: .sisyphus/evidence/task-11-archive-build.txt
  ```

  **Commit**: YES
  - Message: `feat(ios): App Store submission prep`
  - Files: `DingApp/Assets.xcassets, DingApp/DingApp.entitlements, DingApp/Info.plist`
  - Pre-commit: `xcodebuild archive`

- [ ] 12. Shell Auto-Hook (install-hook / uninstall-hook) [Phase 2]

  **What to do**:
  - Implement `InstallHookCommand`:
    - Detect current shell (SHELL env var: zsh, bash)
    - Generate hook script that:
      - Records command start time in a variable
      - On command completion, checks if elapsed time > threshold (default 30s)
      - If threshold exceeded, calls `ding notify` with command name, duration, exit code
    - For zsh: Use `preexec` and `precmd` hooks
    - For bash: Use `PROMPT_COMMAND` and `trap DEBUG`
    - Append hook source line to `~/.zshrc` or `~/.bashrc` (with guard comment: `# Added by ding`)
    - Install hook script to `~/.config/ding/hook.zsh` (or `.bash`)
    - Print instructions: "Hook installed. Restart shell or run `source ~/.zshrc`"
  - Implement `UninstallHookCommand`:
    - Remove the source line from shell RC file
    - Delete hook script file
    - Print confirmation
  - Add `--threshold <seconds>` option (default: 30) to configure minimum command duration for notification
  - Hook script must handle edge cases:
    - Nested shells
    - Commands with pipes/redirects
    - Background commands (skip notification)

  **Must NOT do**:
  - Do NOT support fish shell (v2+)
  - Do NOT modify shell behavior beyond the hook
  - Do NOT auto-install hook during `ding setup`

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Shell hook scripting across zsh/bash with preexec/precmd patterns, file system manipulation
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Tasks 10, 11, 13)
  - **Blocks**: None
  - **Blocked By**: Tasks 4 (CLI + notify command), 7 (setup for credentials)

  **References**:

  **External References**:
  - zsh hook functions: http://zsh.sourceforge.io/Doc/Release/Functions.html#Hook-Functions — preexec, precmd function signatures
  - bash PROMPT_COMMAND: https://www.gnu.org/software/bash/manual/html_node/Controlling-the-Prompt.html

  **Acceptance Criteria**:
  - [ ] `ding install-hook` adds hook to ~/.zshrc (or ~/.bashrc)
  - [ ] After sourcing, commands >30s trigger `ding notify`
  - [ ] Commands <30s do NOT trigger notification
  - [ ] `ding uninstall-hook` removes hook cleanly
  - [ ] Hook script handles commands with special characters

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Hook installation and threshold detection
    Tool: Bash
    Preconditions: CLI built with install-hook command
    Steps:
      1. Run `.build/debug/ding install-hook --threshold 2`
      2. Verify ~/.config/ding/hook.zsh exists
      3. Verify ~/.zshrc contains "# Added by ding" line
      4. Source the hook in current shell
      5. Run `sleep 3` (exceeds 2s threshold)
      6. Assert ding notify was called (check output or mock)
      7. Run `echo fast` (under 2s)
      8. Assert NO notification sent
    Expected Result: Hook triggers only for commands exceeding threshold
    Failure Indicators: Notification on fast commands, no notification on slow commands
    Evidence: .sisyphus/evidence/task-12-hook-threshold.txt

  Scenario: Hook uninstallation
    Tool: Bash
    Preconditions: Hook installed
    Steps:
      1. Run `.build/debug/ding uninstall-hook`
      2. Verify ~/.config/ding/hook.zsh is deleted
      3. Verify ~/.zshrc no longer contains "# Added by ding" line
    Expected Result: Clean removal with no leftover files
    Failure Indicators: File remains, RC line remains
    Evidence: .sisyphus/evidence/task-12-hook-uninstall.txt
  ```

  **Commit**: YES
  - Message: `feat(cli): shell auto-hook install/uninstall`
  - Files: `Sources/DingCore/Commands/InstallHookCommand.swift, Sources/DingCore/Commands/UninstallHookCommand.swift, Sources/DingCore/Resources/hook.zsh, Sources/DingCore/Resources/hook.bash`
  - Pre-commit: `swift build`

- [ ] 13. Relay Multi-Device KV Token Management [Phase 2]

  **What to do**:
  - Replace single DEVICE_TOKEN env var with Cloudflare KV-based token storage
  - Implement POST /register endpoint:
    - Accept JSON: `{ "device_token": "...", "api_key": "..." }`
    - Store device token in KV keyed by API key: `{ devices: ["token1", "token2"], seenAt: timestamp }`
    - Return 200 with confirmation
  - Update POST /push to:
    - Look up device tokens by API key from KV
    - Send to ALL registered device tokens for that API key
    - Handle per-device errors (BadDeviceToken → deregister that token)
    - Return summary: `{ sent: 2, failed: 0, tokens_removed: 0 }`
  - Implement POST /deregister endpoint:
    - Remove specific device token from API key's device list
  - Update CLI `ding setup` to call /register endpoint after storing credentials locally
  - Add rate limiting per API key (not just IP):
    - 10 pushes per minute per API key
    - 100 pushes per hour per API key

  **Must NOT do**:
  - Do NOT implement user accounts or authentication beyond API keys
  - Do NOT add admin dashboard
  - Do NOT store any personal data beyond device tokens

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: KV data model design, multi-device fan-out, error handling per device, rate limiting
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 4 (with Tasks 10, 11, 12)
  - **Blocks**: Task 14
  - **Blocked By**: Task 5 (relay with APNs)

  **References**:

  **Pattern References**:
  - ruddarr/apns-worker device management: https://github.com/ruddarr/apns-worker — KV-based device storage, deregistration on BadDeviceToken, fan-out to multiple devices

  **External References**:
  - Cloudflare KV API: https://developers.cloudflare.com/workers/runtime-apis/kv/ — get, put, delete with JSON type parsing

  **Acceptance Criteria**:
  - [ ] POST /register stores device token in KV under API key
  - [ ] POST /push sends to ALL registered devices for the API key
  - [ ] BadDeviceToken triggers automatic deregistration of that token
  - [ ] Rate limiting: 11th push within a minute returns 429
  - [ ] GET /health still works

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Multi-device registration and fan-out
    Tool: Bash (curl)
    Preconditions: Worker running with KV namespace
    Steps:
      1. Register device A: `curl -X POST /register -d '{"device_token":"aaa...","api_key":"key1"}'`
      2. Register device B: `curl -X POST /register -d '{"device_token":"bbb...","api_key":"key1"}'`
      3. Send push: `curl -X POST /push -H 'Authorization: Bearer key1' -d '{"title":"Test","body":"Multi"}'`
      4. Assert response shows sent: 2
    Expected Result: Both devices receive notification
    Failure Indicators: Only one device notified, registration failure
    Evidence: .sisyphus/evidence/task-13-multi-device.txt

  Scenario: Rate limiting enforcement
    Tool: Bash (curl)
    Preconditions: Worker running
    Steps:
      1. Send 10 push requests rapidly
      2. Assert first 10 return 200/204
      3. Send 11th request
      4. Assert 11th returns 429
    Expected Result: Rate limit kicks in after 10 requests/minute
    Failure Indicators: No rate limiting, wrong threshold
    Evidence: .sisyphus/evidence/task-13-rate-limiting.txt
  ```

  **Commit**: YES
  - Message: `feat(relay): multi-device KV token management`
  - Files: `relay/src/index.ts`
  - Pre-commit: `npx tsc --noEmit`

### Wave 5 — Phase 2 Features

- [ ] 14. Webhook Endpoint for CI/CD [Phase 2]

  **What to do**:
  - Add POST /webhook endpoint to relay:
    - Accept JSON payload: `{ "title": "...", "body": "...", "status": "success|failure|warning|info" }`
    - Authenticate via `Authorization: Bearer <api_key>` (same API key as CLI)
    - Look up device tokens by API key from KV
    - Send APNs notification to all registered devices
    - Return JSON response: `{ "sent": N, "failed": N }`
  - Document webhook usage:
    - curl example for GitHub Actions
    - curl example for GitLab CI
    - Generic script example
  - Webhook-specific features:
    - Optional `source` field in payload (e.g., "GitHub Actions", "Jenkins")
    - Source included in notification subtitle

  **Must NOT do**:
  - Do NOT add OAuth or JWT-based webhook auth (keep simple Bearer token)
  - Do NOT add webhook signature verification (HMAC) for v1
  - Do NOT add webhook retry/queue mechanism

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: API endpoint design with documentation, auth integration with existing KV system
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 5 (with Tasks 15, 16, 17)
  - **Blocks**: Task 18
  - **Blocked By**: Tasks 5 (relay base), 13 (multi-device KV)

  **References**:

  **Pattern References**:
  - `relay/src/index.ts` (from Tasks 5, 13) — Existing relay with /push endpoint and KV device lookup. Webhook reuses same APNs sending + device lookup logic

  **Acceptance Criteria**:
  - [ ] `curl -X POST /webhook -H 'Authorization: Bearer <key>' -d '{"title":"CI","body":"Build passed","status":"success"}'` returns 200 with sent count
  - [ ] Notification includes source in subtitle when provided
  - [ ] Missing auth returns 401
  - [ ] Documentation covers GitHub Actions and GitLab CI examples

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Webhook delivers notification with source
    Tool: Bash (curl)
    Preconditions: Worker running, device registered
    Steps:
      1. Run `curl -X POST /webhook -H 'Authorization: Bearer key1' -H 'Content-Type: application/json' -d '{"title":"Deploy","body":"Production deploy complete","status":"success","source":"GitHub Actions"}'`
      2. Assert response `{"sent":1,"failed":0}`
      3. Verify notification payload includes source in subtitle (check relay logs)
    Expected Result: Notification delivered with source attribution
    Failure Indicators: Missing source field, 4xx response
    Evidence: .sisyphus/evidence/task-14-webhook.txt

  Scenario: Webhook auth validation
    Tool: Bash (curl)
    Preconditions: Worker running
    Steps:
      1. Send webhook without Authorization header
      2. Assert 401 response
    Expected Result: Unauthorized without valid token
    Failure Indicators: 200/204 without auth
    Evidence: .sisyphus/evidence/task-14-webhook-auth.txt
  ```

  **Commit**: YES
  - Message: `feat(relay): webhook endpoint for CI/CD`
  - Files: `relay/src/index.ts, docs/webhook.md`
  - Pre-commit: `npx tsc --noEmit`

- [ ] 15. Custom Notification Sounds [Phase 2]

  **What to do**:
  - Create/source custom notification sounds:
    - `ding-success.caf` — pleasant chime for success
    - `ding-failure.caf` — alert tone for failure
    - `ding-warning.caf` — subtle attention tone for warning
    - `ding-info.caf` — neutral notification tone for info
  - Requirements: .caf or .aiff format, <30 seconds, Linear PCM or MA4 encoding
  - Add sound files to iOS app bundle (drag into Xcode, target membership)
  - Update relay APNs payload to include sound based on status:
    - `aps.sound: "ding-success.caf"` (for status=success)
    - `aps.sound: "ding-failure.caf"` (for status=failure)
    - etc.
  - Update CLI to pass status field to relay (already done in Task 4)
  - Verify sounds play on device for each status type

  **Must NOT do**:
  - Do NOT create sounds from scratch if royalty-free alternatives exist
  - Do NOT add sound customization UI in app

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Adding sound files to bundle + updating payload field — straightforward
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 5 (with Tasks 14, 16, 17)
  - **Blocks**: Task 16
  - **Blocked By**: Task 6 (iOS app with APNs)

  **References**:

  **External References**:
  - UNNotificationSound: https://developer.apple.com/documentation/usernotifications/unnotificationsound — Supported formats, max duration, bundle requirements

  **Acceptance Criteria**:
  - [ ] 4 sound files present in iOS app bundle
  - [ ] Each sound is <30 seconds, .caf format
  - [ ] Relay sends correct sound filename per status
  - [ ] Sounds play on device (verified via `ding test`)

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Sound files bundled and relay references correct filenames
    Tool: Bash
    Preconditions: iOS project with sound files
    Steps:
      1. Verify 4 .caf files exist in DingApp/Sounds/ directory
      2. Verify relay code maps status to sound filename correctly
      3. Build iOS app and verify sound files are in app bundle
    Expected Result: All 4 sounds bundled, relay sends correct names
    Failure Indicators: Missing sound files, wrong format, wrong filename in payload
    Evidence: .sisyphus/evidence/task-15-sounds.txt
  ```

  **Commit**: YES
  - Message: `feat(ios): custom notification sounds`
  - Files: `DingApp/Sounds/*.caf, relay/src/index.ts`
  - Pre-commit: `xcodebuild build`

- [ ] 16. watchOS Companion App [Phase 2]

  **What to do**:
  - Create watchOS target in Xcode project:
    - Minimum deployment: watchOS 10.0
    - Bundle ID: `dev.sijun.ding.watchkitapp`
    - WatchKit App companion
  - Implement `DingWatchApp.swift` entry point
  - Implement `ExtensionDelegate` with `WKApplicationDelegate`:
    - Request notification permissions on Watch
    - Handle incoming notifications
  - Implement `HapticManager`:
    - Map notification status to WKHapticType:
      - success → `.success`
      - failure → `.failure`
      - warning → `.retry`
      - info → `.notification`
    - Play haptic when notification arrives
  - Implement custom notification UI via `UNNotificationContentExtension`:
    - Show status icon (checkmark/x/warning/info)
    - Show command name and duration
    - Color-coded background per status
  - Update iOS app to handle Watch app presence:
    - When Watch app is installed, notifications go to Watch instead of mirroring
    - Ensure notification categories are registered for custom UI
  - Add notification category to relay payload: `"category": "DING_NOTIFICATION"`

  **Must NOT do**:
  - Do NOT implement WatchConnectivity for data sync (v2+)
  - Do NOT add Watch complication (v2+)
  - Do NOT add standalone Watch functionality — it's a notification-focused companion

  **Recommended Agent Profile**:
  - **Category**: `deep`
    - Reason: watchOS target creation, notification content extension, haptic mapping, cross-platform notification routing
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 5 (with Tasks 14, 15, 17)
  - **Blocks**: Task 18
  - **Blocked By**: Tasks 6 (iOS APNs), 15 (custom sounds)

  **References**:

  **Pattern References**:
  - `~/coding/lab/WatchTaskPoC/WatchTaskPoCWatch/WatchTaskPoCWatchApp.swift` — PoC Watch app entry point
  - `~/coding/lab/WatchTaskPoC/WatchTaskPoCWatch/ExtensionDelegate.swift` — PoC extension delegate with notification handling and deduplication. REWRITE: Remove WCSession code, simplify to notification-only
  - `~/coding/lab/WatchTaskPoC/WatchTaskPoCWatch/HapticManager.swift` — PoC haptic mapping (success/failure/warning/info → WKHapticType). REUSE directly
  - `~/coding/lab/WatchTaskPoC/WatchTaskPoCWatch/NotificationController.swift` — PoC notification UI controller. REWRITE: Add rich UI with status icons and colors
  - `~/coding/lab/WatchTaskPoC/WatchTaskPoCWatch/ContentView.swift` — PoC Watch content view with notification list

  **WHY Each Reference Matters**:
  - PoC HapticManager has the exact WKHapticType mapping per status — copy directly, it's validated
  - PoC ExtensionDelegate shows notification scheduling and deduplication — reuse deduplication, remove WCSession
  - PoC NotificationController is the starting point for rich notification UI

  **Acceptance Criteria**:
  - [ ] Watch app builds as companion to iOS app
  - [ ] Custom haptics play for each status type (success/failure/warning/info)
  - [ ] Custom notification UI shows status icon, command, duration
  - [ ] Notifications route to Watch when Watch app is installed
  - [ ] Watch app installs from iOS app (standard companion behavior)

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: watchOS target builds successfully
    Tool: Bash
    Preconditions: Xcode project with watchOS target
    Steps:
      1. Run `xcodebuild -scheme DingWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 10 (46mm)' build`
      2. Assert BUILD SUCCEEDED
    Expected Result: Watch app builds cleanly
    Failure Indicators: Build errors, missing frameworks
    Evidence: .sisyphus/evidence/task-16-watch-build.txt

  Scenario: HapticManager maps all status types
    Tool: Bash (code verification)
    Preconditions: Watch app code written
    Steps:
      1. Verify HapticManager has cases for: success, failure, warning, info
      2. Verify each maps to a distinct WKHapticType
      3. Verify play() function is called from notification handler
    Expected Result: All 4 status types mapped to haptics
    Failure Indicators: Missing status case, same haptic for all
    Evidence: .sisyphus/evidence/task-16-haptics.txt
  ```

  **Commit**: YES
  - Message: `feat(watchos): companion app with custom haptics`
  - Files: `DingWatch/DingWatchApp.swift, DingWatch/ExtensionDelegate.swift, DingWatch/HapticManager.swift, DingWatch/NotificationController.swift, DingWatch/ContentView.swift`
  - Pre-commit: `xcodebuild -scheme DingWatch build`

- [ ] 17. iOS Notification History View [Phase 2]

  **What to do**:
  - Expand notification storage from Task 9:
    - Increase from 20 to 50 stored notifications
    - Use Codable array stored in UserDefaults
    - Auto-prune: when exceeding 50, remove oldest
  - Enhance notification list UI:
    - Section headers by date (Today, Yesterday, Earlier)
    - Pull-to-refresh (re-read from UserDefaults)
    - Swipe-to-delete individual notifications
    - "Clear All" button in navigation bar
  - Add notification detail view:
    - Full command name (not truncated)
    - Exit code with explanation
    - Duration formatted (mm:ss or hh:mm:ss)
    - Timestamp with relative time ("2 hours ago")
    - Status badge with color
  - Add notification count badge on tab bar

  **Must NOT do**:
  - Do NOT persist to Core Data or SQLite (UserDefaults is sufficient for 50 items)
  - Do NOT add search or filtering
  - Do NOT sync notification history across devices

  **Recommended Agent Profile**:
  - **Category**: `visual-engineering`
    - Reason: UI-focused with list sections, detail view, swipe actions, date formatting
  - **Skills**: [`frontend-ui-ux`]
    - `frontend-ui-ux`: SwiftUI list design and UX patterns

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 5 (with Tasks 14, 15, 16)
  - **Blocks**: None
  - **Blocked By**: Task 9 (basic notification list)

  **References**:

  **Pattern References**:
  - `DingApp/Views/NotificationListView.swift` (from Task 9) — Basic notification list to enhance with sections, detail view, swipe actions

  **Acceptance Criteria**:
  - [ ] 50 notifications stored, oldest auto-pruned
  - [ ] Notifications grouped by date sections
  - [ ] Swipe-to-delete works
  - [ ] Detail view shows all notification fields
  - [ ] "Clear All" removes all notifications

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Notification history with sections and limit
    Tool: Bash (code verification)
    Preconditions: iOS app with notification history
    Steps:
      1. Verify UserDefaults storage key for notifications
      2. Verify auto-prune logic removes oldest when >50
      3. Verify date section headers use RelativeDateTimeFormatter or manual grouping
      4. Verify swipe-to-delete modifier exists on list rows
      5. Build app: `xcodebuild build`
    Expected Result: History view with sections, pruning, and swipe actions
    Failure Indicators: No pruning, no sections, build failure
    Evidence: .sisyphus/evidence/task-17-notification-history.txt
  ```

  **Commit**: YES
  - Message: `feat(ios): notification history view`
  - Files: `DingApp/Views/NotificationListView.swift, DingApp/Views/NotificationDetailView.swift, DingApp/Models/NotificationStore.swift`
  - Pre-commit: `xcodebuild build`

### Wave 6 — Tests + Polish

- [ ] 18. Automated Tests (Swift Testing + Wrangler)

  **What to do**:
  - Set up Swift Testing framework:
    - Add test target `DingTests` to Package.swift (depends on DingCore)
    - Create `Tests/DingTests/` directory
  - Write tests for critical paths:
    - **NotificationPayload tests**: encoding/decoding roundtrip, all status types, optional fields (nil command/exitCode/duration)
    - **KeychainService tests**: save/get/delete token, save/get/delete API key, get when not stored (throws itemNotFound)
    - **RelayClient tests**: mock URLSession, verify request format (URL, method, headers, body), verify auth header format, verify error handling for HTTP 4xx/5xx
    - **WaitCommand tests**: verify exit code forwarding (mock Process), verify notification payload fields (command, duration, exit code)
    - **SetupCommand tests**: verify token validation (valid hex, invalid chars, wrong length)
    - **Config tests**: verify relay URL and version constants
  - Set up Wrangler test for relay:
    - Create `relay/test/` directory
    - Write Vitest tests for relay endpoints:
      - Health endpoint returns correct JSON
      - Auth validation (missing, wrong, correct Bearer token)
      - Payload validation (missing fields, extra fields)
      - JWT generation produces valid ES256 token
  - Run all tests and capture output

  **Must NOT do**:
  - Do NOT mock APNs — test relay logic, not Apple's service
  - Do NOT write iOS UI tests (fragile, not worth it for v1)
  - Do NOT add code coverage requirements

  **Recommended Agent Profile**:
  - **Category**: `unspecified-high`
    - Reason: Test writing across two platforms (Swift + TypeScript) with mocking strategies
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 6 (with Task 19)
  - **Blocks**: F1-F4
  - **Blocked By**: Tasks 8 (E2E verified), 14 (webhook), 16 (Watch app)

  **References**:

  **Pattern References**:
  - `~/coding/lab/WatchTaskPoC/WatchTaskCLI/Package.swift` — PoC Package.swift for test target structure reference

  **External References**:
  - Swift Testing: https://developer.apple.com/documentation/testing — @Test macro, #expect, #require
  - Vitest: https://vitest.dev/ — For Cloudflare Workers unit tests

  **Acceptance Criteria**:
  - [ ] `swift test` passes all tests (0 failures)
  - [ ] `npx vitest run` passes all relay tests
  - [ ] NotificationPayload encoding/decoding verified
  - [ ] KeychainService CRUD operations verified
  - [ ] Token validation edge cases covered
  - [ ] Relay auth and payload validation tested

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Swift tests pass
    Tool: Bash
    Preconditions: Test target added to Package.swift
    Steps:
      1. Run `swift test`
      2. Assert exit code 0
      3. Assert output contains "Test Suite passed"
    Expected Result: All Swift tests pass
    Failure Indicators: Test failures, compilation errors
    Evidence: .sisyphus/evidence/task-18-swift-tests.txt

  Scenario: Relay tests pass
    Tool: Bash
    Preconditions: Vitest configured in relay/
    Steps:
      1. Run `npx vitest run` in relay/ directory
      2. Assert exit code 0
      3. Assert output shows all tests passing
    Expected Result: All relay tests pass
    Failure Indicators: Test failures, missing assertions
    Evidence: .sisyphus/evidence/task-18-relay-tests.txt
  ```

  **Commit**: YES
  - Message: `test: add Swift Testing + wrangler tests`
  - Files: `Tests/DingTests/*.swift, relay/test/*.test.ts, relay/vitest.config.ts`
  - Pre-commit: `swift test && cd relay && npx vitest run`

- [ ] 19. CLI Enhanced Status + Token Refresh Awareness

  **What to do**:
  - Enhance `ding status` output:
    - Add "Last notification sent" timestamp (store in UserDefaults/file)
    - Add relay version check (GET /health returns version)
    - Add CLI version check (compare with latest GitHub release)
    - Colorized output: green checkmarks for OK, red X for issues
  - Add token refresh awareness to CLI:
    - On each `ding notify`/`ding wait` send, if relay returns `{"token_invalid": true}`, print warning suggesting `ding setup` re-run
    - Store last successful send timestamp
  - Add `ding version` standalone command (in addition to --version flag)

  **Must NOT do**:
  - Do NOT add auto-update mechanism
  - Do NOT add telemetry for usage tracking

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Small enhancements to existing commands, no new complex logic
  - **Skills**: []

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 6 (with Task 18)
  - **Blocks**: None
  - **Blocked By**: Task 7 (status command base)

  **References**:

  **Pattern References**:
  - `Sources/DingCore/Commands/StatusCommand.swift` (from Task 7) — Base status command to enhance

  **Acceptance Criteria**:
  - [ ] `ding status` shows last send timestamp, relay version, CLI version
  - [ ] Output uses color (green/red) for status indicators
  - [ ] Invalid token warning shown when relay reports token issue

  **QA Scenarios (MANDATORY):**

  ```
  Scenario: Enhanced status output
    Tool: Bash
    Preconditions: CLI built with enhancements
    Steps:
      1. Run `.build/debug/ding status`
      2. Assert output contains relay URL, token status, API key status
      3. Assert output contains ANSI color codes (\033[) for colored output
    Expected Result: Rich status display with colors
    Failure Indicators: Missing fields, no color output
    Evidence: .sisyphus/evidence/task-19-enhanced-status.txt
  ```

  **Commit**: YES
  - Message: `feat(cli): enhanced status + token refresh`
  - Files: `Sources/DingCore/Commands/StatusCommand.swift, Sources/DingCore/Services/RelayClient.swift`
  - Pre-commit: `swift build`

## Final Verification Wave (MANDATORY — after ALL implementation tasks)

> 4 review agents run in PARALLEL. ALL must APPROVE. Rejection → fix → re-run.

- [ ] F1. **Plan Compliance Audit** — `oracle`
  Read the plan end-to-end. For each "Must Have": verify implementation exists (read file, curl endpoint, run command). For each "Must NOT Have": search codebase for forbidden patterns — reject with file:line if found. Check evidence files exist in .sisyphus/evidence/. Compare deliverables against plan.
  Output: `Must Have [N/N] | Must NOT Have [N/N] | Tasks [N/N] | VERDICT: APPROVE/REJECT`

- [ ] F2. **Code Quality Review** — `unspecified-high`
  Run `swift build` + `wrangler deploy --dry-run`. Review all changed files for: `as! Any`, force unwraps, empty catches, print() in production, commented-out code, unused imports. Check AI slop: excessive comments, over-abstraction, generic variable names. Verify total LOC stays under 600.
  Output: `Build [PASS/FAIL] | Swift [PASS/FAIL] | Workers [PASS/FAIL] | Files [N clean/N issues] | VERDICT`

- [ ] F3. **Real QA — Full E2E Verification** — `unspecified-high`
  Start from clean state. Build CLI from source (`swift build`). Run `ding test` and verify 4 notifications arrive (check relay logs via curl). Test `ding wait -- sleep 2` and verify notification. Test `ding wait -- false` and verify exit code 1 + failure notification. Test `ding notify "hello" --status warning`. Test 10 rapid-fire sends. Save all evidence to `.sisyphus/evidence/final-qa/`.
  Output: `Scenarios [N/N pass] | Integration [N/N] | Edge Cases [N tested] | VERDICT`

- [ ] F4. **Scope Fidelity Check** — `deep`
  For each task: read "What to do", read actual files. Verify 1:1 — everything in spec was built (no missing), nothing beyond spec was built (no creep). Check "Must NOT do" compliance. Detect cross-task contamination. Flag unaccounted changes.
  Output: `Tasks [N/N compliant] | Contamination [CLEAN/N issues] | Unaccounted [CLEAN/N files] | VERDICT`

---

## Commit Strategy

| Task | Commit Message | Key Files |
|------|---------------|-----------|
| 1 | `feat(cli): scaffold Swift Package with shared models` | Package.swift, Sources/ |
| 2 | `feat(relay): scaffold Cloudflare Workers project` | watchtask-relay/ |
| 3 | `feat(ios): scaffold Xcode project with APNs entitlements` | DingApp/ |
| 4 | `feat(cli): implement wait and notify commands` | Sources/DingCore/Commands/ |
| 5 | `feat(relay): implement APNs relay with JWT + auth` | watchtask-relay/src/ |
| 6 | `feat(ios): APNs registration + token display UI` | DingApp/ |
| 7 | `feat(cli): implement setup, test, status commands` | Sources/DingCore/Commands/ |
| 8 | `test(e2e): verify CLI → relay → APNs pipeline` | .sisyphus/evidence/ |
| 9 | `feat(ios): add QR code, share, notification list` | DingApp/ |
| 10 | `feat(dist): Homebrew Tap + release script` | Formula/, scripts/ |
| 11 | `feat(ios): App Store submission prep` | DingApp/ |
| 12 | `feat(cli): shell auto-hook install/uninstall` | Sources/DingCore/Commands/ |
| 13 | `feat(relay): multi-device KV token management` | watchtask-relay/src/ |
| 14 | `feat(relay): webhook endpoint for CI/CD` | watchtask-relay/src/ |
| 15 | `feat(ios): custom notification sounds` | DingApp/Sounds/ |
| 16 | `feat(watchos): companion app with custom haptics` | DingWatch/ |
| 17 | `feat(ios): notification history view` | DingApp/ |
| 18 | `test: add Swift Testing + wrangler tests` | Tests/, watchtask-relay/test/ |
| 19 | `feat(cli): enhanced status + token refresh` | Sources/DingCore/ |

---

## Success Criteria

### Verification Commands
```bash
swift build                              # Expected: Build Succeeded
swift build -c release                   # Expected: Build Succeeded (release)
.build/debug/ding --version              # Expected: 0.1.0
.build/debug/ding wait -- echo hello     # Expected: "hello" + exit 0 + notification
.build/debug/ding wait -- false          # Expected: exit 1 + failure notification
.build/debug/ding notify "test"          # Expected: notification arrives
.build/debug/ding test                   # Expected: 4 notifications arrive
.build/debug/ding status                 # Expected: relay reachable, token valid
curl -X POST relay-url/push -H "..."    # Expected: 204 No Content + notification
wrangler deploy --dry-run                # Expected: success
xcodebuild -scheme DingApp build         # Expected: BUILD SUCCEEDED
```

### Final Checklist
- [ ] All "Must Have" items verified present
- [ ] All "Must NOT Have" items verified absent
- [ ] CLI builds as universal binary (arm64 + x86_64)
- [ ] Relay deployed to Cloudflare Workers production
- [ ] iOS app builds and registers for APNs
- [ ] 10/10 rapid-fire delivery test passes
- [ ] Exit code preservation verified (0 and non-0)
- [ ] Stdout/stderr passthrough works in real-time
- [ ] Keychain stores token + API key (no plaintext)
- [ ] Shell hook installs/uninstalls cleanly (Phase 2)
- [ ] Webhook endpoint accepts and delivers (Phase 2)
- [ ] Watch app shows correct haptic per status (Phase 2)
