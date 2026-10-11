# BetterBooth: notes for coding agents

BetterBooth is a macOS 14+ menu-bar camera in Swift: a SwiftPM executable packaged into an app
by `scripts/build.sh` (no Xcode project). To *use* the app from an agent, read
[`skills/betterbooth/SKILL.md`](skills/betterbooth/SKILL.md). This file is for changing it.

## Layout

| File | Owns |
|---|---|
| `Sources/BetterBooth/Camera.swift` | `Config`, the capture session, rendering, the feed state, photos, `Recorder` |
| `Sources/BetterBooth/ContentView.swift` | The popover UI and the in-place capture viewer |
| `Sources/BetterBooth/Library.swift` | `~/Pictures/BetterBooth`: file names, the recent-captures list |
| `Sources/BetterBooth/main.swift` | The menu-bar item, popover, quit handling, and command-line capture |
| `scripts/` | `build.sh` (universal, signed), `install.sh`, `test.sh`, `release.sh`, `make-icon.swift` |

## Invariants

Each of these fixed a real bug. Keep them when changing the code.

- **One config, one apply.** Every setting lives in `Config`, and `Camera.apply()` is the only
  place the session, format and render state are brought in line with it. Add a setting as a
  `Config` field, never as a separate property with its own update path.
- **One buffer for everything.** Each frame is mirrored, then rotated, then cropped and scaled
  once (`render`), then the background blur and brightening are applied; the person mask for the
  blur goes through the same `place` steps as the picture. The preview, the recording and photos all use that buffer, so what you see is
  what is saved.
- **Frame duration is clamped to the format's range.** An out-of-range duration raises an
  Objective-C exception Swift can't catch (this crashed on the Cam Link 4K). Set the format and
  durations again after `startRunning()` and after the mic joins, because both reset them.
- **The microphone is in the session whenever the camera runs with sound on** (`updateMic`), so
  its level shows before recording. It joins before `startRunning()`, because joining a running
  session pauses the camera for most of a second, and it never changes during a recording.
- **One gesture rule in the UI.** A click turns an on/off control on or off (the camera and ⋯
  menus just open); a right-click shows its
  choices (`.contextMenu`). Picking a choice also turns the control on.
- **Location is off by default** and is only written when the person turns on Save Location:
  EXIF GPS in photos, an ISO 6709 `location` tag in videos. Scripted runs never save it.
- **Timestamps.** Samples more than 1 s off the host clock are dropped (a Continuity Camera's
  first frames can be minutes off), and video and audio appends must strictly increase.
- **The feed state comes from frames that actually arrive.** It is live, waiting, black,
  suspended (lid closed) or no camera. A black picture is a hint and still captures.
- **A stand-in camera is never saved.** If the chosen camera is unplugged or suspended, another
  stands in, and the chosen one comes back when it reappears.
- **Command-line captures never persist.** `Camera(persists:)` is fixed at init, because init
  itself can switch cameras and save.
- **Fail closed.** An unknown command-line option or an invalid value is an error naming the
  valid ones, never a capture with defaults.

## Verify on real hardware

Builds prove nothing about a camera app. Before calling a change done:

```sh
./scripts/build.sh                      # universal app in build/
./scripts/test.sh [camera]              # real captures: sizes, frame rates, sound (needs ffprobe)
build/BetterBooth.app/Contents/MacOS/BetterBooth --list
```

`test.sh` writes into `~/Pictures/BetterBooth`; move what it made to the Trash afterwards. For
a UI change, look at the popover itself: open it from the menu bar and take a screenshot.
Cameras are shared hardware, so a capture fails or stutters while another app holds the same
camera. Check that before blaming the code.

## Release

Bump `CFBundleShortVersionString` in `Resources/Info.plist`, merge to `main`, then, from a clean
checkout of `main`:

```sh
APPLE_ID=… APPLE_TEAM_ID=… APPLE_APP_SPECIFIC_PASSWORD=… ./scripts/release.sh notes.md
```

It builds with a secure timestamp, notarizes, staples, and publishes `v<version>` on GitHub.
`docs/preview.png` shows the real popover with a synthetic picture; never put a real camera
capture or anyone's screen in the repo.
