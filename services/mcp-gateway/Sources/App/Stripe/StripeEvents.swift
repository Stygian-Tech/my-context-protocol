import Foundation

struct StripeEvent: Decodable {
    let type: String
    let data: StripeEventData
}

struct StripeEventData: Decodable {
    let object: StripeEventObject
}

struct StripeEventObject: Decodable {
    let id: String?
    let customer: String?
    let subscription: String?
    let status: String?
    let clientReferenceId: String?
    let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case id, customer, subscription, status, metadata
        case clientReferenceId = "client_reference_id"
    }
}
