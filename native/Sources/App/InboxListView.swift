import SwiftUI
import SecondBrainCore

/// 조각 파일 하나를 읽어 받은함 항목을 리스트로 보여준다 (Phase 1 뼈대).
/// 실제 iCloud 조각 파일 읽기·합치기·항목 행동은 다음 단계. 지금은 번들 샘플로 Core↔UI 연결 검증.
struct InboxListView: View {
    @State private var items: [InboxItem] = []
    @State private var sourceLabel = ""

    var body: some View {
        NavigationStack {
            List {
                Section("\(items.count)개 · \(sourceLabel)") {
                    ForEach(items, id: \.id) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.raw).font(.body).lineLimit(3)
                            Text(caption(item)).font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("받은함")
        }
        .onAppear(perform: load)
    }

    private func caption(_ it: InboxItem) -> String {
        var parts = [it.source, "\(it.date) \(it.time)", it.type ?? "미분류"]
        if let due = it.due, due != "none" { parts.append("~\(due)") }
        return parts.joined(separator: " · ")
    }

    private func load() {
        if let url = Bundle.main.url(forResource: "inbox-sample", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            items = FragmentParser.parse(text, sourceFile: "inbox-sample.md")
            sourceLabel = "번들: inbox-sample.md"
        } else {
            items = FragmentParser.parse(Self.embeddedSample, sourceFile: "embedded")
            sourceLabel = "내장 샘플"
        }
    }

    private static let embeddedSample = """
    - 2026-07-15 09:00 | voice | 내일까지 조직도 셋업 (번들 못 찾음 폴백)
      type: promise
      due: 2026-07-16
    - 2026-07-15 09:10 | voice | 아직 분류 안 된 줄
    """
}
