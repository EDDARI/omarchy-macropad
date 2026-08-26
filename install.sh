#!/bin/bash
# Installs the omarchy-macropad remap tool: SUPER+M pops a menu to pick a
# key/knob on a 3-key ch57x-family macropad, then captures your next real
# keypress and uploads it as that control's new shortcut.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$HOME/.local/bin"
BINDINGS_FILE="$HOME/.config/hypr/bindings.lua"
CONFIG_DIR="$HOME/.config/ch57x-keyboard"
CONFIG_FILE="$CONFIG_DIR/mapping.yaml"
BIND_LINE='o.bind("SUPER + M", "Macropad remap", "omarchy-macropad-remap")'

echo "==> Checking dependencies"
if ! command -v ch57x-keyboard-tool >/dev/null 2>&1; then
  if command -v yay >/dev/null 2>&1; then
    yay -S --needed ch57x-keyboard-tool
  else
    echo "error: ch57x-keyboard-tool not found and yay is not available." >&2
    echo "Install it manually (AUR: ch57x-keyboard-tool) and re-run this script." >&2
    exit 1
  fi
fi

if ! python3 -c "import evdev, yaml" >/dev/null 2>&1; then
  echo "error: python3 modules 'evdev' and 'yaml' are required." >&2
  echo "Install with: sudo pacman -S --needed python-evdev python-yaml" >&2
  exit 1
fi

echo "==> Installing scripts to $BIN_DIR"
mkdir -p "$BIN_DIR"
install -m 755 "$REPO_DIR/bin/omarchy-macropad-remap" "$BIN_DIR/omarchy-macropad-remap"
install -m 755 "$REPO_DIR/bin/omarchy-macropad-apply.py" "$BIN_DIR/omarchy-macropad-apply.py"

echo "==> Setting up default mapping"
mkdir -p "$CONFIG_DIR"
if [[ ! -f "$CONFIG_FILE" ]]; then
  cp "$REPO_DIR/mapping.example.yaml" "$CONFIG_FILE"
  echo "    wrote default mapping to $CONFIG_FILE"
else
  echo "    $CONFIG_FILE already exists, leaving it alone"
fi

echo "==> Adding SUPER + M keybinding"
if [[ ! -f "$BINDINGS_FILE" ]]; then
  echo "error: $BINDINGS_FILE not found — is this an Omarchy system?" >&2
  exit 1
fi
if grep -qF "omarchy-macropad-remap" "$BINDINGS_FILE"; then
  echo "    keybinding already present, leaving it alone"
else
  printf '\n-- 3-key macropad: pick a key/knob action and remap it by pressing the shortcut.\n%s\n' "$BIND_LINE" >> "$BINDINGS_FILE"
  echo "    added SUPER + M binding to $BINDINGS_FILE"
fi

if command -v hyprctl >/dev/null 2>&1 && [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  hyprctl reload >/dev/null 2>&1 || true
fi

echo
echo "Done. Plug in your macropad and press SUPER + M to remap a key."
echo "First run may need a device replug for udev's uaccess tag to apply."
