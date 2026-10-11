#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON_INPUT="${1:-$PROJECT_ROOT/Design/Icon.icon}"
ICON_BUILD_ROOT="${IMAGEPRO_ICON_BUILD_ROOT:-${TMPDIR:-/tmp}/image-pro-icon-build}"
mkdir -p "$ICON_BUILD_ROOT"
xcrun actool --compile "$ICON_BUILD_ROOT" --platform macosx \
  --minimum-deployment-target 26.0 --app-icon Icon \
  --output-partial-info-plist "$ICON_BUILD_ROOT/icon-info.plist" "$ICON_INPUT"
cp "$ICON_BUILD_ROOT/Assets.car" "$PROJECT_ROOT/Sources/ImagePro/Resources/Assets.car"
cp "$ICON_BUILD_ROOT/Icon.icns" "$PROJECT_ROOT/Sources/ImagePro/Resources/AppIcon.icns"
