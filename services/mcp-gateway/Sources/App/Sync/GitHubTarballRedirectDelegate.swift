import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// GitHub's tarball API returns `302` to `codeload.github.com`. `URLSession` does not forward
/// `Authorization` across that redirect, which breaks private repos (often 403/404). Re-apply Bearer on redirect.
final class GitHubTarballRedirectDelegate: NSObject, URLSessionTaskDelegate {
    let bearerToken: String

    init(bearerToken: String) {
        self.bearerToken = bearerToken
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var req = request
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        completionHandler(req)
    }
}
