# -*- mode: python ; coding: utf-8 -*-


a = Analysis(
    ['server.py'],
    pathex=[],
    binaries=[('ViGEmClient.dll', '.')],
    datas=[('driver', 'server/driver'), ('driver', 'driver'), ('tools', 'server/tools'), ('tools', 'tools')],
    hiddenimports=[
        'simplejpeg',
        'pyaudiowpatch',
        'comtypes',
        'numpy',
        'pystray',
        'PIL',
        'customtkinter',
        'darkdetect',
        'pc_console',
    ],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name='KernalLink',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    uac_admin=False,
    icon='logo.ico',
)

