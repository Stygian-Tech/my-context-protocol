import Fluent
import Foundation
import Logging
import Vapor

enum ProjectEntitlementReconciler {
    static func reconcileProjects(for account: Account, db: Database, logger: Logger? = nil) async throws {
        if account.hasProEntitlements {
            try await Project.query(on: db)
                .filter(\.$account.$id == account.id!)
                .filter(\.$suspendedAt != .null)
                .set(\.$suspendedAt, to: nil)
                .update()
            logger?.info("project_entitlements account=\(account.id?.uuidString ?? "nil") status=pro unsuspended=all")
            return
        }

        let freeLimit = max(1, Int(Environment.get("FREE_PROJECT_LIMIT") ?? "") ?? 1)
        let projects = try await Project.query(on: db)
            .filter(\.$account.$id == account.id!)
            .sort(\.$createdAt, .ascending)
            .sort(\.$id, .ascending)
            .all()

        for (index, project) in projects.enumerated() {
            let shouldSuspend = index >= freeLimit
            if shouldSuspend, project.suspendedAt == nil {
                project.suspendedAt = Date()
                try await project.save(on: db)
            } else if !shouldSuspend, project.suspendedAt != nil {
                project.suspendedAt = nil
                try await project.save(on: db)
            }
        }
        logger?.info("project_entitlements account=\(account.id?.uuidString ?? "nil") status=free active_limit=\(freeLimit)")
    }
}
