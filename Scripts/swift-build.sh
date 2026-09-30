#!/usr/bin/env bash
# Copyright (C) 2026 SHIXIN LAB / Shixin
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_PATH="${SHIXIN_BUILD_SDK_PATH:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"
test -f "$SDK_PATH/SDKSettings.plist"
SDK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :Version' "$SDK_PATH/SDKSettings.plist")"
MINIMUM_OS="$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$ROOT_DIR/Packaging/Info.plist")"

# Xcode 27's SwiftPM link-only invocation can stamp the deployment target as
# the SDK version. That opts ALL AppKit/SwiftUI controls into pre-26 appearance.
# Supply the actual selected SDK, keeping the deployment target unchanged.
exec swift "$@" --sdk "$SDK_PATH" \
  -Xlinker -platform_version -Xlinker macos \
  -Xlinker "$MINIMUM_OS" -Xlinker "$SDK_VERSION"
