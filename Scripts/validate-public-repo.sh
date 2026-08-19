#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

EXPECTED_BUNDLE_ID="com.shixinqvq.shixinlab.diskhealth"
EXPECTED_SHORT_VERSION="0.2.0"
EXPECTED_BUILD_VERSION="6"
EXPECTED_MINIMUM_OS="15.0"
EXPECTED_SMARTCTL_SHA256="af9162ac684d06d6ade196137af0c284babe03c90e7434b3c600edf48eafcd68"
EXPECTED_SOURCE_SHA256="690b83ca331378da9ea0d9d61008c4b22dde391387b9bbad7f29387f2595f76e"
EXPECTED_COPYING_SHA256="8177f97513213526df2cf6184d8ff986c675afb514d4e68a404010521b880643"

fail() {
  printf 'Public repository validation failed: %s\n' "$1" >&2
  exit 1
}

extract_localization_keys() {
  sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*=.*/\1/p' "$1" | sort
}

for command_name in bash comm file git grep lipo otool plutil sed shasum tar vtool; do
  command -v "$command_name" >/dev/null 2>&1 || fail "missing required command: $command_name"
done

git diff --check
bash -n Scripts/build-app.sh Scripts/package-share.sh Scripts/vendor-smartctl.sh Scripts/validate-public-repo.sh

plutil -lint \
  Packaging/Info.plist \
  Packaging/com.shixinqvq.shixinlab.diskhealth.helper.plist \
  Sources/ShixinDiskHealth/Resources/en.lproj/InfoPlist.strings \
  Sources/ShixinDiskHealth/Resources/en.lproj/Localizable.strings \
  Sources/ShixinDiskHealth/Resources/ja.lproj/InfoPlist.strings \
  Sources/ShixinDiskHealth/Resources/ja.lproj/Localizable.strings \
  Sources/ShixinDiskHealth/Resources/zh-Hans.lproj/InfoPlist.strings \
  Sources/ShixinDiskHealth/Resources/zh-Hans.lproj/Localizable.strings \
  >/dev/null

for locale in en ja zh-Hans; do
  strings_file="Sources/ShixinDiskHealth/Resources/$locale.lproj/Localizable.strings"
  duplicate_keys="$(
    extract_localization_keys "$strings_file" |
      uniq -d
  )"
  [[ -z "$duplicate_keys" ]] || fail "$locale localization contains duplicate keys"
done

diff -u \
  <(extract_localization_keys Sources/ShixinDiskHealth/Resources/en.lproj/Localizable.strings) \
  <(extract_localization_keys Sources/ShixinDiskHealth/Resources/ja.lproj/Localizable.strings) \
  >/dev/null || fail "English and Japanese localization keys differ"

extra_chinese_keys="$(
  comm -23 \
    <(extract_localization_keys Sources/ShixinDiskHealth/Resources/zh-Hans.lproj/Localizable.strings) \
    <(extract_localization_keys Sources/ShixinDiskHealth/Resources/en.lproj/Localizable.strings)
)"
[[ -z "$extra_chinese_keys" ]] || fail "Simplified Chinese localization contains keys missing from English"

for stale_phrase in \
  "当前 Beta" \
  "当前内部 v2" \
  "v1 原始记录没有被修改" \
  "未安装（当前无需安装）"; do
  if grep -R -F -n "$stale_phrase" Sources/ShixinDiskHealth/Resources/*.lproj/Localizable.strings; then
    fail "stale localization text remains: $stale_phrase"
  fi
done

for required_key in \
  "旧版测速历史导入失败" \
  "旧版 SMART 历史导入失败" \
  "旧版原始记录没有被修改；请检查当前数据目录权限后重试。" \
  "旧版原始记录没有被修改；当前版本会继续读取自己的历史记录。"; do
  for locale in en ja zh-Hans; do
    grep -Fq "\"$required_key\" =" \
      "Sources/ShixinDiskHealth/Resources/$locale.lproj/Localizable.strings" ||
      fail "$locale localization is missing: $required_key"
  done
done

[[ "$(plutil -extract CFBundleIdentifier raw -o - Packaging/Info.plist)" == "$EXPECTED_BUNDLE_ID" ]] ||
  fail "published Bundle ID changed"
[[ "$(plutil -extract CFBundleShortVersionString raw -o - Packaging/Info.plist)" == "$EXPECTED_SHORT_VERSION" ]] ||
  fail "published short version changed"
[[ "$(plutil -extract CFBundleVersion raw -o - Packaging/Info.plist)" == "$EXPECTED_BUILD_VERSION" ]] ||
  fail "published build version changed"
[[ "$(plutil -extract LSMinimumSystemVersion raw -o - Packaging/Info.plist)" == "$EXPECTED_MINIMUM_OS" ]] ||
  fail "minimum macOS version changed"

SMARTCTL_PATH="Sources/ShixinDiskHealth/Resources/Tools/smartctl"
SOURCE_ARCHIVE="Licenses/Source/smartmontools-7.5.tar.gz"
[[ -x "$SMARTCTL_PATH" ]] || fail "bundled smartctl is missing or not executable"
[[ "$(shasum -a 256 "$SMARTCTL_PATH" | awk '{ print $1 }')" == "$EXPECTED_SMARTCTL_SHA256" ]] ||
  fail "bundled smartctl hash changed"
[[ "$(shasum -a 256 "$SOURCE_ARCHIVE" | awk '{ print $1 }')" == "$EXPECTED_SOURCE_SHA256" ]] ||
  fail "smartmontools source archive hash changed"
[[ "$(tar -xOf "$SOURCE_ARCHIVE" smartmontools-7.5/COPYING | shasum -a 256 | awk '{ print $1 }')" == "$EXPECTED_COPYING_SHA256" ]] ||
  fail "smartmontools source license does not match the published copy"
[[ "$(shasum -a 256 Licenses/smartmontools-COPYING.txt | awk '{ print $1 }')" == "$EXPECTED_COPYING_SHA256" ]] ||
  fail "published smartmontools license copy changed"
[[ "$(lipo -archs "$SMARTCTL_PATH")" == "arm64" ]] || fail "bundled smartctl is not arm64"
[[ "$(vtool -show-build "$SMARTCTL_PATH" | awk '$1 == "minos" { print $2; exit }')" == "$EXPECTED_MINIMUM_OS" ]] ||
  fail "bundled smartctl minimum macOS version changed"

unexpected_dependencies="$(
  otool -L "$SMARTCTL_PATH" |
    tail -n +2 |
    awk '{ print $1 }' |
    grep -Ev '^(/System/Library/|/usr/lib/)' || true
)"
[[ -z "$unexpected_dependencies" ]] || fail "bundled smartctl has non-system runtime dependencies"

[[ -f CODE_OF_CONDUCT.md ]] || fail "CODE_OF_CONDUCT.md is missing"
grep -Fq 'connection.invalidate()' Sources/ShixinDiskHealthPrivilegedHelper/main.swift ||
  fail "dormant Helper is not fail-closed"
grep -Fq 'return false' Sources/ShixinDiskHealthPrivilegedHelper/main.swift ||
  fail "dormant Helper accepts an XPC connection"
if grep -Fq 'return true' Sources/ShixinDiskHealthPrivilegedHelper/main.swift; then
  fail "dormant Helper contains an accepting connection path"
fi
grep -Fq 'Release App unexpectedly contains a privileged helper.' Scripts/package-share.sh ||
  fail "release packaging no longer rejects the privileged Helper"

tracked_artifacts="$(
  git ls-files |
    grep -E '(^|/)(\.DS_Store|\.build|Backups|Dist)(/|$)|\.(dmg|zip|xcarchive|pem|p12|mobileprovision|provisionprofile)$' ||
    true
)"
[[ -z "$tracked_artifacts" ]] || fail "generated, private, or release artifacts are tracked"

printf '%s\n' "Public repository validation passed."
