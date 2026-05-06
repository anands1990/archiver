#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$PROJECT_DIR")"
APP_NAME="Archiver"
DIST_DIR="$ROOT_DIR/dist"
BUILD_DIR="$PROJECT_DIR/.build/release"

echo "🔨 Building $APP_NAME..."

# 1. Build Swift executable
cd "$PROJECT_DIR"
swift build -c release

# 2. Create .app bundle
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 3. Copy Swift executable
cp "$BUILD_DIR/ArchiveUploader" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# 4. Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Archiver</string>
    <key>CFBundleIdentifier</key>
    <string>com.anand.archiver</string>
    <key>CFBundleName</key>
    <string>Archiver</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
PLIST

# 5. Create PkgInfo
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# 6. Generate app icon
echo "🎨 Generating app icon..."
ICONSET_DIR="$APP_BUNDLE/Contents/Resources/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

for SIZE in 16 32 128 256 512; do
    DOUBLE=$((SIZE * 2))
    python3 -c "
import PIL.Image, PIL.ImageDraw
img = PIL.Image.new('RGBA', ($SIZE, $SIZE), (0,0,0,0))
draw = PIL.ImageDraw.Draw(img)
corner = int($SIZE * 0.2)
draw.rounded_rectangle([0,0,$SIZE,$SIZE], radius=corner, fill=(255,149,0))
margin = int($SIZE * 0.25)
draw.rectangle([margin, margin, $SIZE-margin, $SIZE-margin], fill=(255,255,255,220))
draw.rectangle([margin+int($SIZE*0.1), margin, margin+int($SIZE*0.15), $SIZE-margin], fill=(255,149,0))
img.save('$ICONSET_DIR/icon_${SIZE}x${SIZE}.png')
img2 = img.resize(($DOUBLE, $DOUBLE), PIL.Image.Resampling.LANCZOS)
img2.save('$ICONSET_DIR/icon_${SIZE}x${SIZE}@2x.png')
" 2>/dev/null || true
done

if command -v iconutil &> /dev/null && [ -d "$ICONSET_DIR" ]; then
    iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns" 2>/dev/null || true
    rm -rf "$ICONSET_DIR"
fi

# 7. Code sign (ad-hoc)
echo "🔏 Signing app..."
codesign --deep --force --verify --verbose --sign - "$APP_BUNDLE" 2>/dev/null || true

echo ""
echo "✅ Build complete!"
echo "📍 Location: $APP_BUNDLE"
echo ""
echo "To run: open '$APP_BUNDLE'"
