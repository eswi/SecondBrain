import SwiftUI
import SecondBrainCore

/// 여러 기기별 조각 파일(`inbox*.md`)을 읽어 **합치기 엔진으로 병합**한 받은함을 표시.
/// 우선순위: 앱 Documents의 조각들(실데이터) → 없으면 번들 데모 조각. (iCloud 연결은 다음 단계.)
struct InboxListView: View {
    @State private var items: [ResolvedItem] = []
    @State private var deletedCount = 0
    @State private var sourceLabel = ""

    var body: some View {
        NavigationStack {
            List {
                Section(header: header) {
                    ForEach(items, id: \.id) { item in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.raw ?? "(내용 없음)").font(.body).lineLimit(3)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(items.count)개" + (deletedCount > 0 ? " · \(deletedCount) 삭제 숨김" : ""))
            Text(sourceLabel).font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func caption(_ it: ResolvedItem) -> String {
        var parts = [it.source ?? "?", "\(it.date ?? "") \(it.time ?? "")".trimmingCharacters(in: .whitespaces), it.type ?? "미분류"]
        if let due = it.due, due != "none", !due.isEmpty { parts.append("~\(due)") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func load() {
        // 1) 앱 Documents의 실제 조각 파일들
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let (result, files) = InboxStore.loadDirectory(docs)
            if !files.isEmpty {
                items = result.live; deletedCount = result.deleted.count
                sourceLabel = "조각 \(files.count): " + files.joined(separator: ", ")
                return
            }
        }
        // 2) 번들 데모 조각(2기기) — 실데이터 없을 때
        var texts: [String] = []
        var names: [String] = []
        for n in ["inbox-iphone", "inbox-mac"] {
            if let u = Bundle.main.url(forResource: n, withExtension: "md"),
               let t = try? String(contentsOf: u, encoding: .utf8) {
                texts.append(t); names.append("\(n).md")
            }
        }
        let r = InboxStore.merge(fragmentTexts: texts)
        items = r.live; deletedCount = r.deleted.count
        sourceLabel = "번들 데모 조각: " + names.joined(separator: ", ")
    }
}
