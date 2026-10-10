#!/bin/sh
# Installs the Riff tarball for the current user (no root needed):
#   ./install.sh            install to ~/.local
#   ./install.sh --uninstall
# Arch users can install the riff-mobile-bin package instead.
set -eu

here=$(cd "$(dirname "$0")" && pwd)
data="${XDG_DATA_HOME:-$HOME/.local/share}"
app="$data/riff-mobile"
bin="$HOME/.local/bin"
id=com.aimdi.RiffMobile

if [ "${1:-}" = "--uninstall" ]; then
  rm -rf "$app" "$bin/riff-mobile" \
    "$data/applications/$id.desktop" \
    "$data/icons/hicolor/512x512/apps/$id.png"
  echo "Riff removed. Your library stays in ~/.local/share/com.aimdi.RiffMobile."
  exit 0
fi

rm -rf "$app"
mkdir -p "$app" "$bin" "$data/applications" "$data/icons/hicolor/512x512/apps"
cp -r "$here/riff-mobile" "$here/lib" "$here/data" "$app/"
ln -sf "$app/riff-mobile" "$bin/riff-mobile"
cp "$here/$id.png" "$data/icons/hicolor/512x512/apps/$id.png"
sed "s|^Exec=riff-mobile|Exec=$app/riff-mobile|" "$here/$id.desktop" \
  > "$data/applications/$id.desktop"
command -v update-desktop-database >/dev/null 2>&1 &&
  update-desktop-database "$data/applications" || true
echo "Riff installed. Start it from your app launcher or run: riff-mobile"
