import Fluent
import Vapor

struct BillingController {
    private static func requireAccount(_ req: Request) throws -> Account {
        guard let account = req.storage[AccountKey.self], let account = account else {
            throw Abort(.unauthorized, reason: "Not authenticated")
        }
        return account
    }

    private static func frontendBase(req: Request) throws -> String {
        guard let base = AppFrontendURL.normalizedBase() else {
            throw Abort(.internalServerError, reason: "FRONTEND_URL or CORS_ORIGIN must be set for billing redirects")
        }
        return base
    }

    /// Resolves Stripe Price ID for Pro checkout. Unknown values default to monthly.
    private static func proStripePriceId(interval: String) -> String? {
        let i = interval.lowercased()
        if ["year", "annual", "yearly"].contains(i) {
            if let y = Environment.get("STRIPE_PRICE_PRO_YEARLY"), !y.isEmpty { return y }
            return nil
        }
        if let m = Environment.get("STRIPE_PRICE_PRO_MONTHLY"), !m.isEmpty { return m }
        if let legacy = Environment.get("STRIPE_PRICE_PRO"), !legacy.isEmpty { return legacy }
        return nil
    }

    static func createCheckoutSession(req: Request) async throws -> CheckoutSessionURLResponse {
        let account = try requireAccount(req)
        let base = try frontendBase(req: req)
        struct Body: Content {
            /// `"month"` (default) or `"year"` for yearly billing.
            var interval: String?
            var success_path: String?
            var cancel_path: String?
        }
        let body = try? req.content.decode(Body.self)
        let billingInterval = body?.interval ?? "month"
        guard let priceId = proStripePriceId(interval: billingInterval) else {
            let hint = billingInterval.lowercased().contains("year")
                ? "STRIPE_PRICE_PRO_YEARLY is not configured"
                : "STRIPE_PRICE_PRO_MONTHLY or STRIPE_PRICE_PRO is not configured"
            throw Abort(.serviceUnavailable, reason: hint)
        }
        let successPath = body?.success_path ?? "/?billing=success"
        let cancelPath = body?.cancel_path ?? "/?billing=cancel"
        let successURL = "\(base)\(successPath.hasPrefix("/") ? successPath : "/" + successPath)"
        let cancelURL = "\(base)\(cancelPath.hasPrefix("/") ? cancelPath : "/" + cancelPath)"

        let customerId = try await StripeClient.createCustomer(account: account, client: req.client, req: req)
        let url = try await StripeClient.createCheckoutSession(
            customerId: customerId,
            accountId: account.id!,
            priceId: priceId,
            successURL: successURL,
            cancelURL: cancelURL,
            client: req.client,
            req: req
        )
        return CheckoutSessionURLResponse(url: url)
    }

    static func createPortalSession(req: Request) async throws -> CheckoutSessionURLResponse {
        let account = try requireAccount(req)
        guard let customerId = account.stripeCustomerId, !customerId.isEmpty else {
            throw Abort(.badRequest, reason: "No Stripe customer on file")
        }
        let base = try frontendBase(req: req)
        let returnURL = "\(base)/"
        let url = try await StripeClient.createBillingPortalSession(
            customerId: customerId,
            returnURL: returnURL,
            client: req.client,
            req: req
        )
        return CheckoutSessionURLResponse(url: url)
    }
}

struct CheckoutSessionURLResponse: Content {
    let url: String
}
