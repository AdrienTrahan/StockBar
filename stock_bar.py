import rumps
import yliveticker
import threading
import time
import objc
from AppKit import NSWorkspace
from Foundation import NSObject


class WakeObserver(NSObject):
    def initWithCallback_(self, callback):
        self = objc.super(WakeObserver, self).init()
        if self is None:
            return None
        self.callback = callback
        return self

    def wakeNotification_(self, notification):
        self.callback()


class StockBarApp(rumps.App):
    def __init__(self):
        super(StockBarApp, self).__init__("StockBar")

        self.ticker = 'TQQQ'
        self.price = None
        self.price_lock = threading.Lock()
        self.ticker_obj = None
        self.ticker_thread = None
        self.last_update = time.time()
        self.stale_timeout = 20

        self.start_ticker_thread(self.ticker)
        rumps.Timer(self.update_title, 1).start()
        rumps.Timer(self.watchdog, 5).start()

        self.wake_observer = WakeObserver.alloc().initWithCallback_(self.on_wake)
        NSWorkspace.sharedWorkspace().notificationCenter().addObserver_selector_name_object_(
            self.wake_observer,
            'wakeNotification:',
            'NSWorkspaceDidWakeNotification',
            None
        )

    def on_wake(self):
        self.start_ticker_thread(self.ticker)

    def start_ticker_thread(self, ticker_symbol):
        old_ticker_obj = self.ticker_obj
        self.ticker_obj = None

        if old_ticker_obj:
            try:
                old_ticker_obj.close()
            except Exception as e:
                print("Failed to close yliveticker", e)

        with self.price_lock:
            self.last_update = time.time()

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
                    self.last_update = time.time()

        try:
            self.ticker_obj = yliveticker.YLiveTicker(
                on_ticker=on_ticker,
                ticker_names=[ticker_symbol],
            )
        except Exception as e:
            print("Ticker thread crashed", e)

    def watchdog(self, _):
        with self.price_lock:
            elapsed = time.time() - self.last_update
        if elapsed > self.stale_timeout:
            self.start_ticker_thread(self.ticker)

    def update_title(self, _):
        with self.price_lock:
            price = self.price

        if price is not None:
            self.title = f"${price:.2f}"
        else:
            self.title = "--"


if __name__ == "__main__":
    StockBarApp().run()