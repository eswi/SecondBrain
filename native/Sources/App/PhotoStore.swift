import Foundation
#if os(iOS)
import UIKit
#endif

/// 원본 사진 파일 저장소 — 항목 UUID로 이름 붙인 `.jpg`를 관리한다. **음성 `AudioStore`의 미러.**
/// 원칙: **원본 미디어는 불변(write-once) · 텍스트 층만 가변**(edit-policy §6).
/// 사진의 "원본"은 **캡처 시 1회 리사이즈·압축한 그 파일**이다(무손실 아님 — 설계
/// `docs/native/photo-capture-design.md` §4-④). 한 번 확정하면 다신 안 건드린다.
///
/// **기본은 기기에만**(앱 샌드박스). GPS는 사진 EXIF에만 두고 그릇엔 안 박아 iCloud 누출을 막는다(§5, Stage 3).
/// 저장 위치는 `searchDirs()`로 추상화 → 나중 항목별 iCloud 옵트인을 표시에 자동 반영(§7, 음성과 동형).
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

    /// id로 사진을 찾을 때 탐색할 위치들(순서대로). 지금은 로컬만.
    /// **향후(§7):** iCloud 폴더의 `photo/`를 여기 더하면 항목별 동기화가 표시에 자동 반영된다.
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
            if fm.fileExists(atPath: u.path) { return u }
        }
        return nil
    }

    // MARK: 촬영 이미지 저장 (음성엔 없던 것 — 리사이즈·압축)

    #if os(iOS)
    /// 촬영한 원본 이미지를 **긴 변 ~2048px 리사이즈 + JPEG 품질 0.7**로 임시 파일에 저장.
    /// 이 압축본이 §4-④의 불변 원본. 성공 시 임시 URL, 실패 시 nil.
    static func saveCaptured(_ image: UIImage, sessionId: String) -> URL? {
        let resized = downscaled(image, maxEdge: 2048)
        guard let data = resized.jpegData(compressionQuality: 0.7) else { return nil }
        let url = newTempURL(sessionId: sessionId)
        do { try data.write(to: url, options: .atomic); return url } catch { return nil }
    }

    /// 긴 변이 maxEdge보다 크면 비율 유지 축소. 이미 작으면 그대로.
    private static func downscaled(_ image: UIImage, maxEdge: CGFloat) -> UIImage {
        let w = image.size.width, h = image.size.height
        let longest = max(w, h)
        guard longest > maxEdge, longest > 0 else { return image }
        let scale = maxEdge / longest
        let newSize = CGSize(width: w * scale, height: h * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1                                   // 픽셀 크기 = 논리 크기(과대 렌더 방지)
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: newSize)) }
    }
    #endif
}
