import Foundation
import Security

/// Claude API 키 보관소 — **iOS Keychain에만** 저장(§7 프라이버시 · classify.py 원칙:
/// 키를 저장소·iCloud 어디에도 두지 않는다). 평문 파일(inbox*.md)에도, UserDefaults에도 안 쓴다.
/// generic password 한 항목(account = 고정 키). 앱 전용 기본 access group(무료 서명 OK).
enum KeychainStore {
    private static let service = "kr.teri.secondbrain"
    private static let account = "anthropic_api_key"

    /// 저장(있으면 갱신). 빈 문자열이면 삭제로 취급.
    static func saveAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { deleteAPIKey(); return }
        guard let data = trimmed.data(using: .utf8) else { return }

        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // 이미 있으면 값만 갱신, 없으면 추가.
        let status = SecItemUpdate(base as CFDictionary,
                                   [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    /// 읽기 — 없으면 nil.
    static func loadAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let s = String(data: data, encoding: .utf8),
              !s.isEmpty else { return nil }
        return s
    }

    static func deleteAPIKey() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }

    static var hasKey: Bool { loadAPIKey() != nil }
}
