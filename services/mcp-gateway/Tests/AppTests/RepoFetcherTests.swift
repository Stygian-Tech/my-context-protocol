import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import App

@Suite("Repository fetch authentication fallback")
struct RepoFetcherTests {
    @Test("An authenticated 401 retries anonymously and can fetch a public repository")
    func retriesPublicRepositoryAnonymously() async throws {
        let recorder = TarballRequestRecorder(statuses: [401, 200], successBody: Data("public archive".utf8))
        let data = try await RepoFetcher.downloadTarball(
            url: try #require(URL(string: "https://api.github.com/repos/example/skills/tarball/main")),
            authToken: "stale-token",
            loader: { request, token in
                try await recorder.load(request, token: token)
            }
        )

        #expect(data == Data("public archive".utf8))
        let requests = await recorder.requests
        #expect(requests.count == 2)
        #expect(requests[0].authorization == "Bearer stale-token")
        #expect(requests[0].loaderToken == "stale-token")
        #expect(requests[1].authorization == nil)
        #expect(requests[1].loaderToken == nil)
    }

    @Test("A private repository remains inaccessible after the anonymous retry")
    func privateRepositoryStillFailsClosed() async throws {
        let recorder = TarballRequestRecorder(statuses: [401, 404])

        do {
            _ = try await RepoFetcher.downloadTarball(
                url: try #require(URL(string: "https://api.github.com/repos/example/private/tarball/main")),
                authToken: "stale-token",
                loader: { request, token in
                    try await recorder.load(request, token: token)
                }
            )
            Issue.record("Expected the anonymous retry to fail")
        } catch RepoFetcherError.fetchFailed(let status) {
            #expect(status == 401)
        }

        let requests = await recorder.requests
        #expect(requests.count == 2)
        #expect(requests[1].authorization == nil)
    }

    @Test("A valid credential succeeds without an anonymous retry")
    func validCredentialDoesNotRetry() async throws {
        let recorder = TarballRequestRecorder(statuses: [200], successBody: Data("private archive".utf8))
        let data = try await RepoFetcher.downloadTarball(
            url: try #require(URL(string: "https://api.github.com/repos/example/private/tarball/main")),
            authToken: "valid-token",
            loader: { request, token in
                try await recorder.load(request, token: token)
            }
        )

        #expect(data == Data("private archive".utf8))
        let requests = await recorder.requests
        #expect(requests.count == 1)
        #expect(requests[0].authorization == "Bearer valid-token")
    }

    @Test("Non-authentication failures do not trigger an anonymous retry")
    func doesNotRetryOtherFailures() async throws {
        let recorder = TarballRequestRecorder(statuses: [403])

        do {
            _ = try await RepoFetcher.downloadTarball(
                url: try #require(URL(string: "https://api.github.com/repos/example/skills/tarball/main")),
                authToken: "valid-token",
                loader: { request, token in
                    try await recorder.load(request, token: token)
                }
            )
            Issue.record("Expected the download to fail")
        } catch RepoFetcherError.fetchFailed(let status) {
            #expect(status == 403)
        }

        #expect(await recorder.requests.count == 1)
    }

    @Test("An anonymous 401 is terminal")
    func anonymous401IsTerminal() async throws {
        let recorder = TarballRequestRecorder(statuses: [401])

        do {
            _ = try await RepoFetcher.downloadTarball(
                url: try #require(URL(string: "https://api.github.com/repos/example/skills/tarball/main")),
                authToken: nil,
                loader: { request, token in
                    try await recorder.load(request, token: token)
                }
            )
            Issue.record("Expected the download to fail")
        } catch RepoFetcherError.fetchFailed(let status) {
            #expect(status == 401)
        }

        #expect(await recorder.requests.count == 1)
    }
}

private actor TarballRequestRecorder {
    struct RecordedRequest: Sendable {
        let authorization: String?
        let loaderToken: String?
    }

    private var statuses: [Int]
    private let successBody: Data
    private(set) var requests: [RecordedRequest] = []

    init(statuses: [Int], successBody: Data = Data()) {
        self.statuses = statuses
        self.successBody = successBody
    }

    func load(_ request: URLRequest, token: String?) throws -> (Data, URLResponse) {
        requests.append(RecordedRequest(
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            loaderToken: token
        ))
        let status = statuses.isEmpty ? 500 : statuses.removeFirst()
        let requestURL = try #require(request.url)
        let response = try #require(HTTPURLResponse(
            url: requestURL,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        ))
        return (status == 200 ? successBody : Data(), response)
    }
}
