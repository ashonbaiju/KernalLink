"""
High-Performance PC Server for Touch PC Controller.
Handles Xbox 360 emulation (ViGEm), Trackpad Mouse, Keyboard, and Media controls via WebSockets.
"""

import sys
import os
import json
import asyncio
import socket
import subprocess
import threading
import math
import struct
from pathlib import Path

# Add current dir to path for local imports
server_dir = Path(__file__).parent.resolve()
sys.path.insert(0, str(server_dir))

import websockets
import virtual_gamepad as vg
import input_handler
import screen_streamer
import audio_streamer

try:
    import pystray
    from PIL import Image, ImageDraw
    HAS_PYSTRAY = True
except ImportError:
    HAS_PYSTRAY = False

# Constants & Port
PORT = 8889
AUDIO_PORT = 8891

# Map distinct ViGEm button flags to all recognized alias names
BUTTON_FLAG_TO_NAMES = {
    vg.vcom.XUSB_BUTTON.XUSB_GAMEPAD_A: {"A"},
    vg.vcom.XUSB_BUTTON.XUSB_GAMEPAD_B: {"B"},
    vg.vcom.XUSB_BUTTON.XUSB_GAMEPAD_X: {"X"},
    vg.vcom.XUSB_BUTTON.XUSB_GAMEPAD_Y: {"Y"},
    vg.vcom.XUSB_BUTTON.XUSB_GAMEPAD_LEFT_SHOULDER: {"LB", "L1"},
    vg.vcom.XUSB_BUTTON.XUSB_GAMEPAD_RIGHT_SHOULDER: {"RB", "R1"},
    vg.vcom.XUSB_BUTTON.XUSB_GAMEPAD_LEFT_THUMB: {"THUMBL", "LS", "L3"},
    vg.vcom.XUSB_BUTTON.XUSB_GAMEPAD_RIGHT_THUMB: {"THUMBR", "RS", "R3"},
    vg.vcom.XUSB_BUTTON.XUSB_GAMEPAD_START: {"START", "MENU"},
    vg.vcom.XUSB_BUTTON.XUSB_GAMEPAD_BACK: {"BACK", "SELECT", "VIEW"},
    vg.vcom.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_UP: {"UP"},
    vg.vcom.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_DOWN: {"DOWN"},
    vg.vcom.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_LEFT: {"LEFT"},
    vg.vcom.XUSB_BUTTON.XUSB_GAMEPAD_DPAD_RIGHT: {"RIGHT"},
    vg.vcom.XUSB_BUTTON.XUSB_GAMEPAD_GUIDE: {"GUIDE", "HOME", "XBOX"},
}
BUTTON_MAP = {name: flag for flag, names in BUTTON_FLAG_TO_NAMES.items() for name in names}


class TouchServer:
    def __init__(self):
        input_handler.attach_interactive_desktop()
        self.input_handler = input_handler.InputHandler()
        self.gamepad = None
        self.connected_clients = set()
        self.panel_clients = set()
        self.screen_sessions = {}
        self._packet_count = 0
        self.monitor_mode_enabled = False
        self.current_fps = 60
        self.current_quality = 80
        self.current_scale = 1.0
        self.current_monitor = 0
        # Track primary (control) websocket per client IP for deduplication
        self._client_by_ip: dict = {}
        self._loop = None
        # Audio relay server
        self.audio_relay = audio_streamer.get_audio_relay(port=AUDIO_PORT)
        self.audio_relay.on_device_changed = self._on_external_audio_change
        # Initialize virtual Xbox 360 controller immediately so RDR2 and Windows games detect it continuously
        self.get_or_create_gamepad()

    def _on_external_audio_change(self):
        """Called from AudioRelay thread when Windows output device changes externally (e.g. Win+Ctrl+V)."""
        if self._loop and not self._loop.is_closed():
            try:
                asyncio.run_coroutine_threadsafe(self.broadcast_audio_status(), self._loop)
            except Exception:
                pass

    def build_audio_status_payload(self) -> dict:
        info = audio_streamer.get_audio_devices_info()
        st = self.audio_relay.get_status()
        return {
            "type": "audio_status",
            "default_device": info.get("default_device", ""),
            "is_virtual_default": info.get("is_virtual_default", False),
            "virtual_available": info.get("virtual_available", False),
            "devices": info.get("devices", []),
            "relay": st,
        }

    async def broadcast_audio_status(self):
        payload = json.dumps(self.build_audio_status_payload())
        for ws in list(self.connected_clients | self.panel_clients):
            try:
                await ws.send(payload)
            except Exception:
                pass

    def play_test_chime(self):
        audio_streamer.play_test_chime_async()

    async def set_stream_config(self, fps: int = None, quality: int = None, scale: float = None, monitor: int = None):
        """Dynamically updates stream settings on PC and pushes live sync to connected mobile clients."""
        if fps is not None:
            self.current_fps = max(10, min(144, int(fps)))
        if quality is not None:
            self.current_quality = max(20, min(100, int(quality)))
        if scale is not None:
            self.current_scale = max(0.4, min(1.0, float(scale)))
        if monitor is not None:
            self.current_monitor = int(monitor)

        # Update all active streaming sessions
        for ws, session in list(self.screen_sessions.items()):
            session.update_settings(fps=self.current_fps, quality=self.current_quality, scale=self.current_scale, monitor_index=self.current_monitor)
            try:
                await ws.send(json.dumps({
                    "type": "stream_config",
                    "fps": self.current_fps,
                    "quality": self.current_quality,
                    "scale": self.current_scale,
                    "monitor": self.current_monitor,
                }))
            except Exception:
                pass

    def get_or_create_gamepad(self):
        if self.gamepad is None:
            try:
                self.gamepad = vg.VX360Gamepad()
                self.gamepad.reset()
                self.gamepad.update()
                print("[+] Emulated Xbox 360 controller initialized via ViGEmBus (Ready for RDR2 and all PC games)", flush=True)
            except Exception as e:
                print(f"[!] Warning: Could not initialize ViGEmBus Xbox controller: {e}", flush=True)
                self.gamepad = None
        return self.gamepad

    def release_gamepad(self):
        if self.gamepad is not None:
            try:
                self.gamepad.reset()
                self.gamepad.update()
            except Exception:
                pass

    def stop_all_screen_sessions(self):
        for ws, sess in list(self.screen_sessions.items()):
            try:
                sess.stop()
            except Exception:
                pass
            try:
                asyncio.create_task(ws.send(json.dumps({
                    "type": "screen_stop_ack",
                    "reason": "monitor_mode_disabled"
                })))
            except Exception:
                pass
        self.screen_sessions.clear()

    def handle_gamepad_update(self, data):
        pad = self.get_or_create_gamepad()
        if pad is None:
            return

        # Joystick inputs: lx, ly, rx, ry in range [-1.0, 1.0]
        lx = float(data.get("lx", 0.0))
        ly = float(data.get("ly", 0.0))
        rx = float(data.get("rx", 0.0))
        ry = float(data.get("ry", 0.0))

        # Clamp and scale to [-32768, 32767]
        def clamp_scale(val):
            val = max(-1.0, min(1.0, val))
            return int(val * 32767)

        pad.left_joystick(x_value=clamp_scale(lx), y_value=clamp_scale(ly))
        pad.right_joystick(x_value=clamp_scale(rx), y_value=clamp_scale(ry))

        # Triggers: lt, rt in range [0.0, 1.0] -> [0, 255]
        lt = int(max(0.0, min(1.0, float(data.get("lt", 0.0)))) * 255)
        rt = int(max(0.0, min(1.0, float(data.get("rt", 0.0)))) * 255)
        pad.left_trigger(value=lt)
        pad.right_trigger(value=rt)

        # Buttons bitmask: press button if any alias name is sent
        pressed_buttons = set(data.get("buttons", []))
        for flag, aliases in BUTTON_FLAG_TO_NAMES.items():
            if not pressed_buttons.isdisjoint(aliases):
                pad.press_button(button=flag)
            else:
                pad.release_button(button=flag)

        pad.update()

    async def handle_client(self, websocket):
        client_address = websocket.remote_address
        client_ip = client_address[0]
        req_path = getattr(getattr(websocket, "request", None), "path", None) or getattr(websocket, "path", "/")
        is_panel = (req_path == "/panel")
        conn_mode = "PC Control Panel" if is_panel else ("USB Cable (ADB Reverse)" if client_ip == "127.0.0.1" else "Wi-Fi / LAN")

        if is_panel:
            self.panel_clients.add(websocket)
        else:
            # --- IP-based deduplication: close any stale phone connection from same IP ---
            existing = self._client_by_ip.get(client_ip)
            if existing is not None and existing is not websocket:
                try:
                    await existing.close()
                except Exception:
                    pass
                self.connected_clients.discard(existing)
                print(f"\n[>>>] Phone Reconnected ({conn_mode}): {client_ip}:{client_address[1]}", flush=True)
            else:
                print(f"\n[>>>] Phone Connected ({conn_mode}): {client_ip}:{client_address[1]}", flush=True)

            self._client_by_ip[client_ip] = websocket
            self.connected_clients.add(websocket)
            self.get_or_create_gamepad()

        # Send welcome/handshake ack
        await websocket.send(json.dumps({
            "type": "handshake_ack",
            "server": "KernalLink",
            "status": "ready"
        }))

        msg_type = "unknown"
        try:
            async for raw_message in websocket:
                try:
                    data = json.loads(raw_message)
                    msg_type = data.get("type")
                    self._packet_count += 1

                    if msg_type == "mouse_move":
                        dx = float(data.get("dx", 0.0))
                        dy = float(data.get("dy", 0.0))
                        self.input_handler.mouse_move_relative(dx, dy)

                    elif msg_type == "mouse_click":
                        btn = data.get("button", "left")
                        act = data.get("action", "click")
                        print(f"[*] Mouse click: button={btn}, action={act}", flush=True)
                        if act == "click":
                            self.input_handler.mouse_click(btn)
                        elif act == "down":
                            self.input_handler.mouse_down(btn)
                        elif act == "up":
                            self.input_handler.mouse_up(btn)

                    elif msg_type == "mouse_scroll":
                        dy = int(data.get("dy", 0))
                        self.input_handler.mouse_scroll(dy)

                    elif msg_type == "zoom":
                        direction = data.get("direction", "in")
                        amount = int(data.get("amount", 120))
                        print(f"[*] Zoom: {direction} (amt={amount})", flush=True)
                        self.input_handler.mouse_zoom(direction, amount)

                    elif msg_type == "key":
                        k = data.get("key", "")
                        act = data.get("action", "press")
                        print(f"[*] Keyboard key: {k} ({act})", flush=True)
                        self.input_handler.key_event(k, action=act)

                    elif msg_type == "text":
                        txt = data.get("text", "")
                        print(f"[*] Keyboard text: '{txt}'", flush=True)
                        self.input_handler.send_text(txt)

                    elif msg_type == "gamepad":
                        self.handle_gamepad_update(data)

                    elif msg_type == "media":
                        act = data.get("action", "")
                        print(f"[*] Media action: {act}", flush=True)
                        self.input_handler.trigger_media(act)

                    elif msg_type == "combo":
                        keys = data.get("keys", [])
                        print(f"[*] Keyboard combo: {keys}", flush=True)
                        self.input_handler.key_combo(keys)

                    elif msg_type == "ping":
                        t = data.get("t", 0)
                        await websocket.send(json.dumps({"type": "pong", "t": t}))

                    # --- DUAL MONITOR & SPACEDESK ENGINE ---
                    elif msg_type == "get_monitors":
                        monitors = screen_streamer.get_all_monitors()
                        sd_status = screen_streamer.get_spacedesk_status()
                        vdd_status = screen_streamer.check_virtual_display_status()
                        await websocket.send(json.dumps({
                            "type": "screen_meta",
                            "monitors": monitors,
                            "spacedesk": sd_status,
                            "vdd": vdd_status
                        }))

                    elif msg_type == "screen_start":
                        mon_idx = int(data.get("monitor", 0))

                        # Terminate any existing session on this websocket first
                        if websocket in self.screen_sessions:
                            self.screen_sessions[websocket].stop()

                        quality = int(data.get("quality", self.current_quality))
                        fps = int(data.get("fps", self.current_fps))
                        scale = float(data.get("scale", self.current_scale))
                        self.current_fps = fps
                        self.current_quality = quality
                        self.current_scale = scale
                        self.current_monitor = mon_idx

                        # If secondary display requested:
                        if mon_idx > 0:
                            self.monitor_mode_enabled = True
                            status = screen_streamer.check_virtual_display_status()
                            if not status.get("installed"):
                                print("[*] Secondary display requested: Installing Virtual Display Driver...", flush=True)
                                screen_streamer.install_virtual_display()
                            else:
                                # Driver already installed -> seamlessly extend without device install animation!
                                screen_streamer.switch_display_mode("extend")

                        session = screen_streamer.ScreenStreamSession(
                            websocket=websocket,
                            monitor_index=mon_idx,
                            quality=quality,
                            fps=fps,
                            scale=scale,
                        )
                        self.screen_sessions[websocket] = session
                        session.start()

                    elif msg_type == "screen_stop":
                        if websocket in self.screen_sessions:
                            self.screen_sessions[websocket].stop()
                            del self.screen_sessions[websocket]

                    elif msg_type == "screen_touch":
                        screen_streamer.handle_screen_touch(data)

                    elif msg_type == "display_switch":
                        mode = data.get("mode", "extend")
                        screen_streamer.switch_display_mode(mode)
                        await asyncio.sleep(0.5)
                        # Re-send updated monitors
                        monitors = screen_streamer.get_all_monitors()
                        sd_status = screen_streamer.get_spacedesk_status()
                        vdd_status = screen_streamer.check_virtual_display_status()
                        await websocket.send(json.dumps({
                            "type": "screen_meta",
                            "monitors": monitors,
                            "spacedesk": sd_status,
                            "vdd": vdd_status
                        }))

                    elif msg_type == "spacedesk_action":
                        action = data.get("action", "")
                        if action in ("start", "stop"):
                            screen_streamer.toggle_spacedesk_service(action)
                        elif action == "launch_console":
                            screen_streamer.launch_spacedesk_console()
                        elif action == "open_display_settings":
                            screen_streamer.open_display_settings()

                        await asyncio.sleep(0.8)
                        sd_status = screen_streamer.get_spacedesk_status()
                        monitors = screen_streamer.get_all_monitors()
                        vdd_status = screen_streamer.check_virtual_display_status()
                        await websocket.send(json.dumps({
                            "type": "screen_meta",
                            "monitors": monitors,
                            "spacedesk": sd_status,
                            "vdd": vdd_status
                        }))

                    elif msg_type == "vdd_action":
                        action = data.get("action", "")
                        print(f"[*] Virtual Display Driver (VDD) action requested: {action}", flush=True)
                        if action == "install":
                            self.monitor_mode_enabled = True
                            screen_streamer.install_virtual_display()
                        elif action == "uninstall":
                            self.stop_all_screen_sessions()
                            self.monitor_mode_enabled = False
                            screen_streamer.remove_virtual_display()
                        elif action == "enable":
                            self.monitor_mode_enabled = True
                            screen_streamer.toggle_virtual_display_device(True)
                        elif action == "disable":
                            self.stop_all_screen_sessions()
                            self.monitor_mode_enabled = False
                            screen_streamer.toggle_virtual_display_device(False)

                        await asyncio.sleep(1.0)
                        monitors = screen_streamer.get_all_monitors()
                        sd_status = screen_streamer.get_spacedesk_status()
                        vdd_status = screen_streamer.check_virtual_display_status()
                        await websocket.send(json.dumps({
                            "type": "screen_meta",
                            "monitors": monitors,
                            "spacedesk": sd_status,
                            "vdd": vdd_status
                        }))

                    # --- AUDIO RELAY & VIRTUAL SPEAKER ENGINE ---
                    elif msg_type == "get_audio_status":
                        await websocket.send(json.dumps(self.build_audio_status_payload()))

                    elif msg_type == "switch_audio_device":
                        target = data.get("target", "virtual")
                        print(f"[*] Switching Windows sound output device to: {target}", flush=True)
                        audio_streamer.set_windows_playback_device(target)
                        await asyncio.sleep(0.2)
                        await self.broadcast_audio_status()

                    elif msg_type == "audio_relay_control":
                        action = str(data.get("action", "")).lower()
                        if action == "start":
                            self.audio_relay.start()
                        elif action == "stop":
                            self.audio_relay.stop()
                        elif action == "toggle":
                            if self.audio_relay.running:
                                self.audio_relay.stop()
                            else:
                                self.audio_relay.start()
                        elif action == "set_mode":
                            self.audio_relay.set_mode(str(data.get("mode", "auto")))
                        elif action == "test_chime":
                            self.play_test_chime()
                        elif action == "open_win_flyout":
                            audio_streamer.open_windows_audio_flyout()
                        elif action in ("vol_up", "vol_down", "mute"):
                            self.input_handler.trigger_media(action)
                        await asyncio.sleep(0.1)
                        await self.broadcast_audio_status()

                    elif msg_type == "get_server_status":
                        monitors = screen_streamer.get_all_monitors()
                        await websocket.send(json.dumps({
                            "type": "server_status",
                            "clients": len(self.connected_clients),
                            "screen_streaming": len(self.screen_sessions) > 0,
                            "screen_sessions": len(self.screen_sessions),
                            "fps": self.current_fps,
                            "quality": self.current_quality,
                            "scale": self.current_scale,
                            "monitor": self.current_monitor,
                            "monitors": len(monitors),
                            "audio": self.build_audio_status_payload(),
                        }))

                    elif msg_type == "screen_stop_all":
                        self.stop_all_screen_sessions()
                        if self.monitor_mode_enabled:
                            self.monitor_mode_enabled = False
                            screen_streamer.switch_display_mode("internal")
                        await websocket.send(json.dumps({
                            "type": "server_status",
                            "clients": len(self.connected_clients),
                            "screen_streaming": False,
                            "screen_sessions": 0,
                            "fps": self.current_fps,
                            "quality": self.current_quality,
                            "scale": self.current_scale,
                            "monitor": self.current_monitor,
                            "monitors": len(screen_streamer.get_all_monitors()),
                            "audio": self.build_audio_status_payload(),
                        }))

                    elif msg_type == "restart_server":
                        print("[*] Server restart requested via WebSocket. Shutting down...", flush=True)
                        os._exit(0)

                except Exception as ex:
                    print(f"[!] Error processing message '{msg_type}': {ex}", flush=True)

        except websockets.exceptions.ConnectionClosed:
            pass
        finally:
            if websocket in self.screen_sessions:
                try:
                    self.screen_sessions[websocket].stop()
                    del self.screen_sessions[websocket]
                except Exception:
                    pass
            if is_panel:
                self.panel_clients.discard(websocket)
            else:
                self.connected_clients.discard(websocket)
                # Only clean up IP tracking if this websocket is still the active one for that IP
                if self._client_by_ip.get(client_ip) is websocket:
                    del self._client_by_ip[client_ip]
                print(f"[<<<] Device Disconnected: {client_ip}:{client_address[1]}", flush=True)
                if not self.connected_clients:
                    self.release_gamepad()
                    self.stop_all_screen_sessions()
                    if self.monitor_mode_enabled:
                        self.monitor_mode_enabled = False
                        screen_streamer.switch_display_mode("internal")
                    print("\n[*] Device disconnected -> Secondary display detached.\n", flush=True)
                    print("KernalLink> ", end="", flush=True)


def get_network_ips():
    """Detects active IPv4 addresses on this PC, filtering out APIPA/loopback."""
    ips = []
    try:
        hostname = socket.gethostname()
        for ip in socket.gethostbyname_ex(hostname)[2]:
            # Ignore loopback (127.) and APIPA auto-configuration (169.254.)
            if not ip.startswith("127.") and not ip.startswith("169.254."):
                ips.append(ip)
    except Exception:
        pass

    # Ensure 127.0.0.1 is always listed for USB ADB
    ips.append("127.0.0.1")
    return list(dict.fromkeys(ips))


def get_adb_binary():
    """Finds the adb executable across system PATH and standard Android SDK locations."""
    import shutil
    adb_path = shutil.which("adb")
    if adb_path:
        return adb_path
    
    candidates = [
        Path(os.environ.get("LOCALAPPDATA", "")) / "Android" / "Sdk" / "platform-tools" / "adb.exe",
        Path("C:/platform-tools/adb.exe"),
        Path(os.environ.get("PROGRAMFILES", "")) / "Android" / "platform-tools" / "adb.exe",
        Path(os.environ.get("ProgramFiles(x86)", "")) / "Android" / "platform-tools" / "adb.exe",
        Path("C:/flutter_windows_3.41.8-stable/flutter/bin/cache/artifacts/engine/windows-x64/adb.exe"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return str(candidate)
    return None


def check_and_setup_adb():
    """Attempts to configure adb reverse for zero-config USB Cable connection."""
    adb_bin = get_adb_binary()
    if not adb_bin:
        return False, "ADB not found"

    flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
    try:
        dev_res = subprocess.run([adb_bin, "devices"], capture_output=True, text=True, timeout=6, creationflags=flags)
        lines = [line.strip() for line in dev_res.stdout.strip().splitlines() if line.strip()]
        device_lines = [l for l in lines[1:] if not l.startswith("*")]

        if any("unauthorized" in l for l in device_lines):
            return False, "unauthorized"

        connected_devices = [l.split()[0] for l in device_lines if "\tdevice" in l or " device" in l]
        if not connected_devices:
            return False, "no_device"

        # Device is connected and authorized: run reverse
        rev_res = subprocess.run([adb_bin, "reverse", f"tcp:{PORT}", f"tcp:{PORT}"], capture_output=True, text=True, timeout=6, creationflags=flags)
        subprocess.run([adb_bin, "reverse", f"tcp:{AUDIO_PORT}", f"tcp:{AUDIO_PORT}"], capture_output=True, text=True, timeout=6, creationflags=flags)
        if rev_res.returncode == 0:
            return True, connected_devices[0]
    except Exception:
        pass
    return False, "no_device"


async def run_udp_discovery_beacon(ips):
    """
    Broadcasts UDP discovery packets on port 8890 every 1.5s so mobile apps on Wi-Fi
    can discover this PC automatically without typing IP addresses.
    Also responds immediately to mobile app scan probes.
    """
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setblocking(False)

    try:
        sock.bind(("0.0.0.0", 8890))
    except Exception:
        pass

    loop = asyncio.get_running_loop()

    # Responder for on-demand scan pings from the mobile app
    async def probe_listener():
        while True:
            try:
                data, addr = await loop.sock_recvfrom(sock, 1024)
                text = data.decode("utf-8", errors="ignore")
                if "find_kernallink" in text or "find_touch_pc" in text or "scan" in text.lower():
                    lan_ips = [ip for ip in get_network_ips() if not ip.startswith("127.")]
                    resp = json.dumps({
                        "service": "kernallink_server",
                        "hostname": socket.gethostname(),
                        "port": PORT,
                        "ips": lan_ips,
                    }).encode("utf-8")
                    sock.sendto(resp, addr)
            except Exception:
                await asyncio.sleep(0.5)

    asyncio.create_task(probe_listener())

    # Periodic broadcast beacon
    while True:
        try:
            lan_ips = [ip for ip in get_network_ips() if not ip.startswith("127.")]
            payload = json.dumps({
                "service": "kernallink_server",
                "hostname": socket.gethostname(),
                "port": PORT,
                "ips": lan_ips,
            }).encode("utf-8")
            # Global broadcast
            try:
                sock.sendto(payload, ("255.255.255.255", 8890))
            except Exception:
                pass
            # Specific subnet broadcasts (e.g. 192.168.1.255) for routers that drop 255.255.255.255
            for ip in lan_ips:
                parts = ip.split(".")
                if len(parts) == 4:
                    subnet_bcast = f"{parts[0]}.{parts[1]}.{parts[2]}.255"
                    try:
                        sock.sendto(payload, (subnet_bcast, 8890))
                    except Exception:
                        pass
        except Exception:
            pass
        await asyncio.sleep(1.2)


def force_stop_all():
    """Terminates all running instances of KernalLink and frees ports 8889 and 8890."""
    print("[*] Terminating all KernalLink server processes and freeing network ports...", flush=True)
    try:
        subprocess.run(["taskkill", "/f", "/im", "KernalLink.exe"], capture_output=True)
        subprocess.run(["taskkill", "/f", "/im", "TouchPCServer.exe"], capture_output=True)
        subprocess.run(["taskkill", "/f", "/im", "TouchPCServer_Console.exe"], capture_output=True)
        subprocess.run(["taskkill", "/f", "/im", "TouchPC_Console.exe"], capture_output=True)
        for port in ("8889", "8890", "8891"):
            res = subprocess.run(f"netstat -aon | findstr :{port}", shell=True, capture_output=True, text=True)
            for l in res.stdout.splitlines():
                parts = l.strip().split()
                if len(parts) >= 5 and parts[-1].isdigit():
                    pid = parts[-1]
                    if pid != str(os.getpid()):
                        subprocess.run(["taskkill", "/f", "/pid", pid], capture_output=True)
        print("[OK] All processes terminated and ports 8889 / 8890 released.", flush=True)
    except Exception as e:
        print(f"[!] Error during force stop: {e}", flush=True)


def launch_gui_panel():
    """Spawns the KernalLink Visual Control Panel GUI as an independent window."""
    try:
        if getattr(sys, "frozen", False):
            subprocess.Popen([sys.executable, "--panel"], cwd=str(Path(sys.executable).parent))
        else:
            panel_script = server_dir / "pc_console.py"
            subprocess.Popen([sys.executable, str(panel_script)], cwd=str(server_dir))
        print("[+] Launched KernalLink Visual Control Panel GUI.", flush=True)
    except Exception as e:
        print(f"[!] Could not launch GUI Control Panel: {e}", flush=True)


def print_console_menu():
    print("\n" + "=" * 66, flush=True)
    print("                 KERNALLINK COMMAND CONSOLE", flush=True)
    print("=" * 66, flush=True)
    print(" SERVER & DISPLAY CONTROLS:", flush=True)
    print("  [0] Stop Server            -> Gracefully shut down KernalLink", flush=True)
    print("  [1] Force Stop Server      -> Terminate all instances & release ports", flush=True)
    print("  [2] Enable Monitor Mode    -> Activate Virtual Display (1600x720)", flush=True)
    print("  [3] Uninstall Driver       -> Remove Virtual Display Driver from PC", flush=True)
    print("  [4] Display Settings       -> Open Windows Display Properties", flush=True)
    print("\n AUDIO STREAM & VIRTUAL SPEAKER CONTROLS (PHONE + LAPTOP):", flush=True)
    print("  [5] Start Audio Stream     -> Start PC -> Phone audio relay (Port 8891)", flush=True)
    print("  [6] Stop Audio Stream      -> Stop PC -> Phone audio relay", flush=True)
    print("  [7] Virtual Speaker Mode   -> Switch output to KernalLink Virtual Speaker", flush=True)
    print("  [8] System Speaker Mode    -> Switch output to Laptop Realtek Speakers", flush=True)
    print("  [9] Win Output Switcher    -> Open Windows Audio Flyout (Win+Ctrl+V)", flush=True)
    print("  [10] Stop Screen Stream    -> Stop active phone screen/display stream", flush=True)
    print("  [g] Open PC Panel GUI      -> Launch KernalLink Visual Control Panel", flush=True)
    print("  [vs] / [spk] / [audio]     -> Quick audio switch or status details", flush=True)
    print("\n LIVE DISPLAY & STREAM CONTROLS (Syncs to Mobile App):", flush=True)
    print("  [60] / [90] / [120] / [144] -> Switch Refresh Rate (Hz / FPS)", flush=True)
    print("  [q 60] / [q 80] / [q 90]   -> Change Stream Quality (Balanced/Ultra/Retina)", flush=True)
    print("  [mon 1] / [mon 2]          -> Switch Target Monitor (Display 1 / 2)", flush=True)
    print("  [extend] / [mirror]        -> Switch Windows Display Projection (Win + P)", flush=True)
    print("  [s] Status                 -> Show Live Stream & Device Settings", flush=True)
    print("  [h] Help                   -> Re-display this command list", flush=True)
    print("=" * 66, flush=True)
    print("KernalLink> ", end="", flush=True)


async def run_interactive_console(server):
    """Interactive command-line control loop for managing the server, display drivers, and modes."""
    loop = asyncio.get_running_loop()
    await asyncio.sleep(0.6)
    print_console_menu()

    while True:
        try:
            line = await loop.run_in_executor(None, sys.stdin.readline)
            if not line:
                await asyncio.sleep(1.0)
                continue

            cmd = line.strip().lower()
            if not cmd:
                print("KernalLink> ", end="", flush=True)
                continue

            if cmd == "0":
                print("\n[*] Stopping KernalLink Server...", flush=True)
                server.stop_all_screen_sessions()
                server.audio_relay.stop()
                if server.monitor_mode_enabled:
                    server.monitor_mode_enabled = False
                    screen_streamer.switch_display_mode("internal")
                server.release_gamepad()
                print("[OK] KernalLink server stopped. Goodbye!\n", flush=True)
                os._exit(0)

            elif cmd == "1":
                print("\n[!] Force stopping KernalLink...", flush=True)
                server.stop_all_screen_sessions()
                server.audio_relay.stop()
                if server.monitor_mode_enabled:
                    server.monitor_mode_enabled = False
                    screen_streamer.switch_display_mode("internal")
                server.release_gamepad()
                force_stop_all()
                os._exit(0)

            elif cmd == "2":
                server.monitor_mode_enabled = True
                if screen_streamer.is_driver_installed():
                    print("\n[*] Activating Monitor Mode (Virtual Display Driver already installed)...", flush=True)
                    screen_streamer.switch_display_mode("extend")
                    print("[OK] Monitor Mode Active! Windows switched to Extended Desktop (1600x720).\n", flush=True)
                else:
                    print("\n[*] Activating Monitor Mode: Installing Virtual Display Driver...", flush=True)
                    success = screen_streamer.install_virtual_display()
                    if success:
                        print("[OK] Monitor Mode Active! Virtual Display Driver installed (1600x720).\n", flush=True)
                    else:
                        print("[!] Note: If a Windows prompt appeared, click 'Yes' to complete activation.\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd == "3":
                print("\n[*] Uninstalling Virtual Display Driver from PC...", flush=True)
                server.stop_all_screen_sessions()
                server.monitor_mode_enabled = False
                screen_streamer.remove_virtual_display()
                print("[OK] Virtual Display Driver completely uninstalled & PC monitor restored to primary display.\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd == "4":
                print("\n[*] Opening Windows Display Settings...", flush=True)
                screen_streamer.open_display_settings()
                print("KernalLink> ", end="", flush=True)

            # --- AUDIO STREAMING & OUTPUT CONTROLS ---
            elif cmd in ("5", "a start", "audio start", "start audio"):
                ok = server.audio_relay.start()
                await server.broadcast_audio_status()
                print(f"\n[{'OK' if ok else '!'}] Audio Stream {'STARTED (Port 8891)' if ok else 'could not start (check PyAudioWPatch)'}.\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("6", "a stop", "audio stop", "stop audio"):
                server.audio_relay.stop()
                await server.broadcast_audio_status()
                print("\n[OK] Audio Stream STOPPED.\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("7", "vs", "audio vs", "audio virtual", "phone audio"):
                audio_streamer.set_windows_playback_device("virtual")
                await asyncio.sleep(0.2)
                await server.broadcast_audio_status()
                print("\n[OK] Windows Default Audio -> KernalLink Virtual Speaker (Phone Only).\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("8", "spk", "audio spk", "audio laptop", "laptop audio", "pc audio"):
                audio_streamer.set_windows_playback_device("speakers")
                await asyncio.sleep(0.2)
                await server.broadcast_audio_status()
                print("\n[OK] Windows Default Audio -> System / Laptop Speakers (Mirror).\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("9", "win audio", "flyout"):
                audio_streamer.open_windows_audio_flyout()
                print("\n[*] Triggered Windows Audio Output Switcher (Win+Ctrl+V).\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("10", "stopscreen", "screen stop"):
                server.stop_all_screen_sessions()
                if server.monitor_mode_enabled:
                    server.monitor_mode_enabled = False
                    screen_streamer.switch_display_mode("internal")
                print("\n[OK] Stopped active screen/display streams.\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("g", "gui", "panel", "ui"):
                launch_gui_panel()
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("audio", "sound"):
                info = audio_streamer.get_audio_devices_info()
                st = server.audio_relay.get_status()
                print("\n" + "=" * 66, flush=True)
                print("                 KERNALLINK AUDIO RELAY STATUS", flush=True)
                print("=" * 66, flush=True)
                print(f" Windows Default Output: {info.get('default_device', 'Unknown')}", flush=True)
                print(f" KernalLink Speaker:     {'ACTIVE (Routing to Phone Only)' if info.get('is_virtual_default') else 'STANDBY (Playing on Laptop)'}", flush=True)
                print(f" Audio Relay Server:     Port {st['port']} ({'RUNNING' if st['running'] else 'STOPPED'})", flush=True)
                print(f" Active Capture Device:  {st['device']}", flush=True)
                print(f" Connected Phone Audio:  {st['clients']} active client(s)", flush=True)
                print("=" * 66 + "\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            # --- DYNAMIC REFRESH RATE / FPS CONTROLS (LIKE MOBILE APP) ---
            elif cmd in ("120", "120hz", "hz 120", "hz120", "fps 120", "fps120"):
                await server.set_stream_config(fps=120)
                print(f"\n[+] Switched to 120 Hz / 120 FPS (Pro Zero-Latency Gaming Mode)!\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("90", "90hz", "hz 90", "hz90", "fps 90", "fps90"):
                await server.set_stream_config(fps=90)
                print(f"\n[+] Switched to 90 Hz / 90 FPS (Smooth Refresh Mode)!\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("60", "60hz", "hz 60", "hz60", "fps 60", "fps60"):
                await server.set_stream_config(fps=60)
                print(f"\n[+] Switched to 60 Hz / 60 FPS (Ultra Native Mode)!\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("144", "144hz", "hz 144", "hz144", "fps 144", "fps144"):
                await server.set_stream_config(fps=144)
                print(f"\n[+] Switched to 144 Hz / 144 FPS (Maximum Refresh Rate)!\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("30", "30hz", "hz 30", "hz30", "fps 30", "fps30"):
                await server.set_stream_config(fps=30)
                print(f"\n[+] Switched to 30 Hz / 30 FPS (Power Saver Mode)!\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            # Custom FPS: e.g. "hz 75" or "fps 75"
            elif cmd.startswith("hz ") or cmd.startswith("fps "):
                try:
                    val = int(cmd.split()[-1])
                    await server.set_stream_config(fps=val)
                    print(f"\n[+] Switched to {val} Hz / {val} FPS!\n", flush=True)
                except ValueError:
                    print(f"[!] Invalid frequency: '{cmd}'. Example: hz 120", flush=True)
                print("KernalLink> ", end="", flush=True)

            # --- QUALITY CONTROLS ---
            elif cmd in ("q 80", "q80", "ultra", "80%"):
                await server.set_stream_config(quality=80)
                print(f"\n[+] Stream Quality switched to Q80 (Ultra Native)!\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("q 90", "q90", "retina", "90%"):
                await server.set_stream_config(quality=90)
                print(f"\n[+] Stream Quality switched to Q90 (Crisp Text & Retina)!\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("q 100", "q100", "lossless", "100%"):
                await server.set_stream_config(quality=100)
                print(f"\n[+] Stream Quality switched to Q100 (Uncompressed Lossless)!\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("q 60", "q60", "balanced", "60%"):
                await server.set_stream_config(quality=60)
                print(f"\n[+] Stream Quality switched to Q60 (Balanced Bandwidth)!\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd.startswith("q ") or (cmd.startswith("q") and cmd[1:].isdigit()):
                try:
                    val = int(cmd.replace("q", "").strip())
                    await server.set_stream_config(quality=val)
                    print(f"\n[+] Stream Quality switched to Q{val}!\n", flush=True)
                except ValueError:
                    print(f"[!] Invalid quality: '{cmd}'. Example: q 85", flush=True)
                print("KernalLink> ", end="", flush=True)

            # --- TARGET MONITOR SELECTION ---
            elif cmd in ("mon 1", "mon1", "display 1", "screen 1"):
                await server.set_stream_config(monitor=0)
                print(f"\n[+] Streaming target switched to Display 1 (Main PC Screen)!\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("mon 2", "mon2", "display 2", "screen 2"):
                server.monitor_mode_enabled = True
                if not screen_streamer.is_driver_installed():
                    screen_streamer.install_virtual_display()
                else:
                    screen_streamer.switch_display_mode("extend")
                await server.set_stream_config(monitor=1)
                print(f"\n[+] Streaming target switched to Display 2 (Virtual Extended Screen)!\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            # --- WINDOWS PROJECTION MODES ---
            elif cmd in ("extend", "ext"):
                server.monitor_mode_enabled = True
                screen_streamer.switch_display_mode("extend")
                print(f"\n[*] Windows Projection: Extended Desktop active!\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("mirror", "duplicate", "clone"):
                screen_streamer.switch_display_mode("clone")
                print(f"\n[*] Windows Projection: Duplicate (Mirror) active!\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("internal", "pc"):
                screen_streamer.switch_display_mode("internal")
                print(f"\n[*] Windows Projection: PC screen only active!\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            # --- LIVE STATUS CARD ---
            elif cmd in ("s", "status", "info"):
                monitors = screen_streamer.get_all_monitors()
                curr_mon = server.current_monitor
                mon_name = monitors[curr_mon]["name"] if 0 <= curr_mon < len(monitors) else f"Display {curr_mon + 1}"
                vdd_status = screen_streamer.check_virtual_display_status()
                vdd_str = "ACTIVE (1600x720 Extended)" if vdd_status.get("enabled") else "INACTIVE / STANDBY"

                print("\n" + "=" * 66, flush=True)
                print("                 KERNALLINK LIVE STATUS & SETTINGS", flush=True)
                print("=" * 66, flush=True)
                print(f" Target Stream:    {mon_name}", flush=True)
                print(f" Refresh Rate:     {server.current_fps} Hz / {server.current_fps} FPS", flush=True)
                print(f" Stream Quality:   Q{server.current_quality} (Scale: {server.current_scale}x)", flush=True)
                print(f" Connected Phone:  {len(server.connected_clients)} active connection(s)", flush=True)
                print(f" Virtual Display:  {vdd_str}", flush=True)
                print(f" Total Monitors:   {len(monitors)} monitor(s) detected", flush=True)
                print("=" * 66 + "\n", flush=True)
                print("KernalLink> ", end="", flush=True)

            elif cmd in ("h", "?", "help", "menu"):
                print_console_menu()

            else:
                print(f"[!] Unknown option '{cmd}'. Type 'h' for menu.", flush=True)
                print("KernalLink> ", end="", flush=True)

        except (EOFError, KeyboardInterrupt):
            print("\nExiting KernalLink...", flush=True)
            server.stop_all_screen_sessions()
            if server.monitor_mode_enabled:
                server.monitor_mode_enabled = False
                screen_streamer.switch_display_mode("internal")
            server.release_gamepad()
            os._exit(0)
        except Exception:
            await asyncio.sleep(0.5)


def _start_tray_icon(server):
    """Starts a system tray icon with quick PC audio/stream controls."""
    if not HAS_PYSTRAY:
        return

    def _create_icon_image():
        img = Image.new("RGB", (64, 64), (10, 12, 20))
        d = ImageDraw.Draw(img)
        d.rectangle([8, 8, 56, 56], outline=(59, 130, 246), width=4)
        d.rectangle([20, 20, 44, 44], fill=(255, 255, 255))
        return img

    def _on_start_audio(icon, item):
        server.audio_relay.start()
        server._on_external_audio_change()

    def _on_stop_audio(icon, item):
        server.audio_relay.stop()
        server._on_external_audio_change()

    def _on_virt(icon, item):
        audio_streamer.set_windows_playback_device("virtual")
        server._on_external_audio_change()

    def _on_spk(icon, item):
        audio_streamer.set_windows_playback_device("speakers")
        server._on_external_audio_change()

    def _on_win_flyout(icon, item):
        audio_streamer.open_windows_audio_flyout()

    def _on_panel(icon, item):
        launch_gui_panel()

    def _on_quit(icon, item):
        try:
            icon.stop()
        except Exception:
            pass
        server.stop_all_screen_sessions()
        server.audio_relay.stop()
        os._exit(0)

    def _run():
        try:
            menu = pystray.Menu(
                pystray.MenuItem("Open KernalLink Control Panel", _on_panel, default=True),
                pystray.Menu.SEPARATOR,
                pystray.MenuItem("Start Audio Stream (Port 8891)", _on_start_audio),
                pystray.MenuItem("Stop Audio Stream", _on_stop_audio),
                pystray.Menu.SEPARATOR,
                pystray.MenuItem("Output: KernalLink Virtual Speaker", _on_virt),
                pystray.MenuItem("Output: System Laptop Speakers", _on_spk),
                pystray.MenuItem("Open Win Audio Switcher (Win+Ctrl+V)", _on_win_flyout),
                pystray.Menu.SEPARATOR,
                pystray.MenuItem("Exit Server", _on_quit),
            )
            icon = pystray.Icon("KernalLink", _create_icon_image(), "KernalLink PC Server", menu)
            icon.run()
        except Exception:
            pass

    threading.Thread(target=_run, daemon=True).start()


async def main():
    import logging
    # Suppress verbose websockets protocol tracebacks from empty health-check probes
    logging.getLogger("websockets.server").setLevel(logging.CRITICAL)

    server = TouchServer()
    server._loop = asyncio.get_running_loop()
    ips = get_network_ips()
    adb_ok, adb_info = check_and_setup_adb()

    print("=" * 66, flush=True)
    print("                 KERNALLINK MASTER SERVER (Windows)", flush=True)
    print("=" * 66, flush=True)
    print(f"Status: Listening on port {PORT} (TCP), {AUDIO_PORT} (Audio), 8890 (UDP Discovery)", flush=True)
    print("\n--- AVAILABLE CONNECTION ADDRESSES ---", flush=True)

    for ip in ips:
        if ip == "127.0.0.1":
            print(f" -> USB Cable (ADB Reverse): 127.0.0.1:{PORT}   [0.5ms Zero-Latency]", flush=True)
        elif ip.startswith("192.168.42."):
            print(f" -> USB Tethering:          {ip}:{PORT}   [DETECTED]", flush=True)
        else:
            print(f" -> Wi-Fi / LAN Network:     {ip}:{PORT}", flush=True)

    if adb_ok:
        print(f"\n[OK] USB Phone Detected ({adb_info})! ADB Reverse ACTIVE (Ports {PORT} & {AUDIO_PORT})!", flush=True)
        print(f"     --> On your mobile app, select: USB Cable (127.0.0.1:{PORT})", flush=True)
    elif adb_info == "unauthorized":
        print("\n[!] USB Phone detected, but status is UNAUTHORIZED!", flush=True)
        print("    --> Unlock phone screen now and tap 'ALLOW USB DEBUGGING'!", flush=True)
    else:
        print("\n[*] USB Cable Tip: Enable USB Debugging in phone Developer Options", flush=True)
        print("    for instant zero-latency (<1ms) connection without Wi-Fi router.", flush=True)

    print("=" * 66, flush=True)
    # Audio Relay Engine (Strictly On-Demand: Dormant until explicitly requested by app or console)
    try:
        aud_info = audio_streamer.get_audio_devices_info()
        print(f"[+] Audio Relay Engine Ready (On-Demand Mode on port {AUDIO_PORT})", flush=True)
        print(f"    -> Active Windows Output: {aud_info.get('default_device', 'Unknown')}", flush=True)
        print(f"    -> Virtual Speaker Ready: {'YES (Win+Ctrl+V -> KernalLink Virtual Speaker)' if aud_info.get('virtual_available') else 'NO (Using System Loopback Fallback)'}", flush=True)
        print("    -> Status: DORMANT (Will only start when activated from Mobile App or Console)", flush=True)
    except Exception as e:
        print(f"[!] Warning: Audio device probe note: {e}", flush=True)
    print("Ready and waiting for mobile app connection...\n", flush=True)

    # Start Windows system tray quick controls
    _start_tray_icon(server)

    # Start UDP discovery beacon in background
    asyncio.create_task(run_udp_discovery_beacon(ips))

    # Stateful ADB Watchdog: monitors USB connection changes in background thread
    last_adb_state = adb_ok
    async def adb_watchdog():
        nonlocal last_adb_state
        while True:
            try:
                ok, info = await asyncio.to_thread(check_and_setup_adb)
                if ok and not last_adb_state:
                    print(f"\n[OK] USB Phone Plugged In ({info})! ADB Reverse ACTIVE (Ports {PORT} & {AUDIO_PORT})!", flush=True)
                    print(f"     --> Connect mobile app via: 127.0.0.1:{PORT}\n", flush=True)
                    last_adb_state = True
                elif not ok and last_adb_state:
                    print("\n[*] USB Phone disconnected from ADB Reverse.\n", flush=True)
                    last_adb_state = False
            except Exception:
                pass
            await asyncio.sleep(2.5)

    asyncio.create_task(adb_watchdog())

    # Start Interactive Console
    if sys.stdin is not None:
        asyncio.create_task(run_interactive_console(server))

    try:
        async with websockets.serve(server.handle_client, "0.0.0.0", PORT, ping_interval=None):
            await asyncio.Future()  # Run forever
    except OSError as e:
        if "10048" in str(e) or "already in use" in str(e).lower():
            print("\n" + "=" * 66, flush=True)
            print(f"[!] PORT {PORT} IS ALREADY IN USE!", flush=True)
            print("    KernalLink is ALREADY RUNNING in the background on this PC.", flush=True)
            print("    Check your Windows system tray near the clock for the icon.", flush=True)
            print("=" * 66, flush=True)
            print("\nOptions:", flush=True)
            print("  [1] Force kill old instance and restart fresh now", flush=True)
            print("  [Enter] Keep background instance running and close this window\n", flush=True)
            try:
                choice = input("Enter choice (1 or Enter): ").strip()
                if choice == "1":
                    import subprocess
                    print("[*] Terminating stale processes on ports 8889 / 8890 / 8891...", flush=True)
                    subprocess.run('taskkill /f /im KernalLink.exe >nul 2>&1', shell=True)
                    subprocess.run('powershell -Command "Get-NetTCPConnection -LocalPort 8889,8890,8891 -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue }"', shell=True)
                    time.sleep(1.2)
                    print("[OK] Restarting server...\n", flush=True)
                    asyncio.run(main())
                    return
            except Exception:
                pass
            print("[*] Exiting. The background server is still active and listening.", flush=True)
            time.sleep(1.5)
            sys.exit(0)
        else:
            raise e


if __name__ == "__main__":
    if "--panel" in sys.argv or "--gui" in sys.argv:
        import pc_console
        pc_console.main()
        sys.exit(0)
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nServer terminated by user.", flush=True)
    except Exception as e:
        import traceback
        print("\n" + "=" * 66, flush=True)
        print(f"[ERROR] Server stopped with error: {e}", flush=True)
        traceback.print_exc()
        print("=" * 66, flush=True)
        print("\nPress Enter to exit...", flush=True)
        try:
            input()
        except Exception:
            time.sleep(5)

