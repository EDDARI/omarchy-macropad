#!/bin/bash
# Removes the omarchy-macropad scripts and keybinding. Leaves
# ch57x-keyboard-tool and your mapping.yaml in place (delete manually if
# you want them gone too).
set -euo pipefail

BIN_DIR="$HOME/.local/bin"
BINDINGS_FILE="$HOME/.config/hypr/bindings.lua"

echo "==> Removing scripts from $BIN_DIR"
rm -f "$BIN_DIR/omarchy-macropad-remap" "$BIN_DIR/omarchy-macropad-apply.py"

echo "==> Removing keybinding from $BINDINGS_FILE"
if [[ -f "$BINDINGS_FILE" ]]; then
  sed -i \
    -e '/3-key macropad: pick a key\/knob action/d' \
    -e '/omarchy-macropad-remap/d' \
    "$BINDINGS_FILE"
fi

if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  hyprctl reload >/dev/null 2>&1 || true
fi

echo "Done. ch57x-keyboard-tool and ~/.config/ch57x-keyboard/mapping.yaml were left untouched."
