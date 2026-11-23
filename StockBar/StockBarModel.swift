import Foundation
import SwiftUI

struct StockSuggestion: Decodable, Identifiable, Sendable {
    let symbol: String
    let shortName: String?
    let longName: String?
    let exchangeDisplay: String?
    let quoteType: String?

    var id: String { symbol }
    var companyName: String { longName ?? shortName ?? symbol }
    var exchangeName: String { exchangeDisplay ?? "" }

    enum CodingKeys: String, CodingKey {
        case symbol
        case shortName = "shortname"
        case longName = "longname"
        case exchangeDisplay = "exchDisp"
        case quoteType
    }
}

private struct YahooSearchResponse: Decodable {
    let quotes: [StockSuggestion]
}

struct StockQuote: Identifiable, Equatable, Sendable {
    var id: String { symbol }

    let symbol: String
    let companyName: String
    let price: Double
    let changePercent: Double
    var updatedAt: Date
}

@MainActor
final class StockBarModel: ObservableObject {
    static let shared = StockBarModel()

    @Published private(set) var tickers: [String]
    @Published private(set) var menuBarTickers: Set<String>
    @Published private(set) var showTickerNamesInMenuBar: Bool
    @Published private(set) var quotes: [String: StockQuote] = [:]
    @Published private(set) var searchSuggestions: [StockSuggestion] = []
    @Published private(set) var isSearching = false
    @Published private(set) var isLive = false
    @Published private(set) var connectionStatus = "CONNECTING"
    @Published var tickerInput = ""
    @Published private(set) var validationMessage: String?

    var popoverHeight: CGFloat {
        let rowHeight: CGFloat = 45
        let suggestionsHeight = searchSuggestions.isEmpty
            ? 0
            : CGFloat(searchSuggestions.count) * rowHeight + CGFloat(max(0, searchSuggestions.count - 1)) * 5
        let hasSearchQuery = !tickerInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let searchMessageHeight: CGFloat = isSearching || (hasSearchQuery && searchSuggestions.isEmpty) ? 20 : 0
        let watchlistHeight: CGFloat
        if tickers.isEmpty {
            watchlistHeight = 57
        } else {
            let rowsHeight = CGFloat(tickers.count) * 48
            watchlistHeight = rowsHeight + CGFloat(max(0, tickers.count - 1)) * 7
        }

        let hasSearchResults = suggestionsHeight > 0 || searchMessageHeight > 0
        let betweenSections: CGFloat = hasSearchResults && watchlistHeight > 0 ? 10 : 0
        let scrollContentHeight = suggestionsHeight + searchMessageHeight + betweenSections + watchlistHeight
        return min(max(152, 98 + scrollContentHeight), 600)
    }

    private let defaultsKey = "StockBar.watchlist"
    private let menuBarDefaultsKey = "StockBar.menuBarWatchlist"
    private let showTickerNamesDefaultsKey = "StockBar.showTickerNamesInMenuBar"
    private var streamTask: Task<Void, Never>?
    private var webSocketTask: URLSessionWebSocketTask?
    private var searchTask: Task<Void, Never>?

    init() {
        let saved = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        let normalizedTickers = Self.normalizedUniqueSymbols(saved)
        tickers = normalizedTickers
        if let savedMenuBarTickers = UserDefaults.standard.stringArray(forKey: menuBarDefaultsKey) {
            menuBarTickers = Set(Self.normalizedUniqueSymbols(savedMenuBarTickers).filter(normalizedTickers.contains))
        } else {
            menuBarTickers = Set(normalizedTickers)
        }
        showTickerNamesInMenuBar = UserDefaults.standard.bool(forKey: showTickerNamesDefaultsKey)
        restartStream()
    }

    func addTickers() {
        let candidates = tickerInput
            .uppercased()
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)

        guard !candidates.isEmpty else { return }

        let valid = candidates.filter(Self.isValidSymbol)
        let invalid = candidates.filter { !Self.isValidSymbol($0) }
        let newSymbols = Self.normalizedUniqueSymbols(valid).filter { !tickers.contains($0) }

        if !newSymbols.isEmpty {
            tickers.append(contentsOf: newSymbols)
            menuBarTickers.formUnion(newSymbols)
            saveTickers()
            saveMenuBarTickers()
            restartStream()
        }

        if invalid.isEmpty {
            validationMessage = nil
            tickerInput = ""
            searchSuggestions = []
        } else {
            validationMessage = "Skipped invalid symbol(s): \(invalid.joined(separator: ", "))"
            tickerInput = invalid.joined(separator: ", ")
        }
    }

    func addTicker(_ symbol: String) {
        tickerInput = symbol
        addTickers()
    }

    func updateSearchSuggestions(for query: String) {
        searchTask?.cancel()
        searchSuggestions = []
        isSearching = false

        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !query.contains(",") else { return }
        isSearching = true

        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                guard !Task.isCancelled else { return }

                let suggestions = try await Self.fetchStockSuggestions(for: query)
                guard let self,
                      !Task.isCancelled,
                      self.tickerInput.trimmingCharacters(in: .whitespacesAndNewlines) == query else { return }

                self.searchSuggestions = suggestions
                self.isSearching = false
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.searchSuggestions = []
                self.isSearching = false
            }
        }
    }

    func removeTicker(_ symbol: String) {
        tickers.removeAll { $0 == symbol }
        menuBarTickers.remove(symbol)
        quotes[symbol] = nil
        saveTickers()
        saveMenuBarTickers()
        restartStream()
    }

    func setMenuBarVisibility(_ isVisible: Bool, for symbol: String) {
        guard tickers.contains(symbol) else { return }
        if isVisible {
            menuBarTickers.insert(symbol)
        } else {
            menuBarTickers.remove(symbol)
        }
        saveMenuBarTickers()
    }

    func setShowTickerNamesInMenuBar(_ isVisible: Bool) {
        showTickerNamesInMenuBar = isVisible
        UserDefaults.standard.set(isVisible, forKey: showTickerNamesDefaultsKey)
    }

    private func restartStream() {
        streamTask?.cancel()
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isLive = false
        connectionStatus = tickers.isEmpty ? "ADD TICKERS" : "CONNECTING"

        guard !tickers.isEmpty else { return }
        streamTask = Task { [weak self] in
            await self?.runStream()
        }
    }

    private func runStream() async {
        var reconnectDelay: UInt64 = 1

        while !Task.isCancelled {
            let symbols = tickers
            guard !symbols.isEmpty,
                  let url = URL(string: "wss://streamer.finance.yahoo.com/") else {
                isLive = false
                connectionStatus = "ADD TICKERS"
                return
            }

            let socket = URLSession.shared.webSocketTask(with: url)
            webSocketTask = socket
            socket.resume()
            let connectionStartedAt = Date()

            do {
                let payload = try JSONSerialization.data(withJSONObject: ["subscribe": symbols])
                try await socket.send(.string(String(decoding: payload, as: UTF8.self)))

                guard !Task.isCancelled else {
                    socket.cancel(with: .goingAway, reason: nil)
                    return
                }

                isLive = true
                connectionStatus = "LIVE"

                let pingTask = Task { [weak self] in
                    await self?.sendPings(on: socket)
                }

                do {
                    while !Task.isCancelled {
                        let message = try await socket.receive()
                        guard !Task.isCancelled else { break }

                        let data: Data?
                        switch message {
                        case .string(let value):
                            data = Data(base64Encoded: value)
                        case .data(let value):
                            data = value
                        @unknown default:
                            data = nil
                        }

                        guard let data,
                              var quote = YahooTickerMessage.decode(data),
                              tickers.contains(quote.symbol) else { continue }

                        quote.updatedAt = Date()
                        quotes[quote.symbol] = quote
                    }
                } catch {
                    pingTask.cancel()
                    throw error
                }

                pingTask.cancel()
            } catch {
                guard !Task.isCancelled else { return }
                isLive = false
                connectionStatus = "RECONNECTING"
                if Date().timeIntervalSince(connectionStartedAt) > 60 {
                    reconnectDelay = 1
                }
            }

            socket.cancel(with: .goingAway, reason: nil)
            if webSocketTask === socket {
                webSocketTask = nil
            }

            guard !Task.isCancelled else { return }
            do {
                try await Task.sleep(nanoseconds: reconnectDelay * 1_000_000_000)
            } catch {
                return
            }
            reconnectDelay = min(reconnectDelay * 2, 30)
        }
    }

    private func sendPings(on socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: 15_000_000_000)
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                socket.sendPing { _ in continuation.resume() }
            }
        }
    }

    private func saveTickers() {
        UserDefaults.standard.set(tickers, forKey: defaultsKey)
    }

    private func saveMenuBarTickers() {
        UserDefaults.standard.set(tickers.filter(menuBarTickers.contains), forKey: menuBarDefaultsKey)
    }

    private static func fetchStockSuggestions(for query: String) async throws -> [StockSuggestion] {
        var components = URLComponents(string: "https://query1.finance.yahoo.com/v1/finance/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "quotesCount", value: "8"),
            URLQueryItem(name: "newsCount", value: "0")
        ]

        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let result = try JSONDecoder().decode(YahooSearchResponse.self, from: data)
        return result.quotes.filter { suggestion in
            guard let quoteType = suggestion.quoteType?.uppercased() else { return false }
            return ["EQUITY", "ETF"].contains(quoteType) && isValidSymbol(suggestion.symbol)
        }.prefix(6).map { $0 }
    }

    private static func normalizedUniqueSymbols(_ symbols: [String]) -> [String] {
        var seen = Set<String>()
        return symbols
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { isValidSymbol($0) && seen.insert($0).inserted }
    }

    private static func isValidSymbol(_ symbol: String) -> Bool {
        symbol.range(of: #"^[A-Z0-9.^=-]{1,15}$"#, options: .regularExpression) != nil
    }
}
