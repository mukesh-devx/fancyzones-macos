#!/usr/bin/env bash
# Install FancyZones for Hammerspoon.
#
#   ./install.sh               link the module into ~/.hammerspoon and enable it in init.lua
#   ./install.sh --uninstall   remove the link and the init.lua block (your layouts are kept)
#   ./install.sh --copy        copy the files instead of symlinking
#
# Environment: HS_DIR overrides the Hammerspoon config directory (default ~/.hammerspoon).

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/fancyzones"
HS_DIR="${HS_DIR:-$HOME/.hammerspoon}"
DEST="$HS_DIR/fancyzones"
INIT="$HS_DIR/init.lua"
BEGIN_MARK="-- >>> fancyzones >>>"
END_MARK="-- <<< fancyzones <<<"

MODE="link"
ACTION="install"
for arg in "$@"; do
  case "$arg" in
    --uninstall) ACTION="uninstall" ;;
    --copy) MODE="copy" ;;
    -h|--help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
  esac
done

has_block() { [ -f "$INIT" ] && grep -qF -e "$BEGIN_MARK" "$INIT"; }

backup_init() {
  if [ -f "$INIT" ]; then
    local backup="$INIT.bak-$(date +%Y%m%d-%H%M%S)"
    cp "$INIT" "$backup"
    echo "  backed up init.lua -> $backup"
  fi
}

if [ "$ACTION" = "uninstall" ]; then
  echo "Uninstalling FancyZones from $HS_DIR"
  if has_block; then
    backup_init
    # BSD sed (macOS): delete the marked block
    sed -i '' "/$BEGIN_MARK/,/$END_MARK/d" "$INIT"
    echo "  removed block from init.lua"
  fi
  if [ -L "$DEST" ]; then
    rm "$DEST"; echo "  removed symlink $DEST"
  elif [ -d "$DEST" ]; then
    echo "  $DEST is a real directory (copy install); remove it manually if you want."
  fi
  echo "Layouts in $HS_DIR/fancyzones-data were left untouched."
  echo "Reload Hammerspoon (menu bar icon > Reload Config) to finish."
  exit 0
fi

if [ ! -d "$SRC" ]; then
  echo "Cannot find module sources at $SRC" >&2
  exit 1
fi

echo "Installing FancyZones into $HS_DIR"
mkdir -p "$HS_DIR"

# 1. Put the module where `require("fancyzones")` finds it.
if [ -L "$DEST" ]; then
  rm "$DEST"
elif [ -e "$DEST" ]; then
  echo "  $DEST already exists and is not a symlink. Move it away and re-run." >&2
  exit 1
fi
if [ "$MODE" = "copy" ]; then
  cp -R "$SRC" "$DEST"
  echo "  copied module to $DEST"
else
  ln -s "$SRC" "$DEST"
  echo "  linked $DEST -> $SRC"
fi

# 2. Enable it from init.lua (once).
if has_block; then
  echo "  init.lua already enables FancyZones"
else
  backup_init
  {
    [ -s "$INIT" ] && printf '\n'
    printf '%s\n' "$BEGIN_MARK"
    printf '%s\n' 'local ok, fz = pcall(require, "fancyzones")'
    printf '%s\n' 'if ok then'
    printf '%s\n' '  fz.start()  -- pass overrides here, e.g. fz.start{ spacing = 12 }'
    printf '%s\n' 'else'
    printf '%s\n' '  hs.alert.show("FancyZones failed to load: " .. tostring(fz), 8)'
    printf '%s\n' 'end'
    printf '%s\n' "$END_MARK"
  } >> "$INIT"
  echo "  added FancyZones block to init.lua"
fi

cat <<EOF

Done. Next steps:
  1. Open Hammerspoon (or choose "Reload Config" from its menu bar icon).
  2. When macOS asks, enable Hammerspoon under
     System Settings > Privacy & Security > Accessibility.
  3. Press Option+Z to edit zones. Hold Shift while dragging a window to snap it.
EOF
