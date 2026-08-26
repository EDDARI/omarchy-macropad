#!/usr/bin/env python3
"""Capture a keyboard shortcut from real input devices and push it to the
3-key macropad's config via ch57x-keyboard-tool. Invoked by
omarchy-macropad-remap with a single slot argument, e.g. "button1",
"knob_ccw", "knob_press", "knob_cw".
"""
import os
import select
import subprocess
import sys
import time

import yaml
from evdev import InputDevice, list_devices, ecodes

CONFIG_PATH = os.path.expanduser("~/.config/ch57x-keyboard/mapping.yaml")
MACROPAD_VENDOR = 0x1189

DEFAULT_CONFIG = {
    "orientation": "normal",
    "rows": 1,
    "columns": 3,
    "knobs": 1,
    "layers": [
        {
            "buttons": [["1", "2", "3"]],
            "knobs": [{"ccw": "volumedown", "press": "mute", "cw": "volumeup"}],
        }
    ],
}

MODIFIERS = {
    "KEY_LEFTCTRL": "ctrl", "KEY_RIGHTCTRL": "rctrl",
    "KEY_LEFTSHIFT": "shift", "KEY_RIGHTSHIFT": "rshift",
    "KEY_LEFTALT": "alt", "KEY_RIGHTALT": "ralt",
    "KEY_LEFTMETA": "win", "KEY_RIGHTMETA": "rwin",
}
MODIFIER_ORDER = ["ctrl", "rctrl", "shift", "rshift", "alt", "ralt", "win", "rwin"]

KEYMAP = dict(MODIFIERS)
for c in "abcdefghijklmnopqrstuvwxyz":
    KEYMAP[f"KEY_{c.upper()}"] = c
for d in "0123456789":
    KEYMAP[f"KEY_{d}"] = d
for i in range(1, 25):
    KEYMAP[f"KEY_F{i}"] = f"f{i}"
KEYMAP.update({
    "KEY_ENTER": "enter", "KEY_ESC": "escape", "KEY_BACKSPACE": "backspace",
    "KEY_TAB": "tab", "KEY_SPACE": "space", "KEY_MINUS": "minus",
    "KEY_EQUAL": "equal", "KEY_LEFTBRACE": "leftbracket",
    "KEY_RIGHTBRACE": "rightbracket", "KEY_BACKSLASH": "backslash",
    "KEY_102ND": "nonusbackslash", "KEY_SEMICOLON": "semicolon",
    "KEY_APOSTROPHE": "quote", "KEY_GRAVE": "grave", "KEY_COMMA": "comma",
    "KEY_DOT": "dot", "KEY_SLASH": "slash", "KEY_CAPSLOCK": "capslock",
    "KEY_SYSRQ": "printscreen", "KEY_INSERT": "insert", "KEY_HOME": "home",
    "KEY_PAGEUP": "pageup", "KEY_DELETE": "delete", "KEY_END": "end",
    "KEY_PAGEDOWN": "pagedown", "KEY_RIGHT": "right", "KEY_LEFT": "left",
    "KEY_DOWN": "down", "KEY_UP": "up", "KEY_NUMLOCK": "numlock",
    "KEY_KPSLASH": "numpadslash", "KEY_KPASTERISK": "numpadasterisk",
    "KEY_KPMINUS": "numpadminus", "KEY_KPPLUS": "numpadplus",
    "KEY_KPENTER": "numpadenter", "KEY_KPDOT": "numpaddot",
    "KEY_KPEQUAL": "numpadequal", "KEY_COMPOSE": "application",
    "KEY_POWER": "power", "KEY_NEXTSONG": "next",
    "KEY_PREVIOUSSONG": "previous", "KEY_STOPCD": "stop",
    "KEY_PLAYPAUSE": "play", "KEY_MUTE": "mute", "KEY_VOLUMEUP": "volumeup",
    "KEY_VOLUMEDOWN": "volumedown", "KEY_CALC": "calculator",
    "KEY_SCREENLOCK": "screenlock",
})
for i in range(10):
    name = "KEY_KP0" if i == 0 else f"KEY_KP{i}"
    KEYMAP[name] = f"numpad{i}"

HARD_TIMEOUT = 20.0


def notify(body, urgency="normal"):
    subprocess.run(
        ["notify-send", "-u", urgency, "-a", "Macropad", "Macropad remap", body],
        check=False,
    )


def candidate_devices():
    devs = []
    for path in list_devices():
        try:
            d = InputDevice(path)
        except OSError:
            continue
        if d.info.vendor == MACROPAD_VENDOR:
            continue
        caps = d.capabilities().get(ecodes.EV_KEY, [])
        if ecodes.KEY_A in caps:
            devs.append(d)
    return devs


def capture_combo():
    devices = {d.fd: d for d in candidate_devices()}
    if not devices:
        return None, "no keyboard input devices found"

    pressed = set()
    captured = set()
    deadline = time.time() + HARD_TIMEOUT

    try:
        while time.time() < deadline:
            r, _, _ = select.select(devices.keys(), [], [], 0.5)
            for fd in r:
                dev = devices[fd]
                for event in dev.read():
                    if event.type != ecodes.EV_KEY or event.value == 2:
                        continue
                    keycode = ecodes.KEY[event.code] if event.code in ecodes.KEY else None
                    if isinstance(keycode, list):
                        keycode = keycode[0]
                    mapped = KEYMAP.get(keycode)
                    if mapped is None:
                        continue
                    if event.value == 1:
                        pressed.add(mapped)
                        captured.add(mapped)
                    elif event.value == 0:
                        pressed.discard(mapped)
                        if not pressed and captured:
                            if captured == {"escape"}:
                                return None, "cancelled"
                            return captured, None
    finally:
        for d in devices.values():
            try:
                d.close()
            except OSError:
                pass

    return None, "timed out waiting for a keypress"


def combo_to_token(captured):
    mods = [m for m in MODIFIER_ORDER if m in captured]
    mains = sorted(captured - set(mods))
    return "-".join(mods + mains)


def load_config():
    if os.path.exists(CONFIG_PATH):
        with open(CONFIG_PATH) as f:
            return yaml.safe_load(f)
    return yaml.safe_load(yaml.dump(DEFAULT_CONFIG))


def save_config(cfg):
    os.makedirs(os.path.dirname(CONFIG_PATH), exist_ok=True)
    with open(CONFIG_PATH, "w") as f:
        yaml.dump(cfg, f, sort_keys=False)


def apply_slot(cfg, slot, token):
    layer = cfg["layers"][0]
    if slot.startswith("button"):
        idx = int(slot[len("button"):]) - 1
        layer["buttons"][0][idx] = token
    else:
        knob = layer["knobs"][0]
        field = {"knob_ccw": "ccw", "knob_press": "press", "knob_cw": "cw"}[slot]
        knob[field] = token


def upload(cfg):
    text = yaml.dump(cfg, sort_keys=False)
    validate = subprocess.run(
        ["ch57x-keyboard-tool", "validate"], input=text, capture_output=True, text=True
    )
    if validate.returncode != 0:
        return False, f"validate failed: {validate.stderr.strip() or validate.stdout.strip()}"
    upload_res = subprocess.run(
        ["ch57x-keyboard-tool", "upload"], input=text, capture_output=True, text=True
    )
    if upload_res.returncode != 0:
        return False, f"upload failed: {upload_res.stderr.strip() or upload_res.stdout.strip()}"
    return True, None


def main():
    if len(sys.argv) != 2:
        print("usage: omarchy-macropad-apply.py <slot>", file=sys.stderr)
        return 1
    slot = sys.argv[1]

    notify(f"Press the shortcut for {slot} now… (Esc alone = cancel)")

    captured, err = capture_combo()
    if captured is None:
        notify(f"Not applied: {err}", urgency="critical" if err != "cancelled" else "normal")
        return 0

    token = combo_to_token(captured)

    cfg = load_config()
    apply_slot(cfg, slot, token)

    ok, err = upload(cfg)
    if not ok:
        notify(f"{token} captured but upload failed: {err}", urgency="critical")
        return 1

    save_config(cfg)
    notify(f"{slot} → {token} ✅")
    return 0


if __name__ == "__main__":
    sys.exit(main())
