import Foundation
import NIOCore
import Vapor

enum FlyCertificateService {
    enum Status: String {
        case notConfigured = "not_configured"
        case pending
        case issued
        case failed
        case unknown
    }

    struct Result {
        let status: Status
        let message: String?
    }

    struct Config: Equatable {
        let apiBaseURL: String
        let appName: String
        let apiToken: String

        static func fromEnvironment() -> Config? {
            guard let apiToken = firstNonEmptyEnv(["FLY_API_TOKEN", "FLY_ACCESS_TOKEN"]) else {
                return nil
            }
            guard let appName = firstNonEmptyEnv([
                "FLY_CERTIFICATE_APP_NAME",
                "FLY_MCP_GATEWAY_APP",
                "FLY_APP_NAME",
            ]) else {
                return nil
            }
            let apiBaseURL = firstNonEmptyEnv(["FLY_CERTIFICATE_API_BASE_URL", "FLY_API_BASE_URL"])
                ?? "https://api.machines.dev"
            guard let normalizedBaseURL = normalizeAPIBaseURL(apiBaseURL),
                  isValidFlyAppName(appName) else {
                return nil
            }
            return Config(
                apiBaseURL: normalizedBaseURL,
                appName: appName,
                apiToken: apiToken
            )
        }
    }

    static func currentConfig() -> Config? {
        Config.fromEnvironment()
    }

    static func missingConfigurationResult() -> Result {
        Result(
            status: .notConfigured,
            message: "Fly certificate provisioning is not configured. Set FLY_API_TOKEN and FLY_CERTIFICATE_APP_NAME or FLY_APP_NAME on the MCP gateway."
        )
    }

    static func ensureCertificate(hostname: String, client: Client, logger: Logger) async -> Result {
        guard let config = Config.fromEnvironment() else {
            return missingConfigurationResult()
        }
        do {
            let existing = try await getCertificate(hostname: hostname, config: config, client: client)
            let existingResult = parseResult(from: existing)
            if existingResult.status == .issued {
                logger.info("Fly certificate already issued for custom domain host=\(hostname)")
                return existingResult
            }
            return await checkExistingCertificate(hostname: hostname, config: config, client: client, logger: logger)
        } catch FlyCertificateError.http(let status, _) where status == .notFound {
            // No certificate has been assigned yet; create one and immediately ask Fly to validate DNS.
        } catch {
            logger.warning("Fly certificate lookup failed for custom domain host=\(hostname) reason=\(String(describing: error))")
        }
        do {
            let create = try await createACMECertificate(hostname: hostname, config: config, client: client)
            let created = parseResult(from: create)
            if created.status == .issued {
                logger.info("Fly certificate issued for custom domain host=\(hostname)")
                return created
            }
            let checked = try await checkCertificate(hostname: hostname, config: config, client: client)
            let checkedResult = parseResult(from: checked)
            logger.info("Fly certificate provisioning checked for custom domain host=\(hostname) status=\(checkedResult.status.rawValue)")
            return checkedResult
        } catch FlyCertificateError.http(let status, _) where status == .conflict {
            return await checkExistingCertificate(hostname: hostname, config: config, client: client, logger: logger)
        } catch {
            logger.warning("Fly certificate provisioning failed for custom domain host=\(hostname) reason=\(String(describing: error))")
            return Result(status: .failed, message: "Fly certificate provisioning failed. Check gateway logs and Fly certificate state for this hostname.")
        }
    }

    static func checkCertificateStatus(hostname: String, client: Client, logger: Logger) async -> Result? {
        guard let config = Config.fromEnvironment() else {
            return missingConfigurationResult()
        }
        do {
            let body = try await getCertificate(hostname: hostname, config: config, client: client)
            return parseResult(from: body)
        } catch FlyCertificateError.http(let status, _) where status == .notFound {
            return Result(status: .pending, message: "No Fly certificate exists yet. Verify DNS again to start provisioning.")
        } catch {
            logger.warning("Fly certificate status check failed for custom domain host=\(hostname) reason=\(String(describing: error))")
            return Result(status: .unknown, message: "Could not read Fly certificate status.")
        }
    }

    static func parseResult(from data: Data) -> Result {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Result(status: .unknown, message: nil)
        }
        let certificate = (object["certificate"] as? [String: Any]) ?? object
        let configured = certificate["configured"] as? Bool ?? false
        let clientStatus = firstString(certificate, keys: ["client_status", "clientStatus"])
        let issuedNodes = ((certificate["issued"] as? [String: Any])?["nodes"] as? [Any]) ?? []
        let validationErrors = certificate["validation_errors"] as? [[String: Any]]
            ?? certificate["validationErrors"] as? [[String: Any]]
            ?? []

        if configured || !issuedNodes.isEmpty || statusLooksIssued(clientStatus) {
            return Result(status: .issued, message: "Fly edge TLS certificate is issued.")
        }
        if let firstError = validationErrors.first {
            let message = firstString(firstError, keys: ["message", "remediation", "error_code", "errorCode"])
            return Result(status: .failed, message: message ?? "Fly certificate validation failed.")
        }
        if let clientStatus, !clientStatus.isEmpty {
            return Result(status: .pending, message: "Fly certificate status: \(clientStatus).")
        }
        return Result(status: .pending, message: "Fly certificate provisioning is pending.")
    }

    private static func checkExistingCertificate(hostname: String, config: Config, client: Client, logger: Logger) async -> Result {
        do {
            let checked = try await checkCertificate(hostname: hostname, config: config, client: client)
            let result = parseResult(from: checked)
            logger.info("Fly certificate checked for existing custom domain host=\(hostname) status=\(result.status.rawValue)")
            return result
        } catch {
            logger.warning("Fly certificate check failed for existing custom domain host=\(hostname) reason=\(String(describing: error))")
            return Result(status: .unknown, message: "Fly certificate exists but status could not be refreshed.")
        }
    }

    private static func createACMECertificate(hostname: String, config: Config, client: Client) async throws -> Data {
        let uri = URI(string: "\(config.apiBaseURL)/apps/\(pathSegmentEscape(config.appName))/certificates/acme")
        let payload = #"{"hostname":"\#(jsonEscape(hostname))"}"#
        return try await sendJSON(.POST, uri: uri, payload: payload, config: config, client: client)
    }

    private static func checkCertificate(hostname: String, config: Config, client: Client) async throws -> Data {
        let uri = URI(string: "\(config.apiBaseURL)/apps/\(pathSegmentEscape(config.appName))/certificates/\(pathSegmentEscape(hostname))/check")
        return try await sendJSON(.POST, uri: uri, payload: nil, config: config, client: client)
    }

    private static func getCertificate(hostname: String, config: Config, client: Client) async throws -> Data {
        let uri = URI(string: "\(config.apiBaseURL)/apps/\(pathSegmentEscape(config.appName))/certificates/\(pathSegmentEscape(hostname))")
        return try await sendJSON(.GET, uri: uri, payload: nil, config: config, client: client)
    }

    private static func sendJSON(
        _ method: HTTPMethod,
        uri: URI,
        payload: String?,
        config: Config,
        client: Client
    ) async throws -> Data {
        let response: ClientResponse
        switch method {
        case .GET:
            response = try await client.get(uri) { req in
                addHeaders(to: &req.headers, token: config.apiToken)
            }.get()
        case .POST:
            response = try await client.post(uri) { req in
                addHeaders(to: &req.headers, token: config.apiToken)
                if let payload {
                    var buffer = ByteBufferAllocator().buffer(capacity: payload.utf8.count)
                    buffer.writeString(payload)
                    req.body = buffer
                }
            }.get()
        default:
            throw FlyCertificateError.unsupportedMethod
        }
        var body = response.body
        let readableBytes = body?.readableBytes ?? 0
        let data = body?.readData(length: readableBytes) ?? Data()
        guard (200..<300).contains(Int(response.status.code)) else {
            throw FlyCertificateError.http(status: response.status, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private static func addHeaders(to headers: inout HTTPHeaders, token: String) {
        headers.bearerAuthorization = BearerAuthorization(token: token)
        headers.contentType = .json
        headers.add(name: "Accept", value: "application/json")
        headers.add(name: "User-Agent", value: "MyContextProtocol/1.0")
    }

    static func normalizeAPIBaseURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(), !host.isEmpty else {
            return nil
        }
        components.scheme = scheme
        components.host = host
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func isValidFlyAppName(_ raw: String) -> Bool {
        let app = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...63).contains(app.count),
              app.first?.isLetter == true || app.first?.isNumber == true,
              app.last?.isLetter == true || app.last?.isNumber == true else {
            return false
        }
        return app.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "-" }
    }

    private static func firstNonEmptyEnv(_ keys: [String]) -> String? {
        for key in keys {
            let value = Environment.get(key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty { return value }
        }
        return nil
    }

    private static func firstString(_ object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func statusLooksIssued(_ status: String?) -> Bool {
        guard let status else { return false }
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "ready" || normalized == "issued" || normalized == "configured"
    }

    static func pathSegmentEscape(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func jsonEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

enum FlyCertificateError: Error, CustomStringConvertible {
    case http(status: HTTPResponseStatus, body: String)
    case unsupportedMethod

    var description: String {
        switch self {
        case .http(let status, _):
            return "HTTP \(status.code)"
        case .unsupportedMethod:
            return "Unsupported HTTP method"
        }
    }
}
