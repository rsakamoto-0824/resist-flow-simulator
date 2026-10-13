#!/bin/bash
set -euo pipefail

source_directory="$(cd "$(dirname "$0")" && pwd)"
project_directory="$(dirname "$source_directory")"
build_stamp="$(date +%Y%m%d-%H%M%S)"
output_directory="$project_directory/dist/macos/$build_stamp"
app_directory="$output_directory/Resist Flow Lab.app"
machine_arch="$(uname -m)"

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "macOS 上で実行してください。" >&2
    exit 1
fi
if [[ -e "$output_directory" ]]; then
    echo "出力先が存在します。少し待ってから再実行してください。" >&2
    exit 1
fi
for asset in index.html styles.css app.js infiltration.js; do
    test -f "$source_directory/web/$asset"
done
cd "$project_directory"
npm test
mkdir -p "$app_directory/Contents/MacOS" "$app_directory/Contents/Resources/web" "$project_directory/output/mac-test"
xcrun swiftc -O -swift-version 5 \
    -target "$machine_arch-apple-macosx12.0" \
    -framework AppKit -framework WebKit -framework UniformTypeIdentifiers \
    "$source_directory/App.swift" \
    -o "$app_directory/Contents/MacOS/ResistFlowLabMacTest"
cp "$source_directory/Info.plist" "$app_directory/Contents/Info.plist"
cp "$source_directory/web/"* "$app_directory/Contents/Resources/web/"
cp "$project_directory/verification/js/solver.js" "$app_directory/Contents/Resources/web/solver.js"
plutil -lint "$app_directory/Contents/Info.plist"
codesign --force --sign - "$app_directory"
codesign --verify --deep --strict "$app_directory"
ditto -c -k --keepParent "$app_directory" "$output_directory/ResistFlowLab-Mac-Test.zip"
printf '%s\n' "$app_directory" > "$project_directory/output/mac-test/latest-app-path.txt"
printf 'Built: %s\nArchitecture: %s\n' "$app_directory" "$machine_arch"
