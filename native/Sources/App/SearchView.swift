import SwiftUI
import SecondBrainCore

/// 검색(pull) — **원문 또는 기억 ID** 부분일치로 걸러 본다(ID는 2026-08-28에 더했다). 대상은 **살아있는 것들**(원칙·새·살아있는·챙길것 + 완료).
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

    /// ①**원문 또는 기억 ID** 부분일치 후보(타입 필터 전). 필터 칩의 "실제 있는 분류"도 이 후보 기준으로 뽑는다.
    ///
    /// **ID로도 찾는다**(2026-08-28 사용자 결정): *"기억을 검색할 때 기억 ID로도 검색 가능하게 할 것임."*
    /// - **대소문자 무시 + 부분일치**(사용자가 고른 것) — `e036`·`E036A094`·`036A0` 모두 걸린다.
    /// - **전체 id에 대고 맞춘다**(보이는 앞 8자가 아니라) — 문서에서 전체 UUID를 붙여 넣어도 찾아진다.
    /// - 원문과 **합집합**이다. 짧은 질의(`e0`)는 양쪽에 걸릴 수 있는데, 그것이 「못 찾는 것」보다 낫다.
    private var hits: [ResolvedItem] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return (model.liveNonDone + model.doneItems).filter {
            ($0.raw ?? "").lowercased().contains(q) || $0.id.lowercased().contains(q)
        }
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
        // **문구 둘은 사용자가 골랐다**(2026-08-28) — ID로도 찾게 되면서 「원문…」이 사실과 어긋났다.
        // 자리표시자 「기억 검색」 · 빈 화면 안내 「기억 찾기」.
        .searchable(text: $query, prompt: "기억 검색")
    }

    @ViewBuilder private var resultsArea: some View {
        if !searching {
            hint.frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if results.isEmpty {
            Text("결과 없음").font(.callout).foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            // **한 번만 만든다** — 줄마다 부르면 `partition`이 그때마다 다시 돈다(InboxModel 주석).
            let screens = model.screenNames
            List(results, id: \.id) { item in
                NavigationLink(value: item) {
                    HStack(spacing: 10) {
                        TypeGlyph(type: item.type)
                        VStack(alignment: .leading, spacing: 3) {
                            // 좌우 맞춤(2026-08-21) — 검색도 원문이 보이는 곳이다.
                            JustifiedText(text: item.raw ?? "", style: .callout,
                                          weight: .regular, color: Palette.textPrimary, maxLines: 2)
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
                                // **가장 오른쪽 = 그 기억이 지금 있는 화면 이름**(2026-08-28 사용자 결정).
                                // *"현재 그 기억이 들어가 있는 화면의 이름을 표시하게 할 것임!"*
                                // **섹션 층**을 적는다(사용자가 고름) — 원한 것이 「어디 가면 찾을 수 있나」이므로.
                                // 이름·소속을 여기서 정하지 않는다 — `InboxModel.screenNames`가 진실원이다.
                                // 폭이 좁아지면 **왼쪽 날짜가 줄고 이 이름은 안 줄게** 우선순위를 준다.
                                //
                                // **색은 날짜와 원문의 중간이다 — `textSecondary`**(2026-08-29 사용자 확정).
                                // 시작: *"색이 회색이라 좀 흐리지만 나중에 고치겠음."*(08-28 01:3x)
                                //
                                // ⚠️ **세 값을 폰·시뮬에서 실제로 보고 고른 것이다 — 짐작이 아니다.**
                                // 잰 값(바탕 `bg` #131218 대비 · 픽셀 실측):
                                //   원문   `textPrimary`   #ECEBF1  L* 93.3  15.72:1
                                //   이 이름 `textSecondary` #A7A4B3  L* 68.0   7.63:1  ← **여기**
                                //   날짜   `textTertiary`  #746F82  L* 47.9   3.85:1  ← **안 건드렸다**
                                //
                                // **왕복이 있었다 — 되돌리려는 다음 세션을 위해 남긴다:**
                                //  ① `textTertiary`(날짜와 같은 색) → **흐리다**고 반려
                                //  ② `textSecondary` → *"덜 바꾼거네"* 로 반려(**원문 밝기로 올려라**)
                                //  ③ `textPrimary`(원문과 같은 밝기) → 폰에서 보고 **"너무 밝아"**
                                //  ④ → **다시 `textSecondary`.** 사용자가 *"날짜와 원문의 중간 정도"*로 정했다.
                                // ⛔ **②를 근거로 「더 올려야 한다」고 읽지 말 것** — ③에서 올려 봤고 되돌아왔다.
                                // ⛔ **날짜와 같게 만들지도 말 것**(①에서 반려됐다).
                                //
                                // ★ **왜 새 색을 안 만들었나:** 진짜 중간값은 #AEABB8(L* 70.6)인데
                                // `textSecondary`와 **L*로 2.6밖에 안 벌어진다.** 팔레트에 색을 하나 더
                                // 만들 값이 아니라고 보고 **이미 있는 토큰**을 썼다(사용자가 고름).
                                // 글자 크기는 `.caption2`로 남는다 — 바꾼 것은 밝기뿐이다.
                                if let screen = screens[item.id] {
                                    Text(screen).font(.caption2).foregroundStyle(Palette.textSecondary)
                                        .lineLimit(1).fixedSize().layoutPriority(1)
                                }
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
            Text("기억 찾기").font(.callout).foregroundStyle(Palette.textSecondary)
        }
    }
}
