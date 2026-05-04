#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

PRESET="${PRESET:-macos-arm64}"
VERSION="${VERSION:-0.1}"
APP_NAME="${APP_NAME:-flatPDF}"
BUILD_DIR="${BUILD_DIR:-build-macos-arm64}"
DIST_DIR="${DIST_DIR:-dist/${APP_NAME}-v${VERSION}-macos-arm64}"
QT_DIR="${QT_DIR:-/Applications/Qt/6.9.1/macos}"
PDFTOPPM="${PDFTOPPM:-/opt/homebrew/bin/pdftoppm}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

usage() {
  cat <<EOF
Usage: $0 [--clean]

Environment overrides:
  PRESET         CMake preset. Default: macos-arm64
  VERSION        Release version. Default: 0.1
  BUILD_DIR      Build directory. Default: build-macos-arm64
  DIST_DIR       Distribution directory. Default: dist/flatPDF-v0.1-macos-arm64
  QT_DIR         Qt macOS directory. Default: /Applications/Qt/6.9.1/macos
  PDFTOPPM       Source pdftoppm path. Default: /opt/homebrew/bin/pdftoppm
  SIGN_IDENTITY  Codesign identity. Default: - (ad-hoc)
EOF
}

CLEAN=0
for arg in "$@"; do
  case "$arg" in
    --clean) CLEAN=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
APP_BIN="${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
ZIP_PATH="${DIST_DIR}.zip"

require_file() {
  if [[ ! -e "$1" ]]; then
    echo "Missing required path: $1" >&2
    exit 1
  fi
}

if [[ "$CLEAN" == "1" ]]; then
  echo "== Cleaning ignored build artifacts =="
  git clean -fdX
fi

require_file "${QT_DIR}/bin/macdeployqt"
require_file "$PDFTOPPM"

echo "== Configure ${PRESET} =="
cmake --preset "$PRESET"

echo "== Build ${PRESET} =="
cmake --build --preset "$PRESET"

require_file "$APP_BIN"

echo "== Deploy Qt frameworks =="
"${QT_DIR}/bin/macdeployqt" "$APP_BUNDLE" -verbose=1

echo "== Remove unused SQL plugins =="
rm -rf "${APP_BUNDLE}/Contents/PlugIns/sqldrivers"

echo "== Bundle Poppler pdftoppm =="
bash scripts/bundle_pdftoppm.sh "$APP_BUNDLE" "$PDFTOPPM"

echo "== Remove extended attributes =="
chmod u+w "${APP_BUNDLE}/Contents/Resources/pdftoppm" || true
xattr -cr "$APP_BUNDLE"

echo "== Sign bundled Poppler libraries =="
if [[ -d "${APP_BUNDLE}/Contents/lib" ]]; then
  find "${APP_BUNDLE}/Contents/lib" -type f -name '*.dylib' -print0 \
    | xargs -0 -n 1 codesign --force --sign "$SIGN_IDENTITY"
fi

echo "== Sign pdftoppm and app bundle =="
codesign --force --sign "$SIGN_IDENTITY" "${APP_BUNDLE}/Contents/Resources/pdftoppm"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"

echo "== Verify signatures =="
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
codesign --verify --verbose=4 "${APP_BUNDLE}/Contents/Resources/pdftoppm"

echo "== Run CLI tests =="
bash scripts/test_cli.sh "$APP_BIN"

echo "== Create release ZIP =="
rm -rf "$DIST_DIR" "$ZIP_PATH"
mkdir -p "$DIST_DIR"
ditto "$APP_BUNDLE" "${DIST_DIR}/${APP_NAME}.app"
ditto -c -k --keepParent "${DIST_DIR}/${APP_NAME}.app" "$ZIP_PATH"

echo "== SHA256 =="
shasum -a 256 "$ZIP_PATH"

echo "Release asset ready: $ZIP_PATH"
