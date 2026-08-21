# Notch Capture website shot list

The site is video-first ready, but v1 uses the checked-in still references because Screen Recording and Accessibility permissions require an interactive macOS approval.

## Build and launch

```sh
Scripts/build-app.sh debug
open ".build/Notch Capture.app"
```

## Capture targets

Record the centered notch region for: capture with tag, completion wave, link with favicon, now playing, and idle pill.

```sh
screencapture -v -R <x,y,width,height> /tmp/nc-capture-with-tag.mov
```

Encode each source as H.264 MP4 plus VP9 WebM with a matching poster, targeting less than 2.5 MB per clip. Drop the final files into `public/media/` and keep the poster base name identical.
