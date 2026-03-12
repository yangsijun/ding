# homebrew-tap

Homebrew Tap for [ding](https://github.com/yangsijun/ding) — a CLI tool that sends push notifications to iPhone/Apple Watch when terminal commands complete.

## Installation

```bash
brew tap yangsijun/tap
brew install ding
```

## Usage

```bash
# Notify when a command completes
ding wait -- npm run build

# Send a manual notification
ding notify "Deployment complete" --status success

# Set up with your iPhone token
ding setup <device-token>
```

## Updating

```bash
brew upgrade ding
```
