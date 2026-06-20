import Fluent
import Foundation
import NIOCore
import Vapor

/// Persists cookie sessions in the app database so multiple replicas share session state.
struct FluentSessionDriver: SessionDriver {
    func createSession(_ data: SessionData, for request: Request) -> EventLoopFuture<SessionID> {
        let key = Self.makeKey()
        let row = AppSessionRecord(sessionKey: key, payload: Self.encodePayload(data))
        return row.save(on: request.db).map { SessionID(string: key) }
    }

    func readSession(_ sessionID: SessionID, for request: Request) -> EventLoopFuture<SessionData?> {
        AppSessionRecord.query(on: request.db)
            .filter(\.$sessionKey == sessionID.string)
            .first()
            .map { record in
                guard let record = record else { return nil }
                return Self.decodePayload(record.payload)
            }
    }

    func updateSession(_ sessionID: SessionID, to data: SessionData, for request: Request) -> EventLoopFuture<SessionID> {
        let encoded = Self.encodePayload(data)
        return AppSessionRecord.query(on: request.db)
            .filter(\.$sessionKey == sessionID.string)
            .first()
            .flatMap { existing in
                if let existing = existing {
                    existing.payload = encoded
                    return existing.update(on: request.db).transform(to: sessionID)
                }
                let row = AppSessionRecord(sessionKey: sessionID.string, payload: encoded)
                return row.save(on: request.db).transform(to: sessionID)
            }
    }

    func deleteSession(_ sessionID: SessionID, for request: Request) -> EventLoopFuture<Void> {
        AppSessionRecord.query(on: request.db)
            .filter(\.$sessionKey == sessionID.string)
            .first()
            .flatMap { row -> EventLoopFuture<Void> in
                guard let row = row else {
                    return request.eventLoop.makeSucceededFuture(())
                }
                return row.delete(on: request.db)
            }
    }

    private static func makeKey() -> String {
        var rnd = [UInt8](repeating: 0, count: 32)
        for i in rnd.indices {
            rnd[i] = UInt8.random(in: 0 ... 255)
        }
        return rnd.map { String(format: "%02x", $0) }.joined()
    }

    private static func encodePayload(_ data: SessionData) -> String {
        (try? String(data: JSONEncoder().encode(data.snapshot), encoding: .utf8)) ?? "{}"
    }

    private static func decodePayload(_ snapshot: String) -> SessionData? {
        guard let d = snapshot.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: d) else {     
            return nil
        }
        return SessionData(initialData: dict)
    }
}
