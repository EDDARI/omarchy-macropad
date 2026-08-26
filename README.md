# omarchy-macropad

Remap a cheap 3-key RGB macropad (ch57x/CH552G family, e.g. USB `1189:8890` —
sold under many AliExpress brand names) without touching a config file or
Windows software.

Press **SUPER + M**, pick a key or the knob from the menu, then press the
real shortcut you want assigned to it. Done.

## How it works

- `bin/omarchy-macropad-remap` — Hyprland keybinding target. Shows an
  `omarchy-menu-select` popup to pick a control (Key 1/2/3, knob CCW/press/CW).
- `bin/omarchy-macropad-apply.py` — listens on your real keyboard(s) via
  `python-evdev` for the next key/combo you press, converts it to
  [`ch57x-keyboard-tool`](https://github.com/kriomant/ch57x-keyboard-tool)'s
  key-name syntax, writes it into `~/.config/ch57x-keyboard/mapping.yaml`,
  then runs `validate` + `upload` against the device. Notifies success or
  failure via `notify-send`. Press `Esc` alone during capture to cancel.

The device only supports one layer (no layer-switch button), so this covers
the 3 keys and the knob's turn-left/press/turn-right actions — six
remappable controls total.

## Requirements

- Omarchy (Hyprland + `omarchy-menu-select` + `bindings.lua`)
- [`ch57x-keyboard-tool`](https://aur.archlinux.org/packages/ch57x-keyboard-tool) (AUR)
- `python-evdev`, `python-yaml`

`ch57x-keyboard-tool`'s AUR package installs a udev rule granting no-sudo
device access; replug the macropad after first install if `omarchy-macropad-apply.py`
can't reach the device.

## Install

```sh
git clone https://github.com/EDDARI/omarchy-macropad.git
cd omarchy-macropad
./install.sh
```

This installs the two scripts to `~/.local/bin`, adds a `SUPER + M`
keybinding to `~/.config/hypr/bindings.lua`, and drops a default
`~/.config/ch57x-keyboard/mapping.yaml` if you don't already have one.
Safe to re-run — it won't duplicate the keybinding or overwrite an existing
mapping.

## Uninstall

```sh
./uninstall.sh
```

Removes the scripts and the keybinding. Leaves `ch57x-keyboard-tool` and
your `mapping.yaml` in place.

## Editing macros directly

For multi-key macro sequences the capture tool can't produce, edit
`~/.config/ch57x-keyboard/mapping.yaml` by hand and run:

```sh
ch57x-keyboard-tool upload ~/.config/ch57x-keyboard/mapping.yaml
```

## Compatibility

Written for a specific 3-key + 1-knob, no-display board (USB `1189:8890`),
but should work for any device `ch57x-keyboard-tool` supports — adjust
`rows`/`columns`/`knobs` in `mapping.yaml` and the `SLOTS` map in
`bin/omarchy-macropad-remap` to match your layout.

## License

MIT
