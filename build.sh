#!/bin/bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "$0")" && pwd)"
cd -- "$project_dir"
output_dir="$project_dir/.build"
app_name="Keycap Caper.app"
mkdir -p -- "$output_dir"
staging_dir="$(mktemp -d "$output_dir/staging.XXXXXXXX")"
trap 'rm -rf -- "$staging_dir"' EXIT
app="$staging_dir/$app_name"
mkdir -p -- "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Helpers"

cp -X -- "$project_dir/Info.plist" "$app/Contents/Info.plist"
for portrait in Kitten Pickles Pipkin Periscope; do
    cp -X -- "$project_dir/Art/$portrait.png" "$app/Contents/Resources/"
done
cp -X -- "$project_dir/Branding/UpdatePublicKey.txt" "$app/Contents/Resources/"
iconset="$staging_dir/AppIcon.iconset"
mkdir "$iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$project_dir/Branding/AppIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" "$project_dir/Branding/AppIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
mkdir -p -- "$app/Contents/Resources/Sounds"
cp -X -- "$project_dir"/Sounds/*.wav "$app/Contents/Resources/Sounds/"
cp -X -- "$project_dir"/ThirdParty/*.txt "$app/Contents/Resources/"

flags=(-O -file-prefix-map "$project_dir=." -debug-prefix-map "$project_dir=." -file-compilation-dir .)
for arch in arm64 x86_64; do
    target="$arch-apple-macosx13.0"
    xcrun swiftc "${flags[@]}" -target "$target" -module-name CaperUpdateInstaller \
        Tools/UpdateInstaller.swift -o "$staging_dir/helper-$arch"
    xcrun swiftc "${flags[@]}" -target "$target" -module-name GreenEyedCat \
        Sources/*.swift -o "$staging_dir/pet-$arch"
done
xcrun lipo -create "$staging_dir"/helper-{arm64,x86_64} -output "$app/Contents/Helpers/CaperUpdateInstaller"
xcrun lipo -create "$staging_dir"/pet-{arm64,x86_64} -output "$app/Contents/MacOS/GreenEyedCat"
codesign --force --sign - "$app/Contents/Helpers/CaperUpdateInstaller"
codesign --sign - "$app"
codesign --verify --deep --strict "$app"

xcrun swift - "$app" "$output_dir/$app_name" <<'SWIFT'
import Darwin
let source = CommandLine.arguments[1], destination = CommandLine.arguments[2]
if renamex_np(source, destination, UInt32(RENAME_EXCL)) != 0 {
    guard errno == EEXIST, renamex_np(source, destination, UInt32(RENAME_SWAP)) == 0 else {
        perror("publish app")
        exit(1)
    }
}
SWIFT
printf '%s\n' "$output_dir/$app_name"
