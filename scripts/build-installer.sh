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

for tool in pkgbuild productbuild pkgutil otool codesign lipo xmllint; do
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

package_filename="LinguaFlow-${package_version}-macOS-${architecture}${signature_suffix}.pkg"
output_package="$dist_dir/$package_filename"

mkdir -p "$project_dir/.build" "$dist_dir"
work_dir=$(/usr/bin/mktemp -d "$project_dir/.build/installer.XXXXXX")
staged_package="$work_dir/$package_filename"
cleanup() {
  /bin/rm -rf "$work_dir"
}
trap cleanup EXIT

/bin/rm -f "$output_package" "$output_package.sha256"

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

for opencc_resource in \
  t2s.json \
  t2hk.json \
  t2tw.json \
  CJK_Compatibility_Ideographs.ocd2 \
  TSPhrases.ocd2 \
  TSCharactersExt.ocd2 \
  TSCharacters.ocd2 \
  HKVariantsPhrases.ocd2 \
  HKVariants.ocd2 \
  TWVariantsPhrases.ocd2 \
  TWVariants.ocd2; do
  if [[ ! -r "$payload_input_methods/LinguaFlow.app/Contents/Resources/Rime/opencc/$opencc_resource" ]]; then
    echo "Chinese input method is missing OpenCC data: $opencc_resource" >&2
    exit 65
  fi
done

component_plist="$work_dir/components.plist"
pkgbuild --analyze --root "$payload_root" "$component_plist" >/dev/null

# pkgbuild otherwise treats bundles as relocatable and may silently reinstall an
# input method at a previously registered user-domain path. Keep both products
# pinned to /Library/Input Methods so the payload and postinstall agree.
chinese_component_count=0
english_component_count=0
component_index=0
while component_path=$(/usr/libexec/PlistBuddy \
  -c "Print :$component_index:RootRelativeBundlePath" \
  "$component_plist" 2>/dev/null); do
  case "$component_path" in
    "Library/Input Methods/LinguaFlow.app")
      /usr/libexec/PlistBuddy \
        -c "Set :$component_index:BundleIsRelocatable false" \
        "$component_plist"
      ((chinese_component_count += 1))
      ;;
    "Library/Input Methods/LinguaFlowEnglish.app")
      /usr/libexec/PlistBuddy \
        -c "Set :$component_index:BundleIsRelocatable false" \
        "$component_plist"
      ((english_component_count += 1))
      ;;
    *)
      echo "Unexpected top-level bundle in installer payload: $component_path" >&2
      exit 65
      ;;
  esac
  ((component_index += 1))
done

if [[ "$chinese_component_count" -ne 1 || "$english_component_count" -ne 1 ]]; then
  echo "Expected exactly one component for each input-method bundle." >&2
  exit 65
fi

component_package="$work_dir/LinguaFlow-input-methods.pkg"
pkgbuild \
  --root "$payload_root" \
  --component-plist "$component_plist" \
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

productbuild_arguments=(
  --distribution "$distribution_file"
  --resources "$product_resources"
  --package-path "$work_dir"
)
if [[ -n "$installer_sign_identity" ]]; then
  productbuild_arguments+=(--sign "$installer_sign_identity")
fi
productbuild "${productbuild_arguments[@]}" "$staged_package" >/dev/null

pkgutil --expand "$staged_package" "$work_dir/expanded" >/dev/null
test -f "$work_dir/expanded/Distribution"
test -f "$work_dir/expanded/LinguaFlow-input-methods.pkg/Payload"
test -f "$work_dir/expanded/LinguaFlow-input-methods.pkg/Scripts/postinstall"

package_info="$work_dir/expanded/LinguaFlow-input-methods.pkg/PackageInfo"
package_relocatable=$(/usr/bin/xmllint \
  --xpath 'string(/pkg-info/@relocatable)' "$package_info")
if [[ "$package_relocatable" != false ]]; then
  echo "Installer component must be marked non-relocatable." >&2
  exit 65
fi

relocatable_bundle_count=$(/usr/bin/xmllint \
  --xpath 'count(/pkg-info/relocate/bundle)' "$package_info")
if [[ "$relocatable_bundle_count" != 0 ]]; then
  echo "Installer unexpectedly contains relocatable bundles." >&2
  exit 65
fi

for expected_bundle_path in \
  './Library/Input Methods/LinguaFlow.app' \
  './Library/Input Methods/LinguaFlowEnglish.app'; do
  packaged_bundle_count=$(/usr/bin/xmllint \
    --xpath "count(/pkg-info/bundle[@path='$expected_bundle_path'])" \
    "$package_info")
  if [[ "$packaged_bundle_count" != 1 ]]; then
    echo "Installer is missing its fixed bundle path: $expected_bundle_path" >&2
    exit 65
  fi
done

for expected_bundle_identifier in \
  com.fufangjie.inputmethod.LinguaFlow \
  com.fufangjie.inputmethod.LinguaFlowEnglish; do
  upgrade_bundle_count=$(/usr/bin/xmllint \
    --xpath "count(/pkg-info/upgrade-bundle/bundle[@id='$expected_bundle_identifier'])" \
    "$package_info")
  if [[ "$upgrade_bundle_count" != 1 ]]; then
    echo "Installer is missing upgrade metadata for: $expected_bundle_identifier" >&2
    exit 65
  fi
done

if [[ -n "$notarytool_profile" ]]; then
  if [[ -z "$installer_sign_identity" || "$app_sign_identity" == "-" ]]; then
    echo "Notarization requires CODE_SIGN_IDENTITY and INSTALLER_SIGN_IDENTITY." >&2
    exit 64
  fi
  /usr/bin/xcrun notarytool submit "$staged_package" \
    --keychain-profile "$notarytool_profile" --wait
  /usr/bin/xcrun stapler staple "$staged_package"
  /usr/bin/xcrun stapler validate "$staged_package"
fi

(
  cd "$work_dir"
  /usr/bin/shasum -a 256 "$package_filename"
) > "$staged_package.sha256"

/bin/mv "$staged_package.sha256" "$output_package.sha256"
/bin/mv "$staged_package" "$output_package"
(
  cd "$dist_dir"
  /usr/bin/shasum -a 256 -c "${package_filename}.sha256" >/dev/null
)

echo "$output_package"
echo "$output_package.sha256"
if [[ -z "$installer_sign_identity" ]]; then
  echo "Note: package is unsigned. Set INSTALLER_SIGN_IDENTITY for public distribution." >&2
fi
if [[ -z "$notarytool_profile" ]]; then
  echo "Note: package is not notarized. Set NOTARYTOOL_PROFILE after signing." >&2
fi
