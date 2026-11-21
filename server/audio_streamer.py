"""
KernalLink Audio Streamer - High-Performance Low-Latency Audio Relay Server.
Captures PC / Laptop system audio via Windows WASAPI loopback (Active Device,
KernalLink Virtual Speaker, or System Speakers) and streams ultra-low latency
48kHz 16-bit stereo PCM audio to connected Android devices.
"""

import sys
import os
import time
import socket
import struct
import ctypes
import winreg
import threading
import subprocess
from pathlib import Path
from collections import deque

try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False

try:
    import pyaudiowpatch as pyaudio
    HAS_PYAUDIO = True
except ImportError:
    HAS_PYAUDIO = False

try:
    import comtypes
    from comtypes import CLSCTX_ALL, GUID, IUnknown, COMMETHOD
    from ctypes import HRESULT, POINTER, c_uint, c_void_p
    from ctypes.wintypes import LPCWSTR, DWORD
    HAS_COMTYPES = True
except ImportError:
    HAS_COMTYPES = False

AUDIO_PORT = 8891
SAMPLE_RATE = 48000
CHANNELS = 2
SAMPLE_WIDTH = 2  # 16-bit PCM = 2 bytes per sample
FRAMES_PER_BUFFER = 960  # 20ms chunk at 48kHz (960 * 2 * 2 = 3840 bytes)
CHUNK_BYTES = FRAMES_PER_BUFFER * CHANNELS * SAMPLE_WIDTH

VIRTUAL_SPEAKER_NAME = "KernalLink Virtual Speaker"
VIRTUAL_SPEAKER_DESC = "Phone Audio"

# PortAudio global C library is not reentrant across threads for Pa_Initialize/Pa_Terminate
_pyaudio_lock = threading.Lock()


# ---------------------------------------------------------------------------
# Windows CoreAudio COM Interfaces for Instant Deterministic Device Switching
# ---------------------------------------------------------------------------
if HAS_COMTYPES:
    CLSID_MMDeviceEnumerator = GUID("{BCDE0395-E52F-467C-8E3D-C4579291692E}")
    CLSID_PolicyConfigClient = GUID("{870AF99C-171D-4F9E-AF0D-E63DF40C2BC9}")

    class _IMMDevice(IUnknown):
        _iid_ = GUID("{D666063F-1587-4E43-81F1-B948E807363F}")
        _methods_ = [
            COMMETHOD([], HRESULT, "Activate", (["in"], POINTER(GUID), "iid"), (["in"], DWORD, "dwClsCtx"), (["in"], c_void_p, "pActivationParams"), (["out"], POINTER(c_void_p), "ppInterface")),
            COMMETHOD([], HRESULT, "OpenPropertyStore", (["in"], DWORD, "stgmAccess"), (["out"], POINTER(c_void_p), "ppProperties")),
            COMMETHOD([], HRESULT, "GetId", (["out"], POINTER(LPCWSTR), "ppstrId")),
            COMMETHOD([], HRESULT, "GetState", (["out"], POINTER(DWORD), "pdwState")),
        ]

    class _IMMDeviceCollection(IUnknown):
        _iid_ = GUID("{0BD7A1BE-7A1A-44DB-8397-CC5392387B5E}")
        _methods_ = [
            COMMETHOD([], HRESULT, "GetCount", (["out"], POINTER(c_uint), "pcDevices")),
            COMMETHOD([], HRESULT, "Item", (["in"], c_uint, "nDevice"), (["out"], POINTER(POINTER(_IMMDevice)), "ppDevice")),
        ]

    class _IMMDeviceEnumerator(IUnknown):
        _iid_ = GUID("{A95664D2-9614-4F35-A746-DE8DB63617E6}")
        _methods_ = [
            COMMETHOD([], HRESULT, "EnumAudioEndpoints", (["in"], c_uint, "dataFlow"), (["in"], DWORD, "dwStateMask"), (["out"], POINTER(POINTER(_IMMDeviceCollection)), "ppDevices")),
            COMMETHOD([], HRESULT, "GetDefaultAudioEndpoint", (["in"], c_uint, "dataFlow"), (["in"], c_uint, "role"), (["out"], POINTER(POINTER(_IMMDevice)), "ppEndpoint")),
        ]

    class _IPolicyConfig(IUnknown):
        _iid_ = GUID("{F8679F50-850A-41CF-9C72-430F290290C8}")
        _methods_ = [
            COMMETHOD([], HRESULT, "GetMixFormat", (["in"], LPCWSTR, "pwstrDeviceId"), (["out"], POINTER(c_void_p), "ppFormat")),
            COMMETHOD([], HRESULT, "GetDeviceFormat", (["in"], LPCWSTR, "pwstrDeviceId"), (["in"], c_uint, "bDefault"), (["out"], POINTER(c_void_p), "ppFormat")),
            COMMETHOD([], HRESULT, "ResetDeviceFormat", (["in"], LPCWSTR, "pwstrDeviceId")),
            COMMETHOD([], HRESULT, "SetDeviceFormat", (["in"], LPCWSTR, "pwstrDeviceId"), (["in"], c_void_p, "pEndpointFormat"), (["in"], c_void_p, "pMixFormat")),
            COMMETHOD([], HRESULT, "GetProcessingPeriod", (["in"], LPCWSTR, "pwstrDeviceId"), (["in"], c_uint, "bDefault"), (["out"], POINTER(c_void_p), "pmftDefaultPeriod"), (["out"], POINTER(c_void_p), "pmftMinimumPeriod")),
            COMMETHOD([], HRESULT, "SetProcessingPeriod", (["in"], LPCWSTR, "pwstrDeviceId"), (["in"], c_void_p, "pmftPeriod")),
            COMMETHOD([], HRESULT, "GetShareMode", (["in"], LPCWSTR, "pwstrDeviceId"), (["out"], POINTER(c_void_p), "pMode")),
            COMMETHOD([], HRESULT, "SetShareMode", (["in"], LPCWSTR, "pwstrDeviceId"), (["in"], c_void_p, "mode")),
            COMMETHOD([], HRESULT, "GetPropertyValue", (["in"], LPCWSTR, "pwstrDeviceId"), (["in"], c_void_p, "key"), (["out"], POINTER(c_void_p), "pv")),
            COMMETHOD([], HRESULT, "SetPropertyValue", (["in"], LPCWSTR, "pwstrDeviceId"), (["in"], c_void_p, "key"), (["in"], c_void_p, "pv")),
            COMMETHOD([], HRESULT, "SetDefaultEndpoint", (["in"], LPCWSTR, "pwstrDeviceId"), (["in"], c_uint, "role")),
            COMMETHOD([], HRESULT, "SetEndpointVisibility", (["in"], LPCWSTR, "pwstrDeviceId"), (["in"], c_uint, "bVisible")),
        ]


def get_nircmd_path() -> Path:
    if hasattr(sys, "_MEIPASS"):
        for cand in [
            Path(sys._MEIPASS) / "tools" / "nircmdc.exe",
            Path(sys._MEIPASS) / "server" / "tools" / "nircmdc.exe",
        ]:
            if cand.exists():
                return cand
    return Path(__file__).parent / "tools" / "nircmdc.exe"


def _is_virtual_name(name: str) -> bool:
    nl = (name or "").lower()
    return (
        "kernallink" in nl
        or "virtual speaker" in nl
        or "audiorelay" in nl
        or "phone audio" in nl
    )


def ensure_virtual_speaker_identity(restart_audio_svc: bool = False) -> dict:
    """
    Ensures the virtual speaker audio endpoint is cleanly named
    'KernalLink Virtual Speaker (Phone Audio)' in Windows Sound Settings and
    the Win+Ctrl+V Audio Output Switcher. Requires Administrator privileges.
    """
    result = {"found": False, "renamed": False, "guids": [], "error": ""}
    if sys.platform != "win32":
        return result

    changed = False
    base_render = r"SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Render"
    try:
        with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, base_render, 0, winreg.KEY_READ) as rk:
            i = 0
            while True:
                try:
                    guid = winreg.EnumKey(rk, i)
                    i += 1
                except OSError:
                    break

                props_sub = f"{base_render}\\{guid}\\Properties"
                try:
                    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, props_sub, 0, winreg.KEY_READ) as pk:
                        def q(val_name):
                            try:
                                return str(winreg.QueryValueEx(pk, val_name)[0])
                            except OSError:
                                return ""

                        hwid = q("{a8b865dd-2e3d-4094-ad97-e593a70c75d6},8").lower()
                        ep_name = q("{a45c254e-df1c-4efd-8020-67d146a850e0},2")
                        ep_desc = q("{b3f8fa53-0004-438e-9003-51a46e139bfc},6")

                        if (
                            "audiorelayvirtualspeaker" in hwid
                            or "kernallink" in ep_name.lower()
                            or "virtual speaker" in ep_name.lower()
                            or "audiorelay" in ep_desc.lower()
                        ):
                            result["found"] = True
                            result["guids"].append(guid)
                            if ep_name != VIRTUAL_SPEAKER_NAME or ep_desc != VIRTUAL_SPEAKER_DESC:
                                try:
                                    with winreg.OpenKey(
                                        winreg.HKEY_LOCAL_MACHINE,
                                        props_sub,
                                        0,
                                        winreg.KEY_SET_VALUE,
                                    ) as wpk:
                                        winreg.SetValueEx(
                                            wpk,
                                            "{a45c254e-df1c-4efd-8020-67d146a850e0},2",
                                            0,
                                            winreg.REG_SZ,
                                            VIRTUAL_SPEAKER_NAME,
                                        )
                                        winreg.SetValueEx(
                                            wpk,
                                            "{b3f8fa53-0004-438e-9003-51a46e139bfc},6",
                                            0,
                                            winreg.REG_SZ,
                                            VIRTUAL_SPEAKER_DESC,
                                        )
                                        changed = True
                                        result["renamed"] = True
                                except PermissionError as pe:
                                    result["error"] = f"Admin privileges required to rename endpoint: {pe}"
                except OSError:
                    continue

        # Also update the MediaCategories friendly pin name if present
        cat_path = r"SYSTEM\CurrentControlSet\Control\MediaCategories\{81792D96-4089-440D-A82F-5C2E205DD9EE}"
        try:
            with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, cat_path, 0, winreg.KEY_READ | winreg.KEY_SET_VALUE) as ck:
                curr_cat = str(winreg.QueryValueEx(ck, "Name")[0])
                if curr_cat != VIRTUAL_SPEAKER_NAME:
                    winreg.SetValueEx(ck, "Name", 0, winreg.REG_SZ, VIRTUAL_SPEAKER_NAME)
                    changed = True
                    result["renamed"] = True
        except OSError:
            pass

        if changed and restart_audio_svc:
            flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
            subprocess.run(["net", "stop", "audiosrv", "/y"], capture_output=True, timeout=10, creationflags=flags)
            subprocess.run(["net", "start", "audiosrv"], capture_output=True, timeout=10, creationflags=flags)
    except Exception as e:
        result["error"] = str(e)

    return result


def open_windows_audio_flyout() -> bool:
    """
    Opens the native Windows 11/10 Audio Output Selector (Win+Ctrl+V) so the user
    can switch quickly between KernalLink Virtual Speaker and System Speakers.
    Falls back to Windows Sound Settings if hotkey is unavailable.
    """
    if sys.platform != "win32":
        return False
    try:
        user32 = ctypes.windll.user32
        VK_LWIN = 0x5B
        VK_CONTROL = 0x11
        VK_V = 0x56
        KEYEVENTF_KEYUP = 0x0002

        user32.keybd_event(VK_LWIN, 0, 0, 0)
        user32.keybd_event(VK_CONTROL, 0, 0, 0)
        user32.keybd_event(VK_V, 0, 0, 0)
        time.sleep(0.05)
        user32.keybd_event(VK_V, 0, KEYEVENTF_KEYUP, 0)
        user32.keybd_event(VK_CONTROL, 0, KEYEVENTF_KEYUP, 0)
        user32.keybd_event(VK_LWIN, 0, KEYEVENTF_KEYUP, 0)
        return True
    except Exception:
        try:
            subprocess.Popen(["cmd", "/c", "start", "ms-settings:sound"], shell=False)
            return True
        except Exception:
            return False


def _enumerate_coreaudio_endpoints() -> list:
    """Returns list of dicts with Windows MMDevice ID and display info via registry + COM."""
    if not HAS_COMTYPES or sys.platform != "win32":
        return []

    endpoints = []
    co_inited = False
    try:
        comtypes.CoInitialize()
        co_inited = True
        enum = comtypes.CoCreateInstance(CLSID_MMDeviceEnumerator, _IMMDeviceEnumerator, CLSCTX_ALL)
        default_id = ""
        try:
            def_ep = enum.GetDefaultAudioEndpoint(0, 0)  # eRender=0, eConsole=0
            default_id = def_ep.GetId() or ""
        except Exception:
            pass

        col = enum.EnumAudioEndpoints(0, 1)  # eRender=0, DEVICE_STATE_ACTIVE=1
        cnt = col.GetCount()
        for i in range(cnt):
            dev = col.Item(i)
            did = dev.GetId() or ""
            guid_part = did.split("}.{")[-1].rstrip("}")
            guid = "{" + guid_part + "}" if guid_part else ""
            short_name = ""
            desc = ""
            hwid = ""
            if guid:
                props_sub = f"SOFTWARE\\Microsoft\\Windows\\CurrentVersion\\MMDevices\\Audio\\Render\\{guid}\\Properties"
                try:
                    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, props_sub, 0, winreg.KEY_READ) as pk:
                        def q(k):
                            try:
                                return str(winreg.QueryValueEx(pk, k)[0])
                            except OSError:
                                return ""
                        short_name = q("{a45c254e-df1c-4efd-8020-67d146a850e0},2")
                        desc = q("{b3f8fa53-0004-438e-9003-51a46e139bfc},6")
                        hwid = q("{a8b865dd-2e3d-4094-ad97-e593a70c75d6},8")
                except OSError:
                    pass

            full_name = f"{short_name} ({desc})" if (short_name and desc) else (short_name or desc or did)
            is_virt = (
                "audiorelayvirtualspeaker" in hwid.lower()
                or _is_virtual_name(full_name)
            )
            endpoints.append({
                "id": did,
                "guid": guid,
                "short_name": short_name,
                "desc": desc,
                "name": full_name,
                "is_default": (did == default_id and did != ""),
                "is_virtual": is_virt,
            })
    except Exception:
        pass
    finally:
        if co_inited:
            try:
                comtypes.CoUninitialize()
            except Exception:
                pass
    return endpoints


def _get_default_endpoint_id() -> str:
    """Fast CoreAudio COM query for current Windows default audio output endpoint ID."""
    if not HAS_COMTYPES or sys.platform != "win32":
        return ""
    co_inited = False
    try:
        comtypes.CoInitialize()
        co_inited = True
        enum = comtypes.CoCreateInstance(CLSID_MMDeviceEnumerator, _IMMDeviceEnumerator, CLSCTX_ALL)
        ep = enum.GetDefaultAudioEndpoint(0, 0)
        return ep.GetId() or ""
    except Exception:
        return ""
    finally:
        if co_inited:
            try:
                comtypes.CoUninitialize()
            except Exception:
                pass


def play_test_chime_async():
    """Plays a 48kHz stereo test chime through the active Windows default playback device (non-blocking, zero PortAudio contention)."""
    if sys.platform != "win32":
        return
    def _play():
        try:
            import math
            import winsound
            rate = 48000
            n_frames = int(rate * 0.45)
            pcm_parts = []
            for i in range(n_frames):
                env = 1.0 - (i / n_frames)
                v = int(math.sin(2 * math.pi * 587.33 * i / rate) * 11000 * env)
                pcm_parts.append(struct.pack("<hh", v, v))
            pcm_data = b"".join(pcm_parts)
            data_size = len(pcm_data)
            wav_hdr = struct.pack(
                "<4sI4s4sIHHIIHH4sI",
                b"RIFF",
                36 + data_size,
                b"WAVE",
                b"fmt ",
                16,
                1,       # PCM
                2,       # stereo
                rate,
                rate * 4,
                4,
                16,
                b"data",
                data_size,
            )
            winsound.PlaySound(wav_hdr + pcm_data, winsound.SND_MEMORY)
        except Exception:
            pass
    threading.Thread(target=_play, daemon=True).start()


def _switch_endpoint_com(endpoint_id: str) -> bool:
    """Switches Windows default render endpoint for Console, Multimedia, and Communications roles."""
    if not HAS_COMTYPES or not endpoint_id or sys.platform != "win32":
        return False
    co_inited = False
    try:
        comtypes.CoInitialize()
        co_inited = True
        pc = comtypes.CoCreateInstance(CLSID_PolicyConfigClient, _IPolicyConfig, CLSCTX_ALL)
        for role in (0, 1, 2):  # 0=Console, 1=Multimedia, 2=Communications
            pc.SetDefaultEndpoint(endpoint_id, role)
        return True
    except Exception as e:
        print(f"[!] CoreAudio COM switch failed: {e}", flush=True)
        return False
    finally:
        if co_inited:
            try:
                comtypes.CoUninitialize()
            except Exception:
                pass


def set_windows_playback_device(target: str) -> bool:
    """
    Switches the active Windows default playback device across all roles (Console, Multimedia, Communications).
    target can be:
      - 'virtual' / 'phone' / 'kernallink' / 'audiorelay' -> KernalLink Virtual Speaker
      - 'speakers' / 'laptop' / 'pc' / 'physical' / 'realtek' / 'system' -> System Laptop Speakers
      - or exact / partial name or ID of any Windows playback device.
    """
    t = (target or "").strip().lower()
    endpoints = _enumerate_coreaudio_endpoints()

    # 1. Exact, fast CoreAudio COM Endpoint GUID switch (zero ambiguity)
    if endpoints:
        chosen = None
        if t in ("virtual", "phone", "audiorelay", "kernallink", "kernallink virtual speaker"):
            for ep in endpoints:
                if ep["is_virtual"]:
                    chosen = ep
                    break
        elif t in ("speakers", "laptop", "pc", "physical", "realtek", "system"):
            non_virt = [ep for ep in endpoints if not ep["is_virtual"]]
            # Prefer built-in speakers (Realtek / Speakers) over optional Bluetooth headphones
            for ep in non_virt:
                if "speaker" in ep["name"].lower() or "realtek" in ep["name"].lower():
                    chosen = ep
                    break
            if not chosen and non_virt:
                chosen = non_virt[0]
        else:
            # Match by endpoint id or substring of friendly name
            for ep in endpoints:
                if ep["id"].lower() == t or t in ep["name"].lower():
                    chosen = ep
                    break

        if chosen and _switch_endpoint_com(chosen["id"]):
            return True

    # 2. Fallback: NirCmd across all 3 Windows audio roles (0=Console, 1=Multimedia, 2=Communications)
    if t in ("virtual", "phone", "audiorelay", "kernallink", "kernallink virtual speaker"):
        candidate_names = [VIRTUAL_SPEAKER_NAME, "Virtual Speakers", "KernalLink"]
    elif t in ("speakers", "laptop", "pc", "physical", "realtek", "system"):
        candidate_names = ["Speakers", "Speakers (Realtek(R) Audio)", "Headphones"]
    else:
        candidate_names = [target]

    nircmd = get_nircmd_path()
    if nircmd.exists():
        flags = subprocess.CREATE_NO_WINDOW if sys.platform == "win32" else 0
        for name in candidate_names:
            try:
                for role in ("0", "1", "2"):
                    subprocess.run([str(nircmd), "setdefaultsounddevice", name, role], capture_output=True, timeout=2, creationflags=flags)
            except Exception as e:
                print(f"[!] Error switching sound device with NirCmd: {e}", flush=True)
        return True
    return False


def get_audio_devices_info() -> dict:
    """
    Returns detailed Windows audio output device info including current default device.
    Uses CoreAudio COM directly so it NEVER collides with active PortAudio/WASAPI capture streams.
    """
    endpoints = _enumerate_coreaudio_endpoints()
    if endpoints:
        def_ep = next((e for e in endpoints if e["is_default"]), None)
        def_name = def_ep["name"] if def_ep else ""
        is_virt_def = def_ep["is_virtual"] if def_ep else False
        return {
            "default_device": def_name,
            "is_virtual_default": is_virt_def,
            "virtual_available": any(e["is_virtual"] for e in endpoints),
            "devices": [
                {
                    "index": idx,
                    "id": e["id"],
                    "name": e["name"],
                    "channels": 2,
                    "sample_rate": SAMPLE_RATE,
                    "is_default": e["is_default"],
                    "is_virtual": e["is_virtual"],
                }
                for idx, e in enumerate(endpoints)
            ],
        }

    if not HAS_PYAUDIO:
        return {"error": "pyaudiowpatch not installed", "devices": [], "default_device": "", "is_virtual_default": False, "virtual_available": False}

    with _pyaudio_lock:
        p = pyaudio.PyAudio()
        try:
            wasapi = p.get_host_api_info_by_type(pyaudio.paWASAPI)
            default_out_idx = wasapi.get("defaultOutputDevice", -1)
            default_name = ""
            if default_out_idx >= 0:
                default_name = p.get_device_info_by_index(default_out_idx).get("name", "")

            devices = []
            for i in range(p.get_device_count()):
                d = p.get_device_info_by_index(i)
                if d["hostApi"] == wasapi["index"] and d["maxOutputChannels"] > 0:
                    is_def = (i == default_out_idx)
                    is_virt = _is_virtual_name(d["name"])
                    devices.append({
                        "index": i,
                        "name": d["name"],
                        "channels": d["maxOutputChannels"],
                        "sample_rate": int(d["defaultSampleRate"]),
                        "is_default": is_def,
                        "is_virtual": is_virt,
                    })

            is_virt_def = _is_virtual_name(default_name)
            virt_avail = any(d["is_virtual"] for d in devices)
            return {
                "default_device": default_name,
                "is_virtual_default": is_virt_def,
                "virtual_available": virt_avail,
                "devices": devices,
            }
        except Exception as e:
            return {"error": str(e), "devices": [], "default_device": "", "is_virtual_default": False, "virtual_available": False}
        finally:
            p.terminate()


def _normalize_pcm_to_48k_stereo(raw_bytes: bytes, src_rate: int, src_channels: int) -> bytes:
    """Converts captured WASAPI PCM int16 frames to uniform 48kHz 2-channel 16-bit PCM."""
    if not raw_bytes:
        return b""
    if src_rate == SAMPLE_RATE and src_channels == CHANNELS:
        return raw_bytes
    if not HAS_NUMPY:
        return raw_bytes

    try:
        samples = np.frombuffer(raw_bytes, dtype=np.int16)
        if src_channels > 1:
            usable = (len(samples) // src_channels) * src_channels
            samples = samples[:usable].reshape(-1, src_channels)
            if src_channels > 2:
                samples = samples[:, :2]
        else:
            samples = np.repeat(samples[:, None], 2, axis=1)

        if src_rate != SAMPLE_RATE and len(samples) > 1:
            n_in = samples.shape[0]
            n_out = max(1, int(round(n_in * (SAMPLE_RATE / float(src_rate)))))
            x_old = np.linspace(0.0, 1.0, n_in, endpoint=False)
            x_new = np.linspace(0.0, 1.0, n_out, endpoint=False)
            ch0 = np.interp(x_new, x_old, samples[:, 0].astype(np.float32))
            ch1 = np.interp(x_new, x_old, samples[:, 1].astype(np.float32))
            out = np.stack((ch0, ch1), axis=1).clip(-32768, 32767).astype(np.int16)
            return out.tobytes()

        return samples.astype(np.int16).tobytes()
    except Exception:
        return raw_bytes


class AudioRelayServer:
    """
    Ultra-low latency audio streaming engine.
    Captures system sound playing on Windows (KernalLink Virtual Speaker or System Speakers)
    and broadcasts uniform 48kHz stereo PCM packets over TCP to connected mobile clients.
    """
    def __init__(self, port: int = AUDIO_PORT, mode: str = "auto"):
        self.port = port
        self.mode = mode  # "auto", "virtual", or "speakers"
        self.running = False
        self.clients = {}  # socket -> {"queue": deque, "cond": Condition}
        self.clients_lock = threading.Lock()

        self.p = None
        self.in_stream = None
        self.out_stream = None
        self.server_socket = None

        self._audio_thread = None
        self._server_thread = None

        self.bytes_streamed = 0
        self.active_device_name = ""
        self.active_device_index = -1
        self.on_device_changed = None  # optional callback() when Windows default device changes

    def _find_devices(self):
        wasapi = self.p.get_host_api_info_by_type(pyaudio.paWASAPI)
        v_loop = None
        v_out = None
        def_loop = None

        try:
            def_loop = self.p.get_default_wasapi_loopback()
        except Exception:
            pass

        for i in range(self.p.get_device_count()):
            d = self.p.get_device_info_by_index(i)
            if d["hostApi"] == wasapi["index"] and _is_virtual_name(d["name"]):
                if d.get("isLoopbackDevice", False):
                    v_loop = d
                elif d["maxOutputChannels"] > 0:
                    v_out = d

        if self.mode == "virtual" and v_loop:
            return v_loop, v_out

        if self.mode == "speakers":
            # Explicitly capture non-virtual speaker loopback
            if def_loop and not _is_virtual_name(def_loop["name"]):
                return def_loop, None
            for i in range(self.p.get_device_count()):
                d = self.p.get_device_info_by_index(i)
                if d["hostApi"] == wasapi["index"] and d.get("isLoopbackDevice", False) and not _is_virtual_name(d["name"]):
                    return d, None

        # Mode == "auto": Capture whatever default playback device is currently active!
        target_loop = def_loop or v_loop
        target_out = v_out if (target_loop and _is_virtual_name(target_loop["name"])) else None
        return target_loop, target_out

    def _broadcast_pcm(self, data: bytes):
        if not data:
            return
        with self.clients_lock:
            for c_info in self.clients.values():
                q = c_info["queue"]
                cond = c_info["cond"]
                with cond:
                    q.append(data)
                    cond.notify_all()

    def _audio_capture_loop(self):
        """Captures Windows audio loopback on-demand with auto-device tracking and comfort silence."""
        last_mode = self.mode
        while self.running:
            # Strictly On-Demand: Do not capture or process WASAPI loopback unless at least 1 client is connected
            with self.clients_lock:
                has_clients = len(self.clients) > 0
            if not has_clients:
                time.sleep(0.25)
                continue

            stop_silence = threading.Event()
            t_sil = None
            try:
                with _pyaudio_lock:
                    self.p = pyaudio.PyAudio()
                    loop_dev, out_dev = self._find_devices()
                if not loop_dev:
                    print("[!] AudioRelay: No WASAPI loopback device available. Retrying in 2s...", flush=True)
                    time.sleep(2.0)
                    continue

                initial_com_id = _get_default_endpoint_id()
                self.active_device_name = loop_dev["name"]
                self.active_device_index = loop_dev["index"]
                src_rate = int(loop_dev.get("defaultSampleRate", SAMPLE_RATE))
                src_channels = max(1, int(loop_dev.get("maxInputChannels", CHANNELS)))
                print(
                    f"[+] AudioRelay: Capturing audio from '{self.active_device_name}' ({src_rate}Hz, {src_channels}ch)",
                    flush=True,
                )

                # Keepalive silence output on Virtual Speakers when active (keeps WASAPI clock running)
                if out_dev and _is_virtual_name(out_dev["name"]):
                    try:
                        v_rate = int(out_dev.get("defaultSampleRate", SAMPLE_RATE))
                        v_ch = max(1, int(out_dev.get("maxOutputChannels", CHANNELS)))
                        self.out_stream = self.p.open(
                            format=pyaudio.paInt16,
                            channels=v_ch,
                            rate=v_rate,
                            output=True,
                            output_device_index=out_dev["index"],
                            frames_per_buffer=FRAMES_PER_BUFFER,
                        )
                    except Exception:
                        self.out_stream = None

                def stream_callback(in_data, frame_count, time_info, status):
                    if in_data and self.running:
                        pcm = _normalize_pcm_to_48k_stereo(in_data, src_rate, src_channels)
                        self._broadcast_pcm(pcm)
                    return (None, pyaudio.paContinue)

                self.in_stream = self.p.open(
                    format=pyaudio.paInt16,
                    channels=src_channels,
                    rate=src_rate,
                    input=True,
                    input_device_index=loop_dev["index"],
                    frames_per_buffer=FRAMES_PER_BUFFER,
                    stream_callback=stream_callback,
                )

                def silence_feeder():
                    silence_chunk = b"\x00" * CHUNK_BYTES
                    while self.running and not stop_silence.is_set() and self.out_stream:
                        try:
                            self.out_stream.write(silence_chunk)
                        except Exception:
                            break
                        time.sleep(0.015)

                if self.out_stream:
                    t_sil = threading.Thread(target=silence_feeder, daemon=True)
                    t_sil.start()

                # Monitor Windows default device changes and active clients (uncached real-time)
                while self.running:
                    time.sleep(0.5)
                    with self.clients_lock:
                        if not self.clients:
                            print("[*] AudioRelay: Audio client disconnected. Pausing WASAPI loopback capture.", flush=True)
                            break
                    if self.mode != last_mode:
                        last_mode = self.mode
                        print(f"[*] AudioRelay capture mode changed to '{self.mode}'. Rebinding...", flush=True)
                        break
                    if self.mode == "auto" and initial_com_id:
                        curr_com_id = _get_default_endpoint_id()
                        if curr_com_id and curr_com_id != initial_com_id:
                            print("[*] AudioRelay: Windows output device changed. Rebinding loopback capture...", flush=True)
                            if callable(self.on_device_changed):
                                try:
                                    self.on_device_changed()
                                except Exception:
                                    pass
                            break

            except Exception as e:
                print(f"[!] AudioRelay capture loop note: {e}", flush=True)
                time.sleep(1.0)
            finally:
                stop_silence.set()
                if t_sil and t_sil.is_alive():
                    t_sil.join(timeout=0.5)
                if self.in_stream:
                    try:
                        self.in_stream.stop_stream()
                        self.in_stream.close()
                    except Exception:
                        pass
                    self.in_stream = None
                if self.out_stream:
                    try:
                        self.out_stream.stop_stream()
                        self.out_stream.close()
                    except Exception:
                        pass
                    self.out_stream = None
                if self.p:
                    with _pyaudio_lock:
                        try:
                            self.p.terminate()
                        except Exception:
                            pass
                        self.p = None

    def _client_handler(self, client_sock: socket.socket, addr):
        """Streams uniform 48kHz stereo PCM frames directly to one mobile client."""
        client_sock.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
        client_sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, CHUNK_BYTES * 8)

        c_queue = deque(maxlen=8)
        c_cond = threading.Condition()
        with self.clients_lock:
            self.clients[client_sock] = {"queue": c_queue, "cond": c_cond}

        print(f"[+] Audio Client Connected: {addr[0]}:{addr[1]} (Streaming 48kHz Stereo)", flush=True)

        try:
            # 16-byte Handshake Header: KL_AUDIO (8B) + Ver(1B) + Flags(1B) + Rate(4B LE) + Ch(1B) + Bits(1B)
            header = struct.pack(
                "<8sBBIBB",
                b"KL_AUDIO",
                1,
                0,
                SAMPLE_RATE,
                CHANNELS,
                16,
            )
            client_sock.sendall(header)

            silence_frame = b"\x00" * CHUNK_BYTES

            while self.running:
                chunk = None
                with c_cond:
                    while not c_queue and self.running:
                        if not c_cond.wait(timeout=0.025):
                            break
                    if not self.running:
                        break
                    if c_queue:
                        chunk = c_queue.popleft()
                    else:
                        chunk = silence_frame

                if chunk:
                    # Slice large chunks into safe <= 3840 byte subframes for jitter-free delivery
                    offset = 0
                    total = len(chunk)
                    while offset < total and self.running:
                        sub = chunk[offset : offset + CHUNK_BYTES]
                        payload = struct.pack("<I", len(sub)) + sub
                        client_sock.sendall(payload)
                        self.bytes_streamed += len(sub)
                        offset += CHUNK_BYTES

        except (socket.error, ConnectionResetError, BrokenPipeError, OSError):
            pass
        finally:
            with self.clients_lock:
                self.clients.pop(client_sock, None)
            try:
                client_sock.close()
            except Exception:
                pass
            print(f"[-] Audio Client Disconnected: {addr[0]}:{addr[1]}", flush=True)

    def _tcp_server_loop(self):
        """Listens on port 8891 for mobile audio client connections."""
        srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.server_socket = srv
        try:
            srv.bind(("0.0.0.0", self.port))
            srv.listen(5)
            srv.settimeout(0.8)
            print(f"[+] AudioRelay TCP Server listening on port {self.port}", flush=True)

            while self.running:
                try:
                    client_sock, addr = srv.accept()
                    t = threading.Thread(target=self._client_handler, args=(client_sock, addr), daemon=True)
                    t.start()
                except socket.timeout:
                    continue
                except OSError:
                    break
        except Exception as e:
            print(f"[!] AudioRelay Server Socket bind failed on port {self.port}: {e}", flush=True)
            self.running = False
        finally:
            try:
                srv.close()
            except Exception:
                pass
            if self.server_socket is srv:
                self.server_socket = None

    def set_mode(self, mode: str):
        if mode in ("auto", "virtual", "speakers"):
            self.mode = mode

    def start(self):
        if self.running:
            return True
        if not HAS_PYAUDIO:
            print("[!] AudioRelay cannot start: pyaudiowpatch is not installed.", flush=True)
            return False

        # Ensure Virtual Speaker shows cleanly as "KernalLink Virtual Speaker" if running as Admin
        ensure_virtual_speaker_identity(restart_audio_svc=False)

        self.running = True
        self._audio_thread = threading.Thread(target=self._audio_capture_loop, daemon=True)
        self._audio_thread.start()

        self._server_thread = threading.Thread(target=self._tcp_server_loop, daemon=True)
        self._server_thread.start()
        return True

    def stop(self):
        if not self.running:
            return
        self.running = False

        with self.clients_lock:
            for c_sock, c_info in list(self.clients.items()):
                with c_info["cond"]:
                    c_info["cond"].notify_all()
                try:
                    c_sock.shutdown(socket.SHUT_RDWR)
                    c_sock.close()
                except Exception:
                    pass
            self.clients.clear()

        if self.server_socket:
            try:
                self.server_socket.close()
            except Exception:
                pass
            self.server_socket = None

        # Join briefly so TCP port 8891 releases cleanly before quick restart
        if self._server_thread and self._server_thread.is_alive():
            self._server_thread.join(timeout=1.5)
        if self._audio_thread and self._audio_thread.is_alive():
            self._audio_thread.join(timeout=1.5)
        self.active_device_name = ""
        print("[*] AudioRelay streaming engine stopped.", flush=True)

    def get_status(self) -> dict:
        with self.clients_lock:
            num_clients = len(self.clients)
        return {
            "running": self.running,
            "port": self.port,
            "mode": self.mode,
            "clients": num_clients,
            "device": self.active_device_name,
            "sample_rate": SAMPLE_RATE,
            "channels": CHANNELS,
            "bytes_streamed": self.bytes_streamed,
        }


# Singleton instance
_audio_relay_instance = None


def get_audio_relay(port: int = AUDIO_PORT, mode: str = "auto") -> AudioRelayServer:
    global _audio_relay_instance
    if _audio_relay_instance is None:
        _audio_relay_instance = AudioRelayServer(port=port, mode=mode)
    return _audio_relay_instance
