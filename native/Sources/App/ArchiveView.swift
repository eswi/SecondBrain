import SwiftUI
import SecondBrainCore

/// "보관된 기억" — 흐름에서 빠진 것(memory-philosophy.md §2-3).
/// 완료 = 해냈다(기억할 가치) / 삭제 = 버린다. 같은 "빠짐"이지만 의미가 반대.
/// 뷰 옵션: 완료된 기억(기본) / 삭제된 기억 / 모든 기억.
/// (완전 삭제는 edit-policy.md §8 보류 — 엔진 hard-delete + 재확인 확정 후.)
struct ArchiveView: View {
    @ObservedObject var model: InboxModel

    enum ViewOption: String, CaseIterable, Identifiable {
        case done = "완료된 기억"
        case trashed = "삭제된 기억"
        case all = "모든 기억"
        var id: String { rawValue }
    }
    @State private var option: ViewOption = .done
    /// **해시태그 필터**(2026-09-22 사용자 결정 · 정본 `tag-filter-design.md`) — 「완료된/삭제된/모든 기억」을 거친 목록에서(§2 20번).
    @State private var tagFilter = TagFilter()
    @State private var showTagPanel = false
    @AppStorage(EdgeHandle.topStorageKey) private var edgeHandleTop: Double = -1

    private var items: [ResolvedItem] {
        switch option {
        case .done:    return model.doneItems
        case .trashed: return model.trashed
        case .all:     return model.doneItems + model.trashed
        }
    }
    private var tagCandidates: [String] { TagFilter.available(in: items) }
    private var shown: [ResolvedItem] { tagFilter.pruned(to: tagCandidates).apply(items) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenTitle("보관된 기억")     // 제목 서식은 다섯 화면이 함께 쓴다(`ScreenTitle`)
                Picker("보기", selection: $option) {
                    ForEach(ViewOption.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 4)

                Group {
                    if items.isEmpty {   // ⚠️ 태그 필터 전 기준 — 필터로 전부 숨었을 때는 빈 목록(설계 §2 17번 · 「비었어요」는 다른 뜻이다)
                        VStack(spacing: 10) {
                            Spacer()
                            Image(systemName: "archivebox").font(.system(size: 40)).foregroundStyle(Palette.textTertiary)
                            Text("비었어요").font(.callout).foregroundStyle(Palette.textSecondary)
                            Spacer()
                        }
                    } else {
                        List {
                            ForEach(shown, id: \.id) { item in
                                row(item)
                                    .swipeActions(edge: .leading) {
                                        Button { restore(item) } label: { Label("되돌리기", systemImage: "arrow.uturn.backward") }
                                            .tint(Palette.accent)
                                    }
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                        .background(Palette.bg)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    // 해시태그 필터 손잡이·패널(2026-09-22) — 목록 영역에 얹는다(제목·구분 선택은 안 덮는다).
                    if !items.isEmpty {
                        TagFilterDock(topOffset: $edgeHandleTop, filter: $tagFilter, isOpen: $showTagPanel, items: items)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.bg.ignoresSafeArea())
            .hiddenNavBar()
            .landscapeEdge()               // 제목은 위 `ScreenTitle`이 그린다 — 시스템 큰 제목과 겹치면 안 된다
        }
    }

    /// 완료/삭제 각각의 되돌리기 경로로 라우팅(항목이 done인지 삭제인지로 판별).
    private func restore(_ item: ResolvedItem) {
        if item.deleted || item.type == "discard" { model.restoreFromTrash(item) }
        else { model.restore(item) }
    }

    private func row(_ item: ResolvedItem) -> some View {
        let expired = isExpiredNow(item)   // 유효 기간 지난 정보 = 아이콘·텍스트 회색(2026-09-14) — 보관함도 같은 판정
        return HStack(spacing: 10) {
            TypeGlyph(type: item.type, dimmed: expired)
            VStack(alignment: .leading, spacing: 3) {
                // 좌우 맞춤(2026-08-21) — 보관함도 원문이 보이는 곳이다.
                JustifiedText(text: item.raw ?? "", style: .callout,
                              weight: .regular, color: expired ? Palette.textTertiary : Palette.textSecondary, maxLines: 2)
                // 캡션 색 = 이 화면 원문과 같은 textSecondary(밝게). 크기(.caption2)로 비중은 유지, 색만 올린다.
                itemCaptionText(item).font(.caption2).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(item.deleted || item.type == "discard" ? "삭제" : "완료")
                .font(.caption2).foregroundStyle(Palette.textTertiary)
        }
        .listRowBackground(Palette.bg)
        .listRowSeparator(.hidden)
    }
}
