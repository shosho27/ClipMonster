#!/bin/bash

# build_app.sh
APP_NAME="ClipMonster"
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
# Compile all swift files in src
swiftc -parse-as-library ${SRC_DIR}/*.swift \
    -framework ServiceManagement \
    -framework Vision \
    -o "${MACOS_DIR}/${APP_NAME}"

echo "Creating Info.plist..."
cat <<EOF > "${CONTENTS_DIR}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.sashornock.${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

echo "Generating AppIcon.icns from BoarderPatrol.jpg..."
ICON_SRC="img/Clipmonster.jpg"
if [ -f "$ICON_SRC" ]; then
    ICONSET_DIR="img/ClipMonster.iconset"
    mkdir -p "$ICONSET_DIR"
    sips -s format png -z 16 16     "$ICON_SRC" --out "${ICONSET_DIR}/icon_16x16.png" > /dev/null
    sips -s format png -z 32 32     "$ICON_SRC" --out "${ICONSET_DIR}/icon_16x16@2x.png" > /dev/null
    sips -s format png -z 32 32     "$ICON_SRC" --out "${ICONSET_DIR}/icon_32x32.png" > /dev/null
    sips -s format png -z 64 64     "$ICON_SRC" --out "${ICONSET_DIR}/icon_32x32@2x.png" > /dev/null
    sips -s format png -z 128 128   "$ICON_SRC" --out "${ICONSET_DIR}/icon_128x128.png" > /dev/null
    sips -s format png -z 256 256   "$ICON_SRC" --out "${ICONSET_DIR}/icon_128x128@2x.png" > /dev/null
    sips -s format png -z 256 256   "$ICON_SRC" --out "${ICONSET_DIR}/icon_256x256.png" > /dev/null
    sips -s format png -z 512 512   "$ICON_SRC" --out "${ICONSET_DIR}/icon_256x256@2x.png" > /dev/null
    sips -s format png -z 512 512   "$ICON_SRC" --out "${ICONSET_DIR}/icon_512x512.png" > /dev/null
    sips -s format png -z 1024 1024 "$ICON_SRC" --out "${ICONSET_DIR}/icon_512x512@2x.png" > /dev/null
    
    iconutil -c icns "$ICONSET_DIR" -o "${RESOURCES_DIR}/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    echo "AppIcon.icns generated successfully."
else
    echo "Warning: Icon source not found at $ICON_SRC"
fi

echo "Packaging App for Team Sharing..."
cd "${DIST_DIR}"
zip -qr "${APP_NAME}.zip" "${APP_NAME}.app"
cd ..
echo "Build complete! App is at ${APP_BUNDLE} and zipped at ${DIST_DIR}/${APP_NAME}.zip"
