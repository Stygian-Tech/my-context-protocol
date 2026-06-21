import Foundation
import NIOCore
import Vapor

/// Minimal Stripe REST client (Checkout + Customers). No extra SDK dependency.
enum StripeClient {
    private static let formAllowedCharacters: CharacterSet = {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+")
        return allowed
    }()

    private static func secretKey(req: Request) throws -> String {
        guard let key = Environment.get("STRIPE_SECRET_KEY"), !key.isEmpty else {
            throw Abort(.serviceUnavailable, reason: "Stripe is not configured")
        }
        return key
    }

    private static func formBuffer(_ form: String) -> ByteBuffer {
        var buf = ByteBufferAllocator().buffer(capacity: form.utf8.count)
        buf.writeString(form)
        return buf
    }

    private static func formPair(_ name: String, _ value: String) -> String {
        "\(formEncode(name))=\(formEncode(value))"
    }

    static func formEncode(_ raw: String) -> String {
        raw.addingPercentEncoding(withAllowedCharacters: formAllowedCharacters) ?? ""
    }

    static func createCustomer(account: Account, client: Client, req: Request) async throws -> String {
        if let existing = account.stripeCustomerId, !existing.isEmpty {
            return existing
        }
        let key = try secretKey(req: req)
        var form = formPair("metadata[account_id]", account.id!.uuidString)
        if !account.login.isEmpty {
            form += "&" + formPair("name", account.login)
        }
        if let email = account.email, !email.isEmpty {
            form += "&" + formPair("email", email)
        }
        let response = try await client.post(URI(string: "https://api.stripe.com/v1/customers")) { out in
            out.headers.add(name: "Authorization", value: "Bearer \(key)")
            out.headers.contentType = .urlEncodedForm
            out.body = formBuffer(form)
        }.get()
        guard response.status == .ok, let bodyBuf = response.body else {
            let msg = response.body.map { String(buffer: $0) } ?? ""
            req.logger.error("Stripe createCustomer failed: \(response.status) \(msg)")
            throw Abort(.badGateway, reason: "Stripe customer creation failed")
        }
        let data = Data(buffer: bodyBuf)
        struct Created: Decodable { let id: String }
        let created = try JSONDecoder().decode(Created.self, from: data)
        account.stripeCustomerId = created.id
        try await account.save(on: req.db)
        return created.id
    }

    static func createCheckoutSession(
        customerId: String,
        accountId: UUID,
        priceId: String,
        successURL: String,
        cancelURL: String,
        client: Client,
        req: Request
    ) async throws -> String {
        let key = try secretKey(req: req)
        let parts: [String] = [
            "mode=subscription",
            formPair("customer", customerId),
            formPair("line_items[0][price]", priceId),
            "line_items[0][quantity]=1",
            formPair("success_url", successURL),
            formPair("cancel_url", cancelURL),
            formPair("client_reference_id", accountId.uuidString),
            formPair("metadata[account_id]", accountId.uuidString),
            formPair("subscription_data[metadata][account_id]", accountId.uuidString),
        ]
        let body = parts.joined(separator: "&")
        let response = try await client.post(URI(string: "https://api.stripe.com/v1/checkout/sessions")) { out in
            out.headers.add(name: "Authorization", value: "Bearer \(key)")
            out.headers.contentType = .urlEncodedForm
            out.body = formBuffer(body)
        }.get()
        guard response.status == .ok, let bodyBuf = response.body else {
            let msg = response.body.map { String(buffer: $0) } ?? ""
            req.logger.error("Stripe checkout failed: \(response.status) \(msg)")
            throw Abort(.badGateway, reason: "Stripe checkout failed")
        }
        struct Session: Decodable { let url: String }
        return try JSONDecoder().decode(Session.self, from: Data(buffer: bodyBuf)).url
    }

    static func createBillingPortalSession(
        customerId: String,
        returnURL: String,
        client: Client,
        req: Request
    ) async throws -> String {
        let key = try secretKey(req: req)
        let form = [
            formPair("customer", customerId),
            formPair("return_url", returnURL),
        ].joined(separator: "&")
        let response = try await client.post(URI(string: "https://api.stripe.com/v1/billing_portal/sessions")) { out in
            out.headers.add(name: "Authorization", value: "Bearer \(key)")
            out.headers.contentType = .urlEncodedForm
            out.body = formBuffer(form)
        }.get()
        guard response.status == .ok, let bodyBuf = response.body else {
            throw Abort(.badGateway, reason: "Stripe portal failed")
        }
        struct Portal: Decodable { let url: String }
        return try JSONDecoder().decode(Portal.self, from: Data(buffer: bodyBuf)).url
    }
}
