# Charmera Fixer

A small macOS app that imports photos and videos from a Kodak Charmera keychain camera and fixes the metadata it gets wrong. Plug the camera in, check the list and click Import.

It's a native port of [kodak-charmera-exif-fixer](https://github.com/RAIT-09/kodak-charmera-exif-fixer) by RAIT-09.

## What it fixes

| File | Problem | Fix |
|---|---|---|
| Photo | EXIF dates look like `2026:03:03:12:16:29` | Rewritten as `2026:03:03 12:16:29` |
| Photo | EXIF says 640×480, the image is 1440×1080 | EXIF size set to the real size |
| Photo | Corrupt MakerNote stops EXIF from being written | EXIF block rebuilt first |
| Video | Embedded date is always 2010-06-29 | Date set to when recording started |
| Video | Motion JPEG AVI with PCM audio | Converted to H.264/AAC MP4 |

Files are copied to `~/Pictures/KodakCharmera` (configurable) as `IMG_yyyyMMdd_HHmmss.jpg` and `VID_yyyyMMdd_HHmmss.mp4`, with their file dates set to when they were taken. Nothing on the camera is changed.

The camera stamps each video's file with the time recording stopped. The app subtracts the clip length to get the start time.

## Install

Install the tools the app runs:

```sh
brew install exiftool ffmpeg
```

Download the zip from the latest [release](../../releases/latest), unzip it and move `Charmera Fixer.app` to `/Applications`.

The app isn't notarized, so macOS blocks it the first time. Either allow it in System Settings › Privacy & Security › "Open Anyway", or run:

```sh
xattr -dr com.apple.quarantine "/Applications/Charmera Fixer.app"
```

## Usage

- Open the app and plug in the camera. It picks up any mounted volume with a `DCIM` folder. ⌘O opens a folder of files copied off the camera instead.
- "Open when camera connects" installs a LaunchAgent that opens the app when a volume named `Untitled` with a `DCIM` folder mounts.
- Dates come from the camera's clock. If they're off, set it on the camera: On/Off button, calendar icon, Play/OK, then SET DATE.

## Build

Requires macOS 14+ and Xcode (Swift 6).

```sh
swift test
./scripts/build-app.sh            # builds build/Charmera Fixer.app (universal)
./scripts/build-app.sh --install  # also copies it to /Applications
```

The end-to-end test generates Charmera-style files with ffmpeg and exiftool, and is skipped when they aren't installed.

## Release

Versions are git tags (`v1.2.3`). The build stamps the latest tag into the app, and the commit count as its build number.

```sh
./scripts/release.sh 1.2.3
```

From a clean `main`, this runs the tests, builds the app, zips it, tags and pushes `v1.2.3`, and creates a GitHub release with the zip attached.

## Disclaimer

This project isn't affiliated with Kodak.

MIT licensed. See [LICENSE](LICENSE).
