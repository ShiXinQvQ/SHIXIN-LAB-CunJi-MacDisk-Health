#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SMARTCTL_PATH="${1:-}"
MAXIMUM_MIN_OS="${SHIXIN_DISK_HEALTH_SMARTCTL_MAX_MIN_OS:-15.0}"

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

if [[ -z "$SMARTCTL_PATH" ]]; then
  if [[ -x "/opt/homebrew/bin/smartctl" ]]; then
    SMARTCTL_PATH="/opt/homebrew/bin/smartctl"
  elif [[ -x "/usr/local/bin/smartctl" ]]; then
    SMARTCTL_PATH="/usr/local/bin/smartctl"
  else
    echo "smartctl not found. Install smartmontools or pass a path." >&2
    exit 1
  fi
fi

if [[ ! -x "$SMARTCTL_PATH" ]]; then
  echo "smartctl is not executable: $SMARTCTL_PATH" >&2
  exit 1
fi

command -v vtool >/dev/null 2>&1 || { echo "vtool is required to validate smartctl." >&2; exit 1; }
command -v otool >/dev/null 2>&1 || { echo "otool is required to validate smartctl." >&2; exit 1; }

SMARTCTL_MIN_OS="$(vtool -show-build "$SMARTCTL_PATH" | awk '$1 == "minos" { print $2; exit }')"
if [[ -z "$SMARTCTL_MIN_OS" ]] || ! version_is_at_most "$SMARTCTL_MIN_OS" "$MAXIMUM_MIN_OS"; then
  printf 'Refusing smartctl with minimum macOS %s; required maximum is %s.\n' "${SMARTCTL_MIN_OS:-unknown}" "$MAXIMUM_MIN_OS" >&2
  exit 1
fi

UNEXPECTED_DEPENDENCIES="$(otool -L "$SMARTCTL_PATH" | tail -n +2 | awk '{ print $1 }' | grep -Ev '^(/System/Library/|/usr/lib/)' || true)"
if [[ -n "$UNEXPECTED_DEPENDENCIES" ]]; then
  printf '%s\n%s\n' "Refusing smartctl with non-system runtime dependencies:" "$UNEXPECTED_DEPENDENCIES" >&2
  exit 1
fi

"$SMARTCTL_PATH" --version >/dev/null

mkdir -p "$ROOT_DIR/Sources/ShixinDiskHealth/Resources/Tools" "$ROOT_DIR/Licenses"
cp "$SMARTCTL_PATH" "$ROOT_DIR/Sources/ShixinDiskHealth/Resources/Tools/smartctl"

if [[ -f "/opt/homebrew/Cellar/smartmontools/7.5/COPYING" ]]; then
  cp "/opt/homebrew/Cellar/smartmontools/7.5/COPYING" "$ROOT_DIR/Licenses/smartmontools-COPYING.txt"
fi

cat > "$ROOT_DIR/Licenses/smartmontools-NOTICE.md" <<'NOTICE'
# smartmontools Notice

This project bundles `smartctl` 7.5 from smartmontools for local SMART / NVMe health reporting.

- Upstream: https://github.com/smartmontools/smartmontools
- License: GPL-2.0-or-later, see `smartmontools-COPYING.txt`
- Bundled component name: smartctl
- Corresponding source and checksums: see `smartmontools-SOURCE.md` and `Source/smartmontools-7.5.tar.gz`

The bundled `smartctl` is not owned by SHIXIN LAB and must not be represented as closed-source proprietary code.
NOTICE

"$ROOT_DIR/Sources/ShixinDiskHealth/Resources/Tools/smartctl" --version
printf 'Vendored smartctl minimum macOS: %s\n' "$SMARTCTL_MIN_OS"
