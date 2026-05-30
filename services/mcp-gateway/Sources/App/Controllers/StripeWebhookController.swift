import Fluent
import Foundation
import Vapor

struct StripeWebhookController {
    static func handle(req: Request) async throws -> Response {
        guard let secret = Environment.get("STRIPE_WEBHOOK_SECRET"), !secret.isEmpty else {
            throw Abort(.serviceUnavailable, reason: "Stripe webhook not configured")
        }
        guard let sig = req.headers.first(name: "Stripe-Signature") else {
            throw Abort(.badRequest, reason: "Missing Stripe-Signature")
        }
        let maxBytes = 1_048_576
        guard var collected = try await req.body.collect(max: maxBytes).get() else {
            throw Abort(.badRequest, reason: "Empty body")
        }
        let payload = collected.readData(length: collected.readableBytes) ?? Data()
        _ = try StripeWebhookSignature.verify(payload: payload, header: sig, secret: secret)

        guard let top = try JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let type = top["type"] as? String,
              let data = top["data"] as? [String: Any],
              let object = data["object"] as? [String: Any] else {
            return Response(status: .ok, body: .init(string: "{\"received\":true}"))
        }

        switch type {
        case "checkout.session.completed":
            try await handleCheckoutCompleted(object: object, req: req)
        case "customer.subscription.updated", "customer.subscription.created":
            try await handleSubscriptionUpdated(object: object, req: req)
        case "customer.subscription.deleted":
            try await handleSubscriptionDeleted(object: object, req: req)
        default:
            break
        }
        return Response(status: .ok, body: .init(string: "{\"received\":true}"))
    }

    private static func handleCheckoutCompleted(object: [String: Any], req: Request) async throws {
        guard let subscriptionId = object["subscription"] as? String, !subscriptionId.isEmpty else { return }
        guard let customerId = object["customer"] as? String, !customerId.isEmpty else { return }
        let meta = object["metadata"] as? [String: Any]
        let accountIdStr = meta?["account_id"] as? String ?? object["client_reference_id"] as? String
        guard let accountIdStr, let accountId = UUID(uuidString: accountIdStr),
              let account = try await Account.find(accountId, on: req.db) else {
            req.logger.warning("checkout.session.completed: could not resolve account")
            return
        }
        account.stripeCustomerId = customerId
        account.stripeSubscriptionId = subscriptionId
        account.subscriptionStatus = "active"
        try await account.save(on: req.db)
    }

    private static func handleSubscriptionUpdated(object: [String: Any], req: Request) async throws {
        guard let customerId = object["customer"] as? String, !customerId.isEmpty else { return }
        guard let status = object["status"] as? String else { return }
        guard let subId = object["id"] as? String else { return }
        guard let account = try await Account.query(on: req.db).filter(\.$stripeCustomerId == customerId).first() else {
            return
        }
        account.stripeSubscriptionId = subId
        account.subscriptionStatus = status
        try await account.save(on: req.db)
        if status == "canceled" || status == "unpaid" || status == "incomplete_expired" {
            try await GitHubWebhookCleanup.removeAllWebhooks(
                account: account,
                db: req.db,
                client: req.client,
                logger: req.logger
            )
        }
    }

    private static func handleSubscriptionDeleted(object: [String: Any], req: Request) async throws {
        guard let customerId = object["customer"] as? String, !customerId.isEmpty else { return }
        guard let account = try await Account.query(on: req.db).filter(\.$stripeCustomerId == customerId).first() else {
            return
        }
        account.subscriptionStatus = "canceled"
        account.stripeSubscriptionId = nil
        try await account.save(on: req.db)
        try await GitHubWebhookCleanup.removeAllWebhooks(
            account: account,
            db: req.db,
            client: req.client,
            logger: req.logger
        )
    }
}
