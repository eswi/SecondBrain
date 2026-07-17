import SwiftUI

// MARK: - 다크 팔레트

/// 받은함 다크 테마 색. 한 곳에서만 정의(소모품 UI, 데이터와 분리).
enum Palette {
    static let bg          = Color(hex: 0x0E0F13)   // 화면 배경
    static let card        = Color(hex: 0x191B22)   // 카드 배경
    static let cardStroke  = Color.white.opacity(0.06)
    static let band        = Color(hex: 0x15171E)   // 원칙 띠 배경

    static let textPrimary   = Color.white.opacity(0.94)
    static let textSecondary = Color.white.opacity(0.60)
    static let textTertiary  = Color.white.opacity(0.40)

    static let accent   = Color(hex: 0x6FA8FF)      // 강조(탭 tint 등)

    // D-day 버킷 색
    static let overdue = Color(hex: 0xFF5A5A)       // 지남
    static let today   = Color(hex: 0xFFA23A)       // 오늘
    static let neutral = Color.white.opacity(0.45)  // 미래(무채색)
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

// MARK: - 종류(type) 카탈로그: 라벨·색·아이콘 (classify.py TYPE_KO 정합)

struct TypeMeta: Identifiable, Equatable {
    let key: String?     // 이벤트 type 값. nil = 미분류
    let label: String    // 화면 라벨(한국어)
    let color: Color
    let symbol: String   // SF Symbol
    var id: String { key ?? "_none" }
}

enum TypeCatalog {
    /// key → 메타. 없는 값(discard 등)은 미분류로 폴백.
    static func meta(_ key: String?) -> TypeMeta {
        table[key] ?? table[nil]!
    }

    private static let table: [String?: TypeMeta] = {
        var t: [String?: TypeMeta] = [:]
        for m in allKnown { t[m.key] = m }
        return t
    }()

    /// 알려진 전 종류(폴백용). ('버림' 개념은 없음 — 웹 분류값 discard는 삭제로 취급하며 종류로 노출 안 함)
    static let allKnown: [TypeMeta] = [
        TypeMeta(key: "promise",     label: "약속",     color: Color(hex: 0xE86AA6), symbol: "person.2.fill"),
        TypeMeta(key: "event",       label: "일정",     color: Color(hex: 0x5B8DEF), symbol: "calendar"),
        TypeMeta(key: "info-action", label: "할 일",    color: Color(hex: 0x3FB984), symbol: "checkmark.circle.fill"),
        TypeMeta(key: "info",        label: "정보",     color: Color(hex: 0x8E8E93), symbol: "doc.text.fill"),
        TypeMeta(key: "idea",        label: "아이디어", color: Color(hex: 0xF2C14E), symbol: "lightbulb.fill"),
        TypeMeta(key: "principle",   label: "원칙",     color: Color(hex: 0xB07BE0), symbol: "star.fill"),
        TypeMeta(key: nil,           label: "미분류",   color: Color.white.opacity(0.45), symbol: "questionmark.circle"),
    ]

    /// 분류 변경 메뉴에 뜨는 종류(실제 종류로만 — 미분류 제외).
    static let assignable: [TypeMeta] = allKnown.filter { $0.key != nil }

    /// 필터 칩 — 항상 노출되는 주요 종류.
    static let primaryFilters: [String] = ["promise", "event", "info-action", "info"]
    /// 필터 칩 오버플로우(⋯).
    static let overflowFilters: [TypeFilter] = [.type("idea"), .type("principle"), .type(nil)]
}

// MARK: - 필터

enum TypeFilter: Equatable, Hashable {
    case all
    case type(String?)   // .type(nil) = 미분류

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
