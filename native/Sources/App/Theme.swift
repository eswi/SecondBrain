import SwiftUI

// MARK: - 다크 팔레트 (웹앱 app.css 다크 토큰 정합)

enum Palette {
    static let bg          = Color(hex: 0x131218)   // --bg
    static let surface     = Color(hex: 0x1D1B25)   // --surface (카드)
    static let surface2    = Color(hex: 0x26232F)   // --surface-2
    static let card        = surface                // 별칭
    static let border      = Color(hex: 0x322E3D)   // --border
    static let cardStroke  = Color(hex: 0x322E3D)   // 카드 hairline(=border)

    static let textPrimary   = Color(hex: 0xECEBF1) // --text
    static let textSecondary = Color(hex: 0xA7A4B3) // --text-muted
    static let textTertiary  = Color(hex: 0x746F82) // --text-faint

    static let accent   = Color(hex: 0x8B87F5)      // 인디고~바이올렛 계열 강조

    // D-day 버킷 색
    static let overdue = Color(hex: 0xFB7185)       // 지남(coral)
    static let today   = Color(hex: 0xFBBF24)       // 오늘(amber)
    static let neutral = Color(hex: 0x746F82)       // 미래(무채색)

    static let radius: CGFloat = 14
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

extension View {
    /// 웹앱 .ambient/.digest 스타일: 틴트 그라데이션 바탕 + 틴트 테두리 + 둥근 모서리.
    /// tint를 옅게 섞은 그라데이션(좌상→우하)으로 surface 위에 얹는다.
    func areaStyle(tint: Color, radius: CGFloat = Palette.radius, strong: Bool = false) -> some View {
        self
            .background(
                LinearGradient(
                    colors: [tint.opacity(strong ? 0.20 : 0.14), Palette.surface],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(tint.opacity(strong ? 0.38 : 0.28))
            )
    }
}

// MARK: - 종류(type) 카탈로그 (웹 색 계열 정합)

struct TypeMeta: Identifiable, Equatable {
    let key: String?     // 이벤트 type 값. nil = 미분류
    let label: String
    let color: Color
    let symbol: String
    var id: String { key ?? "_none" }
}

enum TypeCatalog {
    static func meta(_ key: String?) -> TypeMeta { table[key] ?? table[nil]! }

    private static let table: [String?: TypeMeta] = {
        var t: [String?: TypeMeta] = [:]
        for m in allKnown { t[m.key] = m }
        return t
    }()

    /// 알려진 전 종류('버림' 개념 없음 — discard는 삭제 취급, 종류로 노출 안 함).
    static let allKnown: [TypeMeta] = [
        TypeMeta(key: "promise",     label: "약속",     color: Color(hex: 0xF472B6), symbol: "person.2.fill"),
        TypeMeta(key: "event",       label: "일정",     color: Color(hex: 0x38BDF8), symbol: "calendar"),
        TypeMeta(key: "info-action", label: "할 일",    color: Color(hex: 0xFB7185), symbol: "checkmark.circle.fill"),
        TypeMeta(key: "info",        label: "정보",     color: Color(hex: 0x60A5FA), symbol: "doc.text.fill"),
        TypeMeta(key: "idea",        label: "아이디어", color: Color(hex: 0xA78BFA), symbol: "lightbulb.fill"),
        TypeMeta(key: "principle",   label: "원칙",     color: Color(hex: 0x22D3EE), symbol: "star.fill"),
        TypeMeta(key: "recurrence",  label: "되풀이",   color: Color(hex: 0xFBBF24), symbol: "arrow.triangle.2.circlepath"),
        TypeMeta(key: nil,           label: "미분류",   color: Color(hex: 0x746F82), symbol: "questionmark.circle"),
    ]

    static let assignable: [TypeMeta] = allKnown.filter { $0.key != nil }
    static let primaryFilters: [String] = ["promise", "event", "info-action", "info"]
    static let overflowFilters: [TypeFilter] = [.type("idea"), .type(nil)]
}

// MARK: - 필터

enum TypeFilter: Equatable, Hashable {
    case all
    case type(String?)

    var label: String {
        switch self {
        case .all: return "전체"
        case .type(let k): return TypeCatalog.meta(k).label
        }
    }
}

// MARK: - source 아이콘

enum SourceIcon {
    static func symbol(_ s: String?) -> String {
        switch s {
        case "voice":   return "waveform"
        case "web":     return "link"
        case "image":   return "photo"
        case "mail":    return "envelope.fill"
        case "doc":     return "doc.fill"
        case "chat":    return "bubble.left.fill"
        case "meeting": return "person.3.fill"
        default:        return "tray"
        }
    }
}
