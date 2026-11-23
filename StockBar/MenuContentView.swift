import AppKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var model: StockBarModel
    @State private var isHoveringQuit = false

    private var searchQuery: String {
        model.tickerInput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            searchField

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if model.isSearching {
                        Text("Searching stocks…")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    } else if !searchQuery.isEmpty,
                              !searchQuery.contains(","),
                              model.searchSuggestions.isEmpty {
                        Text("No stock matches yet")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }

                    if !model.searchSuggestions.isEmpty {
                        VStack(spacing: 5) {
                            ForEach(model.searchSuggestions) { suggestion in
                                suggestionRow(suggestion)
                            }
                        }
                    }

                    watchlist
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 4)
            }
            .frame(height: max(48, model.popoverHeight - 94))
            .scrollIndicators(.visible)
            .padding(.horizontal, -14)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 360, height: model.popoverHeight, alignment: .top)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Stocks")
                .font(.system(size: 15, weight: .semibold))
            Toggle("Show tickers", isOn: Binding(
                get: { model.showTickerNamesInMenuBar },
                set: model.setShowTickerNamesInMenuBar
            ))
            .font(.system(size: 9, weight: .medium))
            .toggleStyle(ColoredSwitchToggleStyle(accessibilityLabel: "Show ticker symbols"))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            Spacer()
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(isHoveringQuit ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .onHover { isHoveringQuit = $0 }
        }
    }

    private var searchField: some View {
        HStack(spacing: 9) {
            TextField("Search stocks or company names", text: $model.tickerInput)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onChange(of: model.tickerInput) { query in
                    model.updateSearchSuggestions(for: query)
                }
                .onSubmit(model.addTickers)

            Button("Add", action: model.addTickers)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(searchQuery.isEmpty)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var watchlist: some View {
        if model.tickers.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("Your watchlist is empty")
                    .font(.system(size: 13, weight: .medium))
                Text("Search for a company or ticker above.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(model.tickers, id: \.self) { symbol in
                    QuoteRow(
                        symbol: symbol,
                        quote: model.quotes[symbol],
                        isInMenuBar: model.menuBarTickers.contains(symbol),
                        onMenuBarVisibilityChanged: {
                            model.setMenuBarVisibility($0, for: symbol)
                        },
                        onRemove: { model.removeTicker(symbol) }
                    )
                }
            }
        }
    }

    private func suggestionRow(_ suggestion: StockSuggestion) -> some View {
        let alreadyTracked = model.tickers.contains(suggestion.symbol)

        return Button {
            model.addTicker(suggestion.symbol)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(suggestion.companyName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(suggestion.exchangeName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(alreadyTracked ? "Added" : "Add")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(alreadyTracked ? Color.secondary : Color.accentColor)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(alreadyTracked)
    }
}

private struct QuoteRow: View {
    let symbol: String
    let quote: StockQuote?
    let isInMenuBar: Bool
    let onMenuBarVisibilityChanged: (Bool) -> Void
    let onRemove: () -> Void
    @State private var isHoveringRemove = false

    private var movementColor: Color {
        guard let quote else { return .secondary }
        if quote.changePercent > 0 { return .green }
        if quote.changePercent < 0 { return .red }
        return .secondary
    }

    private var hasDistinctCompanyName: Bool {
        guard let quote else { return false }
        return quote.companyName.localizedCaseInsensitiveCompare(symbol) != .orderedSame
    }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(symbol)
                    .font(.system(size: 12, weight: .semibold))
                if hasDistinctCompanyName, let quote {
                    Text(quote.companyName)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 3) {
                if let quote {
                    Text(quote.price.formatted(.number.precision(.fractionLength(2))))
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text("\(quote.changePercent >= 0 ? "+" : "")\(quote.changePercent, specifier: "%.2f")%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(movementColor)
                        .monospacedDigit()
                } else {
                    Text("Waiting for quote…")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minHeight: 32, alignment: .trailing)

            Toggle("", isOn: Binding(
                get: { isInMenuBar },
                set: onMenuBarVisibilityChanged
            ))
            .font(.system(size: 9, weight: .medium))
            .labelsHidden()
            .toggleStyle(ColoredSwitchToggleStyle(accessibilityLabel: "Menu bar"))

            Button(action: onRemove) {
                Text("×")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22, alignment: .center)
                    .background(isHoveringRemove ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove \(symbol)")
            .onHover { isHoveringRemove = $0 }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct ColoredSwitchToggleStyle: ToggleStyle {
    var accessibilityLabel: String

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                configuration.label
                Capsule()
                    .fill(configuration.isOn ? Color.green : Color.gray.opacity(0.35))
                    .frame(width: 30, height: 18)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 14, height: 14)
                            .padding(2)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
