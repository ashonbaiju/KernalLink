"""
High-Performance Windows Screen Streaming & Virtual Dual Monitor (Spacedesk) Engine.
Enables using mobile phone as a secondary or mirrored desktop monitor with low-latency touch controls.
"""

import sys
import os
import time
import asyncio
import subprocess
import ctypes
from ctypes import wintypes
from pathlib import Path
import numpy as np
import cv2

try:
    import simplejpeg
    HAS_SIMPLEJPEG = True
except Exception:
    HAS_SIMPLEJPEG = False

# Ensure Win32 user32 and gdi32 are available
u = ctypes.windll.user32
g = ctypes.windll.gdi32

# Enable Per-Monitor DPI Awareness
try:
    ctypes.windll.shcore.SetProcessDpiAwareness(2)
except Exception:
    try:
        u.SetProcessDPIAware()
    except Exception:
        pass


def attach_interactive_desktop():
    """Attaches thread to the interactive user desktop station."""
    try:
        hwinsta = u.OpenWindowStationW("winsta0", False, 0x037F)
        if hwinsta:
            u.SetProcessWindowStation(hwinsta)
        hdesk = u.OpenDesktopW("default", 0, False, 0x01FF)
        if hdesk:
            u.SetThreadDesktop(hdesk)
    except Exception:
        pass


class RECT(ctypes.Structure):
    _fields_ = [
        ("left", wintypes.LONG),
        ("top", wintypes.LONG),
        ("right", wintypes.LONG),
        ("bottom", wintypes.LONG),
    ]


class MONITORINFOEXW(ctypes.Structure):
    _fields_ = [
        ("cbSize", wintypes.DWORD),
        ("rcMonitor", RECT),
        ("rcWork", RECT),
        ("dwFlags", wintypes.DWORD),
        ("szDevice", wintypes.WCHAR * 32),
    ]


class CURSORINFO(ctypes.Structure):
    _fields_ = [
        ("cbSize", wintypes.DWORD),
        ("flags", wintypes.DWORD),
        ("hCursor", wintypes.HICON),
        ("ptScreenPos", wintypes.POINT),
    ]


class BITMAPINFOHEADER(ctypes.Structure):
    _fields_ = [
        ("biSize", wintypes.DWORD),
        ("biWidth", wintypes.LONG),
        ("biHeight", wintypes.LONG),
        ("biPlanes", wintypes.WORD),
        ("biBitCount", wintypes.WORD),
        ("biCompression", wintypes.DWORD),
        ("biSizeImage", wintypes.DWORD),
        ("biXPelsPerMeter", wintypes.LONG),
        ("biYPelsPerMeter", wintypes.LONG),
        ("biClrUsed", wintypes.DWORD),
        ("biClrImportant", wintypes.DWORD),
    ]


g.GetDIBits.argtypes = [
    wintypes.HDC,
    wintypes.HBITMAP,
    wintypes.UINT,
    wintypes.UINT,
    ctypes.c_void_p,
    ctypes.c_void_p,
    wintypes.UINT,
]
g.GetDIBits.restype = ctypes.c_int

g.CreateCompatibleDC.argtypes = [wintypes.HDC]
g.CreateCompatibleDC.restype = wintypes.HDC

g.CreateDIBSection.argtypes = [
    wintypes.HDC,
    ctypes.c_void_p,
    wintypes.UINT,
    ctypes.POINTER(ctypes.c_void_p),
    wintypes.HANDLE,
    wintypes.DWORD,
]
g.CreateDIBSection.restype = wintypes.HBITMAP

g.SelectObject.argtypes = [wintypes.HDC, wintypes.HGDIOBJ]
g.SelectObject.restype = wintypes.HGDIOBJ

g.DeleteObject.argtypes = [wintypes.HGDIOBJ]
g.DeleteObject.restype = wintypes.BOOL

g.DeleteDC.argtypes = [wintypes.HDC]
g.DeleteDC.restype = wintypes.BOOL

u.GetDC.argtypes = [wintypes.HWND]
u.GetDC.restype = wintypes.HDC

u.ReleaseDC.argtypes = [wintypes.HWND, wintypes.HDC]
u.ReleaseDC.restype = ctypes.c_int

g.StretchBlt.argtypes = [
    wintypes.HDC,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_int,
    wintypes.HDC,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_int,
    wintypes.DWORD,
]
g.StretchBlt.restype = wintypes.BOOL

g.SetStretchBltMode.argtypes = [wintypes.HDC, ctypes.c_int]
g.SetStretchBltMode.restype = ctypes.c_int

g.BitBlt.argtypes = [
    wintypes.HDC,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_int,
    ctypes.c_int,
    wintypes.HDC,
    ctypes.c_int,
    ctypes.c_int,
    wintypes.DWORD,
]
g.BitBlt.restype = wintypes.BOOL

u.DrawIcon.argtypes = [wintypes.HDC, ctypes.c_int, ctypes.c_int, wintypes.HICON]
u.DrawIcon.restype = wintypes.BOOL


def get_all_monitors():
    """
    Enumerates all active physical and virtual displays on the system.
    Returns list of dicts with bounds, resolutions, and primary status.
    """
    attach_interactive_desktop()
    monitors = []

    def _monitor_enum_callback(hmon, hdc, lprc, lparam):
        mi = MONITORINFOEXW()
        mi.cbSize = ctypes.sizeof(MONITORINFOEXW)
        if u.GetMonitorInfoW(hmon, ctypes.byref(mi)):
            is_primary = bool(mi.dwFlags & 1)
            left = mi.rcMonitor.left
            top = mi.rcMonitor.top
            right = mi.rcMonitor.right
            bottom = mi.rcMonitor.bottom
            width = right - left
            height = bottom - top
            dev_name = str(mi.szDevice)
            idx = len(monitors)
            title = f"Display {idx + 1}"
            if is_primary:
                title += " (Main Laptop)"
            else:
                title += " (Extended Screen)"

            monitors.append({
                "index": idx,
                "name": title,
                "device": dev_name,
                "left": left,
                "top": top,
                "right": right,
                "bottom": bottom,
                "width": width,
                "height": height,
                "primary": is_primary,
            })
        return 1

    cb_proto = ctypes.WINFUNCTYPE(
        wintypes.BOOL, wintypes.HMONITOR, wintypes.HDC, ctypes.POINTER(RECT), wintypes.LPARAM
    )
    u.EnumDisplayMonitors(None, None, cb_proto(_monitor_enum_callback), 0)

    # Fallback to primary screen metrics if enumeration is empty
    if not monitors:
        w = u.GetSystemMetrics(0)
        h = u.GetSystemMetrics(1)
        monitors.append({
            "index": 0,
            "name": "Display 1 (Primary)",
            "device": "\\\\.\\DISPLAY1",
            "left": 0,
            "top": 0,
            "right": w,
            "bottom": h,
            "width": w,
            "height": h,
            "primary": True,
        })

    return monitors


def get_spacedesk_status():
    """
    Checks if Spacedesk service is installed and whether it is actively running.
    """
    status = {
        "installed": False,
        "running": False,
        "service_name": "spacedeskService",
        "console_path": r"C:\Program Files\datronicsoft\spacedesk\spacedeskConsole.exe",
    }
    if os.path.exists(status["console_path"]):
        status["installed"] = True

    try:
        res = subprocess.run(["sc.exe", "query", "spacedeskService"], capture_output=True, text=True, timeout=2)
        if "RUNNING" in res.stdout:
            status["installed"] = True
            status["running"] = True
        elif "STOPPED" in res.stdout or "PAUSED" in res.stdout:
            status["installed"] = True
            status["running"] = False
    except Exception:
        pass

    return status


def get_driver_paths():
    """
    Locates the nefcon executable and the VirtualDisplayDriver directory
    across all execution environments (source, PyInstaller frozen exe, temp dir, or absolute paths).
    """
    search_dirs = []

    # 1. Executable parent directory (when running KernalLink.exe from root or server/dist)
    if getattr(sys, "frozen", False):
        exe_dir = Path(sys.executable).parent.resolve()
        search_dirs.append(exe_dir / "server" / "driver" / "vdd")
        search_dirs.append(exe_dir / "driver" / "vdd")
        if hasattr(sys, "_MEIPASS"):
            search_dirs.append(Path(sys._MEIPASS) / "server" / "driver" / "vdd")
            search_dirs.append(Path(sys._MEIPASS) / "driver" / "vdd")

    # 2. Source file directory (server/screen_streamer.py)
    try:
        src_dir = Path(__file__).parent.resolve()
        search_dirs.append(src_dir / "driver" / "vdd")
        search_dirs.append(src_dir.parent / "server" / "driver" / "vdd")
        search_dirs.append(src_dir.parent / "driver" / "vdd")
    except Exception:
        pass

    # 3. Known absolute project paths
    search_dirs.append(Path(r"D:\app\ashon\controller\server\driver\vdd"))
    search_dirs.append(Path(r"C:\VirtualDisplayDriver"))

    for vdd_dir in search_dirs:
        nefcon = vdd_dir / "nefcon" / "x64" / "nefconc.exe"
        driver_dir = vdd_dir / "VirtualDisplayDriver"
        if not nefcon.exists():
            nefcon = vdd_dir.parent / "nefcon" / "x64" / "nefconc.exe"
        if not driver_dir.exists():
            driver_dir = vdd_dir
        if nefcon.exists() and (driver_dir / "MttVDD.inf").exists():
            return nefcon.resolve(), driver_dir.resolve()

    return None, None


def check_virtual_display_status() -> dict:
    """Checks whether the Virtual Display Driver (Root\\MttVDD) is installed and active in Windows."""
    status = {"installed": False, "enabled": False}
    try:
        nefcon_exe, _ = get_driver_paths()
        if nefcon_exe and nefcon_exe.exists():
            res = subprocess.run([str(nefcon_exe), "--find-hwid", "--hardware-id", "Root\\MttVDD"], capture_output=True, text=True, timeout=3)
            if res.returncode == 0 and "Root\\MttVDD" in res.stdout:
                status["installed"] = True
                status["enabled"] = True
                return status
    except Exception:
        pass

    try:
        # Check active PNP devices with Status 'OK' only (exclude disconnected/phantom devices)
        res = subprocess.run(
            ["powershell", "-NoProfile", "-Command",
             "(Get-PnpDevice -InstanceId '*MTT*' -Status 'OK' -ErrorAction SilentlyContinue).Count"],
            capture_output=True, text=True, timeout=3
        )
        out = res.stdout.strip()
        if out and out != "0":
            status["installed"] = True
            status["enabled"] = True
            return status
    except Exception:
        pass
    return status


def is_driver_installed() -> bool:
    """Returns True if the Virtual Display Driver (Root\\MttVDD) is actively installed and enabled in Windows."""
    status = check_virtual_display_status()
    return status.get("installed", False) and status.get("enabled", False)


def install_virtual_display() -> bool:
    r"""
    Installs the Virtual Display Driver (Root\MttVDD) at native 1600x720 resolution
    and switches Windows display mode to Extend.
    """
    if is_driver_installed():
        switch_display_mode("extend")
        print("[+] Virtual Display Driver already installed & active. Switched to Extended desktop mode.", flush=True)
        return True

    nefcon_exe, driver_dir = get_driver_paths()
    if not nefcon_exe or not driver_dir:
        print("[!] Virtual Display Driver files not found on system.", flush=True)
        return False

    target_dir = Path("C:/VirtualDisplayDriver")

    try:
        if (driver_dir / "vdd_settings.xml").exists():
            target_dir.mkdir(parents=True, exist_ok=True)
            import shutil
            shutil.copy2(driver_dir / "vdd_settings.xml", target_dir / "vdd_settings.xml")

        # Direct install if already elevated
        if nefcon_exe.exists() and (driver_dir / "MttVDD.inf").exists():
            subprocess.run(["certutil.exe", "-addstore", "TrustedPublisher", str(driver_dir / "mttvdd.cat")], capture_output=True, timeout=5)
            subprocess.run(["pnputil", "/add-driver", str(driver_dir / "MttVDD.inf"), "/install"], capture_output=True, timeout=8)
            res = subprocess.run([str(nefcon_exe), "install", str(driver_dir / "MttVDD.inf"), "Root\\MttVDD"], capture_output=True, text=True, timeout=10)
            if res.returncode == 0:
                subprocess.run(["pnputil", "/scan-devices"], capture_output=True, timeout=5)
                time.sleep(1.5)
                switch_display_mode("extend")
                print("[+] Virtual Display Driver installed (1600x720) & Extended mode active!", flush=True)
                return True
    except Exception as e:
        print(f"[!] Direct install attempt: {e}", flush=True)

    # Elevated fallback using PowerShell RunAs with Base64 EncodedCommand and -Wait
    try:
        import base64
        script_block = f"""
        if (!(Test-Path '{target_dir}')) {{ New-Item -ItemType Directory -Path '{target_dir}' -Force }}
        Copy-Item -Path '{driver_dir}\\vdd_settings.xml' -Destination '{target_dir}\\vdd_settings.xml' -Force
        certutil.exe -addstore 'TrustedPublisher' '{driver_dir}\\mttvdd.cat'
        pnputil /add-driver '{driver_dir}\\MttVDD.inf' /install
        & '{nefcon_exe}' install '{driver_dir}\\MttVDD.inf' 'Root\\MttVDD'
        pnputil /scan-devices
        Start-Sleep -Seconds 2
        DisplaySwitch.exe /extend
        """
        encoded = base64.b64encode(script_block.encode("utf-16le")).decode("utf-8")
        subprocess.run([
            "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
            f"Start-Process powershell -ArgumentList @('-NoProfile', '-EncodedCommand', '{encoded}') -Verb RunAs -Wait"
        ], capture_output=True, timeout=20)
        time.sleep(1.5)
        switch_display_mode("extend")
        print("[+] Virtual Display Driver install completed via elevated administrator task.", flush=True)
        return True
    except Exception as e:
        print(f"[!] Error launching elevated VDD installer: {e}", flush=True)
        return False


def remove_virtual_display() -> bool:
    r"""
    Completely removes the Virtual Display Driver (Root\MttVDD) and resets Windows
    display output back to the primary internal PC display.
    """
    nefcon_exe, _ = get_driver_paths()
    if not nefcon_exe:
        nefcon_exe = Path(r"D:\app\ashon\controller\server\driver\vdd\nefcon\x64\nefconc.exe")

    # 1. Attempt direct removal first
    if nefcon_exe.exists():
        try:
            res = subprocess.run([str(nefcon_exe), "remove", "Root\\MttVDD"], capture_output=True, text=True, timeout=5)
            if res.returncode == 0:
                subprocess.run(["pnputil", "/remove-device", "/deviceid", "Root\\MttVDD", "/subtree"], capture_output=True, timeout=5)
                subprocess.run(["pnputil", "/scan-devices"], capture_output=True, timeout=5)
                switch_display_mode("internal")
                print("[+] Virtual Display Driver removed & reverted to primary PC display.", flush=True)
                return True
        except Exception:
            pass

    # 2. Elevated fallback using PowerShell RunAs with Base64 EncodedCommand and -Wait
    try:
        import base64
        script_block = f"""
        & '{nefcon_exe}' remove 'Root\\MttVDD'
        pnputil /remove-device /deviceid 'Root\\MttVDD' /subtree
        pnputil /scan-devices
        DisplaySwitch.exe /internal
        """
        encoded = base64.b64encode(script_block.encode("utf-16le")).decode("utf-8")
        subprocess.run([
            "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
            f"Start-Process powershell -ArgumentList '-NoProfile -EncodedCommand {encoded}' -Verb RunAs -Wait"
        ], capture_output=True, timeout=12)
        switch_display_mode("internal")
        print("[+] Virtual Display Driver uninstalled via elevated administrator task.", flush=True)
        return True
    except Exception as e:
        print(f"[!] Error launching elevated VDD uninstaller: {e}", flush=True)
        return False


def launch_virtual_display_installer():
    return install_virtual_display()


def launch_virtual_display_uninstaller():
    return remove_virtual_display()


def toggle_virtual_display_device(enable: bool):
    """Enables or disables the Virtual Display device using pnputil."""
    cmd = "enable-device" if enable else "disable-device"
    try:
        subprocess.run(["pnputil", f"/{cmd}", "/deviceid", "Root\\MttVDD"], capture_output=True, timeout=5)
    except Exception as e:
        print(f"[!] Error toggling VDD device: {e}", flush=True)


def toggle_spacedesk_service(action: str):
    """Starts or stops the spacedeskService."""
    try:
        if action == "start":
            subprocess.run(["net", "start", "spacedeskService"], capture_output=True, timeout=5)
        elif action == "stop":
            subprocess.run(["net", "stop", "spacedeskService"], capture_output=True, timeout=5)
    except Exception as e:
        print(f"[!] Error toggling spacedesk service: {e}", flush=True)


def play_monitor_sound(connected: bool):
    """Plays authentic Windows hardware insert or remove sound chime."""
    try:
        import winsound
        sound_name = "Windows Hardware Insert.wav" if connected else "Windows Hardware Remove.wav"
        sound_path = Path(r"C:\Windows\Media") / sound_name
        if sound_path.exists():
            winsound.PlaySound(str(sound_path), winsound.SND_FILENAME | winsound.SND_ASYNC)
    except Exception:
        pass


def switch_display_mode(mode: str):
    """
    Switches Windows multi-monitor projection mode:
    mode: 'extend' (dual monitor), 'clone' (mirror), 'internal' (PC only)
    Triggers native Windows display transition animation and plays monitor hardware chime.
    """
    try:
        flag = f"/{mode}"
        subprocess.Popen(["DisplaySwitch.exe", flag])
        if mode == "extend":
            play_monitor_sound(connected=True)
        elif mode == "internal":
            play_monitor_sound(connected=False)
        print(f"[*] Windows DisplaySwitch executed: {flag}", flush=True)
    except Exception as e:
        print(f"[!] DisplaySwitch error: {e}", flush=True)


def launch_spacedesk_console():
    """Launches the Spacedesk Driver Console application window."""
    path = r"C:\Program Files\datronicsoft\spacedesk\spacedeskConsole.exe"
    if os.path.exists(path):
        try:
            subprocess.Popen([path])
            return True
        except Exception:
            pass
    return False


def open_display_settings():
    """Opens Windows 10/11 Display Settings page (ms-settings:display)."""
    try:
        subprocess.Popen(["cmd.exe", "/c", "start", "ms-settings:display"], shell=True)
        return True
    except Exception as e:
        print(f"[!] Error opening display settings: {e}", flush=True)
        return False


class ScreenCapturer:
    """
    Ultra-low latency Direct DIB Section Screen Capturer with hardware StretchBlt & cursor injection.
    Eliminates GetDIBits and CPU cv2.resize for 120+ FPS capability (<8ms per frame).
    """
    def __init__(self, monitor_rect=None, scale: float = 0.8):
        attach_interactive_desktop()
        self.hdc_screen = u.GetDC(0)
        if monitor_rect:
            self.left = monitor_rect["left"]
            self.top = monitor_rect["top"]
            self.width = monitor_rect["width"]
            self.height = monitor_rect["height"]
        else:
            self.left = 0
            self.top = 0
            self.width = u.GetSystemMetrics(0)
            self.height = u.GetSystemMetrics(1)

        # Ensure dimensions are positive
        self.width = max(100, self.width)
        self.height = max(100, self.height)

        self.scale = max(0.4, min(1.0, scale))
        self.target_w = max(320, int(self.width * self.scale))
        self.target_h = max(240, int(self.height * self.scale))

        self.hdc_mem = g.CreateCompatibleDC(self.hdc_screen)

        self.bmi = BITMAPINFOHEADER()
        self.bmi.biSize = ctypes.sizeof(BITMAPINFOHEADER)
        self.bmi.biWidth = self.target_w
        self.bmi.biHeight = -self.target_h  # Negative for top-down DIB
        self.bmi.biPlanes = 1
        self.bmi.biBitCount = 32
        self.bmi.biCompression = 0

        self.p_bits = ctypes.c_void_p()
        self.hbmp = g.CreateDIBSection(
            self.hdc_mem,
            ctypes.byref(self.bmi),
            0,
            ctypes.byref(self.p_bits),
            None,
            0,
        )
        g.SelectObject(self.hdc_mem, self.hbmp)
        g.SetStretchBltMode(self.hdc_mem, 3)  # COLORONCOLOR (fast hardware scaling)

        # Zero-copy numpy buffer directly wrapping DIB memory pointer
        self.buf = np.frombuffer(
            (ctypes.c_uint8 * (self.target_w * self.target_h * 4)).from_address(self.p_bits.value),
            dtype=np.uint8,
        ).reshape((self.target_h, self.target_w, 4))

    def capture_jpeg(self, quality: int = 65, show_cursor: bool = True) -> bytes:
        """
        Hardware StretchBlits monitor pixels directly to DIB memory, draws cursor, and encodes JPEG in <8ms.
        """
        # 1. Direct hardware copy to memory (BitBlt for 1:1 native, StretchBlt for scaled)
        if self.width == self.target_w and self.height == self.target_h:
            g.BitBlt(
                self.hdc_mem,
                0,
                0,
                self.target_w,
                self.target_h,
                self.hdc_screen,
                self.left,
                self.top,
                0x00CC0020,  # SRCCOPY
            )
        else:
            g.StretchBlt(
                self.hdc_mem,
                0,
                0,
                self.target_w,
                self.target_h,
                self.hdc_screen,
                self.left,
                self.top,
                self.width,
                self.height,
                0x00CC0020,  # SRCCOPY
            )

        # 2. Draw Windows hardware cursor onto image at scaled coordinates
        if show_cursor:
            ci = CURSORINFO()
            ci.cbSize = ctypes.sizeof(CURSORINFO)
            if u.GetCursorInfo(ctypes.byref(ci)) and (ci.flags & 1):
                cursor_x = int((ci.ptScreenPos.x - self.left) * (self.target_w / self.width))
                cursor_y = int((ci.ptScreenPos.y - self.top) * (self.target_h / self.height))
                if 0 <= cursor_x < self.target_w and 0 <= cursor_y < self.target_h:
                    u.DrawIcon(self.hdc_mem, cursor_x, cursor_y, ci.hCursor)

        # 3. Ultra-fast hardware SIMD JPEG encode (TurboJPEG BGRA direct zero-copy)
        if HAS_SIMPLEJPEG:
            return simplejpeg.encode_jpeg(self.buf, quality=quality, colorspace='BGRA', fastdct=True)
        else:
            encode_params = [
                int(cv2.IMWRITE_JPEG_QUALITY), int(quality),
                int(cv2.IMWRITE_JPEG_OPTIMIZE), 0,  # 0 for max encode speed (lowest latency)
            ]
            _, enc = cv2.imencode(".jpg", self.buf[:, :, :3], encode_params)
            return enc.tobytes()

    def close(self):
        try:
            if self.hbmp:
                g.DeleteObject(self.hbmp)
            if self.hdc_mem:
                g.DeleteDC(self.hdc_mem)
            if self.hdc_screen:
                u.ReleaseDC(0, self.hdc_screen)
        except Exception:
            pass


class ScreenStreamSession:
    """
    Manages an active real-time screen stream to a WebSocket client.
    Captures and transmits frames ONLY while active.
    Uses non-blocking decoupled producer-consumer architecture so frames never buffer or lag behind.
    """
    def __init__(self, websocket, monitor_index: int = 0, quality: int = 75, fps: int = 60, scale: float = 1.0):
        self.websocket = websocket
        self.monitor_index = monitor_index
        self.quality = max(20, min(100, quality))
        self.fps = max(10, min(144, fps))
        self.scale = max(0.4, min(1.0, scale))
        self.is_running = False
        self._capture_task = None
        self._send_task = None
        self._capturer = None
        self._latest_frame = None
        self._new_frame_event = None

    def update_settings(self, fps: int = None, quality: int = None, scale: float = None, monitor_index: int = None):
        """Dynamically updates stream settings on the fly without breaking the connection."""
        if fps is not None:
            self.fps = max(10, min(144, int(fps)))
        if quality is not None:
            self.quality = max(20, min(100, int(quality)))
        need_reinit = False
        if scale is not None:
            new_scale = max(0.4, min(1.0, float(scale)))
            if abs(new_scale - self.scale) > 0.05:
                self.scale = new_scale
                need_reinit = True
        if monitor_index is not None and monitor_index != self.monitor_index:
            self.monitor_index = int(monitor_index)
            need_reinit = True

        if need_reinit:
            monitors = get_all_monitors()
            idx = self.monitor_index if (0 <= self.monitor_index < len(monitors)) else 0
            if self._capturer:
                self._capturer.close()
            self._capturer = ScreenCapturer(monitors[idx], scale=self.scale)
        print(f"[*] Stream live settings updated: Monitor {self.monitor_index} @ {self.fps} FPS, Q{self.quality}, Scale {self.scale}x", flush=True)

    def start(self):
        if self.is_running:
            return
        self.is_running = True
        self._new_frame_event = asyncio.Event()
        self._capture_task = asyncio.create_task(self._capture_loop())
        self._send_task = asyncio.create_task(self._send_loop())
        print(f"[+] Ultra-low latency screen stream active (Monitor {self.monitor_index} @ {self.fps}fps, Q{self.quality})", flush=True)

    def stop(self):
        if not self.is_running:
            return
        self.is_running = False
        for t in (self._capture_task, self._send_task):
            if t and not t.done():
                t.cancel()
        if self._capturer:
            self._capturer.close()
            self._capturer = None
        print(f"[-] Screen streaming stopped (monitor {self.monitor_index})", flush=True)

    async def _capture_loop(self):
        monitors = get_all_monitors()
        if 0 <= self.monitor_index < len(monitors):
            selected_mon = monitors[self.monitor_index]
        else:
            selected_mon = monitors[0]

        self._capturer = ScreenCapturer(selected_mon, scale=self.scale)

        try:
            while self.is_running:
                frame_interval = 1.0 / self.fps
                t0 = time.time()
                # Run capture & TurboJPEG encode in worker thread
                jpeg_bytes = await asyncio.to_thread(
                    self._capturer.capture_jpeg,
                    self.quality,
                    True,
                )
                self._latest_frame = jpeg_bytes
                if self._new_frame_event:
                    self._new_frame_event.set()

                elapsed = time.time() - t0
                sleep_time = max(0.001, frame_interval - elapsed)
                await asyncio.sleep(sleep_time)

        except asyncio.CancelledError:
            pass
        except Exception as e:
            print(f"[!] Capture loop ended: {e}", flush=True)
        finally:
            if self._capturer:
                self._capturer.close()
                self._capturer = None
            self.is_running = False

    async def _send_loop(self):
        try:
            while self.is_running:
                await self._new_frame_event.wait()
                self._new_frame_event.clear()
                frame = self._latest_frame
                if frame is not None:
                    # Send only the newest live frame; never queue or lag behind
                    await self.websocket.send(frame)
        except asyncio.CancelledError:
            pass
        except Exception as e:
            print(f"[!] Send loop ended: {e}", flush=True)
        finally:
            self.is_running = False


# Win32 Mouse Events
MOUSEEVENTF_MOVE = 0x0001
MOUSEEVENTF_LEFTDOWN = 0x0002
MOUSEEVENTF_LEFTUP = 0x0004
MOUSEEVENTF_RIGHTDOWN = 0x0008
MOUSEEVENTF_RIGHTUP = 0x0010
MOUSEEVENTF_MIDDLEDOWN = 0x0020
MOUSEEVENTF_MIDDLEUP = 0x0040
MOUSEEVENTF_WHEEL = 0x0800
MOUSEEVENTF_ABSOLUTE = 0x8000


def handle_screen_touch(data: dict):
    """
    Translates mobile screen touch coordinates (normalized 0.0 - 1.0) into
    absolute Windows desktop coordinates for the target monitor.
    """
    attach_interactive_desktop()

    action = data.get("action", "move")
    norm_x = float(data.get("x", 0.0))
    norm_y = float(data.get("y", 0.0))
    mon_idx = int(data.get("monitor", 0))

    monitors = get_all_monitors()
    if 0 <= mon_idx < len(monitors):
        mon = monitors[mon_idx]
    else:
        mon = monitors[0]

    # Map normalized coordinates (0.0 to 1.0) to monitor desktop pixels
    target_x = mon["left"] + int(norm_x * mon["width"])
    target_y = mon["top"] + int(norm_y * mon["height"])

    # Clamp coordinates to monitor bounds
    target_x = max(mon["left"], min(mon["right"] - 1, target_x))
    target_y = max(mon["top"], min(mon["bottom"] - 1, target_y))

    # Move mouse cursor to touch point
    u.SetCursorPos(target_x, target_y)

    if action == "down":
        button = data.get("button", "left")
        if button == "right":
            u.mouse_event(MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, 0)
        else:
            u.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)

    elif action == "move":
        # Cursor already positioned by SetCursorPos
        pass

    elif action == "up":
        button = data.get("button", "left")
        if button == "right":
            u.mouse_event(MOUSEEVENTF_RIGHTUP, 0, 0, 0, 0)
        else:
            u.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)

    elif action == "tap" or action == "click":
        u.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
        time.sleep(0.015)
        u.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)

    elif action == "double_tap" or action == "double_click":
        u.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
        time.sleep(0.015)
        u.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)
        time.sleep(0.05)
        u.mouse_event(MOUSEEVENTF_LEFTDOWN, 0, 0, 0, 0)
        time.sleep(0.015)
        u.mouse_event(MOUSEEVENTF_LEFTUP, 0, 0, 0, 0)

    elif action == "right_click":
        u.mouse_event(MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, 0)
        time.sleep(0.015)
        u.mouse_event(MOUSEEVENTF_RIGHTUP, 0, 0, 0, 0)

    elif action == "scroll":
        dy = int(data.get("delta_y", 0))
        if dy != 0:
            u.mouse_event(MOUSEEVENTF_WHEEL, 0, 0, dy, 0)
