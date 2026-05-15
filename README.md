# MusicPauser

A minimal macOS menu bar app that automatically pauses Apple Music and Spotify when your microphone is in use — and resumes them when you're done.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/jchadwick/music-pauser/main/install.sh | bash
```

This downloads the latest release, replaces any existing installation, clears the Gatekeeper quarantine flag, and launches the app.

On first launch, macOS will ask if MusicPauser can control Apple Music and Spotify via AppleScript. Click **OK** for each. If you miss a prompt, go to **System Settings → Privacy & Security → Automation** and enable the permissions there.

## How it works

MusicPauser listens to all audio input devices via CoreAudio. When any device starts recording (Zoom, Teams, QuickTime, Voice Memos, etc.), it pauses whichever player(s) are currently playing. When recording stops, it resumes them — but only if it was the one that paused them (so manual pauses are respected).

If both Apple Music and Spotify are playing at the same time, both are paused and both are resumed.

## Features

- Supports **Apple Music** and **Spotify**
- Monitors **all** input devices, not just the system default — catches virtual devices like `ZoomAudioDevice`
- Auto-resume is on by default but can be toggled
- Launch at login support
- No Dock icon — lives entirely in the menu bar
- Menu bar icon reflects current state:
  - `mic.slash + ▶` — mic idle, music playing
  - `mic + ⏸` — mic active, music paused

## Requirements

- macOS 13 Ventura or later
- Apple Music and/or Spotify

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
