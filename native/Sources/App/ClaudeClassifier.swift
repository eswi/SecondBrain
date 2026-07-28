import Foundation

/// 한 줄의 분류 결과(§3 SCHEMA 대응).
struct Classification: Sendable {
    let index: Int
    let type: String
    let due: String
    let resurface: String
    let status: String
    let question: String
}

enum ClassifyError: LocalizedError {
    case noKey
    case http(Int, String)
    case refusal
    case maxTokens
    case network(String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noKey:            return "API 키가 없습니다. 설정에서 Claude API 키를 넣어 주세요."
        case .http(401, _):     return "API 키가 유효하지 않습니다(401). 설정에서 키를 확인해 주세요."
        case .http(403, _):     return "권한/결제 문제일 수 있습니다(403). 콘솔에서 API 접근·크레딧을 확인해 주세요."
        case .http(429, _):     return "요청이 많습니다(429). 잠시 후 다시 시도해 주세요."
        case let .http(code, m): return "API 오류(\(code))\(m.isEmpty ? "" : ": \(m)")"
        case .refusal:          return "분류가 거부되었습니다(refusal)."
        case .maxTokens:        return "한 번에 분류할 항목이 너무 많습니다. 잠시 후 다시 시도해 주세요."
        case let .network(m):   return "네트워크 연결 실패: \(m)"
        case .badResponse:      return "모델 응답을 해석하지 못했습니다."
        }
    }
}

/// iPhone에서 Claude API를 **직접 호출**해 미분류 줄을 분류(사양서 §0-A). SDK가 없어 URLSession 원시 HTTP.
/// classify.py의 요청 형태(model·thinking·output_config.format·system·user)를 그대로 미러링한다.
enum ClaudeClassifier {
    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    /// items(index·원문) → {index: Classification}. 온라인 필요.
    static func classify(items: [(index: Int, raw: String)], apiKey: String) async throws -> [Int: Classification] {
        guard !apiKey.isEmpty else { throw ClassifyError.noKey }
        guard !items.isEmpty else { return [:] }

        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        let today = f.string(from: Date())
        let listing = items.map { "[\($0.index)] \($0.raw)" }.joined(separator: "\n")
        let user = "오늘 날짜: \(today)\n\n미가공 줄:\n\(listing)"

        let body: [String: Any] = [
            "model": ClassifyPrompt.model,
            "max_tokens": 16000,
            "thinking": ["type": "adaptive"],
            "output_config": [
                "effort": "high",
                "format": ["type": "json_schema", "schema": ClassifyPrompt.makeSchema()],
            ],
            "system": ClassifyPrompt.system,
            "messages": [["role": "user", "content": user]],
        ]

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.timeoutInterval = 120
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data, response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: req)
        } catch {
            throw ClassifyError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw ClassifyError.badResponse }
        guard (200...299).contains(http.statusCode) else {
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { ($0?["error"] as? [String: Any])?["message"] as? String } ?? ""
            throw ClassifyError.http(http.statusCode, msg)
        }

        guard let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClassifyError.badResponse
        }
        if (top["stop_reason"] as? String) == "refusal" { throw ClassifyError.refusal }
        if (top["stop_reason"] as? String) == "max_tokens" { throw ClassifyError.maxTokens }

        // output_config.format(json_schema)면 첫 text 블록이 유효 JSON 문자열.
        guard let content = top["content"] as? [[String: Any]],
              let text = content.first(where: { ($0["type"] as? String) == "text" })?["text"] as? String,
              let inner = text.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: inner) as? [String: Any],
              let arr = parsed["classifications"] as? [[String: Any]] else {
            throw ClassifyError.badResponse
        }

        var out: [Int: Classification] = [:]
        for c in arr {
            guard let idx = c["index"] as? Int, let type = c["type"] as? String else { continue }
            out[idx] = Classification(
                index: idx,
                type: type,
                due: (c["due"] as? String) ?? "none",
                resurface: (c["resurface"] as? String) ?? "none",
                status: (c["status"] as? String) ?? "open",
                question: (c["question"] as? String) ?? "")
        }
        return out
    }
}
