#!/bin/zsh

set -euo pipefail

project_dir=${0:A:h:h}
destination=${1:-"$project_dir/.build/rime-shared"}

mkdir -p "$destination"
cp "$project_dir/Vendor/rime-prelude"/*.yaml "$destination/"
cp "$project_dir/Vendor/rime-luna-pinyin"/*.yaml "$destination/"
cp "$project_dir/Vendor/rime-essay/essay.txt" "$destination/essay.txt"
cp "$project_dir/Resources/Rime/default.custom.yaml" "$destination/default.custom.yaml"

echo "$destination"
