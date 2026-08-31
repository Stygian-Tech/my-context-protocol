import Foundation
import NIOCore
import Vapor

enum RailwayDomainService {
    enum Status: String {
        case notConfigured = "not_configured"
        case pending
        case issued
        case failed
        case unknown
    }

    struct DNSRecord: Equatable, Sendable {
        let type: String
        let name: String
        let value: String
        let status: String?
        let purpose: String?
    }

    struct Result: Sendable {
        let status: Status
        let message: String?
        let dnsRecords: [DNSRecord]
        let ownershipVerified: Bool
        let routingReady: Bool
    }

    enum Authentication: Equatable {
        case projectToken(String)
        case bearerToken(String)
    }

    struct Config: Equatable {
        let apiURL: String
        let projectId: String
        let environmentId: String
        let serviceId: String
        let targetPort: Int?
        let authentication: Authentication

        static func fromEnvironment() -> Config? {
            let authentication: Authentication
            if let token = firstNonEmptyEnv(["RAILWAY_PROJECT_TOKEN", "RAILWAY_TOKEN"]) {
                authentication = .projectToken(token)
            } else if let token = firstNonEmptyEnv(["RAILWAY_API_TOKEN"]) {
                authentication = .bearerToken(token)
            } else {
                return nil
            }

            guard let projectId = firstNonEmptyEnv(["RAILWAY_DOMAIN_PROJECT_ID", "RAILWAY_PROJECT_ID"]),
                  let environmentId = firstNonEmptyEnv(["RAILWAY_DOMAIN_ENVIRONMENT_ID", "RAILWAY_ENVIRONMENT_ID"]),
                  let serviceId = firstNonEmptyEnv(["RAILWAY_DOMAIN_SERVICE_ID", "RAILWAY_SERVICE_ID"]),
                  UUID(uuidString: projectId) != nil,
                  UUID(uuidString: environmentId) != nil,
                  UUID(uuidString: serviceId) != nil else {
                return nil
            }

            let apiURL = firstNonEmptyEnv(["RAILWAY_DOMAIN_API_URL"])
                ?? "https://backboard.railway.com/graphql/v2"
            guard let normalizedAPIURL = normalizeAPIURL(apiURL) else { return nil }

            let targetPort = firstNonEmptyEnv(["RAILWAY_DOMAIN_TARGET_PORT"])
                .flatMap(Int.init)
            guard targetPort.map({ (1...65_535).contains($0) }) ?? true else { return nil }

            return Config(
                apiURL: normalizedAPIURL,
                projectId: projectId,
                environmentId: environmentId,
                serviceId: serviceId,
                targetPort: targetPort,
                authentication: authentication
            )
        }
    }

    static func currentConfig() -> Config? {
        Config.fromEnvironment()
    }

    static func missingConfigurationResult() -> Result {
        Result(
            status: .notConfigured,
            message: "Railway domain provisioning is not configured. Set a Railway project token on the Gateway service.",
            dnsRecords: [],
            ownershipVerified: false,
            routingReady: false
        )
    }

    static func ensureDomain(hostname: String, client: Client, logger: Logger) async -> Result {
        guard let config = Config.fromEnvironment() else {
            return missingConfigurationResult()
        }
        let host = normalizedHostname(hostname)
        guard !host.isEmpty else {
            return Result(status: .failed, message: "Invalid custom domain hostname.", dnsRecords: [], ownershipVerified: false, routingReady: false)
        }

        do {
            if let existing = try await findDomain(hostname: host, config: config, client: client) {
                return result(from: existing)
            }
            let created = try await createDomain(hostname: host, config: config, client: client)
            logger.info("Railway custom domain created host=\(host)")
            return result(from: created)
        } catch {
            logger.warning("Railway custom domain provisioning failed host=\(host) reason=\(String(describing: error))")
            return Result(
                status: .failed,
                message: "Railway domain provisioning failed. Check Gateway logs and Railway domain state.",
                dnsRecords: [],
                ownershipVerified: false,
                routingReady: false
            )
        }
    }

    static func checkDomainStatus(hostname: String, client: Client, logger: Logger) async -> Result? {
        guard let config = Config.fromEnvironment() else {
            return missingConfigurationResult()
        }
        let host = normalizedHostname(hostname)
        guard !host.isEmpty else { return nil }
        do {
            guard let domain = try await findDomain(hostname: host, config: config, client: client) else {
                return Result(
                    status: .pending,
                    message: "No Railway domain exists yet. Save the hostname again to start provisioning.",
                    dnsRecords: [],
                    ownershipVerified: false,
                    routingReady: false
                )
            }
            return result(from: domain)
        } catch {
            logger.warning("Railway custom domain status check failed host=\(host) reason=\(String(describing: error))")
            return Result(status: .unknown, message: "Could not read Railway domain status.", dnsRecords: [], ownershipVerified: false, routingReady: false)
        }
    }

    static func result(from domain: CustomDomain) -> Result {
        let records = setupRecords(from: domain.status)
        let routingRecords = records.filter { record in
            record.purpose == "DNS_RECORD_PURPOSE_TRAFFIC_ROUTE"
        }
        let routingReady = !routingRecords.isEmpty && routingRecords.allSatisfy {
            $0.status == "DNS_RECORD_STATUS_PROPAGATED"
        }
        let status: Status
        switch domain.status.certificateStatus {
        case "CERTIFICATE_STATUS_TYPE_VALID":
            status = .issued
        case "CERTIFICATE_STATUS_TYPE_ISSUING", "CERTIFICATE_STATUS_TYPE_VALIDATING_OWNERSHIP":
            status = .pending
        case "CERTIFICATE_STATUS_TYPE_ISSUE_FAILED":
            status = .failed
        default:
            status = .unknown
        }

        let message: String?
        if let error = domain.status.certificateErrorMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !error.isEmpty {
            message = error
        } else {
            switch status {
            case .issued: message = "Railway edge TLS certificate is issued."
            case .pending: message = "Railway TLS certificate provisioning is pending."
            case .failed: message = "Railway certificate issuance failed."
            case .unknown: message = "Railway certificate status is unknown."
            case .notConfigured: message = nil
            }
        }
        return Result(
            status: status,
            message: message,
            dnsRecords: records,
            ownershipVerified: domain.status.verified,
            routingReady: routingReady
        )
    }

    static func setupRecords(from status: CustomDomainStatus) -> [DNSRecord] {
        var records = status.dnsRecords.map {
            DNSRecord(
                type: normalizedRecordType($0.recordType),
                name: $0.fqdn.isEmpty ? $0.hostlabel : $0.fqdn,
                value: $0.requiredValue,
                status: $0.status,
                purpose: $0.purpose
            )
        }
        if let host = status.verificationDnsHost?.trimmingCharacters(in: .whitespacesAndNewlines), !host.isEmpty,
           let token = status.verificationToken?.trimmingCharacters(in: .whitespacesAndNewlines), !token.isEmpty {
            let verification = DNSRecord(
                type: "TXT",
                name: host,
                value: token,
                status: status.verified ? "DNS_RECORD_STATUS_PROPAGATED" : "DNS_RECORD_STATUS_REQUIRES_UPDATE",
                purpose: "OWNERSHIP_VERIFICATION"
            )
            if !records.contains(where: { $0.type == verification.type && $0.name == verification.name && $0.value == verification.value }) {
                records.insert(verification, at: 0)
            }
        }
        return records
    }

    private static func findDomain(hostname: String, config: Config, client: Client) async throws -> CustomDomain? {
        let query = #"query CustomDomains($environmentId: String!, $serviceId: String!) { serviceInstance(environmentId: $environmentId, serviceId: $serviceId) { domains { customDomains { id domain status { verified verificationDnsHost verificationToken certificateStatus certificateErrorMessage dnsRecords { recordType fqdn hostlabel requiredValue status purpose } } } } } }"#
        let data = try await sendGraphQL(
            query: query,
            variables: ["environmentId": config.environmentId, "serviceId": config.serviceId],
            config: config,
            client: client
        )
        let response = try decodeResponse(ServiceInstancePayload.self, from: data)
        return response.serviceInstance.domains.customDomains.first {
            normalizedHostname($0.domain) == hostname
        }
    }

    private static func createDomain(hostname: String, config: Config, client: Client) async throws -> CustomDomain {
        let query = #"mutation CreateCustomDomain($input: CustomDomainCreateInput!) { customDomainCreate(input: $input) { id domain status { verified verificationDnsHost verificationToken certificateStatus certificateErrorMessage dnsRecords { recordType fqdn hostlabel requiredValue status purpose } } } }"#
        var input: [String: Any] = [
            "projectId": config.projectId,
            "environmentId": config.environmentId,
            "serviceId": config.serviceId,
            "domain": hostname,
        ]
        if let targetPort = config.targetPort { input["targetPort"] = targetPort }
        let data = try await sendGraphQL(
            query: query,
            variables: ["input": input],
            config: config,
            client: client
        )
        return try decodeResponse(CreateDomainPayload.self, from: data).customDomainCreate
    }

    private static func sendGraphQL(
        query: String,
        variables: [String: Any],
        config: Config,
        client: Client
    ) async throws -> Data {
        let payload = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let response = try await client.post(URI(string: config.apiURL)) { req in
            switch config.authentication {
            case .projectToken(let token):
                req.headers.replaceOrAdd(name: "Project-Access-Token", value: token)
            case .bearerToken(let token):
                req.headers.bearerAuthorization = BearerAuthorization(token: token)
            }
            req.headers.contentType = .json
            req.headers.replaceOrAdd(name: "Accept", value: "application/json")
            req.headers.replaceOrAdd(name: "User-Agent", value: "MyContextProtocol/1.0")
            var buffer = ByteBufferAllocator().buffer(capacity: payload.count)
            buffer.writeBytes(payload)
            req.body = buffer
        }.get()
        var body = response.body
        let readableBytes = body?.readableBytes ?? 0
        let data = body?.readData(length: readableBytes) ?? Data()
        guard (200..<300).contains(Int(response.status.code)) else {
            throw RailwayDomainError.http(status: response.status, body: String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }

    private static func decodeResponse<Payload: Decodable>(_ type: Payload.Type, from data: Data) throws -> Payload {
        let envelope = try JSONDecoder().decode(GraphQLEnvelope<Payload>.self, from: data)
        if let errors = envelope.errors, !errors.isEmpty {
            throw RailwayDomainError.graphQL
        }
        guard let payload = envelope.data else { throw RailwayDomainError.invalidResponse }
        return payload
    }

    static func normalizeAPIURL(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(), !host.isEmpty else { return nil }
        components.scheme = "https"
        components.host = host
        components.user = nil
        components.password = nil
        components.query = nil
        components.fragment = nil
        return components.string?.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func normalizedHostname(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
    }

    private static func normalizedRecordType(_ raw: String) -> String {
        raw.replacingOccurrences(of: "DNS_RECORD_TYPE_", with: "")
    }

    private static func firstNonEmptyEnv(_ keys: [String]) -> String? {
        for key in keys {
            let value = Environment.get(key)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !value.isEmpty { return value }
        }
        return nil
    }

    struct GraphQLEnvelope<Payload: Decodable>: Decodable {
        let data: Payload?
        let errors: [GraphQLError]?
    }

    struct GraphQLError: Decodable {
        let message: String?
    }

    struct ServiceInstancePayload: Decodable {
        let serviceInstance: ServiceInstance
    }

    struct ServiceInstance: Decodable {
        let domains: DomainCollection
    }

    struct DomainCollection: Decodable {
        let customDomains: [CustomDomain]
    }

    struct CreateDomainPayload: Decodable {
        let customDomainCreate: CustomDomain
    }

    struct CustomDomain: Decodable {
        let id: String
        let domain: String
        let status: CustomDomainStatus
    }

    struct CustomDomainStatus: Decodable {
        let verified: Bool
        let verificationDnsHost: String?
        let verificationToken: String?
        let certificateStatus: String
        let certificateErrorMessage: String?
        let dnsRecords: [DomainDNSRecord]
    }

    struct DomainDNSRecord: Decodable {
        let recordType: String
        let fqdn: String
        let hostlabel: String
        let requiredValue: String
        let status: String
        let purpose: String
    }
}

enum RailwayDomainError: Error, CustomStringConvertible {
    case http(status: HTTPResponseStatus, body: String)
    case graphQL
    case invalidResponse

    var description: String {
        switch self {
        case .http(let status, _): return "HTTP \(status.code)"
        case .graphQL: return "Railway GraphQL request failed"
        case .invalidResponse: return "Invalid Railway GraphQL response"
        }
    }
}
