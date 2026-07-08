#!/usr/bin/env bash
# Build Strawberry as a self-contained macOS app bundle (Homebrew deps).
#
# Usage:
#   ./build-app.sh           Configure (if needed), compile, and install into build-bundle/
#   ./build-app.sh install   Same as above, then deploy and copy to /Applications/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BUILD_DIR="build-bundle"
APP_NAME="strawberry.app"

usage() {
  cat <<EOF
Usage: $(basename "$0") [install]

  (no args)   Configure if needed, build, and install into ${BUILD_DIR}/
  install     Also bundle dependencies and copy to /Applications/

EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ -n "${1:-}" && "${1}" != "install" ]]; then
  echo "error: unknown argument: ${1}" >&2
  usage >&2
  exit 1
fi

INSTALL_TO_APPLICATIONS=false
if [[ "${1:-}" == "install" ]]; then
  INSTALL_TO_APPLICATIONS=true
fi

if ! command -v brew &>/dev/null; then
  echo "error: Homebrew not found (https://brew.sh)" >&2
  exit 1
fi

BREW_PREFIX="$(brew --prefix)"
export PATH="${BREW_PREFIX}/bin:${PATH:-}"
export PKG_CONFIG_PATH="${BREW_PREFIX}/lib/pkgconfig:${BREW_PREFIX}/share/pkgconfig"

ICU_PREFIX=""
if [[ -d "${BREW_PREFIX}/opt/icu4c" ]]; then
  ICU_PREFIX="${BREW_PREFIX}/opt/icu4c"
else
  ICU_VERSIONED="$(find "${BREW_PREFIX}/opt" -maxdepth 1 -name 'icu4c@*' 2>/dev/null | head -1 || true)"
  if [[ -n "$ICU_VERSIONED" ]]; then
    ICU_PREFIX="$ICU_VERSIONED"
  fi
fi

CMAKE_PREFIX_PATH="$BREW_PREFIX"
if [[ -n "$ICU_PREFIX" ]]; then
  CMAKE_PREFIX_PATH="${ICU_PREFIX}:${CMAKE_PREFIX_PATH}"
  # ICU is keg-only: ensure pkg-config can locate uc/i18n .pc files.
  export PKG_CONFIG_PATH="${ICU_PREFIX}/lib/pkgconfig:${PKG_CONFIG_PATH}"
fi

# Strawberry requires KDSingleApplication. Prefer the repo-local prefix
# (built during development) so we don't depend on a system-wide Homebrew install.
KDSA_PREFIX="${SCRIPT_DIR}/.deps/kdsingleapplication"
if [[ -d "${KDSA_PREFIX}/lib/cmake/KDSingleApplication-qt6" ]]; then
  CMAKE_PREFIX_PATH="${KDSA_PREFIX}:${CMAKE_PREFIX_PATH}"
fi

CMAKE_FLAGS=(
  -DCMAKE_BUILD_TYPE=Release
  -DUSE_BUNDLE=ON
  -DCMAKE_PREFIX_PATH="$CMAKE_PREFIX_PATH"
  -DENABLE_AUDIOCD=OFF
  -DENABLE_MTP=OFF
  -DENABLE_GPOD=OFF
  -DENABLE_EBUR128=OFF
  -DENABLE_GSTFASTSPECTRUM=OFF
  -DENABLE_STREAMTAGREADER=OFF
  -DENABLE_SPARKLE=OFF
  -DENABLE_QTSPARKLE=OFF
)

if [[ -n "$ICU_PREFIX" ]]; then
  CMAKE_FLAGS+=(-DICU_ROOT="$ICU_PREFIX")
fi

if [[ -d "${KDSA_PREFIX}/lib/cmake/KDSingleApplication-qt6" ]]; then
  CMAKE_FLAGS+=(-DKDSingleApplication-qt6_DIR="${KDSA_PREFIX}/lib/cmake/KDSingleApplication-qt6")
fi

configure() {
  echo "==> Configuring ${BUILD_DIR}"
  cmake -S . -B "$BUILD_DIR" "${CMAKE_FLAGS[@]}"
}

build() {
  local jobs
  jobs="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

  # If a previous configure tried to resolve ICU headers from the Apple SDK,
  # the build can fail (missing unicode/translit.h, etc.).
  # Detect and clean that state so we re-configure with Homebrew ICU.
  if [[ -f "${BUILD_DIR}/CMakeCache.txt" ]] && \
     (grep -q '^ICU_INCLUDE_DIR:PATH=.*/Library/Developer/' "${BUILD_DIR}/CMakeCache.txt" 2>/dev/null || true); then
    echo "==> Cleaning ${BUILD_DIR} (ICU headers resolved to Apple SDK)"
    rm -rf "${BUILD_DIR}"
  fi

  # If CMake didn't finish generating the build system, CMakeCache.txt can exist
  # but the actual generator files (Makefile / build.ninja) are missing.
  # In that case, we must re-configure.
  if [[ ! -f "${BUILD_DIR}/CMakeCache.txt" || ( ! -f "${BUILD_DIR}/Makefile" && ! -f "${BUILD_DIR}/build.ninja" ) ]]; then
    configure
  fi

  echo "==> Building (${jobs} jobs)"
  cmake --build "$BUILD_DIR" --parallel "$jobs"

  echo "==> Installing into ${BUILD_DIR}"
  cmake --install "$BUILD_DIR"
}

deploy() {
  echo "==> Deploying (bundle Qt, GStreamer, dependencies)"
  export GIO_EXTRA_MODULES="${BREW_PREFIX}/lib/gio/modules"
  export GST_PLUGIN_SCANNER="$(brew --prefix gstreamer)/libexec/gstreamer-1.0/gst-plugin-scanner"
  export GST_PLUGIN_PATH="${BREW_PREFIX}/lib/gstreamer-1.0"
  export LIBSOUP_LIBRARY_PATH="${BREW_PREFIX}/lib/libsoup-3.0.dylib"
  cmake --build "$BUILD_DIR" --target deploy
}

install_to_applications() {
  local app_path="${BUILD_DIR}/${APP_NAME}"
  if [[ ! -d "$app_path" ]]; then
    echo "error: ${app_path} not found" >&2
    exit 1
  fi

  echo "==> Installing to /Applications/${APP_NAME}"
  rm -rf "/Applications/${APP_NAME}"
  cp -R "$app_path" /Applications/
  echo "Installed /Applications/${APP_NAME}"
}

build

if $INSTALL_TO_APPLICATIONS; then
  deploy
  install_to_applications
else
  echo
  echo "Built ${BUILD_DIR}/${APP_NAME}"
  echo "Run: open ${BUILD_DIR}/${APP_NAME}"
  echo "To install to /Applications: $(basename "$0") install"
fi
