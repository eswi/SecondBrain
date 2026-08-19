import Foundation

/// **지도 앱을 여는 링크** — 사진 EXIF 좌표를 Apple 지도에서 보여준다.
///
/// ## 왜 Core에 있나 — 조용히 틀리는 자리가 둘이라서
///
/// 이 URL은 **눈으로 검사할 수 없다.** 열리기는 하니까 「됐다」로 보이고, 틀린 것은
/// **핀이 없다**는 것뿐이다. 실제로 그렇게 **2026-07-19부터 2026-08-20까지 틀린 채로 있었다.**
///
/// | 조용히 틀리는 방식 | 무엇이 보이나 |
/// |---|---|
/// | `q`(이름)를 안 준다 | 지도 앱이 **열리고 그 위치로 가는데 핀이 없다** ← 옛 결함 |
/// | 한글 이름을 인코딩 안 한다 | `URL(string:)`이 **nil** → 버튼이 **아무 일도 안 한다** ← 고치다 만들 수 있는 결함 |
///
/// **둘 다 오류도 로그도 안 남는다.** 그래서 판정을 Core로 올려 **시험이 못박는다.**
public enum MapsLink {

    /// 그 좌표에 **이름 붙은 핀**을 놓는 지도 앱 링크.
    ///
    /// - `ll`: 지도를 옮길 위치. **이것만 주면 핀이 안 놓인다.**
    /// - `q`: 핀의 **이름.** Apple 지도는 `ll`과 함께 오는 `q`를 그 자리의 라벨로 쓴다.
    ///   값은 사용자가 고른 말(`MediaMigrationText.photoPinName`)이라 **여기서 짓지 않는다.**
    ///
    /// `URLComponents`로 만든다 — **문자열 조립은 한글에서 nil이 된다**(위 표).
    public static func pin(latitude: Double, longitude: Double,
                           name: String = MediaMigrationText.photoPinName) -> URL? {
        var c = URLComponents()
        c.scheme = "https"
        c.host = "maps.apple.com"
        c.path = "/"
        c.queryItems = [
            URLQueryItem(name: "ll", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "q", value: name),
        ]
        return c.url
    }
}
