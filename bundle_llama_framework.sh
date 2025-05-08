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

# Remove any existing framework and create destination directory
mkdir -p "$APP_PATH/Contents/Frameworks"
rm -rf "$FRAMEWORK_DST"
mkdir -p "$FRAMEWORK_DST"

# Copy the contents of the framework, not the directory itself
rsync -a "$FRAMEWORK_SRC/" "$FRAMEWORK_DST/"

# Ensure Versions/A exists before making symlinks
if [[ ! -d "$FRAMEWORK_DST/Versions/A" ]]; then
    echo "❌ Error: $FRAMEWORK_DST/Versions/A does not exist after copy."
    exit 1
fi

cd "$FRAMEWORK_DST"

# Remove old symlinks if they exist
rm -f llama Resources Versions/Current

# Create symlinks only if the targets exist
if [[ -f Versions/A/llama ]]; then
    ln -s Versions/A/llama llama
else
    echo "⚠️  Warning: Versions/A/llama does not exist. Skipping symlink."
fi
if [[ -d Versions/A/Resources ]]; then
    ln -s Versions/A/Resources Resources
else
    echo "⚠️  Warning: Versions/A/Resources does not exist. Skipping symlink."
fi
ln -s A Versions/Current

cd - > /dev/null

echo "🔧 Adding rpath to binary..."
install_name_tool -add_rpath "@executable_path/../Frameworks" "$EXECUTABLE"

echo "🔐 Signing the app bundle (ad-hoc)..."
codesign --force --deep --sign - "$APP_PATH"

echo "✅ Done! Signed and bundled framework into:"
echo "$APP_PATH"
