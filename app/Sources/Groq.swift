import Foundation
import Security

/// 「AI に聞く」の相手。iPhone では手元のモデルが動かないので Groq（qwen3.8-27b・無料の枠）に投げる。
/// ⛔ 鍵はリポジトリに入れない。作るときに Secrets.xcconfig から入り、初回にキーチェーンへ移す。
enum Groq {
    static let model = "qwen/qwen3.8-27b"

    static func ask(system: String, user: String) async throws -> String {
        guard let key = Keychain.groqKey(), !key.isEmpty else { throw NSError(domain: "oto", code: 2, userInfo: [NSLocalizedDescriptionKey: "AI の鍵が入っていません"]) }
        var req = URLRequest(url: URL(string: "https://api.groq.com/openai/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["model": model, "temperature": 0.3, "max_tokens": 700, "reasoning_effort": "none",
                                   "messages": [["role": "system", "content": system], ["role": "user", "content": user]]]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else {
            throw NSError(domain: "oto", code: code, userInfo: [NSLocalizedDescriptionKey: code == 429 ? "AI の無料の枠がいっぱいです。少し待ってください" : "AI に聞けませんでした（\(code)）"])
        }
        let j = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let msg = ((j?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String ?? ""
        return msg.replacingOccurrences(of: "<think>[\\s\\S]*?</think>", with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum Keychain {
    private static let service = "com.designyifan.otodrill", account = "groq"

    static func groqKey() -> String? {
        if let k = read(), !k.isEmpty { return k }
        // 初回：アプリに入れてきた鍵をキーチェーンへ移す
        if let k = Bundle.main.object(forInfoDictionaryKey: "GroqKey") as? String, !k.isEmpty, !k.hasPrefix("$(") { save(k); return k }
        return nil
    }
    static func read() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func save(_ k: String) {
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(base as CFDictionary)
        var add = base; add[kSecValueData as String] = Data(k.utf8); add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}
