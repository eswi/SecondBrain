import Foundation
import SecondBrainCore
import CoreLocation
import ImageIO
import UniformTypeIdentifiers
#if os(iOS)
import UIKit
#endif

/// 원본 사진 파일 저장소 — 항목 UUID로 이름 붙인 `.jpg`를 관리한다. **음성 `AudioStore`의 미러.**
/// 원칙: **원본 미디어는 불변(write-once) · 텍스트 층만 가변**(edit-policy §6).
/// 사진의 "원본"은 **캡처 시 1회 리사이즈·압축한 그 파일**이다(무손실 아님 — 설계
/// `docs/native/photo-capture-design.md` §4-④). 한 번 확정하면 다신 안 건드린다.
///
/// **확정은 지금도 로컬에만 한다**(앱 샌드박스). GPS는 사진 EXIF에만 두고 그릇엔 안 박아 누출을 막는다(§5, Stage 3).
///
/// ⚠️ **옛 서술이 뒤집혔다 (2026-08-19)** — `AudioStore` 머리주석과 같은 내용이다.
/// *"`searchDirs()`로 추상화 → 나중 iCloud를 표시에 자동 반영"* 은 안 된다(보안 스코프·자리 계산).
/// iCloud는 `MediaCloud`가 따로 보고 찾는 순서가 **[로컬, iCloud]**로 갈렸다(설계 §4).
/// **유지되는 것:** 확정 목적지는 로컬 · 포인터 필드 `photo:`는 파일명만 담는 성역.
enum PhotoStore {
    /// 포인터 필드 값 = 파일명. 항목 id와 1:1(결정적). 지금은 한 장(`<id>.jpg`).
    static func filename(forId id: String) -> String { "\(id).jpg" }

    // MARK: 디렉터리

    /// 로컬(기기 전용) 사진 디렉터리. 없으면 만든다. 실패 시 nil.
    private static func localPhotoDir() -> URL? {
        let fm = FileManager.default
        guard let base = try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                     appropriateFor: nil, create: true) else { return nil }
        let dir = base.appendingPathComponent("SecondBrain/photo", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// id로 사진을 찾을 때 탐색할 **로컬** 위치들.
    ///
    /// ⚠️ **iCloud는 여기 들어오지 않는다** — 보안 스코프와 자리 계산이 필요해 URL 목록으로 안 담긴다.
    /// iCloud 쪽은 `MediaCloud`가 따로 본다(설계 §4 · 2026-08-19). 음성과 동형.
    /// **찾는 순서 = [로컬, iCloud]** — 로컬이 바이트가 반드시 있는 층이라 먼저다.
    private static func searchDirs() -> [URL] {
        [localPhotoDir()].compactMap { $0 }
    }

    // MARK: 임시(캡처 중) — 촬영 시 임시 저장 → [저장] 때 확정 / [취소] 때 삭제

    /// 새 캡처 세션용 임시 파일 URL.
    static func newTempURL(sessionId: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("sb-photo-\(sessionId).jpg")
    }

    /// 임시 파일 삭제([취소]/미저장 종료/다시 찍기 시).
    static func deleteTemp(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: 확정(불변) · 조회

    /// 임시 파일을 `<id>.jpg`로 확정(이동). 이후 재오픈 없음 = **write-once·불변**.
    /// 성공 시 저장할 포인터 파일명 반환, 실패/파일없음이면 nil(→ 항목은 사진 없이 생성).
    @discardableResult
    static func finalize(temp: URL, forId id: String) -> String? {
        guard let dir = localPhotoDir() else { return nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: temp.path) else { return nil }
        let dest = dir.appendingPathComponent(filename(forId: id))
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }  // UUID 충돌 방어
            try fm.moveItem(at: temp, to: dest)
            return filename(forId: id)
        } catch {
            return nil
        }
    }

    /// 이 기기에서 볼 수 있는 사진 파일 URL. nil이면 다른 기기에서 촬영됨(미동기화).
    static func url(forId id: String) -> URL? {
        let name = filename(forId: id)
        let fm = FileManager.default
        for dir in searchDirs() {
            let u = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: u.path) { return u }   // 로컬은 dataless가 없다 = 있으면 곧 바이트가 있다
        }
        // 로컬에 없으면 iCloud — **바이트가 있는 것만** 돌려준다(§0-B의 「이름만 있는 파일」을 걸러낸다).
        return MediaCloud.readableURL(.photo, id: id)
    }

    /// **세 갈래 판정** (§4) — 「여기 있다」 · 「아직 안 받았다」 · 「어디에도 없다」.
    /// `url(forId:)`는 「볼 수 있나」만 답하므로 **뒤의 둘을 못 가른다.** 화면이 그 둘을 갈라 말해야 한다.
    static func availability(forId id: String) -> MediaAvailability {
        let fm = FileManager.default
        let name = filename(forId: id)
        // 로컬이 먼저 — 여기서 잡히면 iCloud I/O를 **아예 하지 않는다**(폰의 정상 경로).
        if searchDirs().contains(where: { fm.fileExists(atPath: $0.appendingPathComponent(name).path) }) {
            return .here
        }
        let c = MediaCloud.cloudFacts(.photo, id: id)
        return MediaAvailabilityJudge.status(localExists: false,
                                            cloudNameExists: c.nameExists,
                                            cloudBytesPresent: c.bytesPresent)
    }

    // MARK: 촬영 이미지 저장 (음성엔 없던 것 — 리사이즈·압축 + EXIF GPS)

    #if os(iOS)
    /// 촬영한 원본 이미지를 **긴 변 ~2048px 리사이즈 + JPEG 품질 0.7**로 임시 파일에 저장.
    /// `location`이 있으면 **EXIF GPS 태그에 직접 박는다**(사진 안에만 · 그릇엔 안 감 — §5, Stage 3).
    /// 이 압축본이 §4-④의 불변 원본. 성공 시 임시 URL, 실패 시 nil.
    static func saveCaptured(_ image: UIImage, location: CLLocation?, sessionId: String) -> URL? {
        // 방향 정규화 + 리사이즈(항상 재렌더 → orientation upright, EXIF 회전 불필요).
        guard let cg = normalized(image, maxEdge: 2048).cgImage else { return nil }
        let url = newTempURL(sessionId: sessionId)
        guard let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.7]
        if let loc = location { props[kCGImagePropertyGPSDictionary] = gpsDictionary(loc) }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return url
    }

    /// 긴 변이 maxEdge보다 크면 비율 유지 축소. **항상 재렌더**해 카메라 방향 메타를 픽셀로 굽는다(upright).
    private static func normalized(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let longest = max(w, h)
        guard longest > 0 else { return image }
        let scale = longest > maxEdge ? maxEdge / longest : 1
        let newSize = CGSize(width: w * scale, height: h * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1                                   // 픽셀 크기 = 논리 크기(과대 렌더 방지)
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }

    /// CLLocation → EXIF GPS 딕셔너리(위/경도 + 반구 ref, 고도 있으면).
    private static func gpsDictionary(_ loc: CLLocation) -> [CFString: Any] {
        let lat = loc.coordinate.latitude, lon = loc.coordinate.longitude
        var d: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: abs(lat),
            kCGImagePropertyGPSLatitudeRef: lat >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude: abs(lon),
            kCGImagePropertyGPSLongitudeRef: lon >= 0 ? "E" : "W",
        ]
        if loc.verticalAccuracy >= 0 {
            d[kCGImagePropertyGPSAltitude] = abs(loc.altitude)
            d[kCGImagePropertyGPSAltitudeRef] = loc.altitude >= 0 ? 0 : 1
        }
        return d
    }
    #endif

    // MARK: EXIF GPS 읽기 (볼 때 — 그릇엔 없음, 사진에서만)

    /// 사진 파일 EXIF의 촬영 좌표. 없으면(권한 거부·실내 등) nil. 온디바이스.
    static func coordinate(forId id: String) -> CLLocationCoordinate2D? {
        guard let url = url(forId: id),
              let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let gps = props[kCGImagePropertyGPSDictionary] as? [CFString: Any],
              let lat = gps[kCGImagePropertyGPSLatitude] as? Double,
              let lon = gps[kCGImagePropertyGPSLongitude] as? Double else { return nil }
        let latRef = gps[kCGImagePropertyGPSLatitudeRef] as? String ?? "N"
        let lonRef = gps[kCGImagePropertyGPSLongitudeRef] as? String ?? "E"
        return CLLocationCoordinate2D(latitude: latRef == "S" ? -lat : lat,
                                      longitude: lonRef == "W" ? -lon : lon)
    }
}
