import Foundation
import Vapor

enum DnsTxtVerifier {
    /// Uses Cloudflare DNS-over-HTTPS JSON API to read TXT records for `hostname`.
    static func txtRecordsIncludeToken(hostname: String, token: String, client: Client) async throws -> Bool {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?"))
        let enc = hostname.addingPercentEncoding(withAllowedCharacters: allowed) ?? hostname
        let uri = URI(string: "https://cloudflare-dns.com/dns-query?name=\(enc)&type=TXT")
        let response = try await client.get(uri) { out in
            out.headers.add(name: "Accept", value: "application/dns-json")
            out.headers.add(name: "User-Agent", value: "MyContextProtocol/1.0")
        }.get()
        guard response.status == .ok, var body = response.body else { return false }
        let data = body.readData(length: body.readableBytes) ?? Data()
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let answers = obj["Answer"] as? [[String: Any]] else {
            return false
        }
        for a in answers {
            guard let d = a["data"] as? String else { continue }
            let cleaned = d.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            if cleaned == token || cleaned.contains(token) {
                return true
            }
        }
        return false
    }
}
