#!/bin/zsh

set -euo pipefail

project_dir=${0:A:h:h}
destination=${1:-"$project_dir/.build/rime-shared"}
opencc_data_directory=${LINGUAFLOW_OPENCC_DATA_DIR:-}
opencc_binary=${LINGUAFLOW_OPENCC_BINARY:-}

if [[ -z "$opencc_data_directory" ]]; then
  if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew OpenCC data was not found; install librime or set LINGUAFLOW_OPENCC_DATA_DIR." >&2
    exit 69
  fi
  opencc_prefix=$(brew --prefix opencc 2>/dev/null) || {
    echo "Homebrew OpenCC data was not found; install librime or set LINGUAFLOW_OPENCC_DATA_DIR." >&2
    exit 69
  }
  opencc_data_directory="$opencc_prefix/share/opencc"
  [[ -n "$opencc_binary" ]] || opencc_binary="$opencc_prefix/bin/opencc"
fi

if [[ -z "$opencc_binary" ]]; then
  opencc_binary=$(command -v opencc 2>/dev/null || true)
fi
if [[ ! -x "$opencc_binary" ]]; then
  echo "OpenCC command-line validation tool was not found; set LINGUAFLOW_OPENCC_BINARY." >&2
  exit 69
fi

opencc_resources=(
  t2s.json
  t2hk.json
  t2tw.json
  CJK_Compatibility_Ideographs.ocd2
  TSPhrases.ocd2
  TSCharactersExt.ocd2
  TSCharacters.ocd2
  HKVariantsPhrases.ocd2
  HKVariants.ocd2
  TWVariantsPhrases.ocd2
  TWVariants.ocd2
)

for resource in "${opencc_resources[@]}"; do
  if [[ ! -r "$opencc_data_directory/$resource" ]]; then
    echo "Required OpenCC resource is missing: $opencc_data_directory/$resource" >&2
    exit 66
  fi
done

if [[ -L "$destination" || -L "$destination/opencc" ]]; then
  echo "Refusing to prepare Rime data through a symbolic-link destination: $destination" >&2
  exit 65
fi

mkdir -p "$destination/opencc"
cp "$project_dir/Vendor/rime-prelude"/*.yaml "$destination/"
cp "$project_dir/Vendor/rime-luna-pinyin"/*.yaml "$destination/"
cp "$project_dir/Vendor/rime-essay/essay.txt" "$destination/essay.txt"
cp "$project_dir/Resources/Rime/default.custom.yaml" "$destination/default.custom.yaml"
for resource in "${opencc_resources[@]}"; do
  cp "$opencc_data_directory/$resource" "$destination/opencc/$resource"
done

schema_opencc_configs=()
while IFS= read -r config; do
  [[ -n "$config" ]] && schema_opencc_configs+=("$config")
done < <(/usr/bin/awk '$1 == "opencc_config:" { print $2 }' \
  "$project_dir/Vendor/rime-luna-pinyin"/*.yaml | /usr/bin/sort -u)

if [[ "${#schema_opencc_configs[@]}" -eq 0 ]]; then
  echo "No OpenCC configurations were found in the bundled Rime schemas." >&2
  exit 65
fi

for config in "${schema_opencc_configs[@]}"; do
  if [[ ! -r "$destination/opencc/$config" ]]; then
    echo "Bundled Rime schema references missing OpenCC configuration: $config" >&2
    exit 65
  fi
  if ! print -r -- '測試' | "$opencc_binary" \
    -c "$destination/opencc/$config" >/dev/null; then
    echo "Bundled OpenCC configuration failed validation: $config" >&2
    exit 65
  fi
done

echo "$destination"
