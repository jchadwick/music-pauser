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
- Optional **MQTT integration** with Home Assistant auto-discovery

## MQTT Integration

MusicPauser can publish its state to an MQTT broker and receive playback commands. Open the menu bar icon and choose **MQTT Settings** to configure.

### Settings

| Setting | Default | Description |
|---|---|---|
| Host | — | MQTT broker hostname or IP |
| Port | `1883` | Broker port (`8883` for TLS) |
| TLS | off | Enable TLS/SSL |
| Username / Password | — | Broker credentials (password stored in Keychain) |
| Topic prefix | `musicpauser` | Root of all topics |
| Device name | machine hostname | Appended to the prefix: `<prefix>/<device>` |
| Client ID | auto-generated | Unique MQTT client identifier |
| Publish HA discovery | on | Emit Home Assistant auto-discovery configs on connect |

### Topics

All topics share the base `<prefix>/<device>` (e.g. `musicpauser/my-mac`).

| Topic | Direction | Payload | Notes |
|---|---|---|---|
| `…/availability` | published | `online` / `offline` | Retained; LWT sends `offline` |
| `…/mic/state` | published | `ON` / `OFF` | Retained |
| `…/player/state` | published | `playing` / `stopped` | Retained |
| `…/player/attributes` | published | `{"player":"spotify"}` | Retained; `null` when nothing is playing |
| `…/command` | subscribed | see below | QoS 1 |

### Sending commands

Publish to `…/command` in either format:

**Plain text**
```
play
pause
stop
toggle
pause/spotify
play/applemusic
```

**JSON**
```json
{"action": "pause", "player": "spotify"}
{"action": "play"}
```

Supported actions: `play`, `pause`, `stop`, `toggle`.  
Supported players: `spotify`, `applemusic` (also `apple_music`, `apple-music`, `music`, `apple`).  
Omitting the player targets all active players.

### Home Assistant auto-discovery

When **Publish HA discovery** is enabled, MusicPauser publishes three entities to `homeassistant/…` on every connect:

| Entity | Type | Purpose |
|---|---|---|
| Microphone In Use | `binary_sensor` | `ON` while any app is recording |
| Music Player | `sensor` | `playing` / `stopped`; `player` attribute names the active app |
| Playback Command | `select` | Send `play`, `pause`, `stop`, or `toggle` from the HA UI |

All entities appear under a single **MusicPauser** device in Home Assistant and respect the availability topic, so they show as *unavailable* when the app is not running.

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
