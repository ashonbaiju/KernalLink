"""
Windows Native Input Handler for Mouse, Keyboard, and Media Keys.
Uses user32.dll mouse_event, keybd_event, and SendInput (Unicode) for reliable,
zero-latency input injection into the user's interactive desktop session.
"""

import sys
import time
import ctypes
from ctypes import wintypes

# Windows Constants
INPUT_MOUSE = 0
INPUT_KEYBOARD = 1
INPUT_HARDWARE = 2

# Mouse flags for mouse_event
MOUSEEVENTF_MOVE = 0x0001
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
MOUSEEVENTF_RIGHTDOWN = 0x0008
MOUSEEVENTF_RIGHTUP = 0x0010
MOUSEEVENTF_MIDDLEDOWN = 0x0020
MOUSEEVENTF_MIDDLEUP = 0x0040
MOUSEEVENTF_WHEEL = 0x0800
MOUSEEVENTF_ABSOLUTE = 0x8000

# Keyboard flags for keybd_event & SendInput
KEYEVENTF_EXTENDEDKEY = 0x0001
KEYEVENTF_KEYUP = 0x0002
KEYEVENTF_UNICODE = 0x0004
KEYEVENTF_SCANCODE = 0x0008

# Virtual-Key codes
VK_LBUTTON = 0x01
VK_RBUTTON = 0x02
VK_CANCEL = 0x03
VK_MBUTTON = 0x04
VK_BACK = 0x08
VK_TAB = 0x09
VK_CLEAR = 0x0C
VK_RETURN = 0x0D
VK_SHIFT = 0x10
VK_CONTROL = 0x11
VK_MENU = 0x12  # Alt
VK_PAUSE = 0x13
VK_CAPITAL = 0x14
VK_ESCAPE = 0x1B
VK_SPACE = 0x20
VK_PRIOR = 0x21  # Page Up
VK_NEXT = 0x22   # Page Down
VK_END = 0x23
VK_HOME = 0x24
VK_LEFT = 0x25
VK_UP = 0x26
VK_RIGHT = 0x27
VK_DOWN = 0x28
VK_SNAPSHOT = 0x2C  # PrintScreen
VK_INSERT = 0x2D
VK_DELETE = 0x2E
VK_LWIN = 0x5B
VK_RWIN = 0x5C

# Media keys
VK_VOLUME_MUTE = 0xAD
VK_VOLUME_DOWN = 0xAE
VK_VOLUME_UP = 0xAF
VK_MEDIA_NEXT_TRACK = 0xB0
VK_MEDIA_PREV_TRACK = 0xB1
VK_MEDIA_STOP = 0xB2
VK_MEDIA_PLAY_PAUSE = 0xB3

# Function keys F1-F12
VK_F1 = 0x70

# Keys that require the KEYEVENTF_EXTENDEDKEY flag
EXTENDED_KEYS = {
    VK_LEFT, VK_UP, VK_RIGHT, VK_DOWN,
    VK_PRIOR, VK_NEXT, VK_END, VK_HOME,
    VK_INSERT, VK_DELETE,
    VK_LWIN, VK_RWIN,
    VK_VOLUME_MUTE, VK_VOLUME_DOWN, VK_VOLUME_UP,
    VK_MEDIA_NEXT_TRACK, VK_MEDIA_PREV_TRACK,
    VK_MEDIA_STOP, VK_MEDIA_PLAY_PAUSE,
}

# 64-bit safe SendInput Structures for Unicode Text Injection
class KEYBDINPUT(ctypes.Structure):
    _fields_ = [
        ("wVk", wintypes.WORD),
        ("wScan", wintypes.WORD),
        ("dwFlags", wintypes.DWORD),
        ("time", wintypes.DWORD),
        ("dwExtraInfo", ctypes.c_void_p),
    ]

class _INPUT_UNION(ctypes.Union):
    _fields_ = [
        ("ki", KEYBDINPUT),
        ("padding", ctypes.c_ubyte * 32),  # Ensures exactly 32-byte union on 64-bit Windows
    ]

class INPUT(ctypes.Structure):
    _fields_ = [
        ("type", wintypes.DWORD),
        ("union", _INPUT_UNION),
    ]

user32 = ctypes.windll.user32
SendInput = user32.SendInput
SendInput.argtypes = (wintypes.UINT, ctypes.POINTER(INPUT), ctypes.c_int)
SendInput.restype = wintypes.UINT


KEY_NAME_MAP = {
    "backspace": VK_BACK,
    "tab": VK_TAB,
    "enter": VK_RETURN,
    "return": VK_RETURN,
    "shift": VK_SHIFT,
    "ctrl": VK_CONTROL,
    "control": VK_CONTROL,
    "alt": VK_MENU,
    "pause": VK_PAUSE,
    "capslock": VK_CAPITAL,
    "escape": VK_ESCAPE,
    "esc": VK_ESCAPE,
    "space": VK_SPACE,
    "pageup": VK_PRIOR,
    "pagedown": VK_NEXT,
    "end": VK_END,
    "home": VK_HOME,
    "left": VK_LEFT,
    "up": VK_UP,
    "right": VK_RIGHT,
    "down": VK_DOWN,
    "insert": VK_INSERT,
    "delete": VK_DELETE,
    "del": VK_DELETE,
    "win": VK_LWIN,
    "windows": VK_LWIN,
    "vol_up": VK_VOLUME_UP,
    "vol_down": VK_VOLUME_DOWN,
    "vol_mute": VK_VOLUME_MUTE,
    "media_play_pause": VK_MEDIA_PLAY_PAUSE,
    "media_next": VK_MEDIA_NEXT_TRACK,
    "media_prev": VK_MEDIA_PREV_TRACK,
    "media_stop": VK_MEDIA_STOP,
}

for i in range(1, 13):
    KEY_NAME_MAP[f"f{i}"] = VK_F1 + (i - 1)


def attach_interactive_desktop():
    """
    Ensures current thread is attached to the active user desktop (winsta0\\default).
    Crucial when running from background services, IDE runners, or batch scripts.
    """
    try:
        hwinsta = user32.OpenWindowStationW("winsta0", False, 0x037F)
        if hwinsta:
            user32.SetProcessWindowStation(hwinsta)
        hdesk = user32.OpenDesktopW("default", 0, False, 0x01FF)
        if hdesk:
            user32.SetThreadDesktop(hdesk)
    except Exception:
        pass


class InputHandler:
    def __init__(self):
        attach_interactive_desktop()
        self._acc_dx = 0.0
        self._acc_dy = 0.0

    def mouse_move_relative(self, dx: float, dy: float):
        """Relative cursor move for touchpad with sub-pixel accumulation."""
        self._acc_dx += dx
        self._acc_dy += dy
        idx = int(self._acc_dx)
        idy = int(self._acc_dy)
        if idx != 0 or idy != 0:
            self._acc_dx -= idx
            self._acc_dy -= idy
            user32.mouse_event(MOUSEEVENTF_MOVE, idx, idy, 0, 0)

    def mouse_down(self, button="left"):
        button = button.lower().strip()
        flag = MOUSEEVENTF_LEFTDOWN
        if button == "right":
            flag = MOUSEEVENTF_RIGHTDOWN
        elif button == "middle":
            flag = MOUSEEVENTF_MIDDLEDOWN
        user32.mouse_event(flag, 0, 0, 0, 0)

    def mouse_up(self, button="left"):
        button = button.lower().strip()
        flag = MOUSEEVENTF_LEFTUP
        if button == "right":
            flag = MOUSEEVENTF_RIGHTUP
        elif button == "middle":
            flag = MOUSEEVENTF_MIDDLEUP
        user32.mouse_event(flag, 0, 0, 0, 0)

    def mouse_click(self, button="left"):
        self.mouse_down(button)
        time.sleep(0.015)
        self.mouse_up(button)

    def mouse_scroll(self, delta_y: int):
        """Vertical scrollwheel event (positive = up, negative = down)."""
        user32.mouse_event(MOUSEEVENTF_WHEEL, 0, 0, int(delta_y), 0)

    def mouse_zoom(self, direction="in", amount=120):
        """Universal Windows Zoom via Ctrl + MouseWheel."""
        attach_interactive_desktop()
        delta = amount if direction == "in" else -amount
        # Hold Ctrl down
        user32.keybd_event(VK_CONTROL, 0, 0, 0)
        time.sleep(0.01)
        # Mouse wheel scroll
        user32.mouse_event(MOUSEEVENTF_WHEEL, 0, 0, delta, 0)
        time.sleep(0.01)
        # Release Ctrl
        user32.keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, 0)

    def key_event(self, key_name: str, action="press"):
        """Sends key press/down/up via keybd_event."""
        key_name = key_name.lower().strip()
        vk = KEY_NAME_MAP.get(key_name)
        if vk is None:
            if len(key_name) == 1:
                vk = ord(key_name.upper())
            else:
                return

        flags = KEYEVENTF_EXTENDEDKEY if vk in EXTENDED_KEYS else 0

        if action == "down":
            user32.keybd_event(vk, 0, flags, 0)
        elif action == "up":
            user32.keybd_event(vk, 0, flags | KEYEVENTF_KEYUP, 0)
        elif action == "press":
            user32.keybd_event(vk, 0, flags, 0)
            time.sleep(0.015)
            user32.keybd_event(vk, 0, flags | KEYEVENTF_KEYUP, 0)

    def send_text(self, text: str):
        """Sends arbitrary Unicode characters directly (handles any symbols, emojis, or words)."""
        attach_interactive_desktop()
        for char in text:
            code = ord(char)
            # Down
            inp_down = INPUT()
            inp_down.type = INPUT_KEYBOARD
            inp_down.union.ki.wVk = 0
            inp_down.union.ki.wScan = code
            inp_down.union.ki.dwFlags = KEYEVENTF_UNICODE
            inp_down.union.ki.time = 0
            inp_down.union.ki.dwExtraInfo = None

            # Up
            inp_up = INPUT()
            inp_up.type = INPUT_KEYBOARD
            inp_up.union.ki.wVk = 0
            inp_up.union.ki.wScan = code
            inp_up.union.ki.dwFlags = KEYEVENTF_UNICODE | KEYEVENTF_KEYUP
            inp_up.union.ki.time = 0
            inp_up.union.ki.dwExtraInfo = None

            SendInput(1, ctypes.byref(inp_down), ctypes.sizeof(INPUT))
            SendInput(1, ctypes.byref(inp_up), ctypes.sizeof(INPUT))

    def key_combo(self, keys: list):
        """Executes a multi-key shortcut combo (e.g. ['alt', 'tab'] or ['ctrl', 'shift', 'esc'])."""
        attach_interactive_desktop()
        vks = []
        for k in keys:
            k = str(k).lower().strip()
            vk = KEY_NAME_MAP.get(k)
            if vk is None and len(k) == 1:
                vk = ord(k.upper())
            if vk is not None:
                vks.append(vk)

        if not vks:
            return

        # Press keys down in sequence
        for vk in vks:
            flags = KEYEVENTF_EXTENDEDKEY if vk in EXTENDED_KEYS else 0
            user32.keybd_event(vk, 0, flags, 0)
            time.sleep(0.01)

        time.sleep(0.03)

        # Release keys in reverse sequence
        for vk in reversed(vks):
            flags = KEYEVENTF_EXTENDEDKEY if vk in EXTENDED_KEYS else 0
            user32.keybd_event(vk, 0, flags | KEYEVENTF_KEYUP, 0)
            time.sleep(0.01)

    def trigger_media(self, action: str):
        if action == "forward_10":
            # Universal 5-10s forward in YouTube, Netflix, VLC, browsers
            self.key_event("right", action="press")
            return
        elif action == "backward_10":
            # Universal 5-10s backward in YouTube, Netflix, VLC, browsers
            self.key_event("left", action="press")
            return

        mapping = {
            "play_pause": "media_play_pause",
            "next": "media_next",
            "prev": "media_prev",
            "stop": "media_stop",
            "vol_up": "vol_up",
            "vol_down": "vol_down",
            "mute": "vol_mute",
        }
        key = mapping.get(action)
        if key:
            self.key_event(key, action="press")
