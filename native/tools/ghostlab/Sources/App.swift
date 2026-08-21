//
//  GhostLab — **「눌러야만 드러나는 것」을 재는 실험용 앱** (2026-08-20 신설)
//
//  ⚠️⚠️ **이것은 앱 코드가 아니다.** `native/tools/ghostlab/`에 있고 **`SecondBrain` 빌드에 안 섞인다**
//  (앱 타깃은 `native/project.yml`에서 `sources: [Sources/App]`만 컴파일한다).
//  ⛔ **앱에서 이 파일들을 참조하지 말 것.** 색·글꼴은 앱에서 **값만 베껴** 뒀다(`Palette`를 안 쓴다) —
//  그래서 앱 색이 바뀌면 여기는 안 따라온다. **의도한 것이다**(실험용이 앱을 잡아끌지 않게).
//
//  ── 무엇을 재는 도구인가 ────────────────────────────────────────
//  같은 목록을 **여러 꼴(A~L)로 나란히 그려** 놓고, UI 시험으로 **끌다가 멈추게** 한 뒤
//  그 사이 스크린샷을 `measure-frames.swift`로 픽셀 판정한다.
//  「누르면 나오고 안 누르면 안 나오는」 결함을 **사람 손 없이 재현**하는 것이 목적이다.
//
//  ── ★ 이번에 이 장치로 갈린 것 (전말: docs/worklog/2026-08-20-macbook.md) ──
//  ① **잔상** — *"살짝 이동하면 그 아래에 기존 잔상이 남아 있어"*.
//     **두 번 시도하고 「이 구조에서는 안 된다」로 닫아 뒀던 자리를 뒤집었다.**
//     재현 조건이 **「첫 교체 전」**이라는 것을 여기서 찾았다 — 크게 끌면 안 보이고 **22pt**면 나온다.
//  ② **편집모드는 답이 아니다** — 같은 조건으로 셋을 재니
//     `List`+`.onMove` ⛔ · **`editMode = .active`도 똑같이 ⛔** · `UICollectionView` 대화식 이동 ✅.
//     **문서 여러 곳에 「편집 모드 버튼을 두면 된다」고 적혀 있던 안이 이 표에서 죽었다.**
//     (그게 없었으면 손잡이만 되살리고 잔상은 그대로 남는 길로 갔다.)
//  ③ `UIHostingConfiguration`이 **Dynamic Type를 안 끊는다**(XXL에서 둘 다 `callout=20.0pt`) —
//     「글자가 작아진 건 셀 탓」이라는 가설을 버렸다.
//  ④ `List`가 **스스로 주는 세로 여백 = 한쪽 15pt**(줄에 적힌 5pt와 별개). 이걸 몰라 새 여백을
//     6으로 잡았고 **한 줄마다 28pt 좁았다.**
//  ⑤ **좌우 맞춤**: SwiftUI `Text` ⛔ · `AttributedString` 문단 정렬도 **무시됨** ⛔ ·
//     `UILabel(textAlignment: .justified)` ✅.
//
//  ── ⛔ 판정할 때 걸린 함정 둘 (README에 자세히) ──────────────────────
//  · **촬영 루프를 개수로 끊으면** 끌기 전에 끝나서 「끌기가 안 된다」로 잘못 읽는다.
//  · **`Test Case … passed`는 「안 죽었다」가 아니다** — 마지막 동작 뒤 앱이 죽어도 통과로 적는다.
//    `unexpected termination`과 `~/Library/Logs/DiagnosticReports`를 함께 봐야 한다.
//
import SwiftUI

@main
struct GhostLabApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}

struct Row: Identifiable, Hashable {
    let id: String
    let label: String
    let color: Color
}

let seed: [Row] = [
    Row(id: "A", label: "AAAA 첫째줄", color: .red),
    Row(id: "B", label: "BBBB 둘째줄", color: .orange),
    Row(id: "C", label: "CCCC 셋째줄", color: .green),
    Row(id: "D", label: "DDDD 넷째줄", color: .blue),
    Row(id: "E", label: "EEEE 다섯째줄", color: .purple),
]

enum Mode: String, CaseIterable, Identifiable {
    case plain   = "A 기본"        // List + onMove  (지금 앱과 같은 꼴)
    case edit    = "B 편집모드"     // List + onMove + editMode active
    case onDrag  = "C onDrag"      // List + onMove + onDrag (오늘 뺀 꼴)
    case real    = "D 실제꼴"        // NavigationStack + NavigationLink + listRowBackground
    case noLink  = "E 링크뺌"        // D에서 NavigationLink만 뺐다
    case replica = "F 복제"          // PrincipleListView 정밀 복제
    case repEdit = "G 복제편집"       // 복제 + 편집모드(고전 순서 바꾸기)
    case uikit   = "H UIKit"         // UICollectionView 대화식 이동
    case probe   = "I 글자"          // 글자 크기 계측
    case gap     = "J 여백"          // 줄 간격 계측
    case card    = "K 카드"          // 새 카드 모양
    case just    = "L 맞춤"          // 좌우 맞춤 넷 — 표본 ①(62자)
    case just2   = "M 맞춤2"         // 좌우 맞춤 넷 — 표본 ②(102자)
    case punct   = "N 금칙"          // 부호가 줄 앞으로 넘어가나 (전략 셋)
    case rules   = "O 원칙"          // ★ 줄바꿈 원칙 셋 — **앱 코드 그대로**
    case editBox = "P 편집"          // 원문 편집 칸이 가로로 안 늘어나나
    var id: String { rawValue }

    /// ★ **화면을 눌러서 고르는 것을 CLI로 고른다** (2026-08-21 신설).
    /// `xcrun simctl launch <udid> kr.teri.GhostLab -ghostmode L` 처럼 준다.
    /// ⚠️ 이 맥북에서는 `sim-input.swift`(CGEvent)가 막혀 있다 — 시뮬 창이 39×135로 줄어 있고
    /// `System Events`가 창을 못 본다. **탭 없이 꼴을 고르려면 이 길뿐이다.**
    static var fromLaunchArgs: Mode? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-ghostmode"), i + 1 < args.count else { return nil }
        let want = args[i + 1]
        return allCases.first { $0.rawValue.hasPrefix(want) }
    }
}

struct ContentView: View {
    @State private var mode: Mode = Mode.fromLaunchArgs ?? .plain
    @State private var rows = seed

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).padding(8)

            switch mode {
            case .plain:  list(edit: false, drag: false)
            case .edit:   list(edit: true,  drag: false)
            case .onDrag: list(edit: false, drag: true)
            case .real:   realList
            case .noLink: noLinkList
            case .replica: ReplicaList()
            case .repEdit: ReplicaList(edit: true)
            case .uikit:   UIKitListScreen()
            case .probe:   FontProbe()
            case .gap:     GapProbe()
            case .card:    CardProbe()
            case .just:    JustifyProbe(sample: .parking)
            case .just2:   JustifyProbe(sample: .morning)
            case .punct:   PunctProbe()
            case .rules:   RulesProbe()
            case .editBox: EditProbe()
            }
        }
    }

    /// 진짜 앱(PrincipleListView)과 같은 꼴 — NavigationStack + NavigationLink + listRowBackground.
    private var realList: some View {
        NavigationStack {
            List {
                ForEach(Array(rows.enumerated()), id: \.element.id) { _, r in
                    NavigationLink(value: r.id) {
                        HStack(spacing: 10) {
                            Rectangle().fill(r.color).frame(width: 26, height: 26)
                            Text(r.label).font(.title3.weight(.bold))
                        }
                        .padding(.vertical, 5)
                    }
                    .listRowBackground(Color.white)
                    .listRowSeparator(.hidden)
                }
                .onMove { from, to in rows.move(fromOffsets: from, toOffset: to) }
            }
            .listStyle(.plain)
            .navigationDestination(for: String.self) { Text($0) }
        }
    }

    /// D에서 **NavigationLink만** 뺐다 — 나머지(NavigationStack·listRowBackground·구분선 숨김)는 같다.
    private var noLinkList: some View {
        NavigationStack {
            List {
                ForEach(Array(rows.enumerated()), id: \.element.id) { _, r in
                    HStack(spacing: 10) {
                        Rectangle().fill(r.color).frame(width: 26, height: 26)
                        Text(r.label).font(.title3.weight(.bold))
                    }
                    .padding(.vertical, 5)
                    .listRowBackground(Color.white)
                    .listRowSeparator(.hidden)
                }
                .onMove { from, to in rows.move(fromOffsets: from, toOffset: to) }
            }
            .listStyle(.plain)
        }
    }

    @ViewBuilder
    private func list(edit: Bool, drag: Bool) -> some View {
        let l = List {
            ForEach(Array(rows.enumerated()), id: \.element.id) { _, r in
                HStack(spacing: 10) {
                    Rectangle().fill(r.color).frame(width: 26, height: 26)
                    Text(r.label).font(.title3.weight(.bold))
                }
                .padding(.vertical, 5)
                .modifier(MaybeDrag(on: drag, id: r.id))
            }
            .onMove { from, to in rows.move(fromOffsets: from, toOffset: to) }
        }
        .listStyle(.plain)

        if edit { l.environment(\.editMode, .constant(.active)) } else { l }
    }
}

/// C안에서만 `.onDrag`를 얹는다 — 오늘 뺀 그 꼴을 재현하려는 것.
struct MaybeDrag: ViewModifier {
    let on: Bool
    let id: String
    func body(content: Content) -> some View {
        if on { content.onDrag { NSItemProvider(object: NSString(string: id)) } }
        else { content }
    }
}
