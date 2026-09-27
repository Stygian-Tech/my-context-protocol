import Foundation

struct MCPPaginationPage<Element> {
    let items: [Element]
    let nextCursor: String?
}

enum MCPPaginationError: Error {
    case invalidCursor
}

enum MCPPaginator {
    private struct Cursor: Codable {
        let scope: String
        let offset: Int
    }

    static func page<Element>(
        _ items: [Element],
        cursor: String?,
        scope: String,
        pageSize: Int = 50
    ) throws -> MCPPaginationPage<Element> {
        guard pageSize > 0 else { throw MCPPaginationError.invalidCursor }
        let offset: Int
        if let cursor, !cursor.isEmpty {
            guard let decoded = decode(cursor), decoded.scope == scope,
                  decoded.offset >= 0, decoded.offset < items.count else {
                throw MCPPaginationError.invalidCursor
            }
            offset = decoded.offset
        } else {
            offset = 0
        }
        let end = min(items.count, offset + pageSize)
        let next = end < items.count ? encode(Cursor(scope: scope, offset: end)) : nil
        return MCPPaginationPage(items: Array(items[offset..<end]), nextCursor: next)
    }

    private static func encode(_ cursor: Cursor) -> String? {
        guard let data = try? JSONEncoder().encode(cursor) else { return nil }
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func decode(_ raw: String) -> Cursor? {
        guard raw.count <= 1_024,
              raw.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_").contains($0) }) else {
            return nil
        }
        var base64 = raw.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        let padding = (4 - base64.count % 4) % 4
        base64 += String(repeating: "=", count: padding)
        guard let data = Data(base64Encoded: base64) else { return nil }
        return try? JSONDecoder().decode(Cursor.self, from: data)
    }
}
