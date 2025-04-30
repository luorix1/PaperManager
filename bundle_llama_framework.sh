#!/bin/bash

# ----------------------------
# Usage:
# ./bundle_llama_framework.sh /path/to/PaperManager.app /path/to/llama.framework
# ----------------------------

set -e

APP_PATH="$1"
FRAMEWORK_SRC="$2"
FRAMEWORK_NAME="llama.framework"
FRAMEWORK_DST="$APP_PATH/Contents/Frameworks/$FRAMEWORK_NAME"
EXECUTABLE="$APP_PATH/Contents/MacOS/$(basename "$APP_PATH" .app)"

if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ Error: App not found at: $APP_PATH"
    exit 1
fi

if [[ ! -d "$FRAMEWORK_SRC" ]]; then
    echo "❌ Error: llama.framework not found at: $FRAMEWORK_SRC"
    exit 1
fi

echo "📦 Copying $FRAMEWORK_NAME into .app bundle..."

mkdir -p "$APP_PATH/Contents/Frameworks"
rm -rf "$FRAMEWORK_DST"
rsync -a --copy-links "$FRAMEWORK_SRC" "$FRAMEWORK_DST"

echo "🔗 Fixing framework symlinks..."

cd "$FRAMEWORK_DST"
rm -f llama Resources Versions/Current
ln -s Versions/A/llama llama
ln -s Versions/A/Resources Resources
ln -s A Versions/Current

echo "🔧 Adding rpath to binary..."
install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXECUTABLE"

echo "🔐 Signing the app bundle (ad-hoc)..."
codesign --force --deep --sign - "$APP_PATH"

echo "✅ Done! Signed and bundled framework into:"
echo "$APP_PATH"
