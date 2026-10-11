# VertCam

A menu-bar camera for macOS that records vertical video. Click the icon for a live preview, then
take a photo or record a video in 9:16, 4:5, 3:4 or 1:1, at 720p to 4K and 23.98, 24, 30 or 60 fps.

- **Orientation.** The button beside the aspect picker (or R) turns the frame on its side: 9:16
  becomes 16:9, 4:5 becomes 5:4.
- **A camera mounted sideways.** ⋯ → Turn Picture turns its picture upright, remembered per camera,
  so a camera on its side records full-frame vertical video.
- **Microphone.** The mic button picks any connected microphone, the system default, or no sound.
- **The most real pixels.** For each aspect and frame rate VertCam picks the camera mode that keeps
  the most of the sensor: on a MacBook camera, 9:16 uses its native 1080×1920 mode. Rates a camera
  can't deliver are greyed out, and sizes above its real pixels are marked "upscaled".
- **Searchable files.** Captures go to `~/Pictures/VertCam`, named with the camera, aspect,
  resolution and frame rate: `VertCam 2026-10-11 01.18.09 cam-link-4k 9x16 1080p 30fps.mp4`.
  Click one in the strip to view or play it in place; drag it out to share.

Video is H.264 with AAC sound in an `.mp4`; photos are JPEG. Drag the popover off the menu bar to
keep it open as a window.

## Requirements

- macOS 14 or later, Apple silicon or Intel
- Xcode or the Command Line Tools (`xcode-select --install`), for Swift 5.9 or later

## Build and install

```sh
./scripts/install.sh   # build, sign, copy to /Applications and launch
./scripts/build.sh     # only build build/VertCam.app
```

`swift run` works for a quick try, but the bare binary borrows your terminal's camera and
microphone permission. The scripts build a real app with its own permissions and icon.

The build is signed with your Developer ID if your keychain has one. Without one it is signed ad
hoc, which runs the same, but macOS asks for camera permission again after each rebuild.

## Permissions

VertCam asks for the camera the first time you open it, and for the microphone the first time
you record with sound. If you said no, turn it back on in System Settings → Privacy & Security →
Camera (or Microphone). Without microphone access, videos record without sound and VertCam says
so.

A MacBook's own camera is off while its lid is closed. VertCam then uses another connected
camera, and tells you if you pick the built-in one.

## Scripted capture

With no window, VertCam captures once, prints the saved file's path and quits:

```sh
open -n -W --stdout /dev/stdout /Applications/VertCam.app --args \
  --record 5 --aspect 9:16 --res 1080 --fps 24 --camera "Cam Link" --mic Scarlett
```

`--photo` takes a photo instead. `--aspect` takes either orientation (`9:16` or `16:9`), and
`--rotate 90` turns the picture. `--camera` and `--mic` match part of a device's name. Scripted
runs never change the settings the app remembers.

## Testing

`./scripts/test.sh [camera]` takes real photos in every aspect and records at 24 and 30 fps, then
checks each file's size, frame rate and sound. It needs a camera that does both rates, a
microphone, and `ffprobe` (`brew install ffmpeg`), and it saves its captures to
`~/Pictures/VertCam`.

## License

MIT
