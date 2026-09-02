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
    /// **수집 때 이름을 만드는 자리** — `finalize`만 쓴다. `<항목id>.jpg`.
    ///
    /// ⛔ **조회는 이것을 안 쓴다**(2026-08-23 · C). 조회는 **포인터 값을 받는다**(`url(name:)` 등) —
    /// id에서 이름을 계산하는 것이 **「한 항목에 자료 하나」의 원인**이었다(제약 9-a).
    /// ⏸ **추가 기능(3단계)이 `<항목id>-<자료id>.jpg`를 만든다** — 그때 이 함수 밖에서 만든다(§3-W-6).
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

    /// 로컬에 있는 확정 사진 파일 전부 — **업로더의 차집합 왼쪽**(§3·§5).
    /// 임시 파일은 여기 안 들어온다(그쪽은 `temporaryDirectory`에 있다).
    static func localFiles() -> [URL] {
        guard let dir = localPhotoDir() else { return [] }
        let e = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        // ⚠️ 확장자 필터가 들여오기 임시 파일(`.part`)도 걸러낸다 — `AudioStore.localFiles()`의 주석 참고.
        return e.filter { $0.pathExtension == "jpg" && !MediaAdoptNaming.isPartName($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
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
    ///
    /// ## ⛔ **2026-08-30부터 아무도 부르지 않는다 — 지우지 않고 남긴다**
    /// 이것은 **성역(create 블록의 `photo`) 경로**였다. 수집 화면의 사진이 **op으로 옮겨가면서**
    /// (사용자 결정 2026-08-30 · `InboxModel.capture` 머리주석) **호출자가 0이 됐다.**
    /// **지금 쓰는 것은 `finalizeAdded`**(이름에 자료 id가 붙는 꼴 · §3-W-6)다.
    /// ⚠️ **읽는 쪽은 살아 있다** — 이 이름 꼴(`<id>.jpg`)로 저장된 **옛 파일이 실데이터에 그대로 있고**
    /// `MediaPointer`가 옛 단일 필드를 읽는다(§3-W-5). **그래서 이 함수의 「꼴」은 아직 정본이다.**
    /// ⛔ **지우면 그 꼴의 근거가 코드에서 사라진다** — `AudioStore.finalize`(음성 성역)와 짝으로 남긴다.
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

    /// **자료 추가로 붙이는 사진을 확정한다** — 이름은 **`<항목id>-<자료id>.jpg`**(§3-W-6).
    ///
    /// ⛔ **수집의 `finalize`와 다른 함수인 이유:** 수집은 **성역**(create 블록)에 찍고 이름이 `<항목id>.jpg`다.
    /// 추가는 **op으로 붙고**(성역 아니다 · 2026-08-23 사용자 결정 · 제약 10) 이름에 **자료 id가 들어간다.**
    /// ★ **그래서 한 항목에 여럿이 될 수 있다** — 자료 id가 UUID라 두 기기가 동시에 붙여도 안 겹친다.
    ///
    /// 돌려주는 값 = **포인터에 적을 파일명.** 실패면 nil(→ 이벤트를 안 쓴다).
    /// **파일은 write-once** — 확정한 뒤 다시 안 건드린다(`edit-policy.md` §6).
    @discardableResult
    static func finalizeAdded(temp: URL, itemId: String, assetId: String) -> String? {
        guard let dir = localPhotoDir() else { return nil }
        let fm = FileManager.default
        guard fm.fileExists(atPath: temp.path) else { return nil }
        let name = MediaPointer.filename(.photo, itemId: itemId, assetId: assetId)
        let dest = dir.appendingPathComponent(name)
        do {
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }   // 방어(자료 id 충돌은 사실상 없다)
            try fm.moveItem(at: temp, to: dest)
            return name
        } catch {
            return nil
        }
    }

    /// 이 기기에서 볼 수 있는 사진 파일 URL. **로컬만 본다.** `AudioStore.url(forId:)`의 미러 —
    /// **iCloud URL을 돌려주지 않는 이유는 그쪽 주석에 있다**(§2-A C안 · 2026-08-20).
    ///
    /// ## ★ 축이 「항목 id」에서 **「파일명」**으로 바뀌었다 (2026-08-23 · C · 설계 §3-X)
    /// 조회는 이제 **포인터 필드의 값**(= 파일명)을 받는다. **id에서 이름을 계산하지 않는다** —
    /// 그것이 「한 항목에 자료 하나」를 만들던 자리였다(제약 9-a·9-b).
    /// ⚠️ **옛 파일은 이름을 안 바꾼다** — 포인터 값이 `<항목id>.<확장자>`이므로 그대로 찾힌다(§6).
    static func url(name: String) -> URL? {
        let fm = FileManager.default
        for dir in searchDirs() {
            let u = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: u.path) { return u }   // 로컬은 dataless가 없다 = 있으면 곧 바이트가 있다
        }
        return nil
    }

    /// **사본을 버린다** — 자료 삭제 정본(`edit-policy.md` ③)의 뒷부분이다.
    ///
    /// > *"기억에서 떼는 것 **+ SecondBrain이 복사해 둔 사본을 버리는 것.** 복사 전 원본은 안 건드린다."*
    ///
    /// **2026-09-03 사용자 결정: 「정본 그대로 — 사본도 지운다」.**
    /// **로컬 사본**(`Application Support/SecondBrain/photo`)과 **iCloud 사본**(자리 둘 다) 모두 지운다.
    /// ⚠️ **자리를 둘 다 본다** — 하위 폴더와 루트에 흩어져 있을 수 있다(`MediaCloud.candidates`의 이유와 같다).
    /// **한쪽만 지우면 다음 실행이 남은 것을 「있다」로 읽는다.**
    ///
    /// ## ⛔ 받아들인 대가 — **다른 기기가 옛 사본을 들고 있으면 iCloud에 다시 올라올 수 있다**
    /// 업로더가 **op 로그를 안 보고 폴더에 있는 파일 전부**를 올린다
    /// (`media-icloud-design.md` §9 — 2026-08-19에 알고 받아들인 것).
    /// ✅ **그래도 화면에는 안 보인다** — **포인터를 이미 비웠기 때문**이다.
    /// 되살아나는 것은 **고아 파일**이고, `native/tools/media-audit.py`가 그것을 잡는다.
    /// ⛔ **「지워졌나」를 파일 존재로 판정하지 말 것** — 판정선은 **포인터**다.
    ///
    /// ⚠️ **원본 사진(앨범·카메라 롤)은 건드리지 않는다** — 우리가 만든 사본만 지운다.
    /// 확인 문구가 그것을 말한다(*"원본은 그대로 있어요"*).
    /// - Returns: 실제로 지운 개수 — **로컬·iCloud를 갈라 돌려준다**(0이어도 실패가 아니다).
    @discardableResult
    static func deleteCopies(name: String) -> (local: Int, cloud: Int) {
        let fm = FileManager.default
        var local = 0
        for dir in searchDirs() {
            let u = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: u.path), (try? fm.removeItem(at: u)) != nil { local += 1 }
        }
        let cloud = FragmentFolder.withFolder { folder -> Int in
            var n = 0
            for u in MediaCloud.candidates(.photo, name: name, folder: folder) {
                // ⚠️ **dataless여도 지운다** — 이름이 있으면 그것이 사본의 자리다(§0-B).
                if fm.fileExists(atPath: u.path), (try? fm.removeItem(at: u)) != nil { n += 1 }
            }
            return n
        } ?? 0
        return (local, cloud)
    }

    /// **iCloud에 바이트가 있고 로컬에 없으면 로컬로 들여온다**(§2-A C안). `AudioStore`의 미러.
    @discardableResult
    static func adoptFromCloudIfNeeded(name: String) -> Bool {
        let fm = FileManager.default
        let localExists = searchDirs().contains { fm.fileExists(atPath: $0.appendingPathComponent(name).path) }
        guard !localExists, let dir = localPhotoDir() else { return false }
        MediaCloud.sweepAdoptLeftovers(in: dir)
        return MediaCloud.adopt(.photo, name: name, intoDir: dir)
    }

    /// **세 갈래 판정** (§4) — 「여기 있다」 · 「아직 안 받았다」 · 「어디에도 없다」.
    /// `url(name:)`는 「볼 수 있나」만 답하므로 **뒤의 둘을 못 가른다.** 화면이 그 둘을 갈라 말해야 한다.
    static func availability(name: String) -> MediaAvailability {
        let fm = FileManager.default
        // 로컬이 먼저 — 여기서 잡히면 iCloud I/O를 **아예 하지 않는다**(폰의 정상 경로).
        if searchDirs().contains(where: { fm.fileExists(atPath: $0.appendingPathComponent(name).path) }) {
            return .here
        }
        let c = MediaCloud.cloudFacts(.photo, name: name)
        return MediaAvailabilityJudge.status(localExists: false,
                                            cloudNameExists: c.nameExists,
                                            cloudBytesPresent: c.bytesPresent)
    }

    /// **다른 형식의 이미지 파일을 JPEG로 옮긴다** — 앨범에서 온 HEIC를 위한 그물(2026-09-03).
    ///
    /// ⛔ **다시 렌더하지 않는다** — `CGImageDestinationAddImageFromSource`가 **픽셀과 메타를 함께**
    /// 옮기므로 **EXIF(촬영 위치·시각)가 살아 있다**(`saveCaptured`의 재렌더와 다른 길이다).
    /// ⚠️ **JPEG로 바꾸는 것 자체는 손실이다** — 그래서 **첫 길은 시스템 변환**이고 이것은 **둘째**다
    /// (`AlbumPicker` 머리주석).
    /// - Returns: 옮겼으면 `true`.
    static func transcodeToJPEG(from src: URL, to dest: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let out = CGImageDestinationCreateWithURL(
                dest as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        // 0.9 — `saveCaptured`와 같은 값을 쓴다(그쪽 주석에 근거가 있다).
        CGImageDestinationAddImageFromSource(
            out, source, 0, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        return CGImageDestinationFinalize(out)
    }

    // MARK: 촬영 이미지 저장 (음성엔 없던 것 — 리사이즈·압축 + EXIF GPS)

    #if os(iOS)
    /// 촬영한 원본 이미지를 **긴 변 ~2048px 리사이즈 + JPEG 품질 0.7**로 임시 파일에 저장.
    /// `location`이 있으면 **EXIF GPS 태그에 직접 박는다**(사진 안에만 · 그릇엔 안 감 — §5, Stage 3).
    /// 이 압축본이 §4-④의 불변 원본. 성공 시 임시 URL, 실패 시 nil.
    static func saveCaptured(_ image: UIImage, location: CLLocation?, sessionId: String) -> URL? {
        // 방향 정규화(항상 재렌더 → orientation upright, EXIF 회전 불필요).
        //
        // ⛔ **2026-08-23: 축소를 뺐다** — 옛 코드는 `maxEdge: 2048`로 줄였다.
        //    사용자 판정: *"현재 사진찍기 코드가 실기기가 만들어내는 사진 품질을 그대로 가지고 오는지
        //    혹은 해상도를 낮추어서 2048x1536으로 낮추어 가져오는 것인지 체크해서,
        //    **가능하다면 사진 품질을 그대로 유지**하게 해줘."*
        //    → **카메라가 준 픽셀 그대로 굽는다**(iPhone 16 Pro에서 4032×3024 · 12MP).
        //    ⚠️ **상한은 여기가 아니라 `UIImagePickerController`가 정한다** — 그 API는 **12MP**를 준다.
        //    48MP는 이 경로로 안 온다(`AVCapturePhotoOutput`으로 갈아타야 한다 · 이번 범위 밖).
        guard let cg = normalized(image, maxEdge: .infinity).cgImage else { return nil }
        let url = newTempURL(sessionId: sessionId)
        guard let dest = CGImageDestinationCreateWithURL(
                url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        // ⛔ **2026-08-23: 0.7 → 0.9** — 축소를 뺐어도 **재인코딩에서 또 깎이면** 뜻이 없다.
        // ⚠️ **1.0으로 안 올린 이유:** 크기가 크게 늘고 눈으로 갈리지 않는다. **0.9가 관행적 상한**이다.
        var props: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.9]
        if let loc = location { props[kCGImagePropertyGPSDictionary] = gpsDictionary(loc) }
        CGImageDestinationAddImage(dest, cg, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return url
    }

    /// 긴 변이 maxEdge보다 크면 비율 유지 축소. **항상 재렌더**해 카메라 방향 메타를 픽셀로 굽는다(upright).
    /// ⚠️ `maxEdge: .infinity`면 **축소는 없고 방향만 굽는다**(2026-08-23부터 촬영이 그렇게 부른다).
    /// ⛔ **재렌더는 촬영 메타(EXIF 렌즈·노출)를 안 남긴다 — 옛 코드도 그랬다.**
    /// **「품질 그대로」는 픽셀 이야기다.** 촬영 메타까지 남기려면 `info[.mediaMetadata]`를 합쳐야 한다(안 했다).
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
    static func coordinate(name: String) -> CLLocationCoordinate2D? {
        guard let url = url(name: name) else { return nil }
        return coordinate(fileURL: url)
    }

    /// 같은 것을 **파일 경로로** 읽는다 — **아직 확정되지 않은 임시 사진**에 쓴다
    /// (수집 화면의 「보조 자료」 카드 · 2026-08-30에 갈라냈다).
    /// ⛔ **두 벌로 만들지 않았다** — 위 `coordinate(name:)`이 이것을 부른다.
    static func coordinate(fileURL url: URL) -> CLLocationCoordinate2D? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
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
