#!/bin/bash

# build_app.sh
APP_NAME="ClipMonster 2.0"
EXECUTABLE_NAME="ClipMonster2"
BUNDLE_ID="com.sashornock.ClipMonster2"
SRC_DIR="src"
DIST_DIR="dist"
APP_BUNDLE="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_BUNDLE}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"

echo "Cleaning dist directory..."
rm -rf "${DIST_DIR}"
mkdir -p "${MACOS_DIR}"
mkdir -p "${RESOURCES_DIR}"

echo "Compiling Swift source..."
# Compile every Swift file below src so feature areas can use their own folders.
SWIFT_SOURCES=()
while IFS= read -r source_file; do
    SWIFT_SOURCES+=("$source_file")
done < <(find "$SRC_DIR" -type f -name '*.swift' -print | sort)

# Command Line Tools swiftc does not search Xcode's SwiftUI macro plugin path.
SWIFT_FLAGS=()
XCODE_MACOS_PLUGINS="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins"
XCODE_MACOS_SDK="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
if [ -d "$XCODE_MACOS_PLUGINS" ]; then
    SWIFT_FLAGS+=(-plugin-path "$XCODE_MACOS_PLUGINS")
fi
if [ -d "$XCODE_MACOS_SDK" ]; then
    SWIFT_FLAGS+=(-sdk "$XCODE_MACOS_SDK")
fi

swiftc -parse-as-library "${SWIFT_SOURCES[@]}" \
    "${SWIFT_FLAGS[@]}" \
    -framework ServiceManagement \
    -framework Vision \
    -framework ImageIO \
    -o "${MACOS_DIR}/${EXECUTABLE_NAME}"
if [ $? -ne 0 ]; then
    echo "Swift compile failed."
    exit 1
fi

echo "Creating Info.plist..."
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${EXECUTABLE_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleVersion</key>
    <string>2.0</string>
    <key>CFBundleShortVersionString</key>
    <string>2.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

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

echo "Packaging App for Team Sharing..."
cd "${DIST_DIR}"
zip -qr "${APP_NAME}.zip" "${APP_NAME}.app"
cd ..
echo "Build complete! App is at ${APP_BUNDLE} and zipped at ${DIST_DIR}/${APP_NAME}.zip"
