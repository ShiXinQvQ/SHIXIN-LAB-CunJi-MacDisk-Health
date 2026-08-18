#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VARIANT="${SHIXIN_DISK_HEALTH_VARIANT:-v2}"
PUBLISHED_APP_NAME="SHIXIN LAB · 「存迹」"
LEGACY_PUBLISHED_APP_NAME="SHIXIN LAB · 存迹 MacDisk Health"
PUBLISHED_BUNDLE_ID="com.shixinqvq.shixinlab.diskhealth"
PUBLISHED_APP_SUPPORT_NAME="SHIXIN LAB MacDisk Health"
V2_APP_NAME="SHIXIN LAB · 「存迹」v2"
LEGACY_V2_APP_NAME="$LEGACY_PUBLISHED_APP_NAME v2"
V2_BUNDLE_ID="$PUBLISHED_BUNDLE_ID.v2"
V2_APP_SUPPORT_NAME="$PUBLISHED_APP_SUPPORT_NAME v2"

case "$VARIANT" in
  v2)
    DEFAULT_APP_NAME="$V2_APP_NAME"
    DEFAULT_BUNDLE_ID="$V2_BUNDLE_ID"
    DEFAULT_APP_SUPPORT_NAME="$V2_APP_SUPPORT_NAME"
    DEFAULT_APP_ICON_BASENAME="AppIconV2"
    DEFAULT_SHORT_VERSION="0.2.0"
    DEFAULT_BUNDLE_VERSION="5"
    INCLUDE_HELPER="NO"
    ;;
  main)
    if [[ "${SHIXIN_DISK_HEALTH_ALLOW_MAIN_BUILD:-NO}" != "YES" ]]; then
      printf '%s\n' "Refusing to build the main app identity. Set SHIXIN_DISK_HEALTH_ALLOW_MAIN_BUILD=YES only for an explicitly approved main release." >&2
      exit 64
    fi
    if [[ -z "${SHIXIN_DISK_HEALTH_SHORT_VERSION:-}" || -z "${SHIXIN_DISK_HEALTH_BUNDLE_VERSION:-}" ]]; then
      printf '%s\n' "Refusing to build the main app without explicit short and bundle versions." >&2
      exit 64
    fi
    DEFAULT_APP_NAME="$PUBLISHED_APP_NAME"
    DEFAULT_BUNDLE_ID="$PUBLISHED_BUNDLE_ID"
    DEFAULT_APP_SUPPORT_NAME="$PUBLISHED_APP_SUPPORT_NAME"
    DEFAULT_APP_ICON_BASENAME="AppIconV2"
    DEFAULT_SHORT_VERSION="$SHIXIN_DISK_HEALTH_SHORT_VERSION"
    DEFAULT_BUNDLE_VERSION="$SHIXIN_DISK_HEALTH_BUNDLE_VERSION"
    INCLUDE_HELPER="${SHIXIN_DISK_HEALTH_INCLUDE_HELPER:-NO}"
    ;;
  *)
    printf 'Unknown build variant: %s\n' "$VARIANT" >&2
    exit 64
    ;;
esac

APP_NAME="${SHIXIN_DISK_HEALTH_APP_NAME:-$DEFAULT_APP_NAME}"
BUNDLE_ID="${SHIXIN_DISK_HEALTH_BUNDLE_ID:-$DEFAULT_BUNDLE_ID}"
APP_SUPPORT_NAME="${SHIXIN_DISK_HEALTH_APP_SUPPORT_NAME:-$DEFAULT_APP_SUPPORT_NAME}"
APP_ICON_BASENAME="$DEFAULT_APP_ICON_BASENAME"
SHORT_VERSION="${SHIXIN_DISK_HEALTH_SHORT_VERSION:-$DEFAULT_SHORT_VERSION}"
BUNDLE_VERSION="${SHIXIN_DISK_HEALTH_BUNDLE_VERSION:-$DEFAULT_BUNDLE_VERSION}"
APP_PARENT_DIR="${SHIXIN_DISK_HEALTH_APP_PARENT_DIR:-$HOME/Applications}"
TARGET_APP_DIR="${SHIXIN_DISK_HEALTH_APP_DIR:-$APP_PARENT_DIR/$APP_NAME.app}"

version_is_at_most() {
  local actual="$1"
  local maximum="$2"
  awk -v actual="$actual" -v maximum="$maximum" '
    BEGIN {
      split(actual, a, ".")
      split(maximum, m, ".")
      for (i = 1; i <= 3; i++) {
        av = (a[i] == "" ? 0 : a[i]) + 0
        mv = (m[i] == "" ? 0 : m[i]) + 0
        if (av < mv) exit 0
        if (av > mv) exit 1
      }
      exit 0
    }
  '
}

validate_bundled_smartctl() {
  local smartctl_path="$1"
  local app_binary_path="$2"
  local plist_path="$3"
  local app_min_os smartctl_min_os app_archs smartctl_archs unexpected_dependencies

  [[ -x "$smartctl_path" ]] || { printf '%s\n' "Missing executable bundled smartctl." >&2; exit 66; }
  command -v vtool >/dev/null 2>&1 || { printf '%s\n' "vtool is required to validate bundled smartctl compatibility." >&2; exit 69; }
  command -v otool >/dev/null 2>&1 || { printf '%s\n' "otool is required to validate bundled smartctl dependencies." >&2; exit 69; }
  command -v lipo >/dev/null 2>&1 || { printf '%s\n' "lipo is required to validate bundled smartctl architecture." >&2; exit 69; }

  app_min_os="$(plutil -extract LSMinimumSystemVersion raw -o - "$plist_path")"
  smartctl_min_os="$(vtool -show-build "$smartctl_path" | awk '$1 == "minos" { print $2; exit }')"
  [[ -n "$smartctl_min_os" ]] || { printf '%s\n' "Could not read bundled smartctl minimum macOS version." >&2; exit 65; }
  version_is_at_most "$smartctl_min_os" "$app_min_os" || {
    printf 'Bundled smartctl requires macOS %s, but the App declares macOS %s.\n' "$smartctl_min_os" "$app_min_os" >&2
    exit 65
  }

  app_archs="$(lipo -archs "$app_binary_path")"
  smartctl_archs="$(lipo -archs "$smartctl_path")"
  for arch in $app_archs; do
    [[ " $smartctl_archs " == *" $arch "* ]] || {
      printf 'Bundled smartctl is missing required architecture %s (has: %s).\n' "$arch" "$smartctl_archs" >&2
      exit 65
    }
  done

  unexpected_dependencies="$(otool -L "$smartctl_path" | tail -n +2 | awk '{ print $1 }' | grep -Ev '^(/System/Library/|/usr/lib/)' || true)"
  [[ -z "$unexpected_dependencies" ]] || {
    printf '%s\n%s\n' "Bundled smartctl has non-system runtime dependencies:" "$unexpected_dependencies" >&2
    exit 65
  }

  "$smartctl_path" --version >/dev/null
  printf 'Validated bundled smartctl: macOS %s, architecture %s.\n' "$smartctl_min_os" "$smartctl_archs" >&2
}

if [[ "$VARIANT" == "v2" ]]; then
  [[ "$BUNDLE_ID" == "$V2_BUNDLE_ID" ]] || { printf '%s\n' "v2 builds require the fixed v2 Bundle ID." >&2; exit 64; }
  [[ "$APP_NAME" == "$V2_APP_NAME" ]] || { printf '%s\n' "v2 builds require the fixed internal v2 App name." >&2; exit 64; }
  [[ "$APP_SUPPORT_NAME" == "$V2_APP_SUPPORT_NAME" ]] || { printf '%s\n' "v2 builds require the isolated v2 data namespace." >&2; exit 64; }
  [[ "$(basename "$TARGET_APP_DIR")" == "$V2_APP_NAME.app" ]] || { printf '%s\n' "v2 build target must use the fixed v2 App filename." >&2; exit 64; }
  [[ "$(basename "$TARGET_APP_DIR")" != "$PUBLISHED_APP_NAME.app" ]] || { printf '%s\n' "v2 build target may not be the released App path." >&2; exit 64; }
else
  [[ "$BUNDLE_ID" == "$PUBLISHED_BUNDLE_ID" ]] || { printf '%s\n' "main builds must preserve the published Bundle ID." >&2; exit 64; }
  [[ "$APP_NAME" == "$PUBLISHED_APP_NAME" ]] || { printf '%s\n' "main builds must preserve the published App name." >&2; exit 64; }
  [[ "$APP_SUPPORT_NAME" == "$PUBLISHED_APP_SUPPORT_NAME" ]] || { printf '%s\n' "main builds must preserve the published data namespace." >&2; exit 64; }
  [[ "$(basename "$TARGET_APP_DIR")" == "$PUBLISHED_APP_NAME.app" ]] || { printf '%s\n' "main builds must use the published App filename." >&2; exit 64; }
fi

STAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/shixin-disk-health-${VARIANT}.XXXXXX")"
APP_DIR="$STAGE_ROOT/$APP_NAME.app"
BIN_DIR="$APP_DIR/Contents/MacOS"
RES_DIR="$APP_DIR/Contents/Resources"
DAEMON_DIR="$APP_DIR/Contents/Library/LaunchDaemons"

cleanup() {
  rm -rf "$STAGE_ROOT"
}
trap cleanup EXIT

SDK_PROBE_SOURCE="$STAGE_ROOT/sdk-probe.swift"
SDK_PROBE_CACHE="$STAGE_ROOT/sdk-probe-module-cache"
printf '%s\n' 'import Foundation' > "$SDK_PROBE_SOURCE"
mkdir -p "$SDK_PROBE_CACHE"

case "$(uname -m)" in
  arm64) SDK_PROBE_TARGET="arm64-apple-macosx15.0" ;;
  x86_64) SDK_PROBE_TARGET="x86_64-apple-macosx15.0" ;;
  *)
    printf '%s\n' "Unsupported build architecture: $(uname -m)" >&2
    exit 69
    ;;
esac

sdk_is_compatible() {
  local candidate="$1"
  [[ -d "$candidate" ]] || return 1
  swiftc \
    -sdk "$candidate" \
    -target "$SDK_PROBE_TARGET" \
    -module-cache-path "$SDK_PROBE_CACHE" \
    -typecheck "$SDK_PROBE_SOURCE" \
    >/dev/null 2>&1
}

SDK_OVERRIDE="${SHIXIN_DISK_HEALTH_SDK:-}"
if [[ -n "$SDK_OVERRIDE" ]]; then
  if ! sdk_is_compatible "$SDK_OVERRIDE"; then
    printf '%s\n' "The requested SDK is missing or incompatible with the active Swift compiler: $SDK_OVERRIDE" >&2
    exit 69
  fi
  SELECTED_SDK="$SDK_OVERRIDE"
else
  DEFAULT_SDK="$(xcrun --show-sdk-path)"
  if sdk_is_compatible "$DEFAULT_SDK"; then
    SELECTED_SDK="$DEFAULT_SDK"
  else
    SELECTED_SDK=""
    for candidate in \
      /Library/Developer/CommandLineTools/SDKs/MacOSX15*.sdk \
      /Applications/Xcode*.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX15*.sdk; do
      if sdk_is_compatible "$candidate"; then
        SELECTED_SDK="$candidate"
        break
      fi
    done
    if [[ -z "$SELECTED_SDK" ]]; then
      printf '%s\n' "The default macOS SDK is incompatible with the active Swift compiler, and no compatible macOS 15 SDK was found." >&2
      printf '%s\n' "Default SDK: $DEFAULT_SDK" >&2
      printf '%s\n' "Set SHIXIN_DISK_HEALTH_SDK to a compatible SDK path after repairing Command Line Tools." >&2
      exit 69
    fi
    printf '%s\n' "Default SDK is incompatible with the active Swift compiler; using verified fallback: $SELECTED_SDK" >&2
  fi
fi
printf '%s\n' "Using verified macOS SDK: $SELECTED_SDK" >&2

export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-$STAGE_ROOT/swiftpm-module-cache}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$STAGE_ROOT/clang-module-cache}"
mkdir -p "$SWIFTPM_MODULECACHE_OVERRIDE" "$CLANG_MODULE_CACHE_PATH"
SWIFT_BUILD_ARGUMENTS=(-c release --sdk "$SELECTED_SDK")

cd "$ROOT_DIR"
swift build "${SWIFT_BUILD_ARGUMENTS[@]}" --product ShixinDiskHealth
if [[ "$INCLUDE_HELPER" == "YES" ]]; then
  swift build "${SWIFT_BUILD_ARGUMENTS[@]}" --product ShixinDiskHealthPrivilegedHelper
fi
BUILD_BIN_DIR="$(swift build "${SWIFT_BUILD_ARGUMENTS[@]}" --show-bin-path)"

mkdir -p "$BIN_DIR" "$RES_DIR/Tools"
cp "$BUILD_BIN_DIR/ShixinDiskHealth" "$BIN_DIR/ShixinDiskHealth"
cp "Packaging/Info.plist" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "$APP_NAME" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleName -string "$APP_NAME" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleIconFile -string "$APP_ICON_BASENAME" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleIconName -string "$APP_ICON_BASENAME" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$SHORT_VERSION" "$APP_DIR/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUNDLE_VERSION" "$APP_DIR/Contents/Info.plist"
plutil -replace SHIXINAppSupportDirectoryName -string "$APP_SUPPORT_NAME" "$APP_DIR/Contents/Info.plist"
plutil -replace SHIXINSpeedTestCacheDirectoryName -string "$APP_SUPPORT_NAME" "$APP_DIR/Contents/Info.plist"

if [[ "$INCLUDE_HELPER" == "YES" ]]; then
  mkdir -p "$DAEMON_DIR"
  cp "$BUILD_BIN_DIR/ShixinDiskHealthPrivilegedHelper" "$DAEMON_DIR/ShixinDiskHealthPrivilegedHelper"
  cp "Packaging/com.shixinqvq.shixinlab.diskhealth.helper.plist" "$DAEMON_DIR/com.shixinqvq.shixinlab.diskhealth.helper.plist"
fi

[[ -f "Packaging/$APP_ICON_BASENAME.icns" ]] || {
  printf 'Missing required App icon: Packaging/%s.icns\n' "$APP_ICON_BASENAME" >&2
  exit 66
}

for asset in "$APP_ICON_BASENAME.icns" AppIconPreview.png AppIconPreviewInApp.png; do
  if [[ -f "Packaging/$asset" ]]; then
    cp "Packaging/$asset" "$RES_DIR/$asset"
  fi
done

find "Sources/ShixinDiskHealth/Resources" -maxdepth 1 -type d -name "*.lproj" -print0 | while IFS= read -r -d '' lproj_dir; do
  ditto "$lproj_dir" "$RES_DIR/$(basename "$lproj_dir")"
done
find "$RES_DIR" -maxdepth 2 -name "InfoPlist.strings" -print0 | while IFS= read -r -d '' strings_file; do
  printf 'CFBundleDisplayName = "%s";\nCFBundleName = "%s";\n' "$APP_NAME" "$APP_NAME" > "$strings_file"
done

if command -v strip >/dev/null 2>&1; then
  strip -S "$BIN_DIR/ShixinDiskHealth" || true
  if [[ -f "$DAEMON_DIR/ShixinDiskHealthPrivilegedHelper" ]]; then
    strip -S "$DAEMON_DIR/ShixinDiskHealthPrivilegedHelper" || true
  fi
fi

if [[ -x "Sources/ShixinDiskHealth/Resources/Tools/smartctl" ]]; then
  cp "Sources/ShixinDiskHealth/Resources/Tools/smartctl" "$RES_DIR/Tools/smartctl"
elif [[ -x "/opt/homebrew/bin/smartctl" ]]; then
  cp "/opt/homebrew/bin/smartctl" "$RES_DIR/Tools/smartctl"
elif [[ -x "/usr/local/bin/smartctl" ]]; then
  cp "/usr/local/bin/smartctl" "$RES_DIR/Tools/smartctl"
fi

validate_bundled_smartctl "$RES_DIR/Tools/smartctl" "$BIN_DIR/ShixinDiskHealth" "$APP_DIR/Contents/Info.plist"

mkdir -p "$RES_DIR/Licenses"
cp "LICENSE" "$RES_DIR/Licenses/SHIXIN-LAB-GPL-3.0.txt"
cp "COPYRIGHT.md" "$RES_DIR/Licenses/SHIXIN-LAB-Copyright-and-Licensing.md"
cp "TRADEMARKS.md" "$RES_DIR/Licenses/SHIXIN-LAB-Trademark-and-Brand-Policy.md"

if [[ -f "Licenses/smartmontools-COPYING.txt" ]]; then
  cp "Licenses/smartmontools-COPYING.txt" "$RES_DIR/Licenses/smartmontools-COPYING.txt"
  cp "Licenses/smartmontools-NOTICE.md" "$RES_DIR/Licenses/smartmontools-NOTICE.md"
  if [[ -f "Licenses/smartmontools-README.txt" ]]; then
    cp "Licenses/smartmontools-README.txt" "$RES_DIR/Licenses/smartmontools-README.txt"
  fi
  if [[ -f "Licenses/smartmontools-SOURCE.md" ]]; then
    cp "Licenses/smartmontools-SOURCE.md" "$RES_DIR/Licenses/smartmontools-SOURCE.md"
  fi
  if [[ -f "Licenses/Source/smartmontools-7.5.tar.gz" ]]; then
    mkdir -p "$RES_DIR/Licenses/Source"
    cp "Licenses/Source/smartmontools-7.5.tar.gz" "$RES_DIR/Licenses/Source/smartmontools-7.5.tar.gz"
  fi
fi

if command -v codesign >/dev/null 2>&1; then
  if [[ -f "$DAEMON_DIR/ShixinDiskHealthPrivilegedHelper" ]]; then
    codesign --force --sign - "$DAEMON_DIR/ShixinDiskHealthPrivilegedHelper"
  fi
  codesign --force --sign - "$APP_DIR"
fi

ACTUAL_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP_DIR/Contents/Info.plist")"
[[ "$ACTUAL_BUNDLE_ID" == "$BUNDLE_ID" ]] || { printf '%s\n' "Built Bundle ID validation failed." >&2; exit 1; }

mkdir -p "$(dirname "$TARGET_APP_DIR")"
backup_installed_app() {
  local source_app="$1"
  local backup_label="$2"
  BACKUP_STAMP="$(date +%Y%m%d-%H%M%S)"
  REPLACED_DIR="$ROOT_DIR/Backups/${backup_label}-app-before-install-$BACKUP_STAMP"
  mkdir -p "$REPLACED_DIR"
  mv "$source_app" "$REPLACED_DIR/$(basename "$source_app")"
}

if [[ -e "$TARGET_APP_DIR" ]]; then
  backup_installed_app "$TARGET_APP_DIR" "$VARIANT"
fi
if [[ "$VARIANT" == "v2" ]]; then
  LEGACY_V2_APP_DIR="$APP_PARENT_DIR/$LEGACY_V2_APP_NAME.app"
  if [[ "$LEGACY_V2_APP_DIR" != "$TARGET_APP_DIR" && -e "$LEGACY_V2_APP_DIR" ]]; then
    backup_installed_app "$LEGACY_V2_APP_DIR" "v2-legacy-name"
  fi
else
  LEGACY_PUBLISHED_APP_DIR="$APP_PARENT_DIR/$LEGACY_PUBLISHED_APP_NAME.app"
  if [[ "$LEGACY_PUBLISHED_APP_DIR" != "$TARGET_APP_DIR" && -e "$LEGACY_PUBLISHED_APP_DIR" ]]; then
    backup_installed_app "$LEGACY_PUBLISHED_APP_DIR" "main-legacy-name"
  fi
fi
mv "$APP_DIR" "$TARGET_APP_DIR"

touch "$TARGET_APP_DIR"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [[ -x "$LSREGISTER" ]]; then
  "$LSREGISTER" -f "$TARGET_APP_DIR" >/dev/null 2>&1 || true
fi

printf '%s\n' "$TARGET_APP_DIR"
