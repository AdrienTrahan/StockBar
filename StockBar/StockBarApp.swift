import AppKit
import Combine
import SwiftUI

@main
struct StockBarApp: App {
    @NSApplicationDelegateAdaptor(StockBarAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
private final class StockBarAppDelegate: NSObject, NSApplicationDelegate {
    private let model = StockBarModel.shared
    private let panel = StockBarPanel(
        contentRect: NSRect(x: 0, y: 0, width: 360, height: 180),
        styleMask: [.borderless, .nonactivatingPanel],
        backing: .buffered,
        defer: true
    )
    private var statusItem: NSStatusItem?
    private var modelChanges: AnyCancellable?
    private var localEventMonitor: Any?
    private var globalEventMonitor: Any?
    private var fixedPanelOriginX: CGFloat?
    private var fixedPanelTop: CGFloat?
    private var panelScreen: NSScreen?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        let contentController = NSHostingController(
            rootView: MenuContentView().environmentObject(model)
        )
        panel.contentViewController = contentController
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        modelChanges = model.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.refreshStatusTitle()
                self?.resizePanelToFitContent()
            }
        }
        installEventMonitors()
        refreshStatusTitle()
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if panel.isVisible {
            closePopover()
        } else {
            showPopover(from: sender)
        }
    }

    private func showPopover(from button: NSStatusBarButton) {
        guard let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = NSScreen.screens.first(where: { $0.frame.contains(buttonRect.midPoint) })
            ?? NSScreen.main
        guard let screen else { return }

        let width: CGFloat = 360
        let visibleFrame = screen.visibleFrame
        let maxHeight = max(152, buttonRect.minY - visibleFrame.minY - 12)
        let height = min(model.popoverHeight, maxHeight)
        let x = min(
            max(buttonRect.midX - width / 2, visibleFrame.minX + 8),
            visibleFrame.maxX - width - 8
        )
        let top = min(buttonRect.minY - 5, screen.frame.maxY - 8)

        fixedPanelOriginX = x
        fixedPanelTop = top
        panelScreen = screen
        panel.setFrame(
            NSRect(x: x, y: top - height, width: width, height: height),
            display: true
        )
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
    }

    private func resizePanelToFitContent() {
        guard panel.isVisible,
              let x = fixedPanelOriginX,
              let top = fixedPanelTop,
              let screen = panelScreen else { return }

        let availableHeight = max(152, top - screen.visibleFrame.minY - 8)
        let height = min(model.popoverHeight, availableHeight)
        let currentFrame = panel.frame
        guard abs(currentFrame.height - height) > 0.5 else { return }

        // Keep the panel's first-opened top edge and horizontal position fixed.
        panel.setFrame(
            NSRect(x: x, y: top - height, width: currentFrame.width, height: height),
            display: true
        )
    }

    private func closePopover() {
        panel.orderOut(nil)
        fixedPanelOriginX = nil
        fixedPanelTop = nil
        panelScreen = nil
    }

    private func installEventMonitors() {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .keyDown]
        ) { [weak self] event in
            guard let self, self.panel.isVisible else { return event }

            if event.type == .keyDown, event.keyCode == 53 {
                self.closePopover()
                return nil
            }

            if event.type == .leftMouseDown || event.type == .rightMouseDown {
                let panelWindowNumber = self.panel.windowNumber
                let statusWindowNumber = self.statusItem?.button?.window?.windowNumber
                guard event.windowNumber != panelWindowNumber,
                      event.windowNumber != statusWindowNumber else { return event }
                self.closePopover()
            }
            return event
        }

        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.panel.isVisible else { return }
                self.closePopover()
            }
        }
    }

    private func refreshStatusTitle() {
        guard let button = statusItem?.button else { return }

        let title = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let baseAttributes: [NSAttributedString.Key: Any] = [.font: font]
        let visibleTickers = model.tickers.filter(model.menuBarTickers.contains)

        if visibleTickers.isEmpty {
            title.append(NSAttributedString(string: "Stocks", attributes: baseAttributes))
        } else {
            for (index, symbol) in visibleTickers.enumerated() {
                if index > 0 {
                    title.append(NSAttributedString(
                        string: " · ",
                        attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
                    ))
                }

                guard let quote = model.quotes[symbol] else {
                    title.append(NSAttributedString(string: "—", attributes: baseAttributes))
                    continue
                }

                let price = quote.price.formatted(.number.precision(.fractionLength(2)))
                let tickerPrefix = model.showTickerNamesInMenuBar ? "\(symbol) " : ""
                title.append(NSAttributedString(
                    string: "\(tickerPrefix)\(price) ",
                    attributes: baseAttributes
                ))

                let color: NSColor
                if quote.changePercent > 0 {
                    color = .systemGreen
                } else if quote.changePercent < 0 {
                    color = .systemRed
                } else {
                    color = .secondaryLabelColor
                }

                let change = String(format: "%+.2f%%", locale: Locale.current, quote.changePercent)
                title.append(NSAttributedString(
                    string: change,
                    attributes: [.font: font, .foregroundColor: color]
                ))
            }
        }

        button.attributedTitle = title
    }
}

private final class StockBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private extension NSRect {
    var midPoint: NSPoint { NSPoint(x: midX, y: midY) }
}
