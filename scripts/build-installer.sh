#!/bin/zsh

set -euo pipefail
export COPYFILE_DISABLE=1

project_dir=${0:A:h:h}
configuration=${1:-release}
architecture=arm64
app_sign_identity=${CODE_SIGN_IDENTITY:--}
installer_sign_identity=${INSTALLER_SIGN_IDENTITY:-}
notarytool_profile=${NOTARYTOOL_PROFILE:-}
distribution_template="$project_dir/installer/Distribution.xml"
resources_source="$project_dir/installer/Resources"
package_scripts="$project_dir/installer/scripts"
dist_dir="$project_dir/.build/dist"

for tool in pkgbuild productbuild pkgutil otool codesign lipo; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    echo "Missing required developer tool: $tool" >&2
    exit 69
  fi
done

if [[ ! -x "$project_dir/scripts/embed-rime-runtime.sh" ]]; then
  echo "scripts/embed-rime-runtime.sh must be executable" >&2
  exit 66
fi

package_version=$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleShortVersionString' "$project_dir/Resources/Info.plist")
bundle_version=$(/usr/libexec/PlistBuddy \
  -c 'Print :CFBundleVersion' "$project_dir/Resources/Info.plist")
full_version="${package_version}.${bundle_version}"

if [[ "$app_sign_identity" == "-" && -z "$installer_sign_identity" ]]; then
  signature_suffix=-unsigned
elif [[ "$app_sign_identity" != "-" && -n "$installer_sign_identity" ]]; then
  signature_suffix=
else
  echo "Public signing requires both CODE_SIGN_IDENTITY and INSTALLER_SIGN_IDENTITY." >&2
  exit 64
fi

output_package="$dist_dir/LinguaFlow-${package_version}-macOS-${architecture}${signature_suffix}.pkg"

mkdir -p "$project_dir/.build" "$dist_dir"
work_dir=$(/usr/bin/mktemp -d "$project_dir/.build/installer.XXXXXX")
cleanup() {
  /bin/rm -rf "$work_dir"
}
trap cleanup EXIT

CODE_SIGN_IDENTITY="$app_sign_identity" \
  "$project_dir/scripts/build-app.sh" "$configuration" >/dev/null

payload_root="$work_dir/root"
payload_input_methods="$payload_root/Library/Input Methods"
mkdir -p "$payload_input_methods"
/usr/bin/ditto "$project_dir/.build/LinguaFlow.app" \
  "$payload_input_methods/LinguaFlow.app"
/usr/bin/ditto "$project_dir/.build/LinguaFlowEnglish.app" \
  "$payload_input_methods/LinguaFlowEnglish.app"
/usr/bin/xattr -cr "$payload_root"

verify_self_contained_bundle() {
  local app_bundle=$1
  local executable_name
  local executable
  local mach_o
  local detected_architectures
  local dependency
  local rpath
  local -a mach_o_files

  executable_name=$(/usr/libexec/PlistBuddy \
    -c 'Print :CFBundleExecutable' "$app_bundle/Contents/Info.plist")
  executable="$app_bundle/Contents/MacOS/$executable_name"

  codesign --verify --deep --strict "$app_bundle"

  mach_o_files=("$executable")
  while IFS= read -r mach_o; do
    mach_o_files+=("$mach_o")
  done < <(/usr/bin/find "$app_bundle/Contents/Frameworks" \
    -type f -name '*.dylib' -print | /usr/bin/sort)

  for mach_o in "${mach_o_files[@]}"; do
    detected_architectures=$(lipo -archs "$mach_o")
    if [[ "$detected_architectures" != "$architecture" ]]; then
      echo "Expected an arm64-only release, found '$detected_architectures': $mach_o" >&2
      exit 65
    fi

    while IFS= read -r dependency; do
      [[ -n "$dependency" ]] || continue
      case "$dependency" in
        /System/Library/*|/usr/lib/*|/Library/Apple/System/*) ;;
        @rpath/*)
          if [[ ! -f "$app_bundle/Contents/Frameworks/${dependency:t}" ]]; then
            echo "Bundled dependency is missing for $mach_o: $dependency" >&2
            exit 65
          fi
          ;;
        *)
          echo "External dependency remains in $mach_o: $dependency" >&2
          exit 65
          ;;
      esac
    done < <(otool -L "$mach_o" \
      | /usr/bin/tail -n +2 \
      | /usr/bin/sed -E 's/^[[:space:]]+([^[:space:]]+).*/\1/')

    while IFS= read -r rpath; do
      [[ -n "$rpath" ]] || continue
      case "$rpath" in
        @*|/System/Library/*|/usr/lib/*|/Library/Apple/System/*) ;;
        *)
          echo "External LC_RPATH remains in $mach_o: $rpath" >&2
          exit 65
          ;;
      esac
    done < <(otool -l "$mach_o" | /usr/bin/awk '
      $1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
      in_rpath && $1 == "path" { print $2; in_rpath = 0 }
    ')
  done
}

verify_self_contained_bundle "$payload_input_methods/LinguaFlow.app"
verify_self_contained_bundle "$payload_input_methods/LinguaFlowEnglish.app"

component_package="$work_dir/LinguaFlow-input-methods.pkg"
pkgbuild \
  --root "$payload_root" \
  --identifier com.fufangjie.pkg.LinguaFlow.input-methods \
  --version "$full_version" \
  --install-location / \
  --ownership recommended \
  --scripts "$package_scripts" \
  "$component_package" >/dev/null

distribution_file="$work_dir/Distribution.xml"
/usr/bin/sed \
  -e "s/@ARCHITECTURE@/$architecture/g" \
  -e "s/@PACKAGE_VERSION@/$full_version/g" \
  "$distribution_template" > "$distribution_file"

product_resources="$work_dir/Resources"
/usr/bin/ditto "$resources_source" "$product_resources"
{
  echo "LinguaFlow"
  echo
  /bin/cat "$project_dir/LICENSE"
  echo
  /bin/cat "$project_dir/THIRD_PARTY_NOTICES.md"
} > "$product_resources/License.txt"

/bin/rm -f "$output_package"
productbuild_arguments=(
  --distribution "$distribution_file"
  --resources "$product_resources"
  --package-path "$work_dir"
)
if [[ -n "$installer_sign_identity" ]]; then
  productbuild_arguments+=(--sign "$installer_sign_identity")
fi
productbuild "${productbuild_arguments[@]}" "$output_package" >/dev/null

(
  cd "$dist_dir"
  /usr/bin/shasum -a 256 "${output_package:t}"
) > "$output_package.sha256"

pkgutil --expand "$output_package" "$work_dir/expanded" >/dev/null
test -f "$work_dir/expanded/Distribution"
test -f "$work_dir/expanded/LinguaFlow-input-methods.pkg/Payload"
test -f "$work_dir/expanded/LinguaFlow-input-methods.pkg/Scripts/postinstall"

if [[ -n "$notarytool_profile" ]]; then
  if [[ -z "$installer_sign_identity" || "$app_sign_identity" == "-" ]]; then
    echo "Notarization requires CODE_SIGN_IDENTITY and INSTALLER_SIGN_IDENTITY." >&2
    exit 64
  fi
  /usr/bin/xcrun notarytool submit "$output_package" \
    --keychain-profile "$notarytool_profile" --wait
  /usr/bin/xcrun stapler staple "$output_package"
  /usr/bin/xcrun stapler validate "$output_package"
fi

echo "$output_package"
echo "$output_package.sha256"
if [[ -z "$installer_sign_identity" ]]; then
  echo "Note: package is unsigned. Set INSTALLER_SIGN_IDENTITY for public distribution." >&2
fi
if [[ -z "$notarytool_profile" ]]; then
  echo "Note: package is not notarized. Set NOTARYTOOL_PROFILE after signing." >&2
fi
