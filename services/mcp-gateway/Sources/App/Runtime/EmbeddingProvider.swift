import Foundation
import Vapor

protocol SkillEmbeddingProvider: Sendable {
    var providerId: String { get }
    var model: String { get }
    func embed(_ texts: [String], client: Client) async throws -> [[Double]]
}

struct OpenAICompatibleEmbeddingProvider: SkillEmbeddingProvider {
    let providerId: String
    let model: String
    let endpoint: URI
    let apiKey: String

    func embed(_ texts: [String], client: Client) async throws -> [[Double]] {
        struct RequestBody: Content { let model: String; let input: [String] }
        struct ResponseBody: Content { struct Item: Content { let index: Int; let embedding: [Double] }; let data: [Item] }
        let response = try await client.post(endpoint) { request in
            request.headers.bearerAuthorization = .init(token: apiKey)
            try request.content.encode(RequestBody(model: model, input: texts))
        }
        guard response.status == .ok else { throw Abort(.badGateway, reason: "Embedding provider returned HTTP \(response.status.code)") }
        return try response.content.decode(ResponseBody.self).data.sorted { $0.index < $1.index }.map(\.embedding)
    }
}

struct DeterministicTestEmbeddingProvider: SkillEmbeddingProvider {
    let providerId = "deterministic-test"
    let model = "token-buckets-v1"
    func embed(_ texts: [String], client: Client) async throws -> [[Double]] {
        texts.map { text in
            var vector = Array(repeating: 0.0, count: 16)
            for scalar in text.unicodeScalars { vector[Int(scalar.value) % vector.count] += 1 }
            let length = sqrt(vector.reduce(0) { $0 + $1 * $1 })
            return length == 0 ? vector : vector.map { $0 / length }
        }
    }
}
