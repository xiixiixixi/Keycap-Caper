#!/bin/bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "$0")/.." && pwd)"
app="${1:-$project_dir/.build/Keycap Caper.app}"
channel="${2:-$project_dir/.build/release}"
private_key="${CAPER_SIGNING_KEY:?Set CAPER_SIGNING_KEY to the publisher private key path.}"
public_key="$project_dir/Branding/UpdatePublicKey.txt"
plist="$app/Contents/Info.plist"
version="$(plutil -extract CFBundleShortVersionString raw "$plist")"
build="$(plutil -extract CFBundleVersion raw "$plist")"
[[ "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ && "$build" =~ ^[0-9]+$ ]] || {
    echo "Invalid release version or build number." >&2
    exit 1
}
notes="${3:-$project_dir/Releases/$version.txt}"
test -s "$notes"
codesign --verify --strict --deep "$app"
cmp "$public_key" "$app/Contents/Resources/UpdatePublicKey.txt"
for executable in "$app/Contents/MacOS/GreenEyedCat" "$app/Contents/Helpers/CaperUpdateInstaller"; do
    case "$(xcrun lipo -archs "$executable")" in
        "arm64 x86_64"|"x86_64 arm64") ;;
        *) echo "Missing universal executable in release." >&2; exit 1 ;;
    esac
done

mkdir -p -- "$channel"
staging="$(mktemp -d "$channel/.publish.XXXXXXXX")"
trap 'rm -rf -- "$staging"' EXIT
python3 - "$app" "$staging/update.zip" <<'PY'
import stat
import sys
from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo

app = Path(sys.argv[1])
if app.is_symlink() or app.name != "Keycap Caper.app":
    sys.exit("Expected a Keycap Caper application bundle.")
with ZipFile(sys.argv[2], "x", compression=ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob("*")):
        mode = path.lstat().st_mode
        if stat.S_ISDIR(mode):
            continue
        if not stat.S_ISREG(mode) or path.name.startswith("."):
            sys.exit("Unexpected entry in the application bundle.")
        info = ZipInfo(path.relative_to(app.parent).as_posix(), (1980, 1, 1, 0, 0, 0))
        info.create_system = 3
        perm = 0o755 if mode & 0o111 else 0o644
        info.external_attr = (stat.S_IFREG | perm) << 16
        archive.writestr(info, path.read_bytes(), compress_type=ZIP_DEFLATED)
PY
digest="$(shasum -a 256 "$staging/update.zip" | cut -c1-16)"
filename="Keycap-Caper-$version-macOS-universal-$build-$digest.zip"
mv "$staging/update.zip" "$staging/$filename"
xcrun swift "$project_dir/Tools/SignRelease.swift" sign "$private_key" "$public_key" \
    "$app" "$staging/$filename" universal "$notes" "$staging/latest.json"
mv -f -- "$staging/$filename" "$channel/$filename"
mv -f -- "$staging/latest.json" "$channel/latest.json"
printf '%s\n' "$channel/$filename"
