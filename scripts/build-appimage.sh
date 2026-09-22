#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
appdir="$repo_root/build/appimage/DeadSpace1-KR.AppDir"
output="${1:-$repo_root/dist/DeadSpace1-KR-0.3-x86_64.AppImage}"
appimagetool="${APPIMAGETOOL:-$repo_root/build/appimage/appimagetool-x86_64.AppImage}"
appimage_runtime="${APPIMAGE_RUNTIME:-$repo_root/build/appimage/runtime-x86_64}"

for required in \
  "$repo_root/dist/ds1k_utf8.dll" \
  "$repo_root/dist/xinput1_3.dll" \
  "$repo_root/dist/SDL3.dll" \
  "$repo_root/config/DeadSpaceFixes.ini" \
  "$repo_root/packaging/patches/deadspace1-kr-v0.3.pat" \
  "$repo_root/packaging/patches/manifest.json"; do
  if [[ ! -f "$required" ]]; then
    echo "Required build input is missing: $required" >&2
    exit 1
  fi
done

if [[ ! -x "$appimagetool" ]]; then
  echo "Set APPIMAGETOOL to an executable appimagetool x86_64 AppImage." >&2
  exit 1
fi
if [[ ! -f "$appimage_runtime" ]]; then
  echo "Set APPIMAGE_RUNTIME to a verified AppImage x86_64 runtime." >&2
  exit 1
fi

DS1K_GIT_HASH="${DS1K_GIT_HASH:-dev}" cargo build \
  --manifest-path "$repo_root/linux-installer/Cargo.toml" \
  --release --locked

rm -rf "$appdir"
mkdir -p \
  "$appdir/usr/bin" \
  "$appdir/usr/share/applications" \
  "$appdir/usr/share/metainfo" \
  "$appdir/usr/share/icons/hicolor/scalable/apps" \
  "$appdir/usr/share/deadspace1-kr/runtime" \
  "$appdir/usr/share/deadspace1-kr/patches" \
  "$appdir/usr/share/deadspace1-kr/docs" \
  "$appdir/usr/share/deadspace1-kr/licenses" \
  "$appdir/usr/share/deadspace1-kr/fonts"

install -m 0755 "$repo_root/linux-installer/target/release/deadspace1-kr-installer" \
  "$appdir/usr/bin/deadspace1-kr-installer"
install -m 0755 "$repo_root/packaging/appimage/AppRun" "$appdir/AppRun"
install -m 0644 "$repo_root/packaging/appimage/deadspace1-kr.desktop" \
  "$appdir/kr.yjsoft.deadspace1-kr-installer.desktop"
install -m 0644 "$repo_root/packaging/appimage/deadspace1-kr.desktop" \
  "$appdir/usr/share/applications/kr.yjsoft.deadspace1-kr-installer.desktop"
install -m 0644 "$repo_root/packaging/appimage/deadspace1-kr.appdata.xml" \
  "$appdir/usr/share/metainfo/kr.yjsoft.deadspace1-kr-installer.appdata.xml"
install -m 0644 "$repo_root/packaging/appimage/deadspace1-kr.svg" "$appdir/deadspace1-kr.svg"
install -m 0644 "$repo_root/packaging/appimage/deadspace1-kr.svg" \
  "$appdir/usr/share/icons/hicolor/scalable/apps/deadspace1-kr.svg"

install -m 0644 "$repo_root/dist/ds1k_utf8.dll" "$appdir/usr/share/deadspace1-kr/runtime/"
install -m 0644 "$repo_root/dist/xinput1_3.dll" "$appdir/usr/share/deadspace1-kr/runtime/"
install -m 0644 "$repo_root/dist/SDL3.dll" "$appdir/usr/share/deadspace1-kr/runtime/"
install -m 0644 "$repo_root/config/DeadSpaceFixes.ini" "$appdir/usr/share/deadspace1-kr/runtime/"
install -m 0644 "$repo_root/packaging/patches/deadspace1-kr-v0.3.pat" \
  "$appdir/usr/share/deadspace1-kr/patches/"
install -m 0644 "$repo_root/packaging/patches/manifest.json" \
  "$appdir/usr/share/deadspace1-kr/patches/"
install -m 0644 "$repo_root/assets/fonts/NanumBarunGothic.ttf" \
  "$appdir/usr/share/deadspace1-kr/fonts/"

install -m 0644 "$repo_root/docs/INSTALL_KO.txt" \
  "$appdir/usr/share/deadspace1-kr/docs/README_KO.txt"
install -m 0644 "$repo_root/docs/INSTALL_LINUX_KO.md" \
  "$appdir/usr/share/deadspace1-kr/docs/INSTALL_LINUX_KO.md"
install -m 0644 "$repo_root/THIRD_PARTY_NOTICES.txt" \
  "$appdir/usr/share/deadspace1-kr/docs/THIRD_PARTY_NOTICES.txt"
install -m 0644 "$repo_root/third_party/DeadSpace2008Fixes/LICENSE" \
  "$appdir/usr/share/deadspace1-kr/licenses/DeadSpace2008Fixes-MIT.txt"
install -m 0644 "$repo_root/third_party/licenses/DSOpt-MIT.txt" \
  "$appdir/usr/share/deadspace1-kr/licenses/"
install -m 0644 "$repo_root/third_party/licenses/MinHook-BSD-2-Clause.txt" \
  "$appdir/usr/share/deadspace1-kr/licenses/"
install -m 0644 "$repo_root/third_party/licenses/SDL3-zlib.txt" \
  "$appdir/usr/share/deadspace1-kr/licenses/"
install -m 0644 "$repo_root/third_party/NanumBarunGothic/OFL-1.1.txt" \
  "$appdir/usr/share/deadspace1-kr/licenses/NanumBarunGothic-OFL-1.1.txt"
install -m 0644 "$repo_root/third_party/licenses/VPatch-zlib.txt" \
  "$appdir/usr/share/deadspace1-kr/licenses/"
install -m 0644 "$repo_root/third_party/licenses/fltk-rs-MIT.txt" \
  "$appdir/usr/share/deadspace1-kr/licenses/"
install -m 0644 "$repo_root/third_party/licenses/FLTK-License-Notice.txt" \
  "$appdir/usr/share/deadspace1-kr/licenses/"
install -m 0644 "$repo_root/third_party/licenses/AppImage-runtime-MIT.txt" \
  "$appdir/usr/share/deadspace1-kr/licenses/"
install -m 0644 "$repo_root/linux-installer/RUST_DEPENDENCIES.md" \
  "$appdir/usr/share/deadspace1-kr/licenses/"

mkdir -p "$(dirname "$output")"
rm -f "$output"
ARCH=x86_64 VERSION=0.3 "$appimagetool" --appimage-extract-and-run \
  --runtime-file "$appimage_runtime" "$appdir" "$output"
chmod +x "$output"
sha256sum "$output"
