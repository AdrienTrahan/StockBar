# -*- mode: python ; coding: utf-8 -*-

block_cipher = None


a = Analysis(
    ['stock_bar.py'],
    pathex=['/Users/adrientrahan/Desktop/StockBar'],
    binaries=[],
    datas=[],
    hiddenimports=['rumps', 'yliveticker'],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    win_no_prefer_redirects=False,
    win_private_assemblies=False,
    cipher=block_cipher,
    noarchive=False,
)
pyz = PYZ(a.pure, a.zipped_data,
          cipher=block_cipher)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='StockBar',
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    console=False,  # This creates a windowed app (no terminal)
    disable_windowed_traceback=False,
    argv_emulation=True,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
    icon='assets/app_icon.icns',  # Path to your icon file (must be .icns format)
)
coll = COLLECT(
    exe,
    a.binaries,
    a.zipfiles,
    a.datas,
    strip=False,
    upx=True,
    upx_exclude=[],
    name='StockBar')

app = BUNDLE(
    coll,
    name='StockBar.app',
    icon='assets/app_icon.icns',  # Path to your icon file (must be .icns format)
    bundle_identifier='com.stockbar.app',
    info_plist={
        'NSHighResolutionCapable': 'True',
        'LSUIElement': 'True',  # This makes it a menu bar app without dock icon
    },
)