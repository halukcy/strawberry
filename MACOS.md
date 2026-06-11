# Building Strawberry on macOS (Homebrew)

This document describes how to build Strawberry on macOS using Homebrew dependencies. It reflects changes made on the `macos-build` branch to support local development and self-contained app bundles.

> **Note:** Upstream does not officially support Homebrew builds. Official macOS releases use a [prebuilt dependency bundle](https://github.com/strawberrymusicplayer/strawberry-macos-dependencies) with patched Qt and GStreamer. This guide is for personal development and customization.

Tested on **Apple Silicon** (`arm64`) with Homebrew at `/opt/homebrew`.

## Prerequisites

- **Xcode Command Line Tools** (provides Clang)

  ```bash
  xcode-select --install
  ```

- **Homebrew** — https://brew.sh

## Install dependencies

### Required packages

```bash
brew tap KDAB/homebrew-tap
brew install cmake pkgconf boost glib qt sqlite gstreamer taglib chromaprint create-dmg
```

On current Homebrew, the `gstreamer` formula bundles all plugin sets (base, good, bad, ugly, libav) — no separate plugin packages are needed.

`icu4c` is pulled in as a dependency and is keg-only. CMake needs it on `CMAKE_PREFIX_PATH` (see below).

### KDSingleApplication

Strawberry requires [KDSingleApplication](https://github.com/KDAB/KDSingleApplication) ≥ 1.1.0. The KDAB Homebrew formula may fail to install; if so, build from source:

```bash
curl -fsSL -o /tmp/kdsingleapplication-1.2.1.tar.gz \
  https://github.com/KDAB/KDSingleApplication/releases/download/v1.2.1/kdsingleapplication-1.2.1.tar.gz
tar xzf /tmp/kdsingleapplication-1.2.1.tar.gz -C /tmp
cmake -S /tmp/KDSingleApplication-1.2.1 -B /tmp/kdsingleapplication-build \
  -DKDSingleApplication_QT6=ON -DCMAKE_INSTALL_PREFIX=/opt/homebrew
cmake --build /tmp/kdsingleapplication-build
cmake --install /tmp/kdsingleapplication-build
```

### Optional features disabled in this guide

The CMake configuration below disables optional components whose libraries are not installed by default via Homebrew. Enable them by installing the dependency and removing the corresponding `-DENABLE_*=OFF` flag.

| Flag | Missing dependency |
|---|---|
| `ENABLE_AUDIOCD=OFF` | libcdio |
| `ENABLE_MTP=OFF` | libmtp |
| `ENABLE_GPOD=OFF` | libgpod |
| `ENABLE_EBUR128=OFF` | libebur128 |
| `ENABLE_GSTFASTSPECTRUM=OFF` | fftw3 |
| `ENABLE_STREAMTAGREADER=OFF` | sparsehash |
| `ENABLE_SPARKLE=OFF` | Sparkle (auto-update) |
| `ENABLE_QTSPARKLE=OFF` | QtSparkle |

Chromaprint stays enabled (song fingerprinting and MusicBrainz).

## Code changes on `macos-build`

Three small changes were made so Strawberry configures and runs cleanly with Homebrew, without requiring upstream packaging tools.

### `cmake/Dmg.cmake`

`macdeployqt`, `macdeploycheck`, and `create-dmg` are no longer **required** at configure time. They are only needed when running the `deploy` / `dmg` CMake targets. This allows local dev builds without `macdeploycheck` (which is not available in Homebrew).

### `src/engine/gststartup.cpp`

When `USE_BUNDLE=OFF` on macOS, Strawberry auto-configures GStreamer environment variables for Homebrew (`/opt/homebrew` or `/usr/local`):

- `GST_PLUGIN_SCANNER`
- `GST_PLUGIN_PATH`
- `DYLD_LIBRARY_PATH`
- `GI_TYPELIB_PATH`
- `PYTHONPATH`

This prevents GStreamer plugin-scanner warnings at startup. With `USE_BUNDLE=ON`, the app uses libraries inside the bundle instead (no Homebrew paths needed at runtime).

### `.gitignore`

Build directories are ignored with `/build*` (covers both `build/` and `build-bundle/`).

## Development build

A development build links against Homebrew libraries at runtime. It is faster to iterate on and does not bundle dependencies.

```bash
export PATH="/opt/homebrew/bin:$PATH"
export PKG_CONFIG_PATH="/opt/homebrew/lib/pkgconfig:/opt/homebrew/share/pkgconfig"

git clone --recursive https://github.com/<your-fork>/strawberry.git
cd strawberry
git checkout macos-build

cmake -S . -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DUSE_BUNDLE=OFF \
  -DCMAKE_PREFIX_PATH="/opt/homebrew/opt/icu4c@78:/opt/homebrew" \
  -DENABLE_AUDIOCD=OFF \
  -DENABLE_MTP=OFF \
  -DENABLE_GPOD=OFF \
  -DENABLE_EBUR128=OFF \
  -DENABLE_GSTFASTSPECTRUM=OFF \
  -DENABLE_STREAMTAGREADER=OFF \
  -DENABLE_SPARKLE=OFF \
  -DENABLE_QTSPARKLE=OFF

cmake --build build --parallel $(sysctl -n hw.ncpu)
```

### Run (dev build)

```bash
./build/strawberry.app/Contents/MacOS/strawberry
```

Or:

```bash
open build/strawberry.app
```

No manual environment variables are needed — `gststartup.cpp` sets them automatically when `USE_BUNDLE=OFF`.

> **Tip:** Do not run the bundled `/Applications` build from a shell with Homebrew on `DYLD_LIBRARY_PATH`; that can load two copies of Qt. Use Finder or `open` instead.

## Installable app bundle

To produce a self-contained `.app` that runs on other Macs without Homebrew, use a separate build directory with `USE_BUNDLE=ON`.

### Configure and build

```bash
cmake -S . -B build-bundle \
  -DCMAKE_BUILD_TYPE=Release \
  -DUSE_BUNDLE=ON \
  -DCMAKE_PREFIX_PATH="/opt/homebrew/opt/icu4c@78:/opt/homebrew" \
  -DENABLE_AUDIOCD=OFF \
  -DENABLE_MTP=OFF \
  -DENABLE_GPOD=OFF \
  -DENABLE_EBUR128=OFF \
  -DENABLE_GSTFASTSPECTRUM=OFF \
  -DENABLE_STREAMTAGREADER=OFF \
  -DENABLE_SPARKLE=OFF \
  -DENABLE_QTSPARKLE=OFF

cmake --build build-bundle --parallel $(sysctl -n hw.ncpu)
cmake --install build-bundle
```

### Deploy (bundle Qt, GStreamer, and dependencies)

```bash
export GIO_EXTRA_MODULES="$(brew --prefix)/lib/gio/modules"
export GST_PLUGIN_SCANNER="$(brew --prefix gstreamer)/libexec/gstreamer-1.0/gst-plugin-scanner"
export GST_PLUGIN_PATH="$(brew --prefix)/lib/gstreamer-1.0"
export LIBSOUP_LIBRARY_PATH="$(brew --prefix)/lib/libsoup-3.0.dylib"

cmake --build build-bundle --target deploy
```

This runs `dist/macos/macgstcopy.sh` (copies GStreamer plugins and GIO modules into the bundle) followed by `macdeployqt`.

`macdeployqt` may report codesign verification errors on some copied libraries. Re-sign the bundle:

```bash
APP=build-bundle/strawberry.app

find "$APP/Contents/Frameworks" -type f \( -name '*.dylib' -o -perm +111 \) -print0 \
  | while IFS= read -r -d '' f; do codesign --force --sign - "$f"; done
find "$APP/Contents/PlugIns" -type f \( -name '*.dylib' -o -perm +111 \) -print0 \
  | while IFS= read -r -d '' f; do codesign --force --sign - "$f"; done
find "$APP/Contents/Frameworks" -name '*.framework' -print0 \
  | while IFS= read -r -d '' fw; do codesign --force --sign - "$fw"; done
codesign --force --sign - "$APP/Contents/MacOS/strawberry"
codesign --force --deep --sign - "$APP"
```

### Install to Applications

```bash
cp -R build-bundle/strawberry.app /Applications/
open /Applications/strawberry.app
```

### Optional: create a DMG

```bash
cmake --build build-bundle --target dmg
```

Produces `build-bundle/strawberry-<version>-arm64.dmg`.

## Rebuilding after code changes

**Dev build:**

```bash
cmake --build build --parallel $(sysctl -n hw.ncpu)
```

**Installable bundle** — rebuild, redeploy, and re-sign:

```bash
cmake --build build-bundle --parallel $(sysctl -n hw.ncpu)
cmake --install build-bundle

export GIO_EXTRA_MODULES="$(brew --prefix)/lib/gio/modules"
export GST_PLUGIN_SCANNER="$(brew --prefix gstreamer)/libexec/gstreamer-1.0/gst-plugin-scanner"
export GST_PLUGIN_PATH="$(brew --prefix)/lib/gstreamer-1.0"
export LIBSOUP_LIBRARY_PATH="$(brew --prefix)/lib/libsoup-3.0.dylib"
cmake --build build-bundle --target deploy

# re-sign (see commands above), then:
cp -R build-bundle/strawberry.app /Applications/
```

## Copying to another Mac

The bundled app is **arm64 only** (Apple Silicon) and requires **macOS 12.0+**.

```bash
cd /Applications
zip -r ~/Desktop/strawberry.zip strawberry.app
```

On the other Mac, unzip and move `strawberry.app` to `/Applications`. Because the app is ad-hoc signed (not notarized), the first launch may require **right-click → Open**, or **System Settings → Privacy & Security → Open Anyway**.

## Build summary

| | Dev build | App bundle |
|---|---|---|
| CMake dir | `build` | `build-bundle` |
| `USE_BUNDLE` | `OFF` | `ON` |
| Binary | `build/strawberry.app` | `build-bundle/strawberry.app` |
| Homebrew at runtime | Yes | No |
| Suitable for `/Applications` | No | Yes |

## References

- [Upstream README](README.md)
- [Official macOS build wiki](https://wiki.strawberrymusicplayer.org/wiki/Build_macOS) (uses prebuilt dependencies)
- [Homebrew macOS wiki (outdated)](https://wiki.strawberrymusicplayer.org/wiki/Compile_macOS_using_homebrew)
