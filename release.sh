#!/bin/bash
# Archives, exports, notarizes, staples and packages AudioRouter into a
# ready-to-distribute signed .dmg. Requires:
#   - The "Developer ID Application" certificate installed (see project.yml).
#   - A stored notarytool credentials profile named "AudioRouter-notary"
#     (xcrun notarytool store-credentials "AudioRouter-notary" --apple-id ... --team-id WV8SAHT65Z)
#
# Usage: ./release.sh [version]
#   version defaults to whatever MARKETING_VERSION is in project.yml.

set -euo pipefail
cd "$(dirname "$0")"

TEAM_ID="WV8SAHT65Z"
SIGNING_IDENTITY="Developer ID Application: Jose Sanchez Gonzalez ($TEAM_ID)"
NOTARY_PROFILE="AudioRouter-notary"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/AudioRouter.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
APP_PATH="$EXPORT_PATH/AudioRouter.app"
DMG_PATH="$BUILD_DIR/AudioRouter.dmg"
UPDATES_DIR="site"
APPCAST_PATH="$UPDATES_DIR/appcast.xml"
DOWNLOAD_URL_PREFIX="https://audiorouter-app.vercel.app/"
SPARKLE_TOOLS="$HOME/.config/audiorouter/sparkle-tools"
SPARKLE_KEY_FILE="$HOME/.config/audiorouter/sparkle_ed25519_private_key"

echo "==> Regenerating Xcode project"
xcodegen generate

echo "==> Cleaning previous build output"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Archiving (Release)"
xcodebuild -project AudioRouter.xcodeproj -scheme AudioRouter -configuration Release \
  archive -archivePath "$ARCHIVE_PATH"

echo "==> Exporting signed .app"
xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH" -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist ExportOptions.plist

echo "==> Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

echo "==> Building .dmg"
DMG_SRC="$BUILD_DIR/dmg-src"
rm -rf "$DMG_SRC"
mkdir -p "$DMG_SRC"
cp -R "$APP_PATH" "$DMG_SRC/"
ln -s /Applications "$DMG_SRC/Applications"
hdiutil create -volname "AudioRouter Installer" -srcfolder "$DMG_SRC" -ov -format UDZO "$DMG_PATH"
rm -rf "$DMG_SRC"

echo "==> Signing .dmg"
codesign --sign "$SIGNING_IDENTITY" "$DMG_PATH"

echo "==> Zipping .app for notarization"
APP_ZIP="$BUILD_DIR/AudioRouter-app.zip"
rm -f "$APP_ZIP"
ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"

echo "==> Submitting .app for notarization"
xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait \
  || { echo "App notarization failed — inspect with 'xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE'"; exit 1; }

# Notarizing the .app alone doesn't staple it when it's inside a zip/dmg wrapper for
# submission, so staple the .app in place, then rebuild + re-sign the dmg around it,
# then separately notarize+staple the dmg itself (Apple's recommended flow for both).
echo "==> Stapling .app"
xcrun stapler staple "$APP_PATH"

echo "==> Rebuilding .dmg with stapled .app"
rm -rf "$DMG_SRC" "$DMG_PATH"
mkdir -p "$DMG_SRC"
cp -R "$APP_PATH" "$DMG_SRC/"
ln -s /Applications "$DMG_SRC/Applications"
hdiutil create -volname "AudioRouter Installer" -srcfolder "$DMG_SRC" -ov -format UDZO "$DMG_PATH"
rm -rf "$DMG_SRC"
codesign --sign "$SIGNING_IDENTITY" "$DMG_PATH"

echo "==> Submitting .dmg for notarization"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait \
  || { echo "DMG notarization failed — inspect with 'xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE'"; exit 1; }

echo "==> Stapling .dmg"
xcrun stapler staple "$DMG_PATH"

echo "==> Final Gatekeeper check"
spctl -a -vv -t open --context context:primary-signature "$DMG_PATH"

echo "==> Updating Sparkle appcast"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP_PATH/Contents/Info.plist")
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "14.4")

mkdir -p "$UPDATES_DIR"
VERSIONED_DMG="$UPDATES_DIR/AudioRouter-$VERSION.dmg"
cp "$DMG_PATH" "$VERSIONED_DMG"

SIGN_OUTPUT=$("$SPARKLE_TOOLS/sign_update" --ed-key-file "$SPARKLE_KEY_FILE" "$VERSIONED_DMG")
ED_SIGNATURE=$(echo "$SIGN_OUTPUT" | sed -E 's/.*sparkle:edSignature="([^"]*)".*/\1/')
LENGTH=$(echo "$SIGN_OUTPUT" | sed -E 's/.*length="([^"]*)".*/\1/')

python3 - "$APPCAST_PATH" "$VERSION" "$BUILD" "$MIN_OS" "$ED_SIGNATURE" "$LENGTH" "$DOWNLOAD_URL_PREFIX" <<'PYEOF'
import sys, re
from email.utils import formatdate

appcast_path, version, build, min_os, signature, length, url_prefix = sys.argv[1:8]
pub_date = formatdate(localtime=False)
filename = f"AudioRouter-{version}.dmg"

item = f"""    <item>
      <title>Versión {version}</title>
      <sparkle:version>{build}</sparkle:version>
      <sparkle:shortVersionString>{version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>{min_os}</sparkle:minimumSystemVersion>
      <pubDate>{pub_date}</pubDate>
      <enclosure
          url="{url_prefix}{filename}"
          sparkle:edSignature="{signature}"
          length="{length}"
          type="application/octet-stream" />
    </item>
"""

try:
    with open(appcast_path) as f:
        xml = f.read()
except FileNotFoundError:
    xml = """<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0">
  <channel>
    <title>AudioRouter Updates</title>
    <link>{url_prefix}appcast.xml</link>
    <description>Actualizaciones de AudioRouter</description>
    <language>es</language>
  </channel>
</rss>
""".format(url_prefix=url_prefix)

# Drop any existing entry for this exact version (re-releasing the same version
# overwrites rather than duplicates), then insert the new one right after <language>.
xml = re.sub(
    r'\s*<item>\s*<title>Versión ' + re.escape(version) + r'</title>.*?</item>\s*',
    '\n',
    xml,
    flags=re.DOTALL,
)
xml = xml.replace('</language>', '</language>\n' + item, 1)

with open(appcast_path, 'w') as f:
    f.write(xml)

print(f"appcast.xml updated for version {version} (build {build})")
PYEOF

echo ""
echo "Done:"
echo "  $DMG_PATH"
echo "  $VERSIONED_DMG"
echo "  $APPCAST_PATH"
echo ""
echo "Next:"
echo "  cd $UPDATES_DIR && vercel --prod"
echo "  Then re-point the custom alias to the new deployment (it doesn't follow automatically):"
echo "  vercel alias set <new-deployment-url> audiorouter-app.vercel.app"
