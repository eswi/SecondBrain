import SwiftUI
import UniformTypeIdentifiers
import SecondBrainCore

/// 받은함 화면. 고른 iCloud 폴더의 조각들을 병합해 표시하고, 스와이프로 항목 행동(삭제·완료·미루기).
/// 행동은 이 기기 조각(`inbox-<deviceId>.md`)에 이벤트로 append되고 즉시 재병합돼 반영된다.
struct InboxListView: View {
    @StateObject private var model = InboxModel()
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            Group {
                if model.needsFolder {
                    folderPrompt
                } else {
                    list
                }
            }
            .navigationTitle("받은함")
            .toolbar {
                Button {
                    showPicker = true
                } label: {
                    Label("폴더", systemImage: "folder")
                }
            }
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.setFolder(url) }
        }
        .onAppear { model.load() }
    }

    // 폴더 미선택 안내
    private var folderPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark").font(.system(size: 44)).foregroundStyle(.secondary)
            Text("받은함 폴더를 선택하세요").font(.headline)
            Text("iCloud Drive의 SecondBrain 폴더를 고르면\ninbox.md와 조각 파일들을 함께 읽습니다.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("폴더 선택") { showPicker = true }.buttonStyle(.borderedProminent)
        }
        .padding()
    }

    private var list: some View {
        List {
            Section(header: header) {
                ForEach(model.visible, id: \.id) { item in
                    row(item)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { model.delete(item) } label: {
                                Label("삭제", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading) {
                            Button { model.markDone(item) } label: {
                                Label("완료", systemImage: "checkmark")
                            }.tint(.green)
                            Button { model.defer7(item) } label: {
                                Label("미루기", systemImage: "clock")
                            }.tint(.orange)
                        }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(model.visible.count)개"
                 + (model.deletedCount > 0 ? " · \(model.deletedCount) 삭제" : "")
                 + (model.doneCount > 0 ? " · \(model.doneCount) 완료" : ""))
            Text("기기 \(model.deviceId) · \(model.sourceLabel)")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func row(_ it: ResolvedItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(it.raw ?? "(내용 없음)").font(.body).lineLimit(3)
            Text(caption(it)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func caption(_ it: ResolvedItem) -> String {
        var parts = [it.source ?? "?",
                     "\(it.date ?? "") \(it.time ?? "")".trimmingCharacters(in: .whitespaces),
                     it.type ?? "미분류"]
        if let due = it.due, due != "none", !due.isEmpty { parts.append("~\(due)") }
        if let rs = it.resurface, rs != "weekly", !rs.isEmpty { parts.append("↻\(rs)") }
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
