import rumps
import yliveticker
import threading

class StockBarApp(rumps.App):
    def __init__(self):
        super(StockBarApp, self).__init__("StockBar")

        self.ticker = 'TQQQ'
        self.price = None
        self.price_lock = threading.Lock()
        self.ticker_obj = None
        self.ticker_thread = None

        self.start_ticker_thread(self.ticker)
        rumps.Timer(self.update_title, 1).start()

    def start_ticker_thread(self, ticker_symbol):
        if self.ticker_obj:
            try:
                self.ticker_obj.close()
            except Exception:
                pass

        self.ticker_thread = threading.Thread(
            target=self.run_ticker,
            args=(ticker_symbol,),
            daemon=True
        )
        self.ticker_thread.start()

    def run_ticker(self, ticker_symbol):
        def on_ticker(ws, msg):
            if 'price' in msg:
                with self.price_lock:
                    self.price = msg['price']

        self.ticker_obj = yliveticker.YLiveTicker(
            on_ticker=on_ticker,
            ticker_names=[ticker_symbol]
        )

    def update_title(self, _):
        with self.price_lock:
            price = self.price

        if price is not None:
            self.title = f"${price:.2f}"
        else:
            self.title = f"--"


if __name__ == "__main__":
    StockBarApp().run()