from setuptools import setup

APP = ['stock_bar.py']
DATA_FILES = []
OPTIONS = {
    'argv_emulation': True,
    'packages': ['rumps', 'yliveticker', 'zlib'],
    'plist': {
        'LSUIElement': True,  # This makes it a menu bar app without dock icon
        'CFBundleName': 'StockBar',
        'CFBundleDisplayName': 'StockBar',
        'CFBundleIdentifier': 'com.stockbar.app',
        'CFBundleVersion': '1.0.0',
        'CFBundleShortVersionString': '1.0.0',
    },
}

setup(
    app=APP,
    data_files=DATA_FILES,
    options={'py2app': OPTIONS},
)