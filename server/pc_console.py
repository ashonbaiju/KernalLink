"""
KernalLink PC Control Panel - Desktop Driver Console & Audio/Display Hub.
Provides a modern Windows GUI for managing the KernalLink Master Server,
Audio Relay & KernalLink Virtual Speaker, Dual Monitor (Spacedesk/VDD) integration,
USB zero-latency tethering (ADB Reverse), and live streaming controls.
"""

import sys
import os
import json
import time
import socket
import asyncio
import threading
import subprocess
import shutil
from pathlib import Path
import tkinter as tk
from tkinter import messagebox
import customtkinter as ctk

# Ensure working directory is the server directory
os.chdir(Path(__file__).parent.resolve())

try:
    import websockets
    HAS_WEBSOCKETS = True
except ImportError:
    HAS_WEBSOCKETS = False

# Try importing pystray for system tray functionality
try:
    import pystray
    from PIL import Image, ImageDraw
    HAS_PYSTRAY = True
except ImportError:
    HAS_PYSTRAY = False

# Import screen streamer utilities
try:
    import screen_streamer
    HAS_STREAMER = True
except ImportError:
    HAS_STREAMER = False

# Import audio streamer utilities
try:
    import audio_streamer
    HAS_AUDIO = True
except ImportError:
    HAS_AUDIO = False


def find_adb_path() -> str:
    """Locates the ADB executable on the system across common SDK paths."""
    path = shutil.which("adb")
    if path:
        return path
    candidates = [
        os.path.expandvars(r"%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe"),
        r"C:\platform-tools\adb.exe",
        os.path.expandvars(r"%PROGRAMFILES%\Android\platform-tools\adb.exe"),
        os.path.expandvars(r"%ProgramFiles(x86)%\Android\platform-tools\adb.exe"),
        r"C:\flutter_windows_3.41.8-stable\flutter\bin\cache\artifacts\engine\windows-x64\adb.exe",
    ]
    for c in candidates:
        if os.path.exists(c):
            return c
    return ""


def get_local_ip_addresses() -> list:
    """Detects active non-loopback, non-APIPA IPv4 addresses."""
    ips = []
    try:
        hostname = socket.gethostname()
        for ip in socket.gethostbyname_ex(hostname)[2]:
            if not ip.startswith("127.") and not ip.startswith("169.254.") and ":" not in ip:
                ips.append(ip)
    except Exception:
        pass
    if not ips:
        ips.append("127.0.0.1")
    return ips


def is_port_in_use(port: int = 8889) -> bool:
    """Checks if a TCP port is open and listening."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.3)
        return s.connect_ex(("127.0.0.1", port)) == 0


class TouchPCConsole(ctk.CTk):
    def __init__(self):
        super().__init__()

        # Window Configuration
        self.title("KernalLink PC Control Panel - Audio Relay & Dual Monitor Studio")
        self.geometry("980x720")
        self.minsize(900, 640)

        ctk.set_appearance_mode("dark")
        ctk.set_default_color_theme("blue")

        self.server_process = None
        self.adb_path = find_adb_path()
        self.tray_icon = None
        self.auto_monitor_var = ctk.BooleanVar(value=True)
        self._last_mon_count = 0
        self._last_usb_connected = False

        # Live server telemetry state synced via ws://127.0.0.1:8889/panel
        self._ws_loop = None
        self._ws_conn = None
        self._live_server_status = {}
        self._live_audio_status = {}
        self._closing = False

        # Build UI Components
        self._build_header()
        self._build_tabs()
        self._build_status_bar()

        # Start persistent WebSocket control bridge to KernalLink Master Server
        threading.Thread(target=self._start_ws_bridge_thread, daemon=True).start()

        # Start periodic background polling for status updates
        self.after(500, self._periodic_status_refresh)

        # Auto-launch server in background if not already running
        if not is_port_in_use(8889):
            self.after(600, self._restart_server)

        self.protocol("WM_DELETE_WINDOW", self._on_close)

    def _on_close(self):
        self._closing = True
        self.destroy()

    def _build_header(self):
        header_frame = ctk.CTkFrame(self, corner_radius=0, fg_color="#13151F", height=70)
        header_frame.pack(fill="x", side="top")
        header_frame.pack_propagate(False)

        # Title & Branding
        title_box = ctk.CTkFrame(header_frame, fg_color="transparent")
        title_box.pack(side="left", padx=20, pady=12)

        title_lbl = ctk.CTkLabel(
            title_box,
            text="KERNALLINK PC CONTROL PANEL",
            font=ctk.CTkFont(size=18, weight="bold"),
            text_color="#F8FAFC",
        )
        title_lbl.pack(anchor="w")

        sub_lbl = ctk.CTkLabel(
            title_box,
            text="Virtual Speaker Audio Relay · Dual Monitor (120Hz) · USB Zero-Latency",
            font=ctk.CTkFont(size=11),
            text_color="#94A3B8",
        )
        sub_lbl.pack(anchor="w")

        # Right Header: Server Power & Status Indicator
        ctrl_box = ctk.CTkFrame(header_frame, fg_color="transparent")
        ctrl_box.pack(side="right", padx=20, pady=12)

        self.usb_badge = ctk.CTkButton(
            ctrl_box,
            text="USB: SCANNING...",
            width=130,
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#1E293B",
            hover=False,
            corner_radius=20,
        )
        self.usb_badge.pack(side="left", padx=(0, 8))

        self.status_badge = ctk.CTkButton(
            ctrl_box,
            text="CHECKING STATUS...",
            width=165,
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#334155",
            hover=False,
            corner_radius=20,
        )
        self.status_badge.pack(side="left", padx=(0, 8))

        self.btn_restart_srv = ctk.CTkButton(
            ctrl_box,
            text="RESTART SERVER",
            width=120,
            height=32,
            fg_color="#2563EB",
            hover_color="#1D4ED8",
            font=ctk.CTkFont(size=11, weight="bold"),
            corner_radius=8,
            command=self._restart_server,
        )
        self.btn_restart_srv.pack(side="left")

    def _build_tabs(self):
        self.tabview = ctk.CTkTabview(self, fg_color="#0F111A", segmented_button_fg_color="#1E2235")
        self.tabview.pack(fill="both", expand=True, padx=16, pady=(10, 5))

        self.tab_dash = self.tabview.add("  Dashboard & Connectivity  ")
        self.tab_audio = self.tabview.add("  Audio Relay & Virtual Speaker  ")
        self.tab_mon = self.tabview.add("  Dual Monitor & Spacedesk  ")
        self.tab_perf = self.tabview.add("  Performance & Stream  ")
        self.tab_help = self.tabview.add("  Diagnostics & Help  ")

        self._build_dashboard_tab()
        self._build_audio_tab()
        self._build_monitor_tab()
        self._build_performance_tab()
        self._build_help_tab()

    # -------------------------------------------------------------
    # TAB 1: DASHBOARD & CONNECTIVITY
    # -------------------------------------------------------------
    def _build_dashboard_tab(self):
        container = ctk.CTkScrollableFrame(self.tab_dash, fg_color="transparent")
        container.pack(fill="both", expand=True, padx=10, pady=10)

        # 1. Quick Connection Modes Card
        card_modes = ctk.CTkFrame(container, fg_color="#181B29", corner_radius=12)
        card_modes.pack(fill="x", pady=(0, 12), padx=4)

        modes_title = ctk.CTkLabel(
            card_modes,
            text="CONNECTION MODES (MOBILE CLIENT)",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#60A5FA",
        )
        modes_title.pack(anchor="w", padx=16, pady=(12, 6))

        # Two columns: USB Cable & Wi-Fi
        col_box = ctk.CTkFrame(card_modes, fg_color="transparent")
        col_box.pack(fill="x", padx=16, pady=(0, 14))

        # Left Column: USB Cable (ADB Reverse)
        usb_frame = ctk.CTkFrame(col_box, fg_color="#202438", corner_radius=10)
        usb_frame.pack(side="left", fill="both", expand=True, padx=(0, 8), pady=4)

        ctk.CTkLabel(
            usb_frame,
            text="Mode 1: USB Cable (Zero-Latency)",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#34D399",
        ).pack(anchor="w", padx=12, pady=(10, 2))

        ctk.CTkLabel(
            usb_frame,
            text="Ultra-fast sub-millisecond latency (0.5ms). Best for Dual Monitor & Gaming.",
            font=ctk.CTkFont(size=10),
            text_color="#94A3B8",
            wraplength=380,
            justify="left",
        ).pack(anchor="w", padx=12, pady=(0, 8))

        self.btn_adb_reverse = ctk.CTkButton(
            usb_frame,
            text="CONNECT VIA USB (ADB REVERSE)",
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#059669",
            hover_color="#047857",
            command=self._run_adb_reverse,
        )
        self.btn_adb_reverse.pack(fill="x", padx=12, pady=(0, 10))

        # Right Column: Wi-Fi / Hotspot
        wifi_frame = ctk.CTkFrame(col_box, fg_color="#202438", corner_radius=10)
        wifi_frame.pack(side="left", fill="both", expand=True, padx=(8, 0), pady=4)

        ctk.CTkLabel(
            wifi_frame,
            text="Mode 2: Wi-Fi / Mobile Hotspot",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#60A5FA",
        ).pack(anchor="w", padx=12, pady=(10, 2))

        self.wifi_ip_label = ctk.CTkLabel(
            wifi_frame,
            text="Detecting local IP addresses...",
            font=ctk.CTkFont(size=10),
            text_color="#CBD5E1",
            justify="left",
        )
        self.wifi_ip_label.pack(anchor="w", padx=12, pady=(0, 8))

        self.btn_copy_ip = ctk.CTkButton(
            wifi_frame,
            text="COPY SERVER IP (PORT 8889)",
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#2563EB",
            hover_color="#1D4ED8",
            command=self._copy_primary_ip,
        )
        self.btn_copy_ip.pack(fill="x", padx=12, pady=(0, 10))

        # 1.5 Audio Relay & Streaming Quick Control Card (6 Actions)
        card_audio = ctk.CTkFrame(container, fg_color="#181B29", corner_radius=12)
        card_audio.pack(fill="x", pady=(0, 12), padx=4)

        audio_top = ctk.CTkFrame(card_audio, fg_color="transparent")
        audio_top.pack(fill="x", padx=16, pady=(12, 6))

        ctk.CTkLabel(
            audio_top,
            text="AUDIO STREAM & VIRTUAL SPEAKER QUICK CONTROLS",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#60A5FA",
        ).pack(side="left")

        self.lbl_dash_stream_pill = ctk.CTkLabel(
            audio_top,
            text="AUDIO RELAY: CHECKING...",
            font=ctk.CTkFont(size=10, weight="bold"),
            text_color="#94A3B8",
        )
        self.lbl_dash_stream_pill.pack(side="right")

        self.lbl_audio_dev = ctk.CTkLabel(
            card_audio,
            text="Active Output: Detecting...",
            font=ctk.CTkFont(size=11, weight="bold"),
            text_color="#94A3B8",
        )
        self.lbl_audio_dev.pack(anchor="w", padx=16, pady=(0, 8))

        # Row 1: Start / Stop Audio Stream & Stop Screen Stream
        stream_row = ctk.CTkFrame(card_audio, fg_color="transparent")
        stream_row.pack(fill="x", padx=16, pady=(0, 6))

        self.btn_dash_start_audio = ctk.CTkButton(
            stream_row,
            text="1. START AUDIO STREAM",
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#059669",
            hover_color="#047857",
            command=self._start_audio_stream,
        )
        self.btn_dash_start_audio.pack(side="left", fill="x", expand=True, padx=(0, 6))

        self.btn_dash_stop_audio = ctk.CTkButton(
            stream_row,
            text="2. STOP AUDIO STREAM",
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#B91C1C",
            hover_color="#991B1B",
            command=self._stop_audio_stream,
        )
        self.btn_dash_stop_audio.pack(side="left", fill="x", expand=True, padx=6)

        self.btn_dash_stop_screen = ctk.CTkButton(
            stream_row,
            text="5. STOP SCREEN STREAM",
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#475569",
            hover_color="#334155",
            command=self._stop_screen_stream,
        )
        self.btn_dash_stop_screen.pack(side="left", fill="x", expand=True, padx=(6, 0))

        # Row 2: Virtual Speaker / System Speakers / Win Output Flyout
        audio_btn_box = ctk.CTkFrame(card_audio, fg_color="transparent")
        audio_btn_box.pack(fill="x", padx=16, pady=(0, 12))

        ctk.CTkButton(
            audio_btn_box,
            text="3. VIRTUAL SPEAKER (PHONE)",
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#1D4ED8",
            hover_color="#1E40AF",
            command=self._switch_audio_to_virtual,
        ).pack(side="left", fill="x", expand=True, padx=(0, 6))

        ctk.CTkButton(
            audio_btn_box,
            text="4. SYSTEM SPEAKERS (LAPTOP)",
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#334155",
            hover_color="#475569",
            command=self._switch_audio_to_speakers,
        ).pack(side="left", fill="x", expand=True, padx=6)

        ctk.CTkButton(
            audio_btn_box,
            text="6. WIN SWITCHER (WIN+CTRL+V)",
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#4F46E5",
            hover_color="#4338CA",
            command=self._open_win_audio_flyout,
        ).pack(side="left", fill="x", expand=True, padx=(6, 0))

        # 2. Server Live Activity & Log Box
        card_logs = ctk.CTkFrame(container, fg_color="#181B29", corner_radius=12)
        card_logs.pack(fill="both", expand=True, padx=4, pady=6)

        log_head = ctk.CTkFrame(card_logs, fg_color="transparent")
        log_head.pack(fill="x", padx=16, pady=(12, 6))

        ctk.CTkLabel(
            log_head,
            text="LIVE SERVER ACTIVITY & CONNECTED CLIENTS",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#94A3B8",
        ).pack(side="left")

        ctk.CTkButton(
            log_head,
            text="CLEAR LOGS",
            width=80,
            height=24,
            font=ctk.CTkFont(size=10),
            fg_color="#334155",
            hover_color="#475569",
            command=self._clear_logs,
        ).pack(side="right")

        self.log_textbox = ctk.CTkTextbox(
            card_logs,
            height=180,
            font=ctk.CTkFont(family="Consolas", size=10),
            fg_color="#0F1118",
            text_color="#A7F3D0",
            wrap="word",
        )
        self.log_textbox.pack(fill="both", expand=True, padx=16, pady=(0, 14))
        self.log_textbox.insert("end", "[*] KernalLink PC Control Panel Initialized.\n")

    # -------------------------------------------------------------
    # TAB: AUDIO RELAY & VIRTUAL SPEAKER
    # -------------------------------------------------------------
    def _build_audio_tab(self):
        container = ctk.CTkScrollableFrame(self.tab_audio, fg_color="transparent")
        container.pack(fill="both", expand=True, padx=10, pady=10)

        # 0. Hero Card: KernalLink Virtual Speaker & Stream Toggle
        hero_card = ctk.CTkFrame(container, fg_color="#182038", corner_radius=12, border_width=1, border_color="#3B82F6")
        hero_card.pack(fill="x", pady=(0, 12), padx=4)

        hero_top = ctk.CTkFrame(hero_card, fg_color="transparent")
        hero_top.pack(fill="x", padx=16, pady=(14, 6))

        ctk.CTkLabel(
            hero_top,
            text="KERNALLINK VIRTUAL SPEAKER & AUDIO STREAMING ENGINE",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color="#60A5FA",
        ).pack(side="left")

        self.audio_status_pill = ctk.CTkLabel(
            hero_top,
            text="PORT 8891 · CHECKING...",
            font=ctk.CTkFont(size=10, weight="bold"),
            text_color="#94A3B8",
        )
        self.audio_status_pill.pack(side="right")

        ctk.CTkLabel(
            hero_card,
            text=(
                "1) Choose 'KernalLink Virtual Speaker (Phone Audio)' in Windows Win+Ctrl+V or below to silence laptop and stream exclusively to your phone.\n"
                "2) Choose 'Speakers (Realtek(R) Audio)' to hear sound on laptop and optionally mirror to your phone simultaneously."
            ),
            font=ctk.CTkFont(size=11),
            text_color="#CBD5E1",
            justify="left",
            wraplength=840,
        ).pack(anchor="w", padx=16, pady=(0, 10))

        # Master Stream Start / Stop Controls
        stream_ctrl_row = ctk.CTkFrame(hero_card, fg_color="transparent")
        stream_ctrl_row.pack(fill="x", padx=16, pady=(0, 14))

        self.btn_tab_start_audio = ctk.CTkButton(
            stream_ctrl_row,
            text="1. START AUDIO STREAM (PC -> PHONE)",
            height=36,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#059669",
            hover_color="#047857",
            command=self._start_audio_stream,
        )
        self.btn_tab_start_audio.pack(side="left", fill="x", expand=True, padx=(0, 6))

        self.btn_tab_stop_audio = ctk.CTkButton(
            stream_ctrl_row,
            text="2. STOP AUDIO STREAM",
            height=36,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#B91C1C",
            hover_color="#991B1B",
            command=self._stop_audio_stream,
        )
        self.btn_tab_stop_audio.pack(side="left", fill="x", expand=True, padx=6)

        ctk.CTkButton(
            stream_ctrl_row,
            text="5. STOP SCREEN STREAM",
            height=36,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#475569",
            hover_color="#334155",
            command=self._stop_screen_stream,
        ).pack(side="left", fill="x", expand=True, padx=(6, 0))

        # 1. Output Target Switching Card
        card_target = ctk.CTkFrame(container, fg_color="#181B29", corner_radius=12)
        card_target.pack(fill="x", pady=(0, 12), padx=4)

        t_head = ctk.CTkFrame(card_target, fg_color="transparent")
        t_head.pack(fill="x", padx=16, pady=(12, 6))

        ctk.CTkLabel(
            t_head,
            text="WINDOWS AUDIO PLAYBACK OUTPUT (WIN + CTRL + V)",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#60A5FA",
        ).pack(side="left")

        ctk.CTkButton(
            t_head,
            text="6. OPEN WIN OUTPUT FLYOUT",
            width=185,
            height=26,
            font=ctk.CTkFont(size=10, weight="bold"),
            fg_color="#4F46E5",
            hover_color="#4338CA",
            command=self._open_win_audio_flyout,
        ).pack(side="right")

        self.lbl_tab_audio_dev = ctk.CTkLabel(
            card_target,
            text="Active Output: Detecting Windows device...",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#34D399",
        )
        self.lbl_tab_audio_dev.pack(anchor="w", padx=16, pady=(0, 10))

        # Two primary selection buttons + Capture Mode Selector
        btn_box = ctk.CTkFrame(card_target, fg_color="transparent")
        btn_box.pack(fill="x", padx=16, pady=(0, 10))

        self.btn_set_virtual = ctk.CTkButton(
            btn_box,
            text="3. KERNALLINK VIRTUAL SPEAKER (PHONE ONLY)",
            height=36,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#059669",
            hover_color="#047857",
            command=self._switch_audio_to_virtual,
        )
        self.btn_set_virtual.pack(side="left", fill="x", expand=True, padx=(0, 6))

        self.btn_set_speakers = ctk.CTkButton(
            btn_box,
            text="4. SYSTEM LAPTOP SPEAKERS (MIRROR)",
            height=36,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#2563EB",
            hover_color="#1D4ED8",
            command=self._switch_audio_to_speakers,
        )
        self.btn_set_speakers.pack(side="left", fill="x", expand=True, padx=(6, 0))

        # Dynamic Detected Windows Playback Devices list
        self.audio_devices_frame = ctk.CTkFrame(card_target, fg_color="#111420", corner_radius=8)
        self.audio_devices_frame.pack(fill="x", padx=16, pady=(0, 14))

        # 2. Capture Mode & Sound Controls Card
        card_tools = ctk.CTkFrame(container, fg_color="#181B29", corner_radius=12)
        card_tools.pack(fill="x", pady=(0, 12), padx=4)

        ctk.CTkLabel(
            card_tools,
            text="CAPTURE SOURCE MODE & PC SOUND MIXER",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#94A3B8",
        ).pack(anchor="w", padx=16, pady=(12, 8))

        mode_row = ctk.CTkFrame(card_tools, fg_color="transparent")
        mode_row.pack(fill="x", padx=16, pady=(0, 10))

        ctk.CTkButton(
            mode_row,
            text="MODE: AUTO FOLLOW WINDOWS",
            height=30,
            font=ctk.CTkFont(size=10, weight="bold"),
            fg_color="#1E293B",
            hover_color="#334155",
            command=lambda: self._set_audio_capture_mode("auto"),
        ).pack(side="left", fill="x", expand=True, padx=(0, 4))

        ctk.CTkButton(
            mode_row,
            text="MODE: LOCK VIRTUAL SPEAKER",
            height=30,
            font=ctk.CTkFont(size=10, weight="bold"),
            fg_color="#1E293B",
            hover_color="#334155",
            command=lambda: self._set_audio_capture_mode("virtual"),
        ).pack(side="left", fill="x", expand=True, padx=4)

        ctk.CTkButton(
            mode_row,
            text="MODE: LOCK SYSTEM SPEAKERS",
            height=30,
            font=ctk.CTkFont(size=10, weight="bold"),
            fg_color="#1E293B",
            hover_color="#334155",
            command=lambda: self._set_audio_capture_mode("speakers"),
        ).pack(side="left", fill="x", expand=True, padx=(4, 0))

        tools_box = ctk.CTkFrame(card_tools, fg_color="transparent")
        tools_box.pack(fill="x", padx=16, pady=(0, 14))

        ctk.CTkButton(
            tools_box,
            text="VOL -",
            width=80,
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#334155",
            hover_color="#475569",
            command=self._pc_vol_down,
        ).pack(side="left", padx=(0, 6))

        ctk.CTkButton(
            tools_box,
            text="MUTE / UNMUTE",
            width=110,
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#334155",
            hover_color="#475569",
            command=self._pc_vol_mute,
        ).pack(side="left", padx=6)

        ctk.CTkButton(
            tools_box,
            text="VOL +",
            width=80,
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#334155",
            hover_color="#475569",
            command=self._pc_vol_up,
        ).pack(side="left", padx=6)

        ctk.CTkButton(
            tools_box,
            text="TEST CHIME (48KHZ)",
            width=140,
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#4F46E5",
            hover_color="#4338CA",
            command=self._play_test_chime,
        ).pack(side="left", padx=6)

        ctk.CTkButton(
            tools_box,
            text="WINDOWS SOUND PANEL",
            width=160,
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#1E293B",
            hover_color="#334155",
            command=self._open_win_sound_settings,
        ).pack(side="right")

        # 3. Stream Telemetry Card
        card_telemetry = ctk.CTkFrame(container, fg_color="#181B29", corner_radius=12)
        card_telemetry.pack(fill="x", pady=(0, 12), padx=4)

        ctk.CTkLabel(
            card_telemetry,
            text="LIVE AUDIO TELEMETRY & ENDPOINT STATS",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#94A3B8",
        ).pack(anchor="w", padx=16, pady=(12, 6))

        self.telemetry_lbl = ctk.CTkLabel(
            card_telemetry,
            text="Format: 48,000 Hz Stereo PCM (16-bit) · Latency: ~10ms · Port: 8891\nCapture: Connecting to KernalLink Server...",
            font=ctk.CTkFont(size=11),
            text_color="#94A3B8",
            justify="left",
        )
        self.telemetry_lbl.pack(anchor="w", padx=16, pady=(0, 14))

    # -------------------------------------------------------------
    # TAB 2: DUAL MONITOR & SPACEDESK CONSOLE
    # -------------------------------------------------------------
    def _build_monitor_tab(self):
        container = ctk.CTkScrollableFrame(self.tab_mon, fg_color="transparent")
        container.pack(fill="both", expand=True, padx=10, pady=10)

        # 0. Hero Card: Phone as External Monitor & Auto-Detection
        hero_card = ctk.CTkFrame(container, fg_color="#182038", corner_radius=12, border_width=1, border_color="#3B82F6")
        hero_card.pack(fill="x", pady=(0, 12), padx=4)

        hero_top = ctk.CTkFrame(hero_card, fg_color="transparent")
        hero_top.pack(fill="x", padx=16, pady=(14, 6))

        ctk.CTkLabel(
            hero_top,
            text="PHONE AS WINDOWS EXTERNAL MONITOR (DISPLAY 2)",
            font=ctk.CTkFont(size=13, weight="bold"),
            text_color="#60A5FA",
        ).pack(side="left")

        self.switch_auto_monitor = ctk.CTkSwitch(
            hero_top,
            text="Auto-Detect & Extend on Phone Connect",
            variable=self.auto_monitor_var,
            font=ctk.CTkFont(size=11, weight="bold"),
            progress_color="#10B981",
        )
        self.switch_auto_monitor.pack(side="right")

        self.hero_desc = ctk.CTkLabel(
            hero_card,
            text="When enabled, Windows will automatically detect your phone as a genuine external monitor and extend your desktop.\nDrag windows, games, and apps to your phone screen with 60/120Hz high-FPS touch controls!",
            font=ctk.CTkFont(size=11),
            text_color="#CBD5E1",
            justify="left",
            wraplength=840,
        )
        self.hero_desc.pack(anchor="w", padx=16, pady=(0, 10))

        hero_btns = ctk.CTkFrame(hero_card, fg_color="transparent")
        hero_btns.pack(fill="x", padx=16, pady=(0, 14))

        self.btn_hero_activate = ctk.CTkButton(
            hero_btns,
            text="ACTIVATE VIRTUAL MONITOR (DISPLAY 2)",
            height=34,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#10B981",
            hover_color="#059669",
            command=self._install_vdd,
        )
        self.btn_hero_activate.pack(side="left", padx=(0, 8))

        ctk.CTkButton(
            hero_btns,
            text="EXTEND DISPLAYS (Win+P)",
            height=34,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#2563EB",
            hover_color="#1D4ED8",
            command=lambda: self._set_display_mode("extend"),
        ).pack(side="left", padx=8)

        ctk.CTkButton(
            hero_btns,
            text="OPEN DISPLAY SETTINGS",
            height=34,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#6366F1",
            hover_color="#4F46E5",
            command=self._open_win_display_settings,
        ).pack(side="left", padx=(8, 0))

        # 1. Detected Monitors Card
        card_mon = ctk.CTkFrame(container, fg_color="#181B29", corner_radius=12)
        card_mon.pack(fill="x", pady=(0, 12), padx=4)

        m_head = ctk.CTkFrame(card_mon, fg_color="transparent")
        m_head.pack(fill="x", padx=16, pady=(12, 6))

        ctk.CTkLabel(
            m_head,
            text="DETECTED WINDOWS DISPLAYS",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#60A5FA",
        ).pack(side="left")

        self.mon_count_lbl = ctk.CTkLabel(
            m_head,
            text="Scanning displays...",
            font=ctk.CTkFont(size=11, weight="bold"),
            text_color="#FBBF24",
        )
        self.mon_count_lbl.pack(side="right")

        self.mon_list_frame = ctk.CTkFrame(card_mon, fg_color="transparent")
        self.mon_list_frame.pack(fill="x", padx=16, pady=(0, 14))

        # 2. Windows Display Projection Controls (Win + P)
        card_proj = ctk.CTkFrame(container, fg_color="#181B29", corner_radius=12)
        card_proj.pack(fill="x", pady=6, padx=4)

        ctk.CTkLabel(
            card_proj,
            text="WINDOWS DISPLAY PROJECTION MODES (WIN + P)",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#60A5FA",
        ).pack(anchor="w", padx=16, pady=(12, 6))

        proj_row = ctk.CTkFrame(card_proj, fg_color="transparent")
        proj_row.pack(fill="x", padx=16, pady=(0, 14))

        ctk.CTkButton(
            proj_row,
            text="EXTEND DISPLAYS (Win+P)",
            height=34,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#1D4ED8",
            hover_color="#1E40AF",
            command=lambda: self._set_display_mode("extend"),
        ).pack(side="left", fill="x", expand=True, padx=(0, 6))

        ctk.CTkButton(
            proj_row,
            text="DUPLICATE / CLONE",
            height=34,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#047857",
            hover_color="#065F46",
            command=lambda: self._set_display_mode("clone"),
        ).pack(side="left", fill="x", expand=True, padx=6)

        ctk.CTkButton(
            proj_row,
            text="WIN DISPLAY SETTINGS",
            height=34,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#7C3AED",
            hover_color="#6D28D9",
            command=self._open_win_display_settings,
        ).pack(side="left", fill="x", expand=True, padx=(6, 0))

        # 3. Virtual Display Driver (Native Windows IDD - 60/120 FPS)
        card_vdd = ctk.CTkFrame(container, fg_color="#181B29", corner_radius=12)
        card_vdd.pack(fill="x", pady=6, padx=4)

        ctk.CTkLabel(
            card_vdd,
            text="VIRTUAL DISPLAY DRIVER (NATIVE WINDOWS IDD · 60/120 FPS)",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#34D399",
        ).pack(anchor="w", padx=16, pady=(12, 4))

        self.vdd_status_lbl = ctk.CTkLabel(
            card_vdd,
            text="Checking Virtual Display Driver status...",
            font=ctk.CTkFont(size=11),
            text_color="#CBD5E1",
        )
        self.vdd_status_lbl.pack(anchor="w", padx=16, pady=(0, 10))

        vdd_btns = ctk.CTkFrame(card_vdd, fg_color="transparent")
        vdd_btns.pack(fill="x", padx=16, pady=(0, 14))

        self.btn_vdd_install = ctk.CTkButton(
            vdd_btns,
            text="INSTALL VIRTUAL MONITOR (1-CLICK ADMIN)",
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#059669",
            hover_color="#047857",
            command=self._install_vdd,
        )
        self.btn_vdd_install.pack(side="left", padx=(0, 8))

        self.btn_vdd_remove = ctk.CTkButton(
            vdd_btns,
            text="REMOVE VIRTUAL MONITOR",
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#B91C1C",
            hover_color="#991B1B",
            command=self._remove_vdd,
        )
        self.btn_vdd_remove.pack(side="left", padx=8)

        self.btn_vdd_cfg = ctk.CTkButton(
            vdd_btns,
            text="OPEN VDD CONFIG",
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#4F46E5",
            hover_color="#4338CA",
            command=self._open_vdd_xml,
        )
        self.btn_vdd_cfg.pack(side="left", padx=(8, 0))

        # 4. Spacedesk Driver Service Manager
        card_sd = ctk.CTkFrame(container, fg_color="#181B29", corner_radius=12)
        card_sd.pack(fill="x", pady=6, padx=4)

        ctk.CTkLabel(
            card_sd,
            text="SPACEDESK DRIVER SERVICE INTEGRATION",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#60A5FA",
        ).pack(anchor="w", padx=16, pady=(12, 4))

        self.sd_status_lbl = ctk.CTkLabel(
            card_sd,
            text="Checking Spacedesk service...",
            font=ctk.CTkFont(size=11),
            text_color="#CBD5E1",
        )
        self.sd_status_lbl.pack(anchor="w", padx=16, pady=(0, 10))

        sd_btns = ctk.CTkFrame(card_sd, fg_color="transparent")
        sd_btns.pack(fill="x", padx=16, pady=(0, 14))

        self.btn_sd_start = ctk.CTkButton(
            sd_btns,
            text="START SPACEDESK SERVICE",
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#059669",
            hover_color="#047857",
            command=lambda: self._control_spacedesk("start"),
        )
        self.btn_sd_start.pack(side="left", padx=(0, 8))

        self.btn_sd_stop = ctk.CTkButton(
            sd_btns,
            text="STOP SERVICE",
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#B91C1C",
            hover_color="#991B1B",
            command=lambda: self._control_spacedesk("stop"),
        )
        self.btn_sd_stop.pack(side="left", padx=8)

        self.btn_sd_console = ctk.CTkButton(
            sd_btns,
            text="OPEN SPACEDESK CONSOLE",
            height=32,
            font=ctk.CTkFont(size=11, weight="bold"),
            fg_color="#D97706",
            hover_color="#B45309",
            command=lambda: self._control_spacedesk("launch_console"),
        )
        self.btn_sd_console.pack(side="left", padx=(8, 0))

    # -------------------------------------------------------------
    # TAB 3: PERFORMANCE & STREAM SETTINGS
    # -------------------------------------------------------------
    def _build_performance_tab(self):
        container = ctk.CTkScrollableFrame(self.tab_perf, fg_color="transparent")
        container.pack(fill="both", expand=True, padx=10, pady=10)

        card_perf = ctk.CTkFrame(container, fg_color="#181B29", corner_radius=12)
        card_perf.pack(fill="x", pady=6, padx=4)

        ctk.CTkLabel(
            card_perf,
            text="ZERO-COPY SCREEN CAPTURE ENGINE STATS",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#60A5FA",
        ).pack(anchor="w", padx=16, pady=(12, 6))

        info_text = (
            "• Engine: Direct DIB Section Zero-Copy + Hardware GDI StretchBlt\n"
            "• Average Capture & Encode Latency: ~8ms (< 120 FPS capable)\n"
            "• Bandwidth: Real-time OpenCV SIMD compression with adaptive JPEG quality\n"
            "• Input Forwarding: Windows SendInput Win32 driver-level simulation\n"
            "• Gamepad Subsystem: ViGEmBus Virtual Xbox 360 controller emulation"
        )
        ctk.CTkLabel(
            card_perf,
            text=info_text,
            font=ctk.CTkFont(family="Consolas", size=10),
            text_color="#CBD5E1",
            justify="left",
        ).pack(anchor="w", padx=16, pady=(0, 14))

        # ViGEm Controller Card
        card_vigem = ctk.CTkFrame(container, fg_color="#181B29", corner_radius=12)
        card_vigem.pack(fill="x", pady=6, padx=4)

        ctk.CTkLabel(
            card_vigem,
            text="VIRTUAL GAMEPAD SUBSYSTEM (VIGEMBUS)",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#60A5FA",
        ).pack(anchor="w", padx=16, pady=(12, 6))

        self.vigem_status_lbl = ctk.CTkLabel(
            card_vigem,
            text="Checking ViGEmBus driver...",
            font=ctk.CTkFont(size=11),
            text_color="#CBD5E1",
        )
        self.vigem_status_lbl.pack(anchor="w", padx=16, pady=(0, 14))

    # -------------------------------------------------------------
    # TAB 4: DIAGNOSTICS & HELP
    # -------------------------------------------------------------
    def _build_help_tab(self):
        container = ctk.CTkScrollableFrame(self.tab_help, fg_color="transparent")
        container.pack(fill="both", expand=True, padx=10, pady=10)

        card_faq = ctk.CTkFrame(container, fg_color="#181B29", corner_radius=12)
        card_faq.pack(fill="x", pady=6, padx=4)

        ctk.CTkLabel(
            card_faq,
            text="FREQUENTLY ASKED QUESTIONS & TROUBLESHOOTING",
            font=ctk.CTkFont(size=12, weight="bold"),
            text_color="#60A5FA",
        ).pack(anchor="w", padx=16, pady=(12, 8))

        faq_content = (
            "Q: Why does Win + P only mirror instead of extending?\n"
            "A: In Windows 10 & 11, 'Extend' requires at least TWO detected display monitors.\n"
            "   If your laptop only has its 1 built-in screen, Windows has no 2nd screen to extend onto,\n"
            "   so it automatically reverts to Mirroring. To enable Extend mode, connect your phone\n"
            "   via Spacedesk Viewer once to create Display 2, or install a Virtual Display Driver!\n\n"
            "Q: Why was the stream feeling laggy and how was it fixed?\n"
            "A: Standard screen capture (BitBlt + CPU resize) took ~58ms per frame (~17 FPS).\n"
            "   We upgraded the capture engine to Zero-Copy Direct DIB Sections + Hardware StretchBlt,\n"
            "   which drops frame capture and encoding to under 8ms (120+ FPS capability)!\n\n"
            "Q: How do I get absolute zero-lag connectivity?\n"
            "A: Connect your phone to your PC via a USB cable, tap 'CONNECT VIA USB (ADB REVERSE)',\n"
            "   and on your phone choose 'USB Cable (127.0.0.1:8889)'. USB gives 0.5ms latency!"
        )
        ctk.CTkLabel(
            card_faq,
            text=faq_content,
            font=ctk.CTkFont(size=11),
            text_color="#E2E8F0",
            justify="left",
            wraplength=840,
        ).pack(anchor="w", padx=16, pady=(0, 16))

    def _build_status_bar(self):
        status_bar = ctk.CTkFrame(self, height=28, fg_color="#0A0B10", corner_radius=0)
        status_bar.pack(fill="x", side="bottom")
        status_bar.pack_propagate(False)

        self.lbl_footer = ctk.CTkLabel(
            status_bar,
            text="KernalLink PC Control Panel Ready · Ports 8889 / 8890 / 8891",
            font=ctk.CTkFont(size=10),
            text_color="#64748B",
        )
        self.lbl_footer.pack(side="left", padx=16)

    # -------------------------------------------------------------
    # WEBSOCKET BRIDGE TO RUNNING KERNALLINK MASTER SERVER
    # -------------------------------------------------------------
    def _start_ws_bridge_thread(self):
        if not HAS_WEBSOCKETS:
            return
        loop = asyncio.new_event_loop()
        self._ws_loop = loop
        asyncio.set_event_loop(loop)
        loop.run_until_complete(self._ws_panel_loop())

    async def _ws_panel_loop(self):
        while not self._closing:
            try:
                async with websockets.connect("ws://127.0.0.1:8889/panel") as ws:
                    self._ws_conn = ws
                    await ws.send(json.dumps({"type": "get_server_status"}))
                    async for raw in ws:
                        if self._closing:
                            break
                        try:
                            msg = json.loads(raw)
                            mtype = msg.get("type")
                            if mtype == "server_status":
                                self._live_server_status = msg
                                if isinstance(msg.get("audio"), dict):
                                    self._live_audio_status = msg["audio"]
                                self.after(0, self._update_audio_status)
                            elif mtype == "audio_status":
                                self._live_audio_status = msg
                                self.after(0, self._update_audio_status)
                        except Exception:
                            pass
            except Exception:
                self._ws_conn = None
                await asyncio.sleep(1.5)

    def _send_ws_cmd(self, payload: dict):
        if self._ws_loop and self._ws_conn and HAS_WEBSOCKETS:
            try:
                asyncio.run_coroutine_threadsafe(
                    self._ws_conn.send(json.dumps(payload)),
                    self._ws_loop,
                )
                return True
            except Exception:
                pass
        return False

    # -------------------------------------------------------------
    # BACKGROUND POLLING & LOGIC
    # -------------------------------------------------------------
    def _periodic_status_refresh(self):
        """Polls server port, network interfaces, and monitors every 2 seconds."""
        if self._closing:
            return
        port_open = is_port_in_use(8889)

        if port_open:
            self.status_badge.configure(
                text="SERVER ONLINE (8889)",
                fg_color="#065F46",
                text_color="#6EE7B7",
            )
            self._send_ws_cmd({"type": "get_server_status"})
        else:
            self.status_badge.configure(
                text="SERVER OFFLINE",
                fg_color="#7F1D1D",
                text_color="#FCA5A5",
            )

        # Refresh local IPs
        ips = get_local_ip_addresses()
        self.wifi_ip_label.configure(
            text="Active IPs: " + ", ".join(f"{ip}:8889" for ip in ips[:3])
        )

        # Refresh monitors
        if HAS_STREAMER:
            monitors = screen_streamer.get_all_monitors()
            count = len(monitors)
            if count <= 1:
                self.mon_count_lbl.configure(
                    text="1 Display (Mirroring Mode - Single Monitor)",
                    text_color="#F59E0B",
                )
            else:
                self.mon_count_lbl.configure(
                    text=f"{count} Displays (Extended Dual Screen Ready)",
                    text_color="#10B981",
                )

            # Update visual display tiles if changed
            if count != self._last_mon_count:
                self._last_mon_count = count
                self._update_monitor_tiles(monitors)

            # Update Virtual Display Driver status
            vdd = screen_streamer.check_virtual_display_status()
            if vdd.get("enabled"):
                self.vdd_status_lbl.configure(
                    text="Virtual Display (Root\\MttVDD): ACTIVE (Native Windows Monitor Ready @ 60-120Hz)",
                    text_color="#34D399",
                )
                self.btn_hero_activate.configure(
                    text="VIRTUAL MONITOR ACTIVE (DISPLAY 2 READY)",
                    fg_color="#059669",
                )
            elif vdd.get("installed"):
                self.vdd_status_lbl.configure(
                    text="Virtual Display (Root\\MttVDD): INSTALLED but DISABLED (Click 'INSTALL' to activate)",
                    text_color="#FBBF24",
                )
            else:
                self.vdd_status_lbl.configure(
                    text="Virtual Display Driver: NOT INSTALLED (Click 'INSTALL' below for 1-Click Setup)",
                    text_color="#94A3B8",
                )

            # Update Spacedesk status
            sd = screen_streamer.get_spacedesk_status()
            if sd.get("running"):
                self.sd_status_lbl.configure(
                    text="Spacedesk Service: ACTIVE (Port 28252 Listening · Virtual Display Driver Ready)",
                    text_color="#34D399",
                )
            elif sd.get("installed"):
                self.sd_status_lbl.configure(
                    text="Spacedesk Service: STOPPED (Click 'START SPACEDESK SERVICE' to enable virtual display)",
                    text_color="#F87171",
                )
            else:
                self.sd_status_lbl.configure(
                    text="Spacedesk Driver: NOT INSTALLED",
                    text_color="#94A3B8",
                )

        # Check USB phone status via ADB
        usb_detected = False
        if self.adb_path:
            try:
                flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
                res = subprocess.run([self.adb_path, "devices"], capture_output=True, text=True, timeout=2, creationflags=flags)
                lines = [l.strip() for l in res.stdout.strip().splitlines() if l.strip()]
                devs = [l.split()[0] for l in lines[1:] if "\tdevice" in l or " device" in l]
                if devs:
                    usb_detected = True
                    self.usb_badge.configure(
                        text=f"USB: {devs[0]}",
                        fg_color="#065F46",
                        text_color="#6EE7B7",
                    )
                    # If auto-monitor enabled and newly connected
                    if self.auto_monitor_var.get() and not self._last_usb_connected:
                        subprocess.run([self.adb_path, "reverse", "tcp:8889", "tcp:8889"], capture_output=True, timeout=2, creationflags=flags)
                        subprocess.run([self.adb_path, "reverse", "tcp:8891", "tcp:8891"], capture_output=True, timeout=2, creationflags=flags)
                        self.log_textbox.insert("end", f"[OK] USB Phone '{devs[0]}' connected! Reversed ports 8889 & 8891.\n")
                        if HAS_STREAMER:
                            screen_streamer.switch_display_mode("extend")
                            self.log_textbox.insert("end", "[*] Auto-extended Windows desktop to Phone Monitor (Display 2).\n")
                else:
                    self.usb_badge.configure(
                        text="USB: STANDBY",
                        fg_color="#1E293B",
                        text_color="#94A3B8",
                    )
            except Exception:
                pass
        self._last_usb_connected = usb_detected

        # Refresh Audio Relay Status
        self._update_audio_status()

        # Schedule next refresh
        self.after(2000, self._periodic_status_refresh)

    def _start_audio_stream(self):
        if self._send_ws_cmd({"type": "audio_relay_control", "action": "start"}):
            self.log_textbox.insert("end", "[OK] Requested Master Server to START Audio Stream (Port 8891).\n")
        elif HAS_AUDIO:
            audio_streamer.get_audio_relay().start()
            self._update_audio_status()

    def _stop_audio_stream(self):
        if self._send_ws_cmd({"type": "audio_relay_control", "action": "stop"}):
            self.log_textbox.insert("end", "[*] Requested Master Server to STOP Audio Stream.\n")
        elif HAS_AUDIO:
            audio_streamer.get_audio_relay().stop()
            self._update_audio_status()

    def _stop_screen_stream(self):
        if self._send_ws_cmd({"type": "screen_stop_all"}):
            self.log_textbox.insert("end", "[*] Stopped all active phone screen/monitor streams.\n")
        else:
            self.log_textbox.insert("end", "[!] Start KernalLink Server first to control active screen streams.\n")

    def _set_audio_capture_mode(self, mode: str):
        if self._send_ws_cmd({"type": "audio_relay_control", "action": "set_mode", "mode": mode}):
            self.log_textbox.insert("end", f"[*] Set Audio Capture Source Mode to: {mode.upper()}\n")

    def _open_win_audio_flyout(self):
        if HAS_AUDIO:
            audio_streamer.open_windows_audio_flyout()
        else:
            self._send_ws_cmd({"type": "audio_relay_control", "action": "open_win_flyout"})
        self.log_textbox.insert("end", "[*] Opened Windows Audio Output Switcher (Win+Ctrl+V).\n")

    def _switch_audio_to_virtual(self):
        if not self._send_ws_cmd({"type": "switch_audio_device", "target": "virtual"}) and HAS_AUDIO:
            audio_streamer.set_windows_playback_device("virtual")
            self._update_audio_status()
        self.log_textbox.insert("end", "[*] Switched Windows Output -> KernalLink Virtual Speaker (Phone Only).\n")

    def _switch_audio_to_speakers(self):
        if not self._send_ws_cmd({"type": "switch_audio_device", "target": "speakers"}) and HAS_AUDIO:
            audio_streamer.set_windows_playback_device("speakers")
            self._update_audio_status()
        self.log_textbox.insert("end", "[*] Switched Windows Output -> Laptop System Speakers (Mirror).\n")

    def _switch_specific_audio_device(self, dev_name: str):
        if not self._send_ws_cmd({"type": "switch_audio_device", "target": dev_name}) and HAS_AUDIO:
            audio_streamer.set_windows_playback_device(dev_name)
            self._update_audio_status()
        self.log_textbox.insert("end", f"[*] Switched Windows Output -> {dev_name}\n")

    def _pc_vol_up(self):
        if not self._send_ws_cmd({"type": "audio_relay_control", "action": "vol_up"}):
            nircmd = Path(__file__).parent / "tools" / "nircmdc.exe"
            if nircmd.exists():
                subprocess.run([str(nircmd), "changesysvolume", "3000"], capture_output=True)

    def _pc_vol_down(self):
        if not self._send_ws_cmd({"type": "audio_relay_control", "action": "vol_down"}):
            nircmd = Path(__file__).parent / "tools" / "nircmdc.exe"
            if nircmd.exists():
                subprocess.run([str(nircmd), "changesysvolume", "-3000"], capture_output=True)

    def _pc_vol_mute(self):
        if not self._send_ws_cmd({"type": "audio_relay_control", "action": "mute"}):
            nircmd = Path(__file__).parent / "tools" / "nircmdc.exe"
            if nircmd.exists():
                subprocess.run([str(nircmd), "mutesysvolume", "2"], capture_output=True)

    def _open_win_sound_settings(self):
        try:
            subprocess.Popen(["start", "ms-settings:sound"], shell=True)
        except Exception:
            subprocess.Popen(["control", "mmsys.cpl", "sounds"], shell=True)

    def _play_test_chime(self):
        if self._send_ws_cmd({"type": "audio_relay_control", "action": "test_chime"}):
            self.log_textbox.insert("end", "[*] Played 48kHz test chime through active Windows output device.\n")
            return
        if HAS_AUDIO:
            audio_streamer.play_test_chime_async()
            self.log_textbox.insert("end", "[*] Played local 48kHz test chime.\n")

    def _render_audio_device_chips(self, devices: list):
        if not hasattr(self, "audio_devices_frame"):
            return
        sig = tuple((d.get("name", ""), bool(d.get("is_default", False))) for d in devices)
        if getattr(self, "_last_audio_sig", None) == sig:
            return
        self._last_audio_sig = sig

        for child in self.audio_devices_frame.winfo_children():
            child.destroy()

        if not devices:
            ctk.CTkLabel(
                self.audio_devices_frame,
                text="No active Windows playback endpoints detected.",
                font=ctk.CTkFont(size=10),
                text_color="#94A3B8",
            ).pack(anchor="w", padx=12, pady=8)
            return

        ctk.CTkLabel(
            self.audio_devices_frame,
            text="ALL WINDOWS PLAYBACK DEVICES (CLICK TO ROUTE):",
            font=ctk.CTkFont(size=10, weight="bold"),
            text_color="#64748B",
        ).pack(anchor="w", padx=12, pady=(8, 4))

        for d in devices:
            name = d.get("name", "Unknown")
            is_def = d.get("is_default", False)
            is_virt = d.get("is_virtual", False)
            rate = d.get("sample_rate", 48000)
            tag = "ACTIVE DEFAULT" if is_def else ("VIRTUAL" if is_virt else f"{rate}Hz")
            btn = ctk.CTkButton(
                self.audio_devices_frame,
                text=f"{name}   [{tag}]",
                height=28,
                anchor="w",
                font=ctk.CTkFont(size=11, weight="bold" if is_def else "normal"),
                fg_color="#065F46" if is_def else "#1E2235",
                hover_color="#047857" if is_def else "#2D334D",
                text_color="#FFFFFF" if is_def else "#CBD5E1",
                command=lambda n=name: self._switch_specific_audio_device(n),
            )
            btn.pack(fill="x", padx=10, pady=(0, 6))

    def _update_audio_status(self):
        try:
            # Prefer real live state from Master Server over WS, fallback to local device query
            live = self._live_audio_status
            if live and isinstance(live.get("relay"), dict):
                is_virt = live.get("is_virtual_default", False)
                dev = live.get("default_device", "Unknown")
                st = live.get("relay", {})
                devices = live.get("devices", [])
            elif HAS_AUDIO:
                info = audio_streamer.get_audio_devices_info()
                is_virt = info.get("is_virtual_default", False)
                dev = info.get("default_device", "Unknown")
                devices = info.get("devices", [])
                st = {"running": is_port_in_use(8891), "clients": 0, "bytes_streamed": 0, "device": "Server Offline" if not is_port_in_use(8889) else "Connecting...", "mode": "auto"}
            else:
                return

            relay_running = bool(st.get("running", False))
            self._render_audio_device_chips(devices)

            if hasattr(self, "lbl_dash_stream_pill"):
                self.lbl_dash_stream_pill.configure(
                    text="AUDIO STREAM: ACTIVE (8891)" if relay_running else "AUDIO STREAM: STOPPED",
                    text_color="#10B981" if relay_running else "#F87171",
                )

            if hasattr(self, "audio_status_pill"):
                self.audio_status_pill.configure(
                    text="PORT 8891 · STREAMING ACTIVE" if relay_running else "PORT 8891 · STOPPED",
                    text_color="#10B981" if relay_running else "#F87171",
                )

            if hasattr(self, "lbl_audio_dev"):
                if is_virt:
                    self.lbl_audio_dev.configure(
                        text=f"Active Output: {dev}  [ROUTING SOUND TO PHONE ONLY]",
                        text_color="#34D399",
                    )
                else:
                    self.lbl_audio_dev.configure(
                        text=f"Active Output: {dev}  [PLAYING ON SYSTEM SPEAKERS]",
                        text_color="#CBD5E1",
                    )

            if hasattr(self, "lbl_tab_audio_dev"):
                if is_virt:
                    self.lbl_tab_audio_dev.configure(
                        text=f"Active Output: {dev}  (PHONE EXCLUSIVE)",
                        text_color="#34D399",
                    )
                else:
                    self.lbl_tab_audio_dev.configure(
                        text=f"Active Output: {dev}  (LAPTOP MIRROR)",
                        text_color="#60A5FA",
                    )

            if hasattr(self, "telemetry_lbl"):
                mb = st.get("bytes_streamed", 0) / (1024 * 1024)
                clients = st.get("clients", 0)
                cur_dev = st.get("device") or "Standby"
                mode_str = str(st.get("mode", "auto")).upper()
                scr_cnt = self._live_server_status.get("screen_sessions", 0)
                ph_cnt = self._live_server_status.get("clients", 0)
                self.telemetry_lbl.configure(
                    text=(
                        f"Audio Relay: {'RUNNING' if relay_running else 'STOPPED'}  ·  Mode: {mode_str}  ·  Format: 48,000 Hz Stereo PCM (16-bit)\n"
                        f"Capture Device: {cur_dev}\n"
                        f"Phone Audio Clients: {clients}  ·  Connected Phones: {ph_cnt}  ·  Screen Streams: {scr_cnt}  ·  Streamed: {mb:.2f} MB"
                    )
                )
        except Exception:
            pass

    def _update_monitor_tiles(self, monitors):
        """Renders live visual display cards for every display detected by Windows."""
        for w in self.mon_list_frame.winfo_children():
            w.destroy()
        if not monitors:
            ctk.CTkLabel(
                self.mon_list_frame,
                text="No displays detected by Windows.",
                font=ctk.CTkFont(size=11),
                text_color="#94A3B8",
            ).pack(anchor="w", pady=4)
            return

        for m in monitors:
            idx = m.get("index", 0)
            is_prim = m.get("primary", False)
            w = m.get("width", 0)
            h = m.get("height", 0)
            name = m.get("name", f"Display {idx+1}")
            dev = m.get("device", "")

            color = "#1E2433" if is_prim else "#1A2E3B"
            card = ctk.CTkFrame(self.mon_list_frame, fg_color=color, corner_radius=8, border_width=1, border_color="#334155")
            card.pack(fill="x", pady=4)

            top = ctk.CTkFrame(card, fg_color="transparent")
            top.pack(fill="x", padx=12, pady=(8, 2))

            tag = "PRIMARY SCREEN (PC)" if is_prim else "EXTENDED SCREEN (PHONE / VDD)"
            tag_color = "#38BDF8" if is_prim else "#34D399"

            ctk.CTkLabel(
                top,
                text=f"DISPLAY {idx+1}: {name}",
                font=ctk.CTkFont(size=12, weight="bold"),
                text_color="#F8FAFC",
            ).pack(side="left")

            ctk.CTkLabel(
                top,
                text=tag,
                font=ctk.CTkFont(size=10, weight="bold"),
                text_color=tag_color,
            ).pack(side="right")

            info = f"Resolution: {w} × {h} px  ·  Device: {dev}  ·  Bounds: ({m.get('left',0)}, {m.get('top',0)})"
            ctk.CTkLabel(
                card,
                text=info,
                font=ctk.CTkFont(size=10),
                text_color="#94A3B8",
            ).pack(anchor="w", padx=12, pady=(0, 8))

    def _restart_server(self):
        """Cleanly restarts any running KernalLink server instance and spawns server.py / KernalLink.exe."""
        self.log_textbox.insert("end", "[*] Restarting KernalLink Master Server...\n")
        self._send_ws_cmd({"type": "restart_server"})
        time.sleep(0.3)

        my_pid = str(os.getpid())
        try:
            flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
            for p_num in ("8889", "8890", "8891"):
                res = subprocess.run(f"netstat -aon | findstr :{p_num}", shell=True, capture_output=True, text=True, creationflags=flags)
                for ln in res.stdout.splitlines():
                    parts = ln.strip().split()
                    if len(parts) >= 5 and parts[-1].isdigit() and parts[-1] != my_pid:
                        subprocess.run(["taskkill", "/f", "/pid", parts[-1]], capture_output=True, creationflags=flags)
            subprocess.run(["taskkill", "/f", "/im", "TouchPCServer.exe"], capture_output=True, creationflags=flags)
        except Exception:
            pass

        server_dir = Path(__file__).parent.resolve()
        server_script = server_dir / "server.py"

        if getattr(sys, "frozen", False):
            # If launched from inside KernalLink.exe --panel, run KernalLink.exe (without --panel)
            exe_path = Path(sys.executable)
            if "kernallink.exe" in exe_path.name.lower() and "--panel" in sys.argv:
                cmd = [str(exe_path)]
            else:
                candidate_exes = [
                    exe_path.parent / "KernalLink.exe",
                    exe_path.parent.parent / "KernalLink.exe",
                    server_dir / "dist" / "KernalLink.exe",
                ]
                server_bin = next((str(c.resolve()) for c in candidate_exes if c.exists()), None)
                if server_bin:
                    cmd = [server_bin]
                else:
                    py = shutil.which("python") or r"C:\Users\user\AppData\Local\Programs\Python\Python314\python.exe"
                    cmd = [py, str(server_script)]
        else:
            py = sys.executable or "python"
            cmd = [py, str(server_script)]

        try:
            flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
            self.server_process = subprocess.Popen(
                cmd,
                cwd=str(server_dir),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
                creationflags=flags,
            )
            threading.Thread(target=self._read_server_stdout, daemon=True).start()
            self.log_textbox.insert("end", f"[+] KernalLink Server launched: {' '.join(cmd)}\n")
        except Exception as e:
            self.log_textbox.insert("end", f"[!] Error starting server: {e}\n")

    def _read_server_stdout(self):
        """Streams server stdout lines directly into the GUI log window."""
        if not self.server_process:
            return
        for line in self.server_process.stdout:
            if self._closing:
                break
            self.after(0, lambda l=line: self._append_log(l))

    def _append_log(self, text: str):
        self.log_textbox.insert("end", text)
        self.log_textbox.see("end")

    def _clear_logs(self):
        self.log_textbox.delete("1.0", "end")

    def _run_adb_reverse(self):
        """Runs adb reverse tcp:8889 and tcp:8891 for USB cable + audio mode."""
        if not self.adb_path:
            messagebox.showerror(
                "ADB Not Found",
                "Android Debug Bridge (adb.exe) was not found.\n\n"
                "Please make sure Android SDK platform-tools are installed or adb is in PATH.",
            )
            return

        try:
            res = subprocess.run([self.adb_path, "devices"], capture_output=True, text=True, timeout=3)
            lines = res.stdout.strip().split("\n")[1:]
            devices = [l.split()[0] for l in lines if "\tdevice" in l]

            if not devices:
                messagebox.showwarning(
                    "No Device Detected",
                    "No USB Android device detected with USB Debugging enabled.\n\n"
                    "1. Connect phone via USB cable.\n"
                    "2. Enable USB Debugging in Developer Options.\n"
                    "3. Tap 'Allow USB Debugging' on phone screen.",
                )
                return

            res_rev = subprocess.run(
                [self.adb_path, "reverse", "tcp:8889", "tcp:8889"],
                capture_output=True,
                text=True,
                timeout=3,
            )
            subprocess.run(
                [self.adb_path, "reverse", "tcp:8891", "tcp:8891"],
                capture_output=True,
                text=True,
                timeout=3,
            )
            if res_rev.returncode == 0:
                self.log_textbox.insert("end", f"[OK] ADB Ports 8889 & 8891 reversed over USB to {devices[0]}!\n")
                messagebox.showinfo(
                    "USB Mode Connected!",
                    f"Ports 8889 (Control) & 8891 (Audio) forwarded to {devices[0]} over USB!\n\n"
                    "On your phone app, tap:\n'USB Cable (ADB Reverse)' (127.0.0.1:8889) for 0.5ms latency!",
                )
            else:
                self.log_textbox.insert("end", f"[!] ADB reverse error: {res_rev.stderr}\n")
        except Exception as e:
            self.log_textbox.insert("end", f"[!] ADB command failed: {e}\n")

    def _copy_primary_ip(self):
        ips = get_local_ip_addresses()
        primary = f"{ips[0]}:8889" if ips else "127.0.0.1:8889"
        self.clipboard_clear()
        self.clipboard_append(primary)
        messagebox.showinfo("IP Copied", f"Server IP '{primary}' copied to clipboard!")

    def _set_display_mode(self, mode: str):
        if HAS_STREAMER:
            screen_streamer.switch_display_mode(mode)
            self.log_textbox.insert("end", f"[*] Switched Windows display mode: /{mode}\n")

    def _open_win_display_settings(self):
        if HAS_STREAMER:
            screen_streamer.open_display_settings()

    def _control_spacedesk(self, action: str):
        if not HAS_STREAMER:
            return
        if action in ("start", "stop"):
            screen_streamer.toggle_spacedesk_service(action)
            self.log_textbox.insert("end", f"[*] Spacedesk service '{action}' requested.\n")
        elif action == "launch_console":
            screen_streamer.launch_spacedesk_console()
    def _install_vdd(self):
        if HAS_STREAMER:
            self.log_textbox.insert("end", "[*] Launching Administrator Virtual Display Driver installer...\n")
            screen_streamer.launch_virtual_display_installer()

    def _remove_vdd(self):
        if HAS_STREAMER:
            self.log_textbox.insert("end", "[*] Launching Administrator Virtual Display Driver uninstaller...\n")
            screen_streamer.launch_virtual_display_uninstaller()

    def _open_vdd_xml(self):
        cfg = r"C:\VirtualDisplayDriver\vdd_settings.xml"
        if os.path.exists(cfg):
            try:
                os.startfile(cfg)
            except Exception as e:
                self.log_textbox.insert("end", f"[!] Error opening config: {e}\n")
        else:
            local_cfg = Path(__file__).parent / "driver" / "vdd" / "VirtualDisplayDriver" / "vdd_settings.xml"
            if local_cfg.exists():
                try:
                    os.startfile(str(local_cfg))
                except Exception as e:
                    self.log_textbox.insert("end", f"[!] Error opening config: {e}\n")


def main():
    app = TouchPCConsole()
    app.mainloop()


if __name__ == "__main__":
    main()
