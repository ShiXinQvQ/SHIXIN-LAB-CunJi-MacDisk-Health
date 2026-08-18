#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VARIANT="${SHIXIN_DISK_HEALTH_VARIANT:-v2}"
PUBLISHED_APP_NAME="SHIXIN LAB · 「存迹」"
PUBLISHED_APP_SUPPORT_NAME="SHIXIN LAB MacDisk Health"
V2_APP_NAME="SHIXIN LAB · 「存迹」v2"
V2_APP_SUPPORT_NAME="$PUBLISHED_APP_SUPPORT_NAME v2"

case "$VARIANT" in
  v2)
    APP_NAME="${SHIXIN_DISK_HEALTH_APP_NAME:-$V2_APP_NAME}"
    APP_SUPPORT_NAME="${SHIXIN_DISK_HEALTH_APP_SUPPORT_NAME:-$V2_APP_SUPPORT_NAME}"
    DMG_VOLUME_NAME="${SHIXIN_DISK_HEALTH_DMG_VOLUME_NAME:-SHIXIN LAB · 存迹 v2}"
    VERSION="${SHIXIN_DISK_HEALTH_PACKAGE_VERSION:-internal-v2}"
    ;;
  main)
    if [[ "${SHIXIN_DISK_HEALTH_ALLOW_MAIN_PACKAGE:-NO}" != "YES" ]]; then
      printf '%s\n' "Refusing to package the main app identity without SHIXIN_DISK_HEALTH_ALLOW_MAIN_PACKAGE=YES." >&2
      exit 64
    fi
    if [[ -z "${SHIXIN_DISK_HEALTH_PACKAGE_VERSION:-}" ]]; then
      printf '%s\n' "Refusing to package the main app without an explicitly assigned release version." >&2
      exit 64
    fi
    if [[ -z "${SHIXIN_DISK_HEALTH_SHORT_VERSION:-}" || -z "${SHIXIN_DISK_HEALTH_BUNDLE_VERSION:-}" ]]; then
      printf '%s\n' "Refusing to package the main app without explicit short and bundle versions." >&2
      exit 64
    fi
    APP_NAME="${SHIXIN_DISK_HEALTH_APP_NAME:-$PUBLISHED_APP_NAME}"
    APP_SUPPORT_NAME="${SHIXIN_DISK_HEALTH_APP_SUPPORT_NAME:-$PUBLISHED_APP_SUPPORT_NAME}"
    DMG_VOLUME_NAME="${SHIXIN_DISK_HEALTH_DMG_VOLUME_NAME:-SHIXIN LAB · 「存迹」}"
    VERSION="$SHIXIN_DISK_HEALTH_PACKAGE_VERSION"
    ;;
  *)
    printf 'Unknown package variant: %s\n' "$VARIANT" >&2
    exit 64
    ;;
esac

if [[ "$VARIANT" == "v2" ]]; then
  [[ "$APP_NAME" == "$V2_APP_NAME" ]] || { printf '%s\n' "v2 packages require the fixed v2 App name." >&2; exit 64; }
  [[ "$APP_SUPPORT_NAME" == "$V2_APP_SUPPORT_NAME" ]] || { printf '%s\n' "v2 packages require the isolated v2 data namespace." >&2; exit 64; }
else
  [[ "$APP_NAME" == "$PUBLISHED_APP_NAME" ]] || { printf '%s\n' "main packages must preserve the published App name." >&2; exit 64; }
  [[ "$APP_SUPPORT_NAME" == "$PUBLISHED_APP_SUPPORT_NAME" ]] || { printf '%s\n' "main packages must preserve the published data namespace." >&2; exit 64; }
fi
[[ "$VERSION" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { printf '%s\n' "Package version contains unsafe filename characters." >&2; exit 64; }

STAMP="$(date +%Y%m%d-%H%M%S)"
OUT_DIR="$ROOT_DIR/Dist/$VERSION-$STAMP"
STAGE_DIR="$OUT_DIR/stage"
APP_DIR="${SHIXIN_DISK_HEALTH_APP_DIR:-$HOME/Applications/$APP_NAME.app}"
DMG_NAME="SHIXIN-LAB-CunJi-MacDisk-Health-$VERSION-$STAMP.dmg"
ZIP_NAME="SHIXIN-LAB-CunJi-MacDisk-Health-$VERSION-$STAMP.zip"
DMG_PATH="$OUT_DIR/$DMG_NAME"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"
RELEASE_DATE="${SHIXIN_DISK_HEALTH_RELEASE_DATE:-$(date +%Y-%m-%d)}"
SMARTMONTOOLS_SOURCE_SHA256="690b83ca331378da9ea0d9d61008c4b22dde391387b9bbad7f29387f2595f76e"
SMARTMONTOOLS_SOURCE_PATH="$ROOT_DIR/Licenses/Source/smartmontools-7.5.tar.gz"
MOUNT_POINT=""

cleanup_release_mount() {
  if [[ -n "$MOUNT_POINT" ]]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
    rmdir "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
}
trap cleanup_release_mount EXIT

[[ "$(basename "$APP_DIR")" == "$APP_NAME.app" ]] || { printf '%s\n' "Package App path does not match the selected identity." >&2; exit 64; }

for required_file in \
  "$ROOT_DIR/LICENSE" \
  "$ROOT_DIR/COPYRIGHT.md" \
  "$ROOT_DIR/TRADEMARKS.md" \
  "$ROOT_DIR/Packaging/INSTALL-zh-Hans.txt" \
  "$ROOT_DIR/Packaging/INSTALL-en.txt" \
  "$ROOT_DIR/Packaging/ABOUT-zh-Hans.txt" \
  "$ROOT_DIR/Packaging/ABOUT-en.txt" \
  "$ROOT_DIR/Packaging/RELEASE-NOTES-zh-Hans.txt" \
  "$ROOT_DIR/Packaging/RELEASE-NOTES-en.txt" \
  "$ROOT_DIR/Licenses/smartmontools-COPYING.txt" \
  "$ROOT_DIR/Licenses/smartmontools-NOTICE.md" \
  "$ROOT_DIR/Licenses/smartmontools-SOURCE.md" \
  "$SMARTMONTOOLS_SOURCE_PATH"; do
  [[ -f "$required_file" ]] || { printf 'Missing required release file: %s\n' "$required_file" >&2; exit 66; }
done

ACTUAL_SOURCE_SHA256="$(shasum -a 256 "$SMARTMONTOOLS_SOURCE_PATH" | awk '{ print $1 }')"
[[ "$ACTUAL_SOURCE_SHA256" == "$SMARTMONTOOLS_SOURCE_SHA256" ]] || {
  printf 'smartmontools source checksum mismatch: %s\n' "$ACTUAL_SOURCE_SHA256" >&2
  exit 65
}
tar -tzf "$SMARTMONTOOLS_SOURCE_PATH" >/dev/null

cd "$ROOT_DIR"
if [[ "$VARIANT" == "main" ]]; then
  SHIXIN_DISK_HEALTH_VARIANT="$VARIANT" SHIXIN_DISK_HEALTH_ALLOW_MAIN_BUILD=YES "$ROOT_DIR/Scripts/build-app.sh" >/dev/null
else
  SHIXIN_DISK_HEALTH_VARIANT="$VARIANT" "$ROOT_DIR/Scripts/build-app.sh" >/dev/null
fi

APP_PLIST="$APP_DIR/Contents/Info.plist"
APP_EXECUTABLE="$APP_DIR/Contents/MacOS/ShixinDiskHealth"
APP_SMARTCTL="$APP_DIR/Contents/Resources/Tools/smartctl"
[[ -f "$APP_PLIST" && -x "$APP_EXECUTABLE" && -x "$APP_SMARTCTL" ]] || {
  printf '%s\n' "Built App is missing required release contents." >&2
  exit 66
}
plutil -lint "$APP_PLIST" >/dev/null
ACTUAL_APP_NAME="$(plutil -extract CFBundleDisplayName raw -o - "$APP_PLIST")"
ACTUAL_BUNDLE_ID="$(plutil -extract CFBundleIdentifier raw -o - "$APP_PLIST")"
ACTUAL_SHORT_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP_PLIST")"
ACTUAL_BUILD_VERSION="$(plutil -extract CFBundleVersion raw -o - "$APP_PLIST")"
ACTUAL_MINIMUM_OS="$(plutil -extract LSMinimumSystemVersion raw -o - "$APP_PLIST")"
ACTUAL_ARCHITECTURE="$(lipo -archs "$APP_EXECUTABLE")"
[[ "$ACTUAL_APP_NAME" == "$APP_NAME" ]] || { printf '%s\n' "Built App name validation failed." >&2; exit 65; }
[[ ! -e "$APP_DIR/Contents/Library/LaunchDaemons" ]] || { printf '%s\n' "Release App unexpectedly contains a privileged helper." >&2; exit 65; }
"$APP_SMARTCTL" --version | grep -Fq 'smartctl 7.5' || { printf '%s\n' "Bundled smartctl version validation failed." >&2; exit 65; }
if [[ "$VARIANT" == "main" ]]; then
  [[ "$ACTUAL_BUNDLE_ID" == "com.shixinqvq.shixinlab.diskhealth" ]] || { printf '%s\n' "Main Bundle ID validation failed." >&2; exit 65; }
  [[ "$ACTUAL_SHORT_VERSION" == "$SHIXIN_DISK_HEALTH_SHORT_VERSION" ]] || { printf '%s\n' "Main short-version validation failed." >&2; exit 65; }
  [[ "$ACTUAL_BUILD_VERSION" == "$SHIXIN_DISK_HEALTH_BUNDLE_VERSION" ]] || { printf '%s\n' "Main build-number validation failed." >&2; exit 65; }
fi

mkdir -p "$STAGE_DIR"
ditto "$APP_DIR" "$STAGE_DIR/$APP_NAME.app"

render_guide() {
  local template="$1"
  local destination="$2"
  sed \
    -e "s|@APP_NAME@|$APP_NAME|g" \
    -e "s|@VERSION@|$VERSION|g" \
    -e "s|@APP_SUPPORT_NAME@|$APP_SUPPORT_NAME|g" \
    -e "s|@SHORT_VERSION@|$ACTUAL_SHORT_VERSION|g" \
    -e "s|@BUILD_VERSION@|$ACTUAL_BUILD_VERSION|g" \
    -e "s|@BUNDLE_ID@|$ACTUAL_BUNDLE_ID|g" \
    -e "s|@MINIMUM_OS@|$ACTUAL_MINIMUM_OS|g" \
    -e "s|@ARCHITECTURE@|$ACTUAL_ARCHITECTURE|g" \
    -e "s|@RELEASE_DATE@|$RELEASE_DATE|g" \
    "$template" > "$destination"
}

render_guide "$ROOT_DIR/Packaging/INSTALL-zh-Hans.txt" "$STAGE_DIR/安装说明.txt"
render_guide "$ROOT_DIR/Packaging/INSTALL-zh-Hans.txt" "$STAGE_DIR/Install Guide - zh-Hans.txt"
render_guide "$ROOT_DIR/Packaging/INSTALL-en.txt" "$STAGE_DIR/Install Guide - English.txt"
render_guide "$ROOT_DIR/Packaging/ABOUT-zh-Hans.txt" "$STAGE_DIR/产品与版权说明 - 中文.txt"
render_guide "$ROOT_DIR/Packaging/ABOUT-en.txt" "$STAGE_DIR/Product and Copyright - English.txt"
render_guide "$ROOT_DIR/Packaging/RELEASE-NOTES-zh-Hans.txt" "$STAGE_DIR/版本说明 - 中文.txt"
render_guide "$ROOT_DIR/Packaging/RELEASE-NOTES-en.txt" "$STAGE_DIR/Release Notes - English.txt"
ditto "$ROOT_DIR/LICENSE" "$STAGE_DIR/Open Source License - GPL-3.0.txt"
ditto "$ROOT_DIR/COPYRIGHT.md" "$STAGE_DIR/Copyright and Licensing.md"
ditto "$ROOT_DIR/TRADEMARKS.md" "$STAGE_DIR/Trademark and Brand Policy.md"
if [[ -d "$ROOT_DIR/Licenses" ]]; then
  ditto "$ROOT_DIR/Licenses" "$STAGE_DIR/Licenses"
fi
ln -s /Applications "$STAGE_DIR/Applications"

validate_release_tree() {
  local root="$1"
  local packaged_app="$root/$APP_NAME.app"
  local packaged_plist="$packaged_app/Contents/Info.plist"
  local packaged_smartctl="$packaged_app/Contents/Resources/Tools/smartctl"
  local source_archive="$root/Licenses/Source/smartmontools-7.5.tar.gz"
  local actual_source_hash

  for expected_path in \
    "$packaged_app" \
    "$root/安装说明.txt" \
    "$root/Install Guide - zh-Hans.txt" \
    "$root/Install Guide - English.txt" \
    "$root/产品与版权说明 - 中文.txt" \
    "$root/Product and Copyright - English.txt" \
    "$root/版本说明 - 中文.txt" \
    "$root/Release Notes - English.txt" \
    "$root/Open Source License - GPL-3.0.txt" \
    "$root/Copyright and Licensing.md" \
    "$root/Trademark and Brand Policy.md" \
    "$root/Licenses/smartmontools-COPYING.txt" \
    "$root/Licenses/smartmontools-NOTICE.md" \
    "$root/Licenses/smartmontools-SOURCE.md" \
    "$source_archive"; do
    [[ -e "$expected_path" ]] || { printf 'Release package is missing: %s\n' "$expected_path" >&2; return 1; }
  done

  [[ -L "$root/Applications" && "$(readlink "$root/Applications")" == "/Applications" ]] || {
    printf '%s\n' "Applications link validation failed." >&2
    return 1
  }
  [[ ! -e "$packaged_app/Contents/Library/LaunchDaemons" ]] || {
    printf '%s\n' "Packaged App unexpectedly contains a privileged helper." >&2
    return 1
  }
  [[ -f "$packaged_app/Contents/Resources/Licenses/smartmontools-SOURCE.md" ]] || return 1
  [[ -f "$packaged_app/Contents/Resources/Licenses/Source/smartmontools-7.5.tar.gz" ]] || return 1
  [[ -f "$packaged_app/Contents/Resources/Licenses/SHIXIN-LAB-GPL-3.0.txt" ]] || return 1
  [[ -f "$packaged_app/Contents/Resources/Licenses/SHIXIN-LAB-Copyright-and-Licensing.md" ]] || return 1
  [[ -f "$packaged_app/Contents/Resources/Licenses/SHIXIN-LAB-Trademark-and-Brand-Policy.md" ]] || return 1
  [[ "$(plutil -extract CFBundleIdentifier raw -o - "$packaged_plist")" == "$ACTUAL_BUNDLE_ID" ]] || return 1
  [[ "$(plutil -extract CFBundleShortVersionString raw -o - "$packaged_plist")" == "$ACTUAL_SHORT_VERSION" ]] || return 1
  [[ "$(plutil -extract CFBundleVersion raw -o - "$packaged_plist")" == "$ACTUAL_BUILD_VERSION" ]] || return 1
  [[ "$(lipo -archs "$packaged_app/Contents/MacOS/ShixinDiskHealth")" == "$ACTUAL_ARCHITECTURE" ]] || return 1
  "$packaged_smartctl" --version | grep -Fq 'smartctl 7.5' || return 1
  actual_source_hash="$(shasum -a 256 "$source_archive" | awk '{ print $1 }')"
  [[ "$actual_source_hash" == "$SMARTMONTOOLS_SOURCE_SHA256" ]] || return 1
  [[ "$(shasum -a 256 "$packaged_app/Contents/Resources/Licenses/Source/smartmontools-7.5.tar.gz" | awk '{ print $1 }')" == "$SMARTMONTOOLS_SOURCE_SHA256" ]] || return 1
  [[ -z "$(find "$root" -name '.DS_Store' -print -quit)" ]] || {
    printf '%s\n' "Release package contains .DS_Store." >&2
    return 1
  }
  if command -v codesign >/dev/null 2>&1; then
    codesign --verify --deep --strict "$packaged_app"
  fi
}

validate_release_tree "$STAGE_DIR"

hdiutil create \
  -volname "$DMG_VOLUME_NAME" \
  -srcfolder "$STAGE_DIR" \
  -format UDZO \
  -imagekey zlib-level=9 \
  "$DMG_PATH" >/dev/null
hdiutil verify "$DMG_PATH" >/dev/null

MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/shixin-cunji-dmg.XXXXXX")"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$DMG_PATH" >/dev/null
validate_release_tree "$MOUNT_POINT"
hdiutil detach "$MOUNT_POINT" >/dev/null
rmdir "$MOUNT_POINT"
MOUNT_POINT=""

(
  cd "$STAGE_DIR"
  ditto -c -k --sequesterRsrc . "$ZIP_PATH"
)
unzip -tq "$ZIP_PATH" >/dev/null

(
  cd "$OUT_DIR"
  shasum -a 256 "$DMG_NAME" "$ZIP_NAME" > SHA256SUMS.txt
  shasum -a 256 -c SHA256SUMS.txt
)

printf '%s\n' "$OUT_DIR"
printf '%s\n' "$DMG_PATH"
printf '%s\n' "$ZIP_PATH"
