# KernalLink — PC Controller & Ultra-Low Latency Display Hub

A high-performance, low-latency mobile gamepad, trackpad mouse, keyboard, and virtual extended display system for Windows PC, featuring a **Flutter Android App** and a **Native Windows PC Server**.

Re-engineered for ultra-low input lag (<0.5ms over USB cable), native Xbox 360 controller emulation via the **ViGEmBus** driver, hardware-accelerated screen streaming via SIMD libjpeg-turbo (`simplejpeg`), and automatic virtual display lifecycle management.

---

## Key Capabilities

### 1. Unified Master Terminal Console
When starting the server via `start_server.bat` or `KernalLink.exe`, an interactive command console is directly available right in your terminal:
- **`[0]` Stop Server**: Graceful shutdown of the master server and reverts display to primary PC screen. Driver stays installed for instant restart without device detection animations.
- **`[1]` Force Stop Server**: Instantly terminates all server processes and frees ports `8889` & `8890`.
- **`[2]` Enable Monitor Mode**: Seamlessly switches Windows to Extended Desktop (1600x720) in ~50ms without reinstalling or triggering device detection animations.
- **`[3]` Uninstall Driver**: Completely removes the Virtual Display Driver from Windows Device Manager (only when you explicitly choose to remove it).
- **`[4]` Display Settings**: Opens Windows Display Properties directly.
- **`[h]` Menu / Help**: Displays the interactive command menu.

### 2. Instant Reconnection & Zero-Animation Workflow
- **Driver Permanently Ready**: Once installed, the driver remains registered with Windows so you never get interrupted by Windows device detection animations, hardware chimes, or screen re-enumeration flashes.
- **Auto-Revert on Disconnect**: When your phone disconnects, wire is unplugged, or the server is stopped, KernalLink automatically switches Windows projection to PC screen only (`DisplaySwitch.exe /internal`), keeping your mouse bounded to your laptop screen while leaving the driver ready.
- **Works Seamlessly over Wi-Fi and USB**: Whether you connect over USB Cable (`127.0.0.1:8889`) or local Wi-Fi (`LAN IP:8889`), secondary monitor streaming connects instantly.

### 3. Xbox 360 Gamepad Emulation
- **Hardware-Level Virtual Controller**: Integrates with Windows kernel via `ViGEmBus.sys`. Windows, Steam, RetroArch, and PC games (GTA V, Red Dead Redemption 2, Forza, etc.) detect your phone as a genuine physical Xbox 360 controller.
- **Dual Analog Joysticks**: Left Stick (LS) and Right Stick (RS) with custom deadzones and sensitivity. Includes L3/R3 clicks.
- **Triggers & Bumpers**: Analog triggers (LT, RT) and shoulder bumpers (LB, RB).
- **Full D-Pad & ABXY**: Precision tactile directional pad and color-coded action buttons.

### 4. High-Precision Trackpad Mouse & Keyboard
- Sub-pixel cursor movement powered by Windows Native API (`user32.dll SendInput`).
- 1-Finger Tap = Left Click, 2-Finger Tap = Right Click, Tap + Hold & Drag = Selection, 2-Finger Drag = Scroll Wheel.
- Direct typing via Android soft keyboard directly streamed as Unicode keystrokes.

---

## Clean Root Structure

```
d:\app\ashon\controller\
├── start_server.bat          <- Single Master Server Launcher (auto-reverses USB & starts interactive console)
├── stop_server.bat           <- Force stops all server processes, terminals, and frees ports 8889 & 8890
├── stop_server.ps1           <- Administrative cleanup script
├── KernalLink.apk            <- Latest compiled release Android APK for your phone
├── KernalLink.exe            <- High-performance standalone master server binary
├── build_apk.bat             <- 1-click script to rebuild the Android APK
├── ViGEmClient.dll           <- 64-bit ViGEm controller client library
├── README.md                 <- Project documentation
│
├── server\                   <- PC Server Python source files
│   ├── server.py             <- WebSocket server, auto-discovery & interactive console
│   ├── virtual_gamepad.py    <- ViGEm Xbox 360 controller integration
│   ├── screen_streamer.py    <- High-FPS zero-copy screen capture & VDD manager
│   ├── input_handler.py      <- Win32 SendInput mouse & keyboard driver
│   └── driver\vdd\           <- Virtual Display Driver & nefcon binaries
│
└── mobile_client\            <- Flutter Android app source code
```

---

## Quick Start Guide

### Step 1: Start the PC Server
Double-click:
- [**`start_server.bat`**](file:///d:/app/ashon/controller/start_server.bat) (or run [`KernalLink.exe`](file:///d:/app/ashon/controller/KernalLink.exe))

The launcher automatically:
1. Detects your Android phone via USB and activates `adb reverse tcp:8889 tcp:8889` (<0.5ms ultra-low latency).
2. Cleans up any stale processes on port `8889` and `8890`.
3. Activates the UDP auto-discovery beacon on port `8890` for Wi-Fi discovery.
4. Starts the server with live real-time connection logging and displays the interactive command prompt (`KernalLink> `).

### Step 2: Open the Mobile App
1. Install [**`KernalLink.apk`**](file:///d:/app/ashon/controller/KernalLink.apk) on your phone.
2. If connected via USB cable:
   - Tap **USB Cable (127.0.0.1:8889)**.
3. If connected via Wi-Fi:
   - Tap your detected PC from the list.
4. Enjoy ultra-low latency control and high-performance secondary display!
