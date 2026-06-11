import Fluent
import Foundation
import Logging
import NIOCore
import Vapor

enum StripeSubscriptionSync {
    private struct StripeSubscription: Decodable {
        let id: String
        let status: String
        let customer: String
    }

    /// Fetches the current subscription status from Stripe and updates the account if it has changed.
    /// Updates `stripeStatusCheckedAt` regardless so staleness tracking stays accurate.
    /// Returns `true` if the status was changed.
    @discardableResult
    static func syncAccount(
        account: Account,
        client: Client,
        db: Database,
        logger: Logger
    ) async throws -> Bool {
        guard let secretKey = Environment.get("STRIPE_SECRET_KEY"), !secretKey.isEmpty else { return false }
        guard let subId = account.stripeSubscriptionId, !subId.isEmpty else { return false }

        let response = try await client.get(URI(string: "https://api.stripe.com/v1/subscriptions/\(subId)")) { req in
            req.headers.add(name: "Authorization", value: "Bearer \(secretKey)")
        }.get()

        account.stripeStatusCheckedAt = Date()

        guard response.status == .ok, let body = response.body else {
            // Non-200 from Stripe (e.g. sub deleted/not found) — treat as canceled
            if response.status == .notFound {
                logger.warning("stripe_sync: subscription \(subId) not found — marking canceled")
                let changed = account.subscriptionStatus != "canceled"
                account.subscriptionStatus = "canceled"
                account.stripeSubscriptionId = nil
                try await account.save(on: db)
                return changed
            }
            logger.warning("stripe_sync: unexpected status \(response.status) for subscription \(subId)")
            try await account.save(on: db)
            return false
        }

        let sub = try JSONDecoder().decode(StripeSubscription.self, from: Data(buffer: body))
        let changed = account.subscriptionStatus != sub.status
        if changed {
            logger.info("stripe_sync: account \(account.id?.uuidString ?? "?") status \(account.subscriptionStatus ?? "nil") → \(sub.status)")
        }
        account.subscriptionStatus = sub.status
        try await account.save(on: db)
        return changed
    }

    /// Reconciles all accounts that have a Stripe subscription, skipping any checked within `skipIfCheckedWithin`.
    /// Called by the background lifecycle; also safe to call directly for admin tooling.
    static func reconcileAll(
        db: Database,
        client: Client,
        logger: Logger,
        skipIfCheckedWithin: TimeInterval = 3600
    ) async {
        guard let secretKey = Environment.get("STRIPE_SECRET_KEY"), !secretKey.isEmpty else {
            logger.debug("stripe_reconcile: STRIPE_SECRET_KEY not set, skipping")
            return
        }
        _ = secretKey  // confirm key exists before querying DB

        let cutoff = Date().addingTimeInterval(-skipIfCheckedWithin)
        let accounts: [Account]
        do {
            accounts = try await Account.query(on: db)
                .filter(\.$stripeSubscriptionId != nil)
                .group(.or) { g in
                    g.filter(\.$stripeStatusCheckedAt == nil)
                    g.filter(\.$stripeStatusCheckedAt < cutoff)
                }
                .all()
        } catch {
            logger.error("stripe_reconcile: DB query failed: \(error)")
            return
        }

        guard !accounts.isEmpty else {
            logger.debug("stripe_reconcile: no accounts need reconciliation")
            return
        }

        logger.info("stripe_reconcile: syncing \(accounts.count) account(s)")
        var synced = 0
        var changed = 0
        for account in accounts {
            guard !Task.isCancelled else { break }
            do {
                let didChange = try await syncAccount(account: account, client: client, db: db, logger: logger)
                synced += 1
                if didChange { changed += 1 }
            } catch {
                logger.warning("stripe_reconcile: failed for account \(account.id?.uuidString ?? "?"): \(error)")
            }
            // Brief pause to avoid bursting the Stripe rate limit (100 reads/s per key)
            try? await Task.sleep(for: .milliseconds(50))
        }
        logger.info("stripe_reconcile: done — synced=\(synced) changed=\(changed)")
    }
}
