#!/bin/bash
set -e

APP_NAME="SchematicModeler"
BUNDLE_ID="com.marshallbenson.SchematicModeler"
VERSION="1.0.0"
BUILD_DIR=".build/release"
APP_BUNDLE="$APP_NAME.app"

echo "Building release..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy executable
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# Copy SPM resource bundle (contains AppIcon.png)
if [ -d "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" ]; then
    cp -R "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" "$APP_BUNDLE/Contents/Resources/"
fi

# Copy app icon
ICON_SRC="Sources/SchematicModeler/Resources/AppIcon.png"
if [ -f "$ICON_SRC" ]; then
    # Create .icns from PNG using sips + iconutil
    ICONSET_DIR=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET_DIR"
    sips -z 16 16     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16.png"      > /dev/null 2>&1
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_16x16@2x.png"   > /dev/null 2>&1
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32.png"      > /dev/null 2>&1
    sips -z 64 64     "$ICON_SRC" --out "$ICONSET_DIR/icon_32x32@2x.png"   > /dev/null 2>&1
    sips -z 128 128   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128.png"    > /dev/null 2>&1
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null 2>&1
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256.png"    > /dev/null 2>&1
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null 2>&1
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512.png"    > /dev/null 2>&1
    sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null 2>&1
    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET_DIR")"
    echo "  Icon converted to .icns"
fi

# Write Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>3D Schematic Modeler</string>
    <key>CFBundleDisplayName</key>
    <string>3D Schematic Modeler</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

# Install to /Applications
echo "Installing to /Applications..."
rm -rf "/Applications/$APP_BUNDLE"
cp -R "$APP_BUNDLE" /Applications/

# Add to Dock (or replace existing entry)
APP_PATH="/Applications/$APP_BUNDLE"
echo "Updating Dock..."

# Remove existing entry if present
DOCK_PLIST="$HOME/Library/Preferences/com.apple.dock.plist"
CURRENT=$(/usr/libexec/PlistBuddy -c "Print persistent-apps" "$DOCK_PLIST" 2>/dev/null | grep -c "file-label" || true)
for (( i=CURRENT-1; i>=0; i-- )); do
    LABEL=$(/usr/libexec/PlistBuddy -c "Print persistent-apps:$i:tile-data:file-label" "$DOCK_PLIST" 2>/dev/null || true)
    if [ "$LABEL" = "3D Schematic Modeler" ] || [ "$LABEL" = "$APP_NAME" ]; then
        /usr/libexec/PlistBuddy -c "Delete persistent-apps:$i" "$DOCK_PLIST"
        echo "  Removed old Dock entry"
    fi
done

# Add new entry
defaults write com.apple.dock persistent-apps -array-add \
    "<dict>
        <key>tile-data</key>
        <dict>
            <key>file-data</key>
            <dict>
                <key>_CFURLString</key>
                <string>file://$APP_PATH/</string>
                <key>_CFURLStringType</key>
                <integer>15</integer>
            </dict>
            <key>file-label</key>
            <string>3D Schematic Modeler</string>
            <key>file-type</key>
            <integer>41</integer>
        </dict>
        <key>tile-type</key>
        <string>file-tile</string>
    </dict>"

killall Dock

echo ""
echo "Done! Installed to /Applications/$APP_BUNDLE and added to Dock."
