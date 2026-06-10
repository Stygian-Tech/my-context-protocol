import Foundation
import NIOCore
import Vapor

/// Minimal Stripe REST client (Checkout + Customers). No extra SDK dependency.
enum StripeClient {
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

    static func createCustomer(account: Account, client: Client, req: Request) async throws -> String {
        if let existing = account.stripeCustomerId, !existing.isEmpty {
            return existing
        }
        let key = try secretKey(req: req)
        var form = "metadata[account_id]=\(account.id!.uuidString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        if !account.login.isEmpty {
            form += "&name=\(account.login.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        }
        if let email = account.email, !email.isEmpty {
            form += "&email=\(email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
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
            "customer=\(customerId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? customerId)",
            "line_items[0][price]=\(priceId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? priceId)",
            "line_items[0][quantity]=1",
            "success_url=\(successURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? successURL)",
            "cancel_url=\(cancelURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? cancelURL)",
            "client_reference_id=\(accountId.uuidString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")",
            "metadata[account_id]=\(accountId.uuidString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")",
            "subscription_data[metadata][account_id]=\(accountId.uuidString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")",
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
            "customer=\(customerId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? customerId)",
            "return_url=\(returnURL.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? returnURL)",
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
