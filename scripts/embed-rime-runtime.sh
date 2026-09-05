#!/bin/zsh

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 /path/to/InputMethod.app" >&2
  exit 64
fi

app_bundle=$1
info_plist="$app_bundle/Contents/Info.plist"

if [[ ! -f "$info_plist" ]]; then
  echo "Input method bundle is missing Info.plist: $app_bundle" >&2
  exit 66
fi

executable_name=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$info_plist")
main_executable="$app_bundle/Contents/MacOS/$executable_name"
frameworks_dir="$app_bundle/Contents/Frameworks"

if [[ ! -x "$main_executable" ]]; then
  echo "Input method executable is missing: $main_executable" >&2
  exit 66
fi

mkdir -p "$frameworks_dir"

is_system_dependency() {
  local dependency=$1
  [[ "$dependency" == /System/Library/* \
    || "$dependency" == /usr/lib/* \
    || "$dependency" == /Library/Apple/System/* \
    || "$dependency" == @* ]]
}

dependencies_for() {
  /usr/bin/otool -L "$1" \
    | /usr/bin/tail -n +2 \
    | /usr/bin/sed -E 's/^[[:space:]]+([^[:space:]]+).*/\1/'
}

rpaths_for() {
  /usr/bin/otool -l "$1" | /usr/bin/awk '
    $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
    in_rpath && $1 == "path" { print $2; in_rpath = 0 }
  '
}

is_allowed_rpath() {
  local rpath=$1
  [[ "$rpath" == @* \
    || "$rpath" == /System/Library/* \
    || "$rpath" == /usr/lib/* \
    || "$rpath" == /Library/Apple/System/* ]]
}

typeset -a pending
typeset -A visited
typeset -A source_paths
pending=("$main_executable")

while (( ${#pending[@]} > 0 )); do
  current=${pending[1]}
  pending[1]=()

  while IFS= read -r dependency; do
    [[ -n "$dependency" ]] || continue
    is_system_dependency "$dependency" && continue

    if [[ ! -e "$dependency" ]]; then
      echo "Cannot embed missing dynamic library: $dependency" >&2
      exit 66
    fi

    library_name=${dependency:t}
    destination="$frameworks_dir/$library_name"
    resolved_source=${dependency:A}

    if [[ -z ${visited[$library_name]-} ]]; then
      # Dereference Homebrew's version aliases so every copied file is
      # self-contained and never points back into /opt/homebrew.
      /bin/cp -fL "$dependency" "$destination"
      /bin/chmod u+w "$destination"
      /usr/bin/codesign --remove-signature "$destination" >/dev/null 2>&1 || true
      visited[$library_name]=1
      source_paths[$library_name]=$resolved_source
      pending+=("$destination")
    elif [[ ${source_paths[$library_name]} != "$resolved_source" ]] \
      && ! /usr/bin/cmp -s "${source_paths[$library_name]}" "$resolved_source"; then
      echo "Dynamic libraries share the same filename but differ: $dependency" >&2
      exit 65
    fi
  done < <(dependencies_for "$current")
done

typeset -a mach_o_files
mach_o_files=("$main_executable")
while IFS= read -r library; do
  mach_o_files+=("$library")
done < <(/usr/bin/find "$frameworks_dir" -type f -name '*.dylib' -print | /usr/bin/sort)

for mach_o in "${mach_o_files[@]}"; do
  if [[ "$mach_o" == *.dylib ]]; then
    /usr/bin/install_name_tool -id "@rpath/${mach_o:t}" "$mach_o"
  fi

  while IFS= read -r dependency; do
    [[ -n "$dependency" ]] || continue
    is_system_dependency "$dependency" && continue
    /usr/bin/install_name_tool \
      -change "$dependency" "@rpath/${dependency:t}" "$mach_o"
  done < <(dependencies_for "$mach_o")

  while IFS= read -r rpath; do
    [[ -n "$rpath" ]] || continue
    if ! is_allowed_rpath "$rpath"; then
      /usr/bin/install_name_tool -delete_rpath "$rpath" "$mach_o"
    fi
  done < <(rpaths_for "$mach_o")
done

if ! /usr/bin/otool -l "$main_executable" \
  | /usr/bin/grep -Fq 'path @executable_path/../Frameworks '; then
  /usr/bin/install_name_tool \
    -add_rpath '@executable_path/../Frameworks' "$main_executable"
fi

bad_dependencies=()
bad_rpaths=()
for mach_o in "${mach_o_files[@]}"; do
  while IFS= read -r dependency; do
    [[ -n "$dependency" ]] || continue
    if ! is_system_dependency "$dependency"; then
      bad_dependencies+=("$mach_o -> $dependency")
    fi
  done < <(dependencies_for "$mach_o")

  while IFS= read -r rpath; do
    [[ -n "$rpath" ]] || continue
    if ! is_allowed_rpath "$rpath"; then
      bad_rpaths+=("$mach_o -> $rpath")
    fi
  done < <(rpaths_for "$mach_o")
done

if (( ${#bad_dependencies[@]} > 0 )); then
  echo "The bundle still has external dynamic-library dependencies:" >&2
  printf '  %s\n' "${bad_dependencies[@]}" >&2
  exit 65
fi

if (( ${#bad_rpaths[@]} > 0 )); then
  echo "The bundle still has external runtime search paths:" >&2
  printf '  %s\n' "${bad_rpaths[@]}" >&2
  exit 65
fi

echo "$frameworks_dir"
