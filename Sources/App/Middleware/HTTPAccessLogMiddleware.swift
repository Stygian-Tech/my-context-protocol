import Foundation
import Vapor

/// Emits a single line per finished request with **status** and duration (Vapor’s default `RouteLoggingMiddleware` only logs method + path).
/// Registered outermost so the status reflects the final response (including `ErrorMiddleware` handling).
struct HTTPAccessLogMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: AsyncResponder) async throws -> Response {
        guard DevLoggingConfig.httpAccessLogEnabled else {
            return try await next.respond(to: request)
        }

        let method = request.method.rawValue
        let path = request.url.path
        let query = DevLogRedaction.redactedQueryString(request.url.query)
        let start = Date()

        do {
            let response = try await next.respond(to: request)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let code = response.status.code
            let routeHint = request.route?.description ?? "-"
            let line =
                "http_access \(method) \(path) query=\(query) status=\(code) durationMs=\(ms) route=\(routeHint)"
            if code >= 400 {
                request.logger.warning("\(line)")
            } else {
                request.logger.info("\(line)")
            }
            return response
        } catch {
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            request.logger.warning(
                "http_access \(method) \(path) query=\(query) status=thrown durationMs=\(ms) error=\(String(reflecting: error))"
            )
            throw error
        }
    }
}
