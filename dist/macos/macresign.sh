#!/bin/sh

# Re-sign a deployed strawberry.app bundle.
# macgstcopy.sh modifies libraries with install_name_tool, which invalidates
# signatures that macdeployqt applies. This script re-signs inner components
# before signing the app bundle itself.

set -e

if [ "$1" = "" ]; then
  echo "Usage: $0 <strawberry.app> [codesign-identity]"
  exit 1
fi

APP="$1"
IDENTITY="${2:--}"

if [ ! -d "${APP}/Contents" ]; then
  echo "Error: ${APP} is not a valid app bundle."
  exit 1
fi

echo "Re-signing ${APP} with identity '${IDENTITY}'"

if [ -d "${APP}/Contents/Frameworks" ]; then
  find "${APP}/Contents/Frameworks" -type f \( -name '*.dylib' -o -perm +111 \) -exec codesign --force --sign "${IDENTITY}" {} \;
  find "${APP}/Contents/Frameworks" -name '*.framework' -exec codesign --force --sign "${IDENTITY}" {} \;
fi

if [ -d "${APP}/Contents/PlugIns" ]; then
  find "${APP}/Contents/PlugIns" -type f \( -name '*.dylib' -o -name '*.so' -o -perm +111 \) -exec codesign --force --sign "${IDENTITY}" {} \;
fi

codesign --force --sign "${IDENTITY}" "${APP}/Contents/MacOS/strawberry"
codesign --force --deep --sign "${IDENTITY}" "${APP}"
codesign --verify --deep --strict "${APP}"

echo "Codesign verification passed."
