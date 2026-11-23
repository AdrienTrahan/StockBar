import Foundation

enum YahooTickerMessage {
    static func decode(_ data: Data) -> StockQuote? {
        let bytes = Array(data)
        var offset = 0
        var symbol: String?
        var price: Double?
        var changePercent = 0.0
        var companyName: String?
        var timestamp: UInt64 = 0

        while offset < bytes.count {
            guard let key = readVarint(from: bytes, offset: &offset) else { return nil }
            let field = Int(key >> 3)
            let wireType = Int(key & 0x07)

            switch wireType {
            case 0:
                guard let value = readVarint(from: bytes, offset: &offset) else { return nil }
                if field == 3 { timestamp = value }
            case 1:
                guard offset + 8 <= bytes.count else { return nil }
                offset += 8
            case 2:
                guard let rawLength = readVarint(from: bytes, offset: &offset),
                      rawLength <= UInt64(bytes.count - offset) else { return nil }
                let length = Int(rawLength)
                let value = String(decoding: bytes[offset..<(offset + length)], as: UTF8.self)
                offset += length
                if field == 1 { symbol = value }
                if field == 13 { companyName = value }
            case 5:
                guard offset + 4 <= bytes.count else { return nil }
                let bits = UInt32(bytes[offset])
                    | (UInt32(bytes[offset + 1]) << 8)
                    | (UInt32(bytes[offset + 2]) << 16)
                    | (UInt32(bytes[offset + 3]) << 24)
                let value = Double(Float(bitPattern: bits))
                offset += 4
                if field == 2 { price = value }
                if field == 8 { changePercent = value }
            default:
                return nil
            }
        }

        guard let symbol, !symbol.isEmpty,
              let price, price.isFinite,
              changePercent.isFinite else { return nil }

        let seconds = timestamp > 10_000_000_000 ? Double(timestamp) / 1_000 : Double(timestamp)
        return StockQuote(
            symbol: symbol,
            companyName: companyName.flatMap { $0.isEmpty ? nil : $0 } ?? symbol,
            price: price,
            changePercent: changePercent,
            updatedAt: Date(timeIntervalSince1970: seconds)
        )
    }

    private static func readVarint(from bytes: [UInt8], offset: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0

        while offset < bytes.count && shift < 64 {
            let byte = bytes[offset]
            offset += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }

        return nil
    }
}
