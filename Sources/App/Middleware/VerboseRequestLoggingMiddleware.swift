import Foundation
import Vapor

struct RequestTraceIDKey: StorageKey {
    typealias Value = String
}

/// Non-production HTTP access tracing when `DEV_LOG_HTTP=1` (see `DevLoggingConfig`).
struct VerboseRequestLoggingMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard DevLoggingConfig.verboseHttpEnabled else {
            return try await next.respond(to: request)
        }

        let traceId = UUID().uuidString
        request.storage[RequestTraceIDKey.self] = traceId
        request.logger[metadataKey: "traceId"] = .string(traceId)

        let path = request.url.path
        let queryRedacted = DevLogRedaction.redactedQueryString(request.url.query)
        let method = request.method.string
        let peer = request.peerAddress?.description ?? "unknown"
        let host = request.headers.first(name: .host) ?? "-"
        let contentType = request.headers.contentType?.description ?? "-"
        let contentLength = request.headers.first(name: .contentLength) ?? "-"
        let reqHeaders = DevLogRedaction.safeRequestHeaders(from: request.headers)

        request.logger.devTrace(
            "req_start traceId=\(traceId) \(method) \(path) query=\(queryRedacted) host=\(host) peer=\(peer) contentType=\(contentType) contentLength=\(contentLength) headers=[\(reqHeaders)]"
        )

        let start = Date()
        do {
            let response = try await next.respond(to: request)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let status = response.status.code
            let respHeaders = DevLogRedaction.safeResponseHeaders(from: response.headers)
            let respLen = response.headers.first(name: .contentLength) ?? "-"
            request.logger.devTrace(
                "req_end traceId=\(traceId) \(method) \(path) status=\(status) durationMs=\(ms) respContentLength=\(respLen) respHeaders=[\(respHeaders)]"
            )
            return response
        } catch {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            request.logger.devTrace(
                "req_end traceId=\(traceId) \(method) \(path) status=thrown durationMs=\(ms) error=\(String(reflecting: error))"
            )
            throw error
        }
    }
}
