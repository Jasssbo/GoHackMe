#!/usr/bin/env bash
# ── build_appimage.sh ─────────────────────────────────────────────────────────
# Packages the GoHackMe Flutter Linux build into a portable AppImage that runs
# on any x86_64 Linux distro (Ubuntu 20.04+, Fedora, Arch, Debian, etc.)
# without any installation or dependencies.
#
# Requirements: wget, appimagetool (already installed at /usr/local/bin)
# Usage:  ./scripts/build_appimage.sh [--skip-build]
#
# Output: build/GoHackMe-x86_64.AppImage
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUNDLE_DIR="$REPO_ROOT/app/build/linux/x64/release/bundle"
APPDIR="$REPO_ROOT/build/AppDir"
OUT_DIR="$REPO_ROOT/build"
ICON_SRC="$REPO_ROOT/app/web/icons/Icon-512.png"
FINAL="$OUT_DIR/GoHackMe-x86_64.AppImage"

# ── Parse args ────────────────────────────────────────────────────────────────
SKIP_BUILD=0
for arg in "$@"; do
  [[ "$arg" == "--skip-build" ]] && SKIP_BUILD=1
done

# ── Step 1: Flutter build ─────────────────────────────────────────────────────
if [[ "$SKIP_BUILD" -eq 0 ]]; then
  echo "[1/4] Building Flutter Linux release..."
  cd "$REPO_ROOT/app"
  flutter build linux --release
else
  echo "[1/4] Skipping Flutter build (--skip-build)"
fi

if [[ ! -f "$BUNDLE_DIR/gohackme" ]]; then
  echo "ERROR: Bundle not found at $BUNDLE_DIR — run without --skip-build first."
  exit 1
fi

# ── Step 2: Build AppDir ──────────────────────────────────────────────────────
echo "[2/4] Setting up AppDir..."
rm -rf "$APPDIR"
mkdir -p "$APPDIR/lib" "$APPDIR/sys_libs" "$APPDIR/usr/share/icons/hicolor/256x256/apps"

# Mirror the exact Flutter bundle layout (binary, data/, lib/ at the same level).
# Flutter's embedder resolves libapp.so as ./lib/libapp.so relative to the binary.
cp "$BUNDLE_DIR/gohackme"   "$APPDIR/gohackme"
cp -r "$BUNDLE_DIR/data"    "$APPDIR/data"
cp "$BUNDLE_DIR/lib/"*.so   "$APPDIR/lib/"     # libapp.so, libflutter_linux_gtk.so, libwebrtc.so ...

# Icon + desktop
cp "$ICON_SRC"                               "$APPDIR/gohackme.png"
cp "$ICON_SRC"                               "$APPDIR/usr/share/icons/hicolor/256x256/apps/gohackme.png"
cp "$REPO_ROOT/app/linux/gohackme.desktop"   "$APPDIR/gohackme.desktop"

# ── Step 3: Bundle system libs ────────────────────────────────────────────────
echo "[3/4] Bundling system libraries..."

# Walk ldd output and copy every system .so into sys_libs/,
# skipping Flutter's own libs (already in lib/) and kernel-provided ones.
LD_LIBRARY_PATH="$APPDIR/lib" ldd "$APPDIR/gohackme" \
  | awk '/=>/{print $3}' | grep -v '^$' \
  | grep -v 'ld-linux\|linux-vdso' \
  | while read -r lib; do
      name="$(basename "$lib")"
      [[ -f "$APPDIR/lib/$name" ]] && continue
      [[ -f "$APPDIR/sys_libs/$name" ]] && continue
      cp -L "$lib" "$APPDIR/sys_libs/$name" 2>/dev/null || true
    done

echo "  Flutter libs : $(ls "$APPDIR/lib" | wc -l)"
echo "  System libs  : $(ls "$APPDIR/sys_libs" | wc -l)"

# ── Step 4: Write AppRun ──────────────────────────────────────────────────────
# sys_libs first so GTK etc. are visible; then lib/ so Flutter's own .so files
# are found; the binary itself resolves lib/libapp.so via its own relative path.
cat > "$APPDIR/AppRun" << 'APPRUN_EOF'
#!/bin/bash
HERE="${APPDIR:-$(dirname "$(readlink -f "$0")")}"
export LD_LIBRARY_PATH="${HERE}/sys_libs:${HERE}/lib:${LD_LIBRARY_PATH:-}"
exec "${HERE}/gohackme" "$@"
APPRUN_EOF
chmod +x "$APPDIR/AppRun"

# ── Step 5: Package into AppImage ────────────────────────────────────────────
echo "[4/4] Creating AppImage..."
rm -f "$FINAL"

APPIMAGE_TOOL="appimagetool"
if ! command -v appimagetool &> /dev/null; then
  echo "appimagetool not found on PATH. Downloading local version..."
  LOCAL_TOOL="$OUT_DIR/appimagetool-x86_64.AppImage"
  if [[ ! -f "$LOCAL_TOOL" ]]; then
    mkdir -p "$OUT_DIR"
    wget -q --show-progress -O "$LOCAL_TOOL" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage" || \
      curl -Lo "$LOCAL_TOOL" "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
    chmod +x "$LOCAL_TOOL"
  fi
  APPIMAGE_TOOL="$LOCAL_TOOL"
fi

ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 \
  "$APPIMAGE_TOOL" "$APPDIR" "$FINAL"

echo ""
echo "Done!"
echo "  Output : $FINAL"
echo "  Size   : $(du -sh "$FINAL" | cut -f1)"
echo ""
echo "  To run : chmod +x GoHackMe-x86_64.AppImage && ./GoHackMe-x86_64.AppImage"
echo "  Works on: Ubuntu 20.04+, Fedora 36+, Arch, Debian 11+, any x86_64 Linux"
