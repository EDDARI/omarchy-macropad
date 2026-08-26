# omarchy-macropad

Remap a cheap 3-key RGB macropad (ch57x/CH552G family, e.g. USB `1189:8890` —
sold under many AliExpress brand names) without touching a config file or
Windows software: pick a key or the knob from a menu, then press the real
shortcut you want assigned to it. Done.

Two ways to install it — pick one.

## Option A: one-command setup (recommended)

```sh
git clone https://github.com/EDDARI/omarchy-macropad.git
cd omarchy-macropad
./install.sh
```

Installs `ch57x-keyboard-tool` (AUR) and the Python deps if missing, copies
the scripts to `~/.local/bin`, adds a `SUPER + M` Hyprland keybinding, and
drops a default `~/.config/ch57x-keyboard/mapping.yaml` if you don't already
have one. Safe to re-run.

Uninstall with `./uninstall.sh`.

## Option B: `omarchy plugin add`

This repo doubles as a native Omarchy shell "menu" plugin (`manifest.json` +
`Macropad.qml`), so it can also be loaded straight into the running shell:

```sh
omarchy plugin add https://github.com/EDDARI/omarchy-macropad.git --enable
```

**This only gets you the picker UI** — `omarchy plugin add` clones the repo,
validates the manifest, and toggles it on inside `omarchy-shell`. By design
it never runs install scripts or touches your Hyprland config (see
`omarchy-shell`'s own docs: *"The installer never runs plugin code, install
hooks, or sudo"*). So two things are still on you:

1. **Dependencies** — install these yourself, once:
   ```sh
   yay -S --needed ch57x-keyboard-tool
   sudo pacman -S --needed python-evdev python-yaml
   ```
   (replug the macropad afterwards so the AUR package's udev rule applies)
2. **A keybinding** — the plugin doesn't summon itself. Add a line like this
   to `~/.config/hypr/bindings.lua`:
   ```lua
   o.bind("SUPER + M", "Macropad remap", "omarchy-shell shell toggle eddari.macropad")
   ```

Update with `omarchy plugin update eddari.macropad`, remove with
`omarchy plugin remove eddari.macropad`.

Don't run both options — they'd fight over the same `SUPER + M` binding.

## How it works

- **Option A's trigger** (`bin/omarchy-macropad-remap`) shows an
  `omarchy-menu-select` popup outside the shell process.
- **Option B's picker** (`Macropad.qml`) is a native Quickshell menu running
  inside `omarchy-shell` itself.
- Either way, picking a control spawns `omarchy-macropad-apply.py`, which
  listens on your real keyboard(s) via `python-evdev` for the next
  key/combo you press, converts it to
  [`ch57x-keyboard-tool`](https://github.com/kriomant/ch57x-keyboard-tool)'s
  key-name syntax, writes it into `~/.config/ch57x-keyboard/mapping.yaml`,
  then runs `validate` + `upload` against the device. Notifies success or
  failure via `notify-send`. Press `Esc` alone during capture to cancel.

The device only supports one layer (no layer-switch button), so this covers
the 3 keys and the knob's turn-left/press/turn-right actions — six
remappable controls total.

## Editing macros directly

For multi-key macro sequences the capture tool can't produce, edit
`~/.config/ch57x-keyboard/mapping.yaml` by hand and run:

```sh
ch57x-keyboard-tool upload ~/.config/ch57x-keyboard/mapping.yaml
```

## Compatibility

Written for a specific 3-key + 1-knob, no-display board (USB `1189:8890`),
but should work for any device `ch57x-keyboard-tool` supports — adjust
`rows`/`columns`/`knobs` in `mapping.yaml` and the `slots` list in
`Macropad.qml` / `SLOTS` map in `bin/omarchy-macropad-remap` to match your
layout.

## License

MIT
