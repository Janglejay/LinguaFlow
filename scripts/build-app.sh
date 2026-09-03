#!/bin/zsh

set -euo pipefail

project_dir=${0:A:h:h}
configuration=${1:-release}
app_bundle="$project_dir/.build/LinguaFlow.app"
helper_bundle="$app_bundle/Contents/Helpers/LinguaFlowSetup.app"

cd "$project_dir"

if ! brew list --versions librime >/dev/null 2>&1; then
  echo "Missing librime. Install it with: brew install librime" >&2
  exit 1
fi

swift build -c "$configuration" --product LinguaFlowIME
swift build -c "$configuration" --product LinguaFlowSetup
binary_dir=$(swift build -c "$configuration" --show-bin-path)

mkdir -p "$app_bundle/Contents/MacOS"
mkdir -p "$app_bundle/Contents/Resources/Rime"
mkdir -p "$helper_bundle/Contents/MacOS"

cp "$project_dir/Resources/Info.plist" "$app_bundle/Contents/Info.plist"
cp "$binary_dir/LinguaFlowIME" "$app_bundle/Contents/MacOS/LinguaFlowIME"
"$project_dir/scripts/prepare-rime-data.sh" "$app_bundle/Contents/Resources/Rime" >/dev/null
swift "$project_dir/scripts/make-icon.swift" "$app_bundle/Contents/Resources/InputSourceIcon.tiff"

cp "$project_dir/Resources/Setup-Info.plist" "$helper_bundle/Contents/Info.plist"
cp "$binary_dir/LinguaFlowSetup" "$helper_bundle/Contents/MacOS/LinguaFlowSetup"

codesign --force --sign - "$helper_bundle"
codesign --force --deep --sign - "$app_bundle"

plutil -lint "$app_bundle/Contents/Info.plist"
plutil -lint "$helper_bundle/Contents/Info.plist"
codesign --verify --deep --strict "$app_bundle"

echo "$app_bundle"
