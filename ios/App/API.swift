import Foundation

struct Credentials: Codable { let userId: String; let secret: String }
struct Note: Decodable, Identifiable {
    let id: String
    let mine: Bool
    let text: String
    let createdAt: Double
    var date: Date { Date(timeIntervalSince1970: createdAt / 1000) }
}
struct PairCode: Decodable { let code: String; let expiresAt: Double }

struct APIError: LocalizedError {
    let status: Int
    let message: String
    var errorDescription: String? { message }
}

private struct Empty: Decodable {}
private struct NotesResponse: Decodable { let notes: [Note] }
private struct MeResponse: Decodable { let paired: Bool }

struct API {
    var credentials: Credentials?

    private func send<T: Decodable>(_ method: String, _ path: String, body: [String: Any]? = nil, as type: T.Type) async throws -> T {
        var req = URLRequest(url: Config.baseURL.appendingPathComponent(path))
        req.httpMethod = method
        if let c = credentials { req.setValue("Bearer \(c.userId).\(c.secret)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, res) = try await URLSession.shared.data(for: req)
        let status = (res as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw APIError(status: status, message: msg ?? "Something went wrong (\(status))")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    func register() async throws -> Credentials { try await send("POST", "register", as: Credentials.self) }
    func isPaired() async throws -> Bool { try await send("GET", "me", as: MeResponse.self).paired }
    func setPushToken(_ token: String) async throws { _ = try await send("PUT", "me/push-token", body: ["token": token], as: Empty.self) }
    func createCode() async throws -> PairCode { try await send("POST", "pair/code", as: PairCode.self) }
    func join(code: String) async throws { _ = try await send("POST", "pair/join", body: ["code": code], as: Empty.self) }
    func unpair() async throws { _ = try await send("DELETE", "pair", as: Empty.self) }
    func deleteAccount() async throws { _ = try await send("DELETE", "me", as: Empty.self) }
    func sendNote(_ text: String) async throws { _ = try await send("POST", "notes", body: ["text": text], as: Empty.self) }
    func notes() async throws -> [Note] { try await send("GET", "notes?limit=50", as: NotesResponse.self).notes }
}
