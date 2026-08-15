#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
app_name='ChatGPT 订阅额度监控 V2'
app_path="$project_dir/build/$app_name.app"
temporary_dir="$(mktemp -d)"
iconset_dir="$temporary_dir/AppIcon.iconset"

cleanup() {
  rm -rf "$temporary_dir"
}
trap cleanup EXIT

rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$iconset_dir"

cp "$project_dir/AppBundle/Info.plist" "$app_path/Contents/Info.plist"
cp "$project_dir/Assets/AppIcon.iconset/icon_16x16.png" "$iconset_dir/"
cp "$project_dir/Assets/AppIcon.iconset/icon_16x16@2x.png" "$iconset_dir/"
cp "$project_dir/Assets/AppIcon.iconset/icon_32x32.png" "$iconset_dir/"
cp "$project_dir/Assets/AppIcon.iconset/icon_32x32@2x.png" "$iconset_dir/"
cp "$project_dir/Assets/AppIcon.iconset/icon_128x128.png" "$iconset_dir/"
cp "$project_dir/Assets/AppIcon.iconset/icon_128x128@2x.png" "$iconset_dir/"
cp "$project_dir/Assets/AppIcon.iconset/icon_256x256.png" "$iconset_dir/"
cp "$project_dir/Assets/AppIcon.iconset/icon_256x256@2x.png" "$iconset_dir/"
cp "$project_dir/Assets/AppIcon.iconset/icon_512x512.png" "$iconset_dir/"

iconutil -c icns "$iconset_dir" -o "$app_path/Contents/Resources/AppIcon.icns"
swiftc "$project_dir/Sources/CodexQuotaMeter.swift" \
  -O \
  -parse-as-library \
  -framework AppKit \
  -framework SwiftUI \
  -o "$app_path/Contents/MacOS/CodexQuotaMeter"
strip -x "$app_path/Contents/MacOS/CodexQuotaMeter"
codesign --force --sign - --timestamp=none "$app_path"

echo "Built: $app_path"
