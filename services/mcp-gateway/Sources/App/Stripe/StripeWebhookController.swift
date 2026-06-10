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

        let event: StripeEvent
        do {
            event = try JSONDecoder().decode(StripeEvent.self, from: payload)
        } catch {
            return Response(status: .ok, body: .init(string: "{\"received\":true}"))
        }

        switch event.type {
        case "checkout.session.completed":
            try await handleCheckoutCompleted(object: event.data.object, req: req)
        case "customer.subscription.updated", "customer.subscription.created":
            try await handleSubscriptionUpdated(object: event.data.object, req: req)
        case "customer.subscription.deleted":
            try await handleSubscriptionDeleted(object: event.data.object, req: req)
        default:
            break
        }
        return Response(status: .ok, body: .init(string: "{\"received\":true}"))
    }

    private static func handleCheckoutCompleted(object: StripeEventObject, req: Request) async throws {
        guard let subscriptionId = object.subscription, !subscriptionId.isEmpty else { return }
        guard let customerId = object.customer, !customerId.isEmpty else { return }
        let accountIdStr = object.metadata?["account_id"] ?? object.clientReferenceId
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

    private static func handleSubscriptionUpdated(object: StripeEventObject, req: Request) async throws {
        guard let customerId = object.customer, !customerId.isEmpty else { return }
        guard let status = object.status else { return }
        guard let subId = object.id else { return }
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

    private static func handleSubscriptionDeleted(object: StripeEventObject, req: Request) async throws {
        guard let customerId = object.customer, !customerId.isEmpty else { return }
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
