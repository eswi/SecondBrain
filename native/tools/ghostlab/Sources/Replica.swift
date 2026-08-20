import SwiftUI

/// **PrincipleListView 정밀 복제** — 다크 팔레트 · Section 머리글 · 여러 줄 문장 ·
/// listRowBackground · scrollContentBackground 숨김 · opacity · contentShape.
/// 실험용 앱의 A~E가 못 닮았던 것들을 전부 넣는다.
enum P {
    static let bg            = Color(red: 0x13/255, green: 0x12/255, blue: 0x18/255)
    static let surface       = Color(red: 0x1D/255, green: 0x1B/255, blue: 0x25/255)
    static let textPrimary   = Color(red: 0xEC/255, green: 0xEB/255, blue: 0xF1/255)
    static let textSecondary = Color(red: 0xA7/255, green: 0xA4/255, blue: 0xB3/255)
    static let textTertiary  = Color(red: 0x74/255, green: 0x6F/255, blue: 0x82/255)
}

struct ReplicaRow: Identifiable, Hashable {
    let id: String
    let mark: Color
    let text: String
}

let replicaSeed: [ReplicaRow] = [
    ReplicaRow(id: "R1", mark: .red,
               text: "AAAA 첫째줄 — 이 문장은 일부러 길게 써서 두 줄 이상으로 접히게 만든 것이다. 여러 줄로 접히는 줄이 범인인지 보려는 것."),
    ReplicaRow(id: "R2", mark: .orange,
               text: "BBBB 둘째줄 — 이것도 길게 써서 접히게 한다. 실제 원칙 문장들이 대체로 이 정도 길이다."),
    ReplicaRow(id: "R3", mark: .green,
               text: "CCCC 셋째줄 — 세 번째 줄도 마찬가지로 여러 줄이 되도록 길게 적어 둔다."),
    ReplicaRow(id: "R4", mark: .blue,  text: "DDDD 넷째줄 — 짧은 줄"),
    ReplicaRow(id: "R5", mark: .purple, text: "EEEE 다섯째줄 — 짧은 줄"),
]

struct ReplicaList: View {
    var edit = false
    @State private var rows = replicaSeed
    private let activeN = 3

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, r in
                        NavigationLink(value: r.id) {
                            row(r, active: idx < activeN)
                        }
                        .listRowBackground(P.bg)
                        .listRowSeparator(.hidden)
                    }
                    .onMove { from, to in rows.move(fromOffsets: from, toOffset: to) }
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("아래 \(activeN)개가 원칙 영역에 노출됩니다")
                        Text("눌러 끌어서 순서를 바꾸세요")
                    }
                    .font(.footnote).foregroundStyle(P.textSecondary).textCase(nil)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(P.bg.ignoresSafeArea())
            .navigationTitle("원칙")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: String.self) { Text($0) }
            .environment(\.editMode, .constant(edit ? .active : .inactive))
        }
    }

    private func row(_ item: ReplicaRow, active: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            // 진짜는 star.fill(caption2)이다. 재는 표적을 크게 하려고 사각형으로 둔다.
            Rectangle().fill(item.mark).frame(width: 22, height: 22).padding(.top, 3)
            Text(item.text)
                .font(.callout.weight(.medium)).foregroundStyle(P.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !active {
                Text("대기").font(.caption2).foregroundStyle(P.textTertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(P.surface, in: Capsule())
            }
        }
        .padding(.vertical, 5)
        .opacity(active ? 1 : 0.55)
        .contentShape(Rectangle())
    }
}
