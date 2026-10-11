---
name: betterbooth
description: Take a photo or record a video from a Mac's cameras with one shell command, and get the file's path back. Use it when a task needs a picture or a clip from the built-in camera, an iPhone through Continuity Camera, a USB webcam or an HDMI capture card, in vertical (9:16, 4:5, 3:4), square or landscape framing.
---

# BetterBooth

BetterBooth is a free, open-source menu-bar camera for macOS
([github.com/muqsitnawaz/betterbooth](https://github.com/muqsitnawaz/betterbooth)). The same app
captures from the command line without opening a window:

```sh
/Applications/BetterBooth.app/Contents/MacOS/BetterBooth --photo --aspect 9:16
# prints: /Users/you/Pictures/BetterBooth/BetterBooth 2026-10-11 09.41.52 iphone 9x16 1080p.jpg
```

## Why use it instead of ffmpeg or imagesnap

- **One line out, one exit code.** Success prints the saved file's absolute path and exits 0.
  Failure prints `error: <reason>` and exits 1, so you never parse a log or guess whether a file
  was written.
- **It waits for a real picture.** It waits for the camera to deliver live frames (up to 6
  seconds), then lets exposure settle for a second before capturing. ffmpeg's `-f avfoundation`
  can hang with no output when a camera sends nothing (a closed MacBook lid, for one). BetterBooth
  says why instead: `error: MacBook Pro Camera is off while the lid is closed`.
- **Framing is done for you.** Ask for `9:16` and you get a centred 9:16 crop at the size you
  asked for. BetterBooth picks the camera mode that keeps the most real pixels: the MacBook camera
  has a native 1080×1920 portrait mode, so vertical photos are not cut from a landscape frame.
- **Cameras by name, not index.** `--camera iphone`, `--camera "cam link"`: part of the name is
  enough, and `--list` prints every camera and microphone.
- **Video with synced sound.** H.264 + AAC `.mp4`, picture and sound on one clock, at 23.98,
  24, 30 or 60 fps, from any connected microphone.
- **Strict input.** An invalid value is an error that names the valid ones (`error: --fps takes
  23.98, 24, 30 or 60`), never a silent fallback.
- **It leaves the person's setup alone.** Command-line captures never change the camera,
  rotation or other settings the app remembers.

## Install

Download the zip from
[Releases](https://github.com/muqsitnawaz/betterbooth/releases/latest), unzip it and move
`BetterBooth.app` to `/Applications`. It is signed and notarized, and needs macOS 14 or later on
Apple silicon or Intel. The first capture asks the person for camera access, and the first
recording with sound asks for microphone access. Those prompts need a human click.

## Commands

| Command | What it does |
|---|---|
| `--list` | Prints the cameras and microphones, marking a camera that is off |
| `--photo` | Saves a JPEG |
| `--record <seconds>` | Saves an `.mp4` with sound |

Options for `--photo` and `--record`:

| Option | Values | Default |
|---|---|---|
| `--aspect` | `9:16` `4:5` `3:4` `1:1` `16:9` `5:4` `4:3` | the app's setting (9:16 out of the box) |
| `--res` | `720` `1080` `1440` `2160` (the short side) | the app's setting (1080) |
| `--fps` | `23.98` `24` `30` `60` | the app's setting (30) |
| `--camera <name>` | part of a name from `--list` | the person's chosen camera |
| `--mic <name>` | part of a name from `--list`; turns sound on | the app's microphone setting (on, system default) |
| `--rotate <degrees>` | `0` `90` `180` `270`, clockwise | that camera's saved rotation |

Anything you leave out follows the app's own settings, including whether sound is recorded and
mirroring (on by default, like a selfie camera).

## Cases it handles

- **iPhone as a camera.** Continuity Camera shows up as "<Name>'s iPhone Camera". It is wireless
  and can drop out between sessions; a capture then fails with `error: No picture from ... yet`
  instead of hanging, so retry.
- **Vertical from a landscape camera.** `--aspect 9:16` crops the centre of the frame.
- **A camera mounted on its side.** `--rotate 90` (or `270`) turns the picture first, so the
  full sensor becomes an upright vertical frame instead of a narrow strip.
- **A capture card.** An HDMI capture card such as the Elgato Cam Link 4K turns any camera with
  HDMI out into a source, at up to 60 fps.
- **A closed MacBook lid.** The built-in camera is off, so BetterBooth uses another connected
  camera. Ask for the built-in one explicitly and it reports that the lid is closed.
- **A rate the camera can't do.** It records at the nearest rate the camera supports, and the
  file name says which.

## Output

Files go to `~/Pictures/BetterBooth`, named so `ls` or Spotlight finds them:

```
BetterBooth 2026-10-11 09.41.52 cam-link-4k 9x16 1080p.jpg
BetterBooth 2026-10-11 09.40.31 cam-link-4k 9x16 1080p 30fps.mp4
```

A recording starts once the microphone has joined, so a `--record 5` file runs about half a
second short of 5 seconds.

## Recipes

```sh
BB=/Applications/BetterBooth.app/Contents/MacOS/BetterBooth

# What's connected?
$BB --list

# A vertical photo from the iPhone, retrying once if Continuity Camera drops out
f=$($BB --photo --camera iphone --aspect 9:16) || f=$($BB --photo --camera iphone --aspect 9:16)

# A 10-second vertical clip at 60 fps from a capture card, with the USB interface's sound
$BB --record 10 --camera "cam link" --aspect 9:16 --res 1080 --fps 60 --mic scarlett

# Check what you got
ffprobe -v error -show_entries stream=codec_type,width,height,r_frame_rate -of csv "$f"
```
