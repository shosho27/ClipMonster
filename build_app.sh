#!/bin/bash
set -euo pipefail

# Direct edition: ./build_app.sh
# Mac App Store (sandboxed, -D MAS): ./build_app.sh mas

APP_NAME="ClipMonster 2.0"
EXECUTABLE_NAME="ClipMonster2"
BUNDLE_ID="com.sashornock.ClipMonster2"
SRC_DIR="src"
DIST_DIR="dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
MAS_BUILD=0
if [ "${1:-}" = "mas" ]; then
    MAS_BUILD=1
fi

echo "Cleaning dist directory..."
rm -rf "${DIST_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "Compiling Swift source..."
SWIFT_SOURCES=()
while IFS= read -r source_file; do
    SWIFT_SOURCES+=("$source_file")
done < <(find "$SRC_DIR" -type f -name '*.swift' -print | sort)

SWIFT_FLAGS=()
XCODE_MACOS_PLUGINS="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
XCODE_MACOS_SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
if [ -d "$XCODE_MACOS_PLUGINS" ]; then
    SWIFT_FLAGS+=(-plugin-path "$XCODE_MACOS_PLUGINS")
fi
if [ -d "$XCODE_MACOS_SDK" ]; then
    SWIFT_FLAGS+=(-sdk "$XCODE_MACOS_SDK")
fi
export MACOSX_DEPLOYMENT_TARGET=14.0
SWIFT_FLAGS+=(-target arm64-apple-macos14)
if [ "$MAS_BUILD" -eq 1 ]; then
    SWIFT_FLAGS+=(-D MAS)
    echo "Building Mac App Store edition (sandboxed, no synthetic paste)."
fi

swiftc -parse-as-library "${SWIFT_SOURCES[@]}" \
    "${SWIFT_FLAGS[@]}" \
    -framework ServiceManagement \
    -framework Vision \
    -framework ImageIO \
    -framework Carbon \
    -o "${MACOS_DIR}/${EXECUTABLE_NAME}"

echo "Installing Info.plist and privacy manifest..."
cp "Config/Info.plist" "${CONTENTS_DIR}/Info.plist"
cp "Config/PrivacyInfo.xcprivacy" "${RESOURCES_DIR}/PrivacyInfo.xcprivacy"

echo "Bundling ClipMonster artwork and application icon..."
ICON_SRC="img/Clipmonster.jpg"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "${RESOURCES_DIR}/Clipmonster.jpg"
    ICONSET_DIR="${DIST_DIR}/ClipMonster.iconset"
    mkdir -p "$ICONSET_DIR"
    sips -s format png -z 16 16     "$ICON_SRC" --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null
    sips -s format png -z 32 32     "$ICON_SRC" --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null
    sips -s format png -z 64 64     "$ICON_SRC" --out "${ICONSET_DIR}/icon_64x64.png" > /dev/null
    sips -s format png -z 128 128   "$ICON_SRC" --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null
    sips -s format png -z 256 256   "$ICON_SRC" --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null
    sips -s format png -z 512 512   "$ICON_SRC" --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null
    sips -s format png -z 1024 1024 "$ICON_SRC" --out "${ICONSET_DIR}/icon_1024x1024.png" > /dev/null
    swift Scripts/make_icns.swift "$ICONSET_DIR" "${RESOURCES_DIR}/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    echo "Menu-bar artwork and AppIcon.icns bundled successfully."
else
    echo "Warning: Icon source not found at $ICON_SRC"
fi

if [ "$MAS_BUILD" -eq 1 ]; then
    echo "Ad-hoc signing with App Sandbox entitlements..."
    codesign --force --deep --sign - \
        --identifier "${BUNDLE_ID}" \
        --entitlements "Config/ClipMonsterMAS.entitlements" \
        "${APP_BUNDLE}"
    echo "Sandboxed signature:"
    codesign -d --entitlements - "${APP_BUNDLE}" 2>&1 | head -20
else
    DEV_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Apple Development:[^"]*\)"/\1/p' | head -1)
    if [ -n "${DEV_IDENTITY}" ]; then
        echo "Signing with ${DEV_IDENTITY} so Accessibility survives rebuilds..."
        codesign --force --deep --sign "${DEV_IDENTITY}" --identifier "${BUNDLE_ID}" "${APP_BUNDLE}"
    else
        echo "Ad-hoc signing (direct edition)..."
        codesign --force --deep --sign - --identifier "${BUNDLE_ID}" "${APP_BUNDLE}" || true
    fi
fi

echo "Packaging App for Team Sharing..."
cd "${DIST_DIR}"
zip -qr "${APP_NAME}.zip" "${APP_NAME}.app"
cd ..
if [ "$MAS_BUILD" -eq 1 ]; then
    echo "MAS build complete: ${APP_BUNDLE}"
else
    echo "Direct build complete: ${APP_BUNDLE}"
fi
echo "Zipped at ${DIST_DIR}/${APP_NAME}.zip"
