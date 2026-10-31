#!/bin/bash
set -e
umask 077

cd "$(dirname "$0")"
ROOT_DIR="$(pwd)"
APP_NAME="MyBackup"
APP_DIR="$ROOT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
BACKEND_DIR="$RESOURCES_DIR/backend"
VENV_DIR="$RESOURCES_DIR/venv"
SWIFT_SRC="$ROOT_DIR/MyBackupApp.swift"
BACKEND_PY="$BACKEND_DIR/backend.py"
EXECUTABLE="$MACOS_DIR/$APP_NAME"
ICONSET_DIR="$ROOT_DIR/MyBackup.iconset"
ICNS_FILE="$RESOURCES_DIR/MyBackup.icns"
BACKGROUND_SRC="$ROOT_DIR/MyBackupBackground.png"
BACKGROUND_FALLBACK_SRC="/Users/yvancognasse/Downloads/MyTranslator/MyTranslatorBackground.png"
BACKGROUND_FILE="$RESOURCES_DIR/MyBackupBackground.png"
PREVIOUS_ICON_FILE="$(mktemp /private/tmp/mybackup-previous-icon.XXXXXX)"
if [ -s "$RESOURCES_DIR/MyBackup.icns" ]; then
  cp "$RESOURCES_DIR/MyBackup.icns" "$PREVIOUS_ICON_FILE"
fi
trap 'rm -f "$PREVIOUS_ICON_FILE"' EXIT

CURRENT_BUILD="1"
if [ -f "$CONTENTS_DIR/Info.plist" ]; then
  CURRENT_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CONTENTS_DIR/Info.plist" 2>/dev/null || printf "1")"
fi
if [[ "$CURRENT_BUILD" == *.* ]]; then
  CURRENT_BUILD="${CURRENT_BUILD##*.}"
fi
if ! [[ "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
  CURRENT_BUILD="1"
fi
APP_BUILD=$((CURRENT_BUILD + 1))

printf "\n[MyBackup] Stable macOS generator - Swift UI + Python backend\n"
printf "[MyBackup] Folder: %s\n\n" "$ROOT_DIR"
printf "[MyBackup] Build: %s\n" "$APP_BUILD"

if ! command -v python3 >/dev/null 2>&1; then
  printf "[ERROR] python3 not found. Install Python 3.\n"
  exit 1
fi

if ! command -v swiftc >/dev/null 2>&1; then
  printf "[ERROR] swiftc not found. Install the Apple Command Line Tools:\n"
  printf "        xcode-select --install\n"
  exit 1
fi

if [ ! -f "$ROOT_DIR/MyBackup.env" ]; then
  printf "[MyBackup] MyBackup.env not found. Setup is now stored in macOS preferences.\n"
else
  printf "[MyBackup] Existing MyBackup.env kept for first-run import only.\n"
fi

if [ ! -f "$ROOT_DIR/credentials.json" ]; then
  printf "[WARNING] credentials.json is missing in %s\n" "$ROOT_DIR"
  printf "                The app will open, but Google Drive sign-in will fail until credentials.json is present.\n"
fi

printf "[MyBackup] Cleaning the previous bundle...\n"
rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$BACKEND_DIR"

if [ -f "$BACKGROUND_SRC" ]; then
  cp "$BACKGROUND_SRC" "$BACKGROUND_FILE"
  printf "[MyBackup] Background image copied from MyBackupBackground.png.\n"
elif [ -f "$BACKGROUND_FALLBACK_SRC" ]; then
  cp "$BACKGROUND_FALLBACK_SRC" "$BACKGROUND_FILE"
  printf "[MyBackup] Background image copied.\n"
else
  printf "[WARNING] Background image not found: %s\n" "$BACKGROUND_SRC"
fi

ICON_ENABLED="false"
ICON_SOURCE="$ROOT_DIR/MyBackup-icon.png"
if [ -f "$ICON_SOURCE" ]; then
  printf "[MyBackup] Creating the icon from MyBackup-icon.png...\n"
  mkdir -p "$ICONSET_DIR"
  set +e
  sips -s format png -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null 2>&1
  sips -s format png -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null 2>&1
  sips -s format png -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null 2>&1
  sips -s format png -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null 2>&1
  sips -s format png -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null 2>&1
  sips -s format png -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null 2>&1
  sips -s format png -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null 2>&1
  sips -s format png -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null 2>&1
  sips -s format png -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null 2>&1
  sips -s format png -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null 2>&1
  iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE" >/dev/null 2>&1
  ICON_STATUS=$?
  set -e
  rm -rf "$ICONSET_DIR"
  if [ "$ICON_STATUS" -eq 0 ] && [ -f "$ICNS_FILE" ]; then
    ICON_ENABLED="true"
    printf "[MyBackup] Icon created.\n"
  elif [ -s "$PREVIOUS_ICON_FILE" ]; then
    cp "$PREVIOUS_ICON_FILE" "$ICNS_FILE"
    ICON_ENABLED="true"
    printf "[MyBackup] Reusing the previous icon.\n"
  else
    printf "[WARNING] Could not generate the icon from MyBackup-icon.png. Keeping the default icon.\n"
  fi
else
  printf "[MyBackup] MyBackup-icon.png not found. Keeping the default icon.\n"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>local.mybackup.app</string>
    <key>CFBundleVersion</key>
    <string>$APP_BUILD</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_BUILD</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>LSMinimumSystemVersion</key>
    <string>10.15</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>MyBackup opens local log and configuration files.</string>
    <key>NSDocumentsFolderUsageDescription</key>
    <string>MyBackup needs access to the configured source folders.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>MyBackup needs access to the configured source folders.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>MyBackup needs access to the configured source folders.</string>
PLIST
if [ "$ICON_ENABLED" = "true" ]; then
  cat >> "$CONTENTS_DIR/Info.plist" <<PLIST
    <key>CFBundleIconFile</key>
    <string>MyBackup</string>
PLIST
fi
cat >> "$CONTENTS_DIR/Info.plist" <<'PLIST'
</dict>
</plist>
PLIST

cp "$ROOT_DIR/backend.py" "$BACKEND_PY"

printf "[MyBackup] Compiling the native Swift interface...\n"
swiftc "$SWIFT_SRC" -o "$EXECUTABLE" -framework Cocoa
chmod +x "$EXECUTABLE"

printf "[MyBackup] Creating the embedded Python venv...\n"
python3 -m venv --copies "$VENV_DIR"

printf "[MyBackup] Installing Python dependencies...\n"
"$VENV_DIR/bin/python" -m pip install --upgrade pip >/dev/null
"$VENV_DIR/bin/python" -m pip install --quiet \
  google-api-python-client \
  google-auth-httplib2 \
  google-auth-oauthlib

printf "[MyBackup] Checking the backend...\n"
"$VENV_DIR/bin/python" - <<'PY'
import googleapiclient
import google_auth_oauthlib
import google_auth_httplib2
import httplib2
print("backend ok")
PY

chmod -R u+rwX "$APP_DIR"
xattr -cr "$APP_DIR" 2>/dev/null || true
touch "$APP_DIR" "$CONTENTS_DIR/Info.plist" "$ICNS_FILE" 2>/dev/null || true
printf "[MyBackup] Signing and verifying the local app bundle...\n"
codesign --force --deep --sign - --timestamp=none "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f "$APP_DIR" 2>/dev/null || true
fi

printf "\n[OK] MyBackup.app created here:\n"
printf "%s\n" "$APP_DIR"
printf "\nRuntime files next to the app:\n"
printf "%s\n" "- credentials.json"
printf "%s\n" "- token.json, MyBackup.cache.json, MyBackup.log, MyBackup.launch.log, crash.log"
printf "\nLaunch:\n"
printf "%s\n" "open '$APP_DIR'"
printf "\nIf Finder still shows the previous icon:\n"
printf "%s\n\n" "touch '$APP_DIR' && killall Finder"
