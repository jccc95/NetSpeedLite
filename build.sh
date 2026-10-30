#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_BUNDLE="$PROJECT_DIR/build/NetSpeedLite.app"
CACHE_DIR="$(mktemp -d "${TMPDIR:-/tmp}/netspeedlite-modules.XXXXXX")"
trap 'rm -rf "$CACHE_DIR"' EXIT

command -v swiftc >/dev/null || { echo "swiftc is required (install Xcode Command Line Tools)." >&2; exit 1; }
command -v codesign >/dev/null || { echo "codesign is required (install Xcode Command Line Tools)." >&2; exit 1; }

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
cp "$PROJECT_DIR/Info.plist" "$APP_BUNDLE/Contents/Info.plist"

swiftc \
  -module-cache-path "$CACHE_DIR" \
  -O \
  -framework AppKit \
  "$PROJECT_DIR/NetSpeedLite.swift" \
  -o "$APP_BUNDLE/Contents/MacOS/NetSpeedLite"

codesign --force --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

echo "Built: $APP_BUNDLE"
