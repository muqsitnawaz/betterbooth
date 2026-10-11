# BetterBooth

[![Latest release](https://img.shields.io/github/v/release/muqsitnawaz/betterbooth?label=version&color=2563eb)](https://github.com/muqsitnawaz/betterbooth/releases/latest)
[![Free and open source](https://img.shields.io/badge/price-free-16a34a)](LICENSE)
[![MIT license](https://img.shields.io/github/license/muqsitnawaz/betterbooth?color=16a34a)](LICENSE)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111827?logo=apple)](#requirements)
[![Apple silicon and Intel](https://img.shields.io/badge/Apple%20silicon%20%2B%20Intel-universal-111827)](#requirements)

A better Photo Booth that lives in your menu bar and records vertical video. Click the icon for a
live preview, then take a photo or record a video in 9:16, 4:5, 3:4 or 1:1, at 720p to 4K and
23.98, 24, 30 or 60 fps.

<p align="center"><img src="docs/preview.png" width="600" alt="BetterBooth's popover under the menu bar: a 9:16 live preview, the aspect picker, resolution and frame rate, and recent captures"></p>

Download the latest signed and notarized app from
[Releases](https://github.com/muqsitnawaz/betterbooth/releases/latest), unzip it and move it to
Applications.

- **Orientation.** The button beside the aspect picker (or R) turns the frame on its side: 9:16
  becomes 16:9, 4:5 becomes 5:4.
- **A camera mounted sideways.** ⋯ → Turn Picture turns its picture upright, remembered per camera,
  so a camera on its side records full-frame vertical video.
- **Microphone.** The mic button picks any connected microphone, the system default, or no sound.
- **The most real pixels.** For each aspect and frame rate BetterBooth picks the camera mode that keeps
  the most of the sensor: on a MacBook camera, 9:16 uses its native 1080×1920 mode. Rates a camera
  can't deliver are greyed out, and sizes above its real pixels are marked "upscaled".
- **Searchable files.** Captures go to `~/Pictures/BetterBooth`, named with the camera, aspect,
  resolution and frame rate: `BetterBooth 2026-10-11 01.18.09 cam-link-4k 9x16 1080p 30fps.mp4`.
  Click one in the strip to view or play it in place; drag it out to share.

Video is H.264 with AAC sound in an `.mp4`; photos are JPEG. Drag the popover off the menu bar to
keep it open as a window.

## Works with

- **Your iPhone, wirelessly.** With Continuity Camera, your iPhone shows up as a camera: shoot
  vertical photos and video on the iPhone's camera while working on your Mac.
- **The MacBook camera, vertical for real.** 9:16 uses the camera's native 1080×1920 mode
  instead of cutting a strip out of a landscape frame.
- **Capture cards.** An HDMI capture card such as the Elgato Cam Link 4K turns a mirrorless or
  DSLR camera into a source, at up to 60 fps.
- **USB webcams and audio interfaces.** Any camera and any microphone macOS sees.
- **A camera mounted on its side.** Turn its picture upright once and the full sensor becomes a
  vertical frame; BetterBooth remembers it for that camera.
- **A closed MacBook lid.** The built-in camera is off, so BetterBooth uses another connected
  camera and switches back to your choice when it returns.

## For AI agents

BetterBooth captures from the command line without a window, which makes it a camera an agent
can call: one command, the saved file's path on stdout, a reason and exit code 1 on failure.
[`skills/betterbooth/SKILL.md`](skills/betterbooth/SKILL.md) is a ready-made skill to give your
agent; copy the folder into your agent's skills directory (for Claude Code,
`~/.claude/skills/`). Agents changing the code start at [`AGENTS.md`](AGENTS.md).

## Requirements

- macOS 14 or later, Apple silicon or Intel
- Xcode or the Command Line Tools (`xcode-select --install`), for Swift 5.9 or later

## Build and install

```sh
./scripts/install.sh   # build, sign, copy to /Applications and launch
./scripts/build.sh     # only build build/BetterBooth.app
./scripts/release.sh notes.md   # notarize and publish the Info.plist version on GitHub
```

`swift run` works for a quick try, but the bare binary borrows your terminal's camera and
microphone permission. The scripts build a real app with its own permissions and icon.

The build is signed with your Developer ID if your keychain has one. Without one it is signed ad
hoc, which runs the same, but macOS asks for camera permission again after each rebuild.

## Permissions

BetterBooth asks for the camera the first time you open it, and for the microphone the first time
you record with sound. If you said no, turn it back on in System Settings → Privacy & Security →
Camera (or Microphone). Without microphone access, videos record without sound and BetterBooth says
so.

A MacBook's own camera is off while its lid is closed. BetterBooth then uses another connected
camera, and tells you if you pick the built-in one.

## Scripted capture

With no window, BetterBooth captures once, prints the saved file's path and quits:

```sh
BB=/Applications/BetterBooth.app/Contents/MacOS/BetterBooth
$BB --list                                    # cameras and microphones
$BB --photo --aspect 9:16 --camera iphone
$BB --record 5 --aspect 9:16 --res 1080 --fps 24 --camera "cam link" --mic scarlett
```

`--aspect` takes either orientation (`9:16` or `16:9`), and `--rotate 90` turns the picture.
`--camera` and `--mic` match part of a device's name. An unknown option or invalid value is an
error that lists the valid ones. Scripted runs never change the settings the app remembers. The full reference is in
[`skills/betterbooth/SKILL.md`](skills/betterbooth/SKILL.md).

## Testing

`./scripts/test.sh [camera]` takes real photos in every aspect and records at 24 and 30 fps, then
checks each file's size, frame rate and sound. It needs a camera that does both rates, a
microphone, and `ffprobe` (`brew install ffmpeg`), and it saves its captures to
`~/Pictures/BetterBooth`.

## License

MIT
