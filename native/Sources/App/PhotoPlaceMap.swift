import SwiftUI
import MapKit
import CoreLocation
import SecondBrainCore

//
//  PhotoPlaceMap — **사진 EXIF 좌표를 지도로** (2026-09-30 · 회사 맥북)
//
//  ── 어디서 왔나 ─────────────────────────────────────────────────
//  `DetailView.photoMap`이 **2026-08-23부터 아무도 안 부르는 채** 남아 있었다(자료가 보조 자료 카드로
//  나가면서 `photoRow`가 사라졌다). 그 주석: *"뷰어의 「위치 보기」가 이것을 쓴다(설계 §0 26번) ·
//  ⛔ 지우지 않는다 — 지도 핀 결함(27일 묵었던 것)을 고친 코드가 여기 있고, 다시 만들면 그 값을 잃는다."*
//  ✅ **그 자리가 왔다** — 사용자 2026-09-30: *"사진을 선택하여 '사진 뷰어'로 진입하면 그 화면의 적절한 곳에
//  위치정보 조회 버턴이 나타나게 하고, 그 버튼을 누르면 지도가 표시되는 등의 방법으로 위치를 보여줘."*
//  그래서 **옮겼다**(지우지 않았다 — 핀 이름 `MediaMigrationText.photoPinName`·`MapsLink`·`PlatformMedia.openInMaps`
//  그대로). 상세의 옛 자리에는 「여기로 옮겼다」만 남겼다(기록 규칙 9).
//
//  ── 화면에 나오는 말 ────────────────────────────────────────────
//  「지도 앱에서 열기」·핀 이름 「촬영 위치」 = **이미 있던 말**(항시 규칙 6 — 새로 짓지 않았다).
//
//  ── `interactive` ────────────────────────────────────────────────
//  상세(옛 자리)는 비상호작용이었다(작은 미리보기 · 스크롤과 싸우지 않게). **뷰어는 화면이 검고 스크롤이
//  없으므로** 손으로 옮기고 키울 수 있게 연다 — 주차 위치를 찾을 때 **주변을 보는 것**이 값이다(Claude 판단 ·
//  사용자가 뒤집을 수 있다).
//

struct PhotoPlaceMap: View {
    let coord: CLLocationCoordinate2D
    var height: CGFloat = 150
    var interactive: Bool = false

    var body: some View {
        let region = MKCoordinateRegion(center: coord,
                                        span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003))
        VStack(alignment: .leading, spacing: 6) {
            Map(initialPosition: .region(region), interactionModes: interactive ? [.pan, .zoom] : []) {
                Marker(MediaMigrationText.photoPinName, coordinate: coord)
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border))
            Button {
                PlatformMedia.openInMaps(coord)
            } label: {
                Label("지도 앱에서 열기", systemImage: "map").font(.caption)
            }
            .buttonStyle(.plain).foregroundStyle(Palette.accent)
        }
    }
}
