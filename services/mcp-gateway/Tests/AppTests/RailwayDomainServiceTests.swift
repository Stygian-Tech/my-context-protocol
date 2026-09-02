import Testing
@testable import App

@Suite("Railway custom-domain TLS")
struct RailwayDomainServiceTests {
    @Test("Railway ownership TXT and routing CNAME are both required setup records")
    func requiredDNSRecords() {
        let result = RailwayDomainService.result(from: domain())

        #expect(result.dnsRecords.map(\.type) == ["TXT", "CNAME"])
        #expect(result.dnsRecords.map(\.name) == ["_railway-verify.mcp.example.com", "mcp.example.com"])
        #expect(result.dnsRecords.map(\.value) == ["railway-ownership-token", "gateway.up.railway.app"])
        #expect(result.dnsRecords.first?.purpose == "OWNERSHIP_VERIFICATION")
        #expect(result.dnsRecords.first?.status == "DNS_RECORD_STATUS_REQUIRES_UPDATE")
        #expect(!result.ownershipVerified)
        #expect(!result.routingReady)
        #expect(result.status == .pending)
    }

    @Test("Ownership, routing, and certificate readiness remain independent")
    func independentReadiness() {
        let pendingCertificate = RailwayDomainService.result(from: domain(
            verified: true,
            records: [routingRecord(status: "DNS_RECORD_STATUS_PROPAGATED")]
        ))
        #expect(pendingCertificate.ownershipVerified)
        #expect(pendingCertificate.routingReady)
        #expect(pendingCertificate.status == .pending)

        let issuedCertificate = RailwayDomainService.result(from: domain(
            certificate: "CERTIFICATE_STATUS_TYPE_VALID"
        ))
        #expect(issuedCertificate.status == .issued)
        #expect(!issuedCertificate.ownershipVerified)
        #expect(!issuedCertificate.routingReady)
    }

    @Test("All traffic records must propagate, and absent records are not ready")
    func routingRequiresEveryRecord() {
        let ready = routingRecord(status: "DNS_RECORD_STATUS_PROPAGATED")
        let pending = routingRecord(status: "DNS_RECORD_STATUS_REQUIRES_UPDATE")
        #expect(!RailwayDomainService.result(from: domain(records: [])).routingReady)
        #expect(!RailwayDomainService.result(from: domain(records: [ready, pending])).routingReady)
        #expect(!RailwayDomainService.result(from: domain(records: [routingRecord(status: "FUTURE_STATUS")])).routingReady)
    }

    @Test("Certificate validation records are preserved without becoming traffic records")
    func certificateValidationRecords() {
        let validation = RailwayDomainService.DomainDNSRecord(
            recordType: "DNS_RECORD_TYPE_CNAME",
            fqdn: "_acme-challenge.mcp.example.com",
            hostlabel: "_acme-challenge.mcp",
            requiredValue: "validation.example.com",
            status: "DNS_RECORD_STATUS_REQUIRES_UPDATE",
            purpose: "DNS_RECORD_PURPOSE_CERTIFICATE_VALIDATION"
        )
        let result = RailwayDomainService.result(from: domain(records: [
            routingRecord(status: "DNS_RECORD_STATUS_PROPAGATED"), validation,
        ]))
        #expect(result.routingReady)
        #expect(result.dnsRecords.last?.name == "_acme-challenge.mcp.example.com")
        #expect(result.dnsRecords.last?.value == "validation.example.com")
        #expect(result.dnsRecords.last?.status == "DNS_RECORD_STATUS_REQUIRES_UPDATE")
    }

    @Test("Duplicate Railway ownership requirements are only shown once")
    func deduplicatedOwnershipRecord() {
        let ownership = RailwayDomainService.DomainDNSRecord(
            recordType: "DNS_RECORD_TYPE_TXT",
            fqdn: "_railway-verify.mcp.example.com",
            hostlabel: "_railway-verify.mcp",
            requiredValue: "railway-ownership-token",
            status: "DNS_RECORD_STATUS_REQUIRES_UPDATE",
            purpose: "OWNERSHIP_VERIFICATION"
        )
        let result = RailwayDomainService.result(from: domain(records: [ownership, routingRecord()]))
        #expect(result.dnsRecords.count == 2)
    }

    @Test("Railway certificate states are normalized without assuming unknown states are ready", arguments: [
        ("CERTIFICATE_STATUS_TYPE_VALID", RailwayDomainService.Status.issued),
        ("CERTIFICATE_STATUS_TYPE_ISSUING", .pending),
        ("CERTIFICATE_STATUS_TYPE_VALIDATING_OWNERSHIP", .pending),
        ("CERTIFICATE_STATUS_TYPE_ISSUE_FAILED", .failed),
        ("FUTURE_STATUS", .unknown),
    ])
    func certificateStates(raw: String, expected: RailwayDomainService.Status) {
        #expect(RailwayDomainService.result(from: domain(certificate: raw)).status == expected)
    }

    private func domain(
        verified: Bool = false,
        certificate: String = "CERTIFICATE_STATUS_TYPE_ISSUING",
        records: [RailwayDomainService.DomainDNSRecord]? = nil
    ) -> RailwayDomainService.CustomDomain {
        RailwayDomainService.CustomDomain(
            id: "railway-domain-id",
            domain: "mcp.example.com",
            status: .init(
                verified: verified,
                verificationDnsHost: "_railway-verify.mcp.example.com",
                verificationToken: "railway-ownership-token",
                certificateStatus: certificate,
                certificateErrorMessage: nil,
                dnsRecords: records ?? [routingRecord()]
            )
        )
    }

    private func routingRecord(status: String = "DNS_RECORD_STATUS_REQUIRES_UPDATE") -> RailwayDomainService.DomainDNSRecord {
        .init(
            recordType: "DNS_RECORD_TYPE_CNAME",
            fqdn: "mcp.example.com",
            hostlabel: "mcp",
            requiredValue: "gateway.up.railway.app",
            status: status,
            purpose: "DNS_RECORD_PURPOSE_TRAFFIC_ROUTE"
        )
    }
}
