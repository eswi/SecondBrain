import Foundation

/// **create 블록의 원문을 한 줄에 담는 꼴** — 줄바꿈을 `\n`(역슬래시 + n, **두 글자**)으로 접는다.
///
/// ## 왜 있나 — 성역이 줄바꿈을 못 담고 있었다 (2026-08-31 사용자 결정)
///
/// 사용자: *"수집단에서 줄바꿈 처리한 것은 줄바꿈으로 계속 유지되어야 해."*
///
/// create 블록의 꼴이 **`- <날짜> <시각> | <source> | <원문>`** 한 줄이라
/// 원문에 진짜 줄바꿈이 있으면 **파서가 거기서 블록을 끊는다.** 그래서 `InboxModel.capture`가
/// **줄바꿈을 빈칸으로 접고 있었다** — 새 녹음의 「빈 줄 둘」(`TranscriptJoin`)이 **저장하면 사라졌다.**
///
/// ★ **앱은 이미 줄바꿈을 담을 수 있었다 — op 쪽만** 그랬다.
/// 상세에서 원문을 편집하면 `EventWriter`가 `fields.v1` JSON으로 보내고 거기서 `\n`으로 이스케이프된다
/// (실데이터에 그렇게 저장된 항목이 있다 — 2026-08-31 맥미니에서 확인: `"raw":"…쓰자.\n\n\n월요일…"`).
/// **못 담는 자리는 create 블록 하나였다.**
///
/// ## ⛔ 옛 데이터가 안 깨지는 근거 — **쟀다**
/// 이 꼴은 `\`를 만나면 이스케이프로 읽으므로, **역슬래시가 들어 있던 옛 원문은 뜻이 달라진다.**
/// **2026-08-31 맥미니 실측: iCloud의 `inbox*.md` 전체에서 역슬래시가 있는 줄은 여섯이고
/// 여섯 다 `fields.v1` JSON(op)이다 — create 블록에는 0개다.**
/// ⚠️ **다른 기기·다른 시점의 데이터는 못 잼** — 그때는 이 문단이 근거가 아니다.
///
/// ## ⚠️ 이 꼴을 읽는 다른 것들
/// - **`FragmentParser`** — 레거시 v0 파서. **앱이 안 쓴다**(시험에서만 쓰인다 · 살아 있는 경로는 `EventLog`).
/// - **루트 `classify.py` · 웹 v0** — **둘 다 「쓰지 않는다」로 표시된 세대**다(`automation/README.md`).
///   ⛔ 그것들이 이 꼴을 읽으면 `\n`을 **글자 그대로** 보인다. **되살릴 때 함께 볼 자리다.**
public enum RawLine {

    /// 한 줄에 담을 꼴로 접는다. **역슬래시를 먼저 두 배로** 만든 뒤 줄바꿈을 `\n`으로 바꾼다
    /// (순서가 반대면 방금 만든 `\n`의 역슬래시까지 두 배가 된다).
    public static func encode(_ raw: String) -> String {
        var out = ""
        out.reserveCapacity(raw.count + 8)
        // CRLF를 LF 하나로 모은다 — 안 모으면 `\n\n`(빈 줄)이 되어 줄이 하나 늘어난다.
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        for ch in normalized.unicodeScalars {
            if ch == "\\" { out += "\\\\" }
            else if CharacterSet.newlines.contains(ch) { out += "\\n" }
            else { out.unicodeScalars.append(ch) }
        }
        return out
    }

    /// 접힌 꼴을 되돌린다. `\n` → 줄바꿈 · `\\` → 역슬래시 하나.
    /// ⚠️ **모르는 이스케이프는 그대로 둔다**(`\t` 같은 것) — 관용적 파서 원칙(설계 §6).
    /// **뜻을 지어내지 않는다.**
    public static func decode(_ s: String) -> String {
        guard s.contains("\\") else { return s }      // 대부분의 줄은 여기서 끝난다
        var out = ""
        out.reserveCapacity(s.count)
        var it = s.makeIterator()
        var pending: Character? = nil
        while let ch = pending ?? it.next() {
            pending = nil
            guard ch == "\\" else { out.append(ch); continue }
            guard let next = it.next() else { out.append(ch); break }   // 끝의 홀로 남은 `\`
            switch next {
            case "n":  out.append("\n")
            case "\\": out.append("\\")
            default:   out.append(ch); pending = next                   // 모르는 것 → 둘 다 그대로
            }
        }
        return out
    }
}
