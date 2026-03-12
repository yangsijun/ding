# ding

Terminal command notifications on your iPhone and Apple Watch.

`ding wait -- npm run build` — walk away, get a push notification when it's done.

## How It Works

```
CLI (ding) → Cloudflare Workers → APNs → iPhone → Apple Watch
```

No Mac app needed. No local server. One CLI binary and a Cloudflare relay.

## Features

- **Command wrapping** — `ding wait -- <command>` notifies on completion with exit status
- **Shell hook** — Auto-notify when any command runs longer than a threshold (default 30s)
- **AI coding tool hooks** — Claude Code, Gemini CLI, OpenCode integration
- **Custom notifications** — `ding notify "deployed" --status success`
- **iOS app** — Notification history, mute toggle, grouped by date
- **Apple Watch** — Automatic mirroring via iOS visible push

## Installation

### Homebrew

```bash
brew tap yangsijun/tap
brew install ding
```

### GitHub Releases

Download the latest universal binary from [Releases](https://github.com/yangsijun/ding/releases):

```bash
curl -sL https://github.com/yangsijun/ding/releases/latest/download/ding-0.1.0-macos.zip -o ding.zip
unzip ding.zip
sudo mv ding /usr/local/bin/
```

### Build from Source

```bash
git clone https://github.com/yangsijun/ding.git
cd ding
swift build -c release
sudo cp .build/release/ding /usr/local/bin/
```

## Setup

### 1. Install the iOS app

Install the Ding app on your iPhone. The app will request notification permissions and display a device token.

### 2. Register your device

```bash
ding setup <device-token>
```

The 64-character hex token is shown in the iOS app.

### 3. Test it

```bash
ding test
```

You should receive 4 test notifications (success, failure, warning, info).

## Usage

### Wrap a command

```bash
ding wait -- npm run build
ding wait -- python train.py
ding wait -- make test
```

Runs the command, sends a notification with the result when it finishes.

### Send a notification

```bash
ding notify "Deployment complete" --status success
ding notify "Build failed" --status failure
```

### Shell hook (auto-notify long commands)

```bash
ding hook install           # default threshold: 30s
ding hook install -t 10     # notify after 10s+
```

Any command that runs longer than the threshold automatically sends a notification. No `ding wait` needed.

### AI coding tool hooks

```bash
ding hook install claude    # Claude Code
ding hook install gemini    # Gemini CLI
ding hook install opencode  # OpenCode
```

Notifies when AI agent tasks complete.

### Check status

```bash
ding status                 # CLI config & relay connectivity
ding hook status            # installed hooks
```

## Architecture

| Component | Tech | Location |
|-----------|------|----------|
| CLI | Swift + ArgumentParser | `Sources/` |
| Relay | Cloudflare Workers | `relay/` |
| iOS App | SwiftUI | `Ding/` |
| OpenCode Plugin | TypeScript | `opencode-plugin/` |

## License

MIT
