import Foundation
import Security

enum TokenStore {
    private static let service = "com.replay.videocoach.connection"
    static func read() -> String {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: "server-token",
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ token: String) throws {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: "server-token"]
        let attributes: [String: Any] = [kSecValueData as String: Data(token.utf8),
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if result == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else {
                throw ReplayError.message("Could not securely save the connection token.")
            }
        } else if result != errSecSuccess {
            throw ReplayError.message("Could not securely save the connection token.")
        }
    }
}

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

private struct APIErrorBody: Decodable { let error: String }

struct APIClient {
    let baseURL: URL
    let token: String

    init(address: String, token: String) throws {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              let host = url.host, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty || url.path == "/" else {
            throw ReplayError.message("Add your review server’s address in Settings, for example https://replay.example.com.")
        }
        let components = host.split(separator: ".", omittingEmptySubsequences: false)
        let octets = components.compactMap { Int($0) }
        let ipv4 = components.count == 4 && octets.count == 4 && octets.allSatisfy { (0...255).contains($0) }
        let privateIPv4 = ipv4 && (octets[0] == 10 || octets[0] == 127 ||
            (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1])))
        let local = host == "localhost" || host == "[::1]" || host == "::1" || host.hasSuffix(".local") || privateIPv4
        guard scheme == "https" || (scheme == "http" && local) else {
            throw ReplayError.message("Use HTTPS for a hosted server. HTTP is supported only on your local network for development.")
        }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ReplayError.message("Add the server connection token in Settings first.")
        }
        self.baseURL = url
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send<T: Decodable>(_ method: String, _ path: String, body: Data? = nil, offset: Int64? = nil) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(offset == nil ? "application/json" : "application/octet-stream", forHTTPHeaderField: "Content-Type")
        if let offset { request.setValue(String(offset), forHTTPHeaderField: "Upload-Offset") }
        request.httpBody = body
        request.timeoutInterval = 300
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw ReplayError.message("The review server did not respond.") }
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorBody.self, from: data).error) ?? "The server returned an error (\(response.statusCode))."
            throw APIError(status: response.statusCode, message: message)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func configuration() async throws -> ServerConfiguration { try await send("GET", "api/config") }

    func create(_ session: VideoSession) async throws -> RemoteSession {
        let object: [String: Any] = ["id": session.id.uuidString.lowercased(), "title": session.title,
                                    "activity": session.activity.rawValue, "goal": session.goal, "criteria": session.criteria,
                                    "durationSeconds": session.durationSeconds, "byteCount": session.byteCount, "mimeType": session.mimeType]
        return try await send("POST", "api/sessions", body: JSONSerialization.data(withJSONObject: object))
    }
    func status(_ id: UUID) async throws -> RemoteSession { try await send("GET", "api/sessions/\(id.uuidString.lowercased())") }
    func upload(_ id: UUID, data: Data, offset: Int64) async throws -> RemoteSession {
        try await send("PUT", "api/sessions/\(id.uuidString.lowercased())/video", body: data, offset: offset)
    }
    func analyze(_ id: UUID) async throws -> RemoteSession { try await send("POST", "api/sessions/\(id.uuidString.lowercased())/analyze") }
    func delete(_ id: UUID) async throws {
        struct Result: Decodable { let deleted: Bool }
        let _: Result = try await send("DELETE", "api/sessions/\(id.uuidString.lowercased())")
    }
}
