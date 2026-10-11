#!/bin/zsh
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_ROOT="${IMAGEPRO_BUILD_ROOT:-${TMPDIR:-/tmp}/image-pro-swift-build}"
mkdir -p "$BUILD_ROOT"
zsh "$PROJECT_ROOT/scripts/compile-icon.sh"
xcrun -sdk macosx metal -c -fcikernel -mmacosx-version-min=14.0 "$PROJECT_ROOT/Shaders/ImageKernels.metal" -o "$BUILD_ROOT/ImageKernels.air"
xcrun -sdk macosx metallib -cikernel "$BUILD_ROOT/ImageKernels.air" -o "$PROJECT_ROOT/Sources/ImagePro/Resources/ImageKernels.metallib"
swift build --package-path "$PROJECT_ROOT" --scratch-path "$BUILD_ROOT" -c release
APP_ROOT="$PROJECT_ROOT/dist/iMage Pro.app"
LOCAL_APP_ROOT="${IMAGEPRO_STAGING_ROOT:-${TMPDIR:-/tmp}/image-pro-bundle/iMage Pro.app}"
BIN_ROOT="$(swift build --package-path "$PROJECT_ROOT" --scratch-path "$BUILD_ROOT" -c release --show-bin-path)"
# Start with a clean staging bundle so removed resources cannot survive a rebuild.
rm -rf "$LOCAL_APP_ROOT"
mkdir -p "$LOCAL_APP_ROOT/Contents/MacOS" "$LOCAL_APP_ROOT/Contents/Resources" "$PROJECT_ROOT/dist"
cp "$BIN_ROOT/ImagePro" "$LOCAL_APP_ROOT/Contents/MacOS/ImagePro"
ditto --noextattr --norsrc "$BIN_ROOT/ImagePro_ImagePro.bundle" "$LOCAL_APP_ROOT/Contents/Resources/ImagePro_ImagePro.bundle"
cp "$PROJECT_ROOT/Info.plist" "$LOCAL_APP_ROOT/Contents/Info.plist"
cp "$PROJECT_ROOT/Sources/ImagePro/Legal/ThirdPartyLicenses.txt" "$LOCAL_APP_ROOT/Contents/Resources/ThirdPartyLicenses.txt"
mkdir -p "$LOCAL_APP_ROOT/Contents/Frameworks"
cp "$PROJECT_ROOT/ThirdParty/ONNXRuntime/lib/libonnxruntime.1.30.0.dylib" \
   "$LOCAL_APP_ROOT/Contents/Frameworks/libonnxruntime.1.30.0.dylib"
install_name_tool -change \
  "$PROJECT_ROOT/ThirdParty/ONNXRuntime/lib/libonnxruntime.1.30.0.dylib" \
  "@loader_path/../Frameworks/libonnxruntime.1.30.0.dylib" \
  "$LOCAL_APP_ROOT/Contents/MacOS/ImagePro" 2>/dev/null || true
mkdir -p "$LOCAL_APP_ROOT/Contents/Resources/Licenses" \
  "$LOCAL_APP_ROOT/Contents/Resources/Licenses/MI-GAN" \
  "$LOCAL_APP_ROOT/Contents/Resources/Licenses/ONNXRuntime"
cp "$PROJECT_ROOT/ThirdParty/MI-GAN/LICENSE" "$LOCAL_APP_ROOT/Contents/Resources/Licenses/MI-GAN/LICENSE"
cp "$PROJECT_ROOT/ThirdParty/MI-GAN/LICENSE-WEIGHTS" "$LOCAL_APP_ROOT/Contents/Resources/Licenses/MI-GAN/LICENSE-WEIGHTS"
cp "$PROJECT_ROOT/ThirdParty/ONNXRuntime/LICENSE" "$LOCAL_APP_ROOT/Contents/Resources/Licenses/ONNXRuntime/LICENSE"
cp "$PROJECT_ROOT/ThirdParty/ONNXRuntime/ThirdPartyNotices.txt" "$LOCAL_APP_ROOT/Contents/Resources/Licenses/ONNXRuntime/ThirdPartyNotices.txt"
mkdir -p "$LOCAL_APP_ROOT/Contents/Resources/Licenses/Compositor"
cp "$PROJECT_ROOT/ThirdParty/Compositor/LICENSE" "$LOCAL_APP_ROOT/Contents/Resources/Licenses/Compositor/LICENSE"
cp "$PROJECT_ROOT/ThirdParty/Compositor/NOTICE.md" "$LOCAL_APP_ROOT/Contents/Resources/Licenses/Compositor/NOTICE.md"
cp "$PROJECT_ROOT/Sources/ImagePro/Resources/AppIcon.icns" "$LOCAL_APP_ROOT/Contents/Resources/AppIcon.icns"
cp "$PROJECT_ROOT/Sources/ImagePro/Resources/ImageKernels.metallib" "$LOCAL_APP_ROOT/Contents/Resources/ImageKernels.metallib"
cp "$PROJECT_ROOT/Sources/ImagePro/Resources/PrivacyInfo.xcprivacy" "$LOCAL_APP_ROOT/Contents/Resources/PrivacyInfo.xcprivacy"
if [[ -f "$PROJECT_ROOT/Sources/ImagePro/Resources/Assets.car" ]]; then
    cp "$PROJECT_ROOT/Sources/ImagePro/Resources/Assets.car" "$LOCAL_APP_ROOT/Contents/Resources/Assets.car"
fi
mkdir -p "$LOCAL_APP_ROOT/Contents/Resources/Fonts"
cp "$PROJECT_ROOT"/Sources/ImagePro/Resources/Fonts/* "$LOCAL_APP_ROOT/Contents/Resources/Fonts/"
python3 "$PROJECT_ROOT/scripts/verify-distribution.py" "$LOCAL_APP_ROOT"
dot_clean -m "$LOCAL_APP_ROOT"
xattr -cr "$LOCAL_APP_ROOT"
# Replace the upstream distribution signature with the bundle's reproducible
# ad-hoc signature before signing the enclosing app.
codesign --remove-signature "$LOCAL_APP_ROOT/Contents/Frameworks/libonnxruntime.1.30.0.dylib" 2>/dev/null || true
codesign --force --sign - "$LOCAL_APP_ROOT/Contents/Frameworks/libonnxruntime.1.30.0.dylib"
codesign --force --deep --sign - "$LOCAL_APP_ROOT"
INCOMING_APP_ROOT="$PROJECT_ROOT/dist/.image-Pro-incoming.app"
rm -rf "$INCOMING_APP_ROOT"
ditto --noextattr --norsrc "$LOCAL_APP_ROOT" "$INCOMING_APP_ROOT"
rm -f "$INCOMING_APP_ROOT/Contents/Resources/IconSource.png"
dot_clean -m "$INCOMING_APP_ROOT"
codesign --verify --deep --strict "$INCOMING_APP_ROOT"
if [[ -d "$APP_ROOT" ]]; then
    PREVIOUS_APP_ROOT="$PROJECT_ROOT/dist/Previous/iMage Pro-$(date +%Y%m%d-%H%M%S).app"
    mkdir -p "$PROJECT_ROOT/dist/Previous"
    mv "$APP_ROOT" "$PREVIOUS_APP_ROOT"
fi
LEGACY_APP_ROOT="$PROJECT_ROOT/dist/image Pro.app"
if [[ -d "$LEGACY_APP_ROOT" ]]; then
    mkdir -p "$PROJECT_ROOT/dist/Previous"
    mv "$LEGACY_APP_ROOT" "$PROJECT_ROOT/dist/Previous/image Pro-$(date +%Y%m%d-%H%M%S).app"
fi
mv "$INCOMING_APP_ROOT" "$APP_ROOT"
codesign --verify --deep --strict "$APP_ROOT"
python3 "$PROJECT_ROOT/scripts/verify-distribution.py" "$APP_ROOT"
echo "Built: $APP_ROOT"
