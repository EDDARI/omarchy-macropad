#!/usr/bin/env python3
"""Capture a keyboard shortcut from real input devices and push it to a
ch57x-family macropad's config via ch57x-keyboard-tool.

Subcommands (invoked by the Omarchy plugin and the legacy CLI trigger):
  capture <slot>          Wait for a real keypress, print {"status": ..., "token": ...}
  apply <slot> <token>    Write token into mapping.yaml and upload to the device
  led <mode> [quiet]      Send LED backlight mode <mode> (integer) to the device;
                           "quiet" suppresses the notify-send (used while live-
                           previewing modes as the user browses a list)
  current                 Print the currently-mapped token for every slot as JSON,
                           plus the last LED mode set via this tool ("led_mode")
  <slot>                  Legacy one-shot mode: capture then apply immediately,
                           no confirmation step (kept for old callers only).

Splitting capture from apply lets the caller show the captured shortcut and
get a confirmation before anything is written to the device — a stray
keypress during capture no longer silently overwrites a mapping.
"""
import json
import os
import select
import subprocess
import sys
import time

import yaml
from evdev import InputDevice, list_devices, ecodes

CONFIG_PATH = os.path.expanduser("~/.config/ch57x-keyboard/mapping.yaml")

# Most ch57x/CH552G-family boards (including many AliExpress rebrands) share
# this reference vendor id — it's also ch57x-keyboard-tool's own default.
# Override for a different board via env vars rather than editing this file.
MACROPAD_VENDOR = int(os.environ.get("MACROPAD_VENDOR_ID", "0x1189"), 0)
MACROPAD_PRODUCT_ID = os.environ.get("MACROPAD_PRODUCT_ID")

LABELS = {
    "button1": "Key 1",
    "button2": "Key 2",
    "button3": "Key 3",
    "knob_ccw": "Knob ↺ turn left (CCW)",
    "knob_press": "Knob press",
    "knob_cw": "Knob ↻ turn right (CW)",
    "led": "LED backlight",
}

# ch57x-keyboard-tool's `led <mode>` takes a raw integer with no validation —
# it just forwards the byte to the device, and unrecognized values are
# silently accepted (not rejected) by this board's firmware. There's no
# documented mode list or read-back for the 0x8890 variant, so this is an
# empirically-picked wraparound range for the "Next/Previous" cycle UI, not a
# confirmed mode count — cycling past the real number of distinct effects
# just repeats some of them, which is harmless.
LED_MODE_COUNT = 16
LED_STATE_PATH = os.path.expanduser("~/.config/ch57x-keyboard/led_mode")

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


def load_led_mode():
    try:
        with open(LED_STATE_PATH) as f:
            return int(f.read().strip())
    except (OSError, ValueError):
        return 0


def save_led_mode(mode):
    os.makedirs(os.path.dirname(LED_STATE_PATH), exist_ok=True)
    with open(LED_STATE_PATH, "w") as f:
        f.write(str(mode))


def ch57x_base_command():
    cmd = ["ch57x-keyboard-tool"]
    cmd += ["--vendor-id", str(MACROPAD_VENDOR)]
    if MACROPAD_PRODUCT_ID:
        cmd += ["--product-id", str(int(MACROPAD_PRODUCT_ID, 0))]
    return cmd


def upload(cfg):
    text = yaml.dump(cfg, sort_keys=False)
    base = ch57x_base_command()
    validate = subprocess.run(
        base + ["validate"], input=text, capture_output=True, text=True
    )
    if validate.returncode != 0:
        return False, f"validate failed: {validate.stderr.strip() or validate.stdout.strip()}"
    upload_res = subprocess.run(
        base + ["upload"], input=text, capture_output=True, text=True
    )
    if upload_res.returncode != 0:
        return False, f"upload failed: {upload_res.stderr.strip() or upload_res.stdout.strip()}"
    return True, None


def cmd_capture(slot):
    label = LABELS.get(slot, slot)
    notify(f"Press the shortcut for {label} now… (Esc alone = cancel)")
    captured, err = capture_combo()
    if captured is None:
        if err != "cancelled":
            notify(f"Not captured: {err}", urgency="critical")
        print(json.dumps({"status": "cancelled" if err == "cancelled" else "error", "message": err}))
        return 0 if err == "cancelled" else 1
    token = combo_to_token(captured)
    print(json.dumps({"status": "ok", "token": token}))
    return 0


def cmd_apply(slot, token):
    label = LABELS.get(slot, slot)
    cfg = load_config()
    apply_slot(cfg, slot, token)
    ok, err = upload(cfg)
    if not ok:
        notify(f"{token} captured but upload failed: {err}", urgency="critical")
        return 1
    save_config(cfg)
    notify(f"{label} → {token} ✅")
    return 0


def cmd_led(mode_str, quiet=False):
    try:
        mode = int(mode_str)
    except ValueError:
        print(json.dumps({"status": "error", "message": f"not a number: {mode_str}"}))
        return 1
    base = ch57x_base_command()
    result = subprocess.run(base + ["led", str(mode)], capture_output=True, text=True)
    if result.returncode != 0:
        err = result.stderr.strip() or result.stdout.strip()
        if not quiet:
            notify(f"LED mode {mode} failed: {err}", urgency="critical")
        print(json.dumps({"status": "error", "message": err}))
        return 1
    save_led_mode(mode)
    # `quiet` is used while live-previewing as the user browses the mode
    # list — one notification per mode would spam notify-send. The caller
    # sends a final, non-quiet `led` once the user settles on a mode.
    if not quiet:
        notify(f"LED backlight → mode {mode} ✅")
    print(json.dumps({"status": "ok", "mode": mode}))
    return 0


def cmd_current():
    cfg = load_config()
    layer = cfg["layers"][0]
    buttons = layer["buttons"][0]
    knobs = layer["knobs"][0]
    out = {
        "button1": buttons[0] if len(buttons) > 0 else "",
        "button2": buttons[1] if len(buttons) > 1 else "",
        "button3": buttons[2] if len(buttons) > 2 else "",
        "knob_ccw": knobs.get("ccw", ""),
        "knob_press": knobs.get("press", ""),
        "knob_cw": knobs.get("cw", ""),
        "led_mode": load_led_mode(),
    }
    print(json.dumps(out))
    return 0


def main():
    args = sys.argv[1:]
    if not args:
        print("usage: omarchy-macropad-apply.py capture|apply|led|current|<slot>", file=sys.stderr)
        return 1

    if args[0] == "capture" and len(args) == 2:
        return cmd_capture(args[1])
    if args[0] == "apply" and len(args) == 3:
        return cmd_apply(args[1], args[2])
    if args[0] == "led" and len(args) in (2, 3):
        quiet = len(args) == 3 and args[2] == "quiet"
        return cmd_led(args[1], quiet=quiet)
    if args[0] == "current" and len(args) == 1:
        return cmd_current()
    if len(args) == 1 and args[0] in LABELS:
        # Legacy one-shot mode: capture then apply immediately, no
        # confirmation. Kept only for backward compatibility.
        slot = args[0]
        label = LABELS.get(slot, slot)
        notify(f"Press the shortcut for {label} now… (Esc alone = cancel)")
        captured, err = capture_combo()
        if captured is None:
            notify(f"Not applied: {err}", urgency="critical" if err != "cancelled" else "normal")
            return 0
        return cmd_apply(slot, combo_to_token(captured))

    print("usage: omarchy-macropad-apply.py capture|apply|led|current|<slot>", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
