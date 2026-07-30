# kadr

A minimal video player: libmpv for decoding, Qt 6 Quick for the UI, and a
"Liquid Glass" control layer whose buttons refract the video playing underneath
them. Built to watch The Mentalist with English subtitles as English practice,
so subtitle legibility and comfortable playback controls are the priorities.

## Build and run

```bash
cmake -B build -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=$HOME/.local
cmake --build build
cmake --install build          # -> ~/.local/bin/kadr
build/kadr ~/Videos/Mentalist/S01E01.mkv
```

Dependencies (all present on this machine): Qt 6.11 (`Quick`, `OpenGL`,
`ShaderTools`), libmpv 2.5 via pkg-config, and the **SF Pro Rounded** font,
which both the UI and the default subtitle style hardcode.

`build/` is gitignored. The binary in `~/.local/bin/kadr` is a copy from
`cmake --install`, not a symlink, so it goes stale until you install again.

## Layout

| Path | What it holds |
| --- | --- |
| `src/main.cpp` | Env setup before `QGuiApplication`, CLI file arg, context properties |
| `src/mpvobject.{h,cpp}` | `MpvObject` + `MpvRenderer`: libmpv wrapped as a `QQuickFramebufferObject` |
| `src/theme.{h,cpp}` | `Theme` singleton, watches the desktop's matugen palette |
| `qml/Main.qml` | The whole UI: transport, seek bar, settings pages, OSD, keys, smoke test |
| `qml/GlassItem.qml` | One glass surface; wraps `glass.frag` and feeds it uniforms |
| `shaders/glass.frag` | hyprglass "liquid lens" port; also does plain frosted blur (`mode 1`) |
| `shaders/rounded.frag` | Rounded-corner mask, used for the seek thumbnail |

Both QML files and both C++ pairs are registered through `qt_add_qml_module`
(URI `Kadr`), so new QML files and new `QML_ELEMENT` classes must be added to
`CMakeLists.txt` or they will not resolve.

## Architecture notes

**`MpvObject`** is an FBO item. mpv renders into Qt's framebuffer through
`mpv_render_context_render` with `vo=libmpv`. Properties are observed via
`mpv_observe_property` and re-emitted as Qt signals, so QML binds to
`mpv.position`, `mpv.pause`, `mpv.speed`, etc. Commands and property writes go
through the async libmpv API (`mpv_command_async`, `mpv_set_property_async`).
`mpv.setProp(name, value)` is the generic escape hatch from QML for anything
without a dedicated `Q_PROPERTY`.

**`thumbnailMode: true`** makes a second, cheap MpvObject: paused, muted, no
audio/sub tracks, software decode, keyframe-only seeks, tiny demuxer cache. It
backs the timeline hover thumbnail so scrubbing never disturbs the main
instance. Set it at creation only.

**`Theme`** is a QML singleton that reads
`~/.local/state/quickshell/user/generated/colors.json` (the palette matugen
regenerates on every wallpaper change) and re-emits `colorsChanged`, so kadr
recolors live with the rest of the desktop. matugen replaces the file
atomically, which kills an inode watch, hence the directory watch and `rearm()`.

**`GlassItem`** samples the video item's texture *directly* — an FBO item is a
texture provider, so there is no `ShaderEffectSource` and no per-frame copy
pass. It needs its own rect in normalized video-texture coordinates, and
`mapToItem` gives QML bindings nothing to track, so `syncRect()` is re-run every
frame from `Window.onAfterAnimating`. Do not convert that back to a binding.

## Hard-won constraints - do not "simplify" these

These each fixed a real, visible bug. Comments in the code mark them too.

- **`QSG_RENDER_LOOP=threaded`** (`main.cpp`). On this driver Qt picks the
  single-threaded `basic` loop, where mpv's per-frame render blocks UI
  animations.
- **`MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME = 0`** (`mpvobject.cpp`). Otherwise
  mpv sleeps on the render thread until each frame's display time and stalls the
  whole scene graph 30-60 ms per video frame. Its companion is
  **`video-timing-offset=0`**.
- **Playback must not start before the render context exists.** The context can
  only be created with a GL context current, i.e. inside
  `createFramebufferObject`. Files requested earlier are held in
  `m_pendingFile` and loaded from `renderContextReady()`; loading sooner makes
  mpv drop the video track with "No render context set".
- **`QQuickWindow::setGraphicsApi(OpenGL)`** — libmpv here uses the OpenGL
  render API, so the RHI backend has to match.
- **`setlocale(LC_NUMERIC, "C")`** after `QGuiApplication`, which libmpv
  requires and Qt may have changed.
- **`setPersistentSceneGraph(true)`** so the mpv render context survives.

## UI conventions

Animation vocabulary is consistent and worth matching in new code: reveals and
presses use `SpringAnimation { spring: 2.8; damping: 0.40 }`, fades use
`NumberAnimation { duration: 180 }` (140-220 for panels), page slides use
`OutCubic` over 220 ms. Icons are `Shape`/`PathSvg` with
`preferredRendererType: Shape.CurveRenderer`, drawn on a 24x24 grid and scaled
with a `Scale` transform — no icon fonts, no images. Interactive elements set a
`cursorShape` (`PointingHandCursor`, `ClosedHandCursor` while dragging).

Controls auto-hide 2600 ms after the last input via `poke()`/`hideTimer`; they
stay up while paused, while the settings panel is open, or under
`KADR_HOLD_CONTROLS`.

The settings panel is a YouTube-style stack of `MenuPage`s (`root`, `speed`,
`subtitles`, `option`, `theme`, `skip`) switched by
`settingsPanel.navigate(name, dir)`, with the panel height springing to the
active page's `implicitHeight`. Subtitle pages are generated from
`win.subOptionDefs`: each entry has display `options` and matching mpv `values`,
and `applySubStyle()` pushes the selected indices into mpv (combining background
color plus opacity into `sub-back-color`). Add a subtitle setting by adding one
entry there and one `Settings` property — no new page needed.

`Settings` (QtCore) persists `glassTheme`, `skipInterval`, `speed` and every
`sub*Idx`. Anything user-visible and adjustable should be persisted the same way.

**Keys:** space play/pause, ←/→ skip by `skipInterval` (replays the button's
press dip and ring spin), ↑/↓ volume ±5, `f` fullscreen, `m` mute, `s` subtitle
toggle, `esc` close panel then leave fullscreen, `q` quit. Wheel is volume,
double-click is fullscreen.

## Environment variables

| Variable | Effect |
| --- | --- |
| `KADR_SMOKE=1` | Headless check: after 6 s prints `KADR_SMOKE_OK duration=… frames=…` and exits, or `KADR_SMOKE_FAIL` with exit 1 |
| `KADR_SHOT=<path>` | With `KADR_SMOKE`, seeks to 13:00, opens the settings panel, forces the seek preview, grabs a PNG |
| `KADR_HOLD_CONTROLS=1` | Never auto-hide controls; opens the settings panel at startup |
| `KADR_THEME=liquid\|blur` | Force a glass theme without touching saved settings |
| `KADR_HWDEC=<mode>` | mpv `hwdec`, default `auto-safe` |
| `QSG_RENDER_LOOP` | Respected if already set; otherwise forced to `threaded` |

Verifying a visual change end to end:

```bash
KADR_SMOKE=1 KADR_SHOT=/tmp/kadr.png QT_FORCE_STDERR_LOGGING=1 \
  build/kadr ~/Videos/Mentalist/S01E01.mkv
# qml: KADR_SMOKE_OK duration=2709.077 frames=145 speed=1 theme=liquid skip=5 …
# qml: KADR_SHOT_SAVED /tmp/kadr.png speed=1
```

**`QT_FORCE_STDERR_LOGGING=1` is not optional here.** Qt on this machine is
built with journald support, so `console.log` goes to the systemd journal and the
smoke test looks completely silent on the terminal — it still exits 0 on pass and
1 on fail, but you see no assertion line. Without the variable, read the result
with `journalctl --user -t kadr -n 20` instead.

`updateCount()` counts frames mpv asked us to render — a steady climb is the
proof that video is actually flowing, which is what the smoke test asserts
(`frames > 30`). There is no unit test suite; this is the regression check.

Under `KADR_SHOT` the seek preview is forced open without a real cursor, so its
time label reads `0:00` (it tracks live mouse X) while the thumbnail itself shows
13:15. That is expected in screenshots, not a sync bug.

## Watching workflow

`~/.local/bin/mentalist [--mpv] <season> <episode>` plays
`~/Videos/Mentalist/S%02dE%02d.mkv` in kadr, or in plain mpv with matching
subtitle styling as a fallback. It refuses with a clear message when the file is
absent. kadr itself is a general player and takes any path as `argv[1]`.

An episode is "ready" when it is an mkv at that exact path with a default
English `subrip` track tagged `language=eng`. `S01E01.mkv` (h264 + aac + eng
subrip, 45:09) is the reference.

Useful facts about the existing copy: it is 23.976 fps with roughly 90 s of
black padding after the content ends (45:09 file vs ~43:30 of show), so
subtitles that stop "early" relative to the file duration are normal, not a sync
bug.

Subtitle alignment, when a track is off: use `alass` (`~/.local/bin/alass`),
which aligns by voice activity against the video. Do **not** derive an offset
from transcribed snippet timestamps — that was ~3 s wrong in noisy scenes where
alass was correct. Mux with `ffmpeg -c copy -c:s srt
-metadata:s:s:0 language=eng -disposition:s:0 default` (`mkvmerge` is not
installed here).

**Sourcing the video files is the user's step.** A previous session pulled
S01E01 by ripping the HLS stream from an unauthorized streaming site; do not
repeat that or write tooling for it. Ask the user to supply the episode from
something they have rights to, then do the remux, subtitle alignment and muxing
described above.
