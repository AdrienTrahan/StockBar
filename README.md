# StockBar.app

## About

StockBar.app is a lightweight macOS menu bar application that streams the real-time price of a single stock and displays it directly in your macOS menu bar for quick, always-visible market tracking.

## Setup Instructions

1. Navigate to the project: `cd StockBar-app`

2. Sync dependencies: `uv sync`

3. Edit `stock_bar.py` and set your desired symbols (example: `SYMBOLS = ["AAPL", "MSFT", "GOOGL"]`)

4. Build the app: `uv run pyinstaller stock_bar_app.spec`

5. Run the app: `open dist/StockBar.app`

## Troubleshooting

- **uv not found**: `curl -LsSf https://astral.sh/uv/install.sh | sh`
- **App won't open (unverified developer)**: Right-click → Open, or run `xattr -cr dist/StockBar.app`
