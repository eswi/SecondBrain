import SwiftUI
import UniformTypeIdentifiers
import SecondBrainCore

extension View {
    /// 그룹 리스트 스타일 — iOS는 insetGrouped, macOS는 지원되는 inset.
    /// (insetGrouped는 macOS 미지원 → 플랫폼별로 맞는 스타일을 쓴다.)
    @ViewBuilder func groupedListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }
}

/// 설정 — 폴더 연결·데이터 현황·앱 정보. (기존 "원칙" 탭 자리를 대체)
/// 수집([+])은 하단 버튼으로 풀지 않는다(별도 설계, 보류) — 이 탭은 운영·정보용.
struct SettingsView: View {
    @ObservedObject var model: InboxModel
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()
                List {
                    Section {
                        row("연결된 폴더", model.needsFolder ? "미선택" : model.sourceLabel)
                        Button {
                            showPicker = true
                        } label: {
                            Label(model.needsFolder ? "폴더 선택" : "폴더 변경", systemImage: "folder")
                                .foregroundStyle(Palette.accent)
                        }
                        .listRowBackground(Palette.surface)
                    } header: { header("데이터") }

                    Section {
                        row("총 기억", "\(model.totalMemoryCount)")
                        row("미기억 · 기억함", "\(model.unconfirmedCount) · \(model.confirmedCount)")
                        row("완료 · 삭제", "\(model.doneItems.count) · \(model.deletedCount)")
                        row("이 기기", model.deviceId)
                    } header: { header("현황") }

                    Section {
                        row("SecondBrain", "네이티브 v1")
                    } header: { header("앱") }
                }
                .groupedListStyle()
                .scrollContentBackground(.hidden)
                .background(Palette.bg)
            }
            .navigationTitle("설정")
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.setFolder(url) }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.textPrimary)
            Spacer()
            Text(value).foregroundStyle(Palette.textSecondary).font(.callout).lineLimit(1)
        }
        .listRowBackground(Palette.surface)
    }

    private func header(_ t: String) -> some View {
        Text(t).font(.caption).foregroundStyle(Palette.textTertiary).textCase(nil)
    }
}
