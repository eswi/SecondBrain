import SwiftUI
import SecondBrainCore

/// 검색(pull) — 원문 부분일치로 걸러 본다. 대상은 **살아있는 것들**(원칙·새·살아있는·챙길것 + 완료).
/// 삭제·discard된 항목은 제외(되살리기는 보관된 기억 화면 몫 — 검색에서 상세로 열면 [삭제하기]가 애매).
///
/// - 결과 터치 → 상세 화면(DetailView 재사용).
/// - 검색창 아래 **필터 UI**(살아있는 기억과 같은 FilterChipsBar) — 단, 독립 상태(`filter`)에 물려
///   **검색 결과 전체**를 2단계로 거른다: ①원문 텍스트 일치로 후보 수집 → ②그 후보에 타입 필터.
/// - `query`·`filter`는 @State라 상세에서 돌아와도 검색어·결과·필터가 그대로 유지된다.
struct SearchView: View {
    @ObservedObject var model: InboxModel
    @State private var query = ""
    @State private var filter: TypeFilter = .all   // 살아있는 기억(model.filter)과 분리된 독립 필터

    private var searching: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// ①원문 부분일치 후보(타입 필터 전). 필터 칩의 "실제 있는 분류"도 이 후보 기준으로 뽑는다.
    private var hits: [ResolvedItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return (model.liveNonDone + model.doneItems).filter { ($0.raw ?? "").lowercased().contains(q) }
    }

    /// ①원문 부분일치 후보 → ②타입 필터. 필터는 특정 영역이 아니라 검색 결과 합집합에 적용된다.
    private var results: [ResolvedItem] {
        switch filter {
        case .all:            return hits
        case .type(let key):  return hits.filter { norm($0.type) == key }
        }
    }

    private func norm(_ t: String?) -> String? { (t?.isEmpty ?? true) ? nil : t }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if searching {   // 검색창 아래 필터 UI(살아있는 기억 재사용) — 실재 분류만
                    FilterChipsBar(filter: $filter, presentTypes: Array(Set(hits.map { norm($0.type) })))
                }
                resultsArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("검색")
            .navigationDestination(for: ResolvedItem.self) { DetailView(item: $0, model: model) }
        }
        .searchable(text: $query, prompt: "원문 검색")
    }

    @ViewBuilder private var resultsArea: some View {
        if !searching {
            hint.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            Text("결과 없음").font(.callout).foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(results, id: \.id) { item in
                NavigationLink(value: item) {
                    HStack(spacing: 10) {
                        TypeGlyph(type: item.type)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.raw ?? "").font(.callout).foregroundStyle(Palette.textPrimary).lineLimit(2)
                            // **「임시」는 캡션 줄(날짜) 오른쪽에 붙인다 (2026-08-18 사용자 결정).**
                            //
                            // **왜 원문 줄이 아닌가:** 검색 결과는 **확정된 기억이 훨씬 많다**
                            // (실데이터 189개 중 미확정 74개, 그중 66개는 이미 완료·삭제된 것).
                            // 「새 기억들」(`MemoryRow`)처럼 원문 줄에 붙이면 **소수를 위해 다수의 원문 자리를**
                            // 깎는다 — 그 줄은 `lineLimit(2)`라 잘리는 쪽이 언제나 원문이다.
                            // 캡션 줄은 날짜 한 조각뿐이라 **남는 폭이 크다.**
                            //
                            // **검색에 표시가 필요한 이유:** 검색은 `liveNonDone + doneItems` **전체**를 훑어
                            // **미확정도 걸린다.** 같은 항목이 「새 기억들」에는 배지와 함께 뜨는데
                            // 여기서는 표시 없이 떠서 **같은 것이 두 화면에서 달라 보였다**
                            // (`2026-08-14-macbook.md` §14-3·§14-4에서 걸린 구멍).
                            HStack(spacing: 6) {
                                Text(itemCaption(item)).font(.caption2).foregroundStyle(Palette.textTertiary).lineLimit(1)
                                if !item.confirmed { ProvisionalBadge() }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }
                .listRowBackground(Palette.bg)
                .listRowSeparatorTint(Palette.cardStroke)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
        }
    }

    private var hint: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundStyle(Palette.textTertiary)
            Text("원문으로 찾기").font(.callout).foregroundStyle(Palette.textSecondary)
        }
    }
}
