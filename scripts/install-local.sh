#!/bin/zsh

set -euo pipefail

project_dir=${0:A:h:h}
source_bundle=$($project_dir/scripts/build-app.sh release | tail -n 1)
destination_dir="$HOME/Library/Input Methods"
destination_bundle="$destination_dir/LinguaFlow.app"

pkill -x LinguaFlowIME >/dev/null 2>&1 || true
pkill -x LinguaFlowSetup >/dev/null 2>&1 || true
mkdir -p "$destination_dir"
ditto "$source_bundle" "$destination_bundle"
codesign --verify --deep --strict "$destination_bundle"
"$destination_bundle/Contents/MacOS/LinguaFlowIME" --register-input-source

echo "Installed: $destination_bundle"
echo "Next: System Settings > Keyboard > Text Input > Edit, then add LinguaFlow 英语输入."
echo "Before translating, open LinguaFlow's input menu and choose 准备本地中英翻译."
