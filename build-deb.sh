#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
NAME="nitro-control"
# Single source of truth for the version: the VERSION file.
VERSION="$(tr -d ' \t\n\r' < "$ROOT/VERSION")"
[[ -n "$VERSION" ]] || { echo "VERSION fayli bo'sh yoki yo'q" >&2; exit 1; }
ARCH="all"
OUT_DIR="${1:-$ROOT/dist}"
PKG_DIR="$OUT_DIR/${NAME}_${VERSION}_${ARCH}"

rm -rf "$PKG_DIR"
mkdir -p "$PKG_DIR"
rsync -a \
  --exclude 'dist' \
  --exclude 'releases' \
  --exclude 'build-deb.sh' \
  --exclude 'VERSION' \
  --exclude 'tests' \
  --exclude '.github' \
  --exclude '*.deb' \
  --exclude '.git' \
  --exclude '__pycache__' \
  --exclude '*.pyc' \
  "$ROOT/" "$PKG_DIR/"

# Keep the packaged control's Version in sync with the VERSION file.
sed -i "s/^Version:.*/Version: $VERSION/" "$PKG_DIR/DEBIAN/control"

# doc dir name matches old path still fine; also symlink name for package
mkdir -p "$PKG_DIR/usr/share/doc/nitro-control"
cp -a "$PKG_DIR/usr/share/doc/nitro-acer-fan/." "$PKG_DIR/usr/share/doc/nitro-control/" 2>/dev/null || true

chmod 755 "$PKG_DIR/DEBIAN"
chmod 755 "$PKG_DIR/DEBIAN/postinst" "$PKG_DIR/DEBIAN/prerm" "$PKG_DIR/DEBIAN/postrm" 2>/dev/null || true
chmod 755 "$PKG_DIR/usr/bin/nitro-fan" "$PKG_DIR/usr/bin/nitro-fan-gui"
chmod 755 "$PKG_DIR/usr/lib/nitro-control/hw-detect.sh"
chmod 755 "$PKG_DIR/usr/lib/nitro-control/display.sh"
find "$PKG_DIR/usr/share" -type f -exec chmod 644 {} \;
if [[ -f "$PKG_DIR/usr/lib/udev/rules.d/99-nitro-control.rules" ]]; then
  chmod 644 "$PKG_DIR/usr/lib/udev/rules.d/99-nitro-control.rules"
fi

SIZE=$(du -sk "$PKG_DIR" | cut -f1)
if grep -q '^Installed-Size:' "$PKG_DIR/DEBIAN/control"; then
  sed -i "s/^Installed-Size:.*/Installed-Size: $SIZE/" "$PKG_DIR/DEBIAN/control"
else
  sed -i "/^Architecture:/a Installed-Size: $SIZE" "$PKG_DIR/DEBIAN/control"
fi

DEB="$OUT_DIR/${NAME}_${VERSION}_${ARCH}.deb"
dpkg-deb --root-owner-group --build "$PKG_DIR" "$DEB"
echo
echo "OK: $DEB"
dpkg-deb -I "$DEB"
ls -lh "$DEB"
