# MusicPauser

A minimal macOS menu bar app that automatically pauses Apple Music when your microphone is in use — and resumes it when you're done.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/jchadwick/music-pauser/main/install.sh | bash
```

This downloads the latest release, replaces any existing installation, clears the Gatekeeper quarantine flag, and launches the app.

On first launch, macOS will ask if MusicPauser can control Apple Music via AppleScript. Click **OK**. If you miss it, go to **System Settings → Privacy & Security → Automation** and enable it there.

## How it works

MusicPauser listens to all audio input devices via CoreAudio. When any device starts recording (Zoom, Teams, QuickTime, Voice Memos, etc.), it pauses Apple Music. When recording stops, it resumes playback — but only if it was the one that paused it (so manual pauses are respected).

## Features

- Monitors **all** input devices, not just the system default — catches virtual devices like `ZoomAudioDevice`
- Auto-resume is on by default but can be toggled
- Launch at login support
- No Dock icon — lives entirely in the menu bar
- Menu bar icon reflects current state:
  - `mic.slash + ▶` — mic idle, music playing
  - `mic + ⏸` — mic active, music paused

## Requirements

- macOS 13 Ventura or later
- Apple Music

## Build from source

Requires Xcode 15+.

```bash
git clone https://github.com/jchadwick/music-pauser.git
cd music-pauser
xcodebuild \
  -project MusicPauser.xcodeproj \
  -scheme MusicPauser \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=YES \
  CODE_SIGNING_ALLOWED=YES \
  build
open build/Build/Products/Release/MusicPauser.app
```

## License

MIT
