import SwiftUI
import UIKit
import QuickLook
import QuickLookThumbnailing

//
//  CanPreviewProbe — **`canPreviewItem`이 무엇에 답하나**를 잰다 (2026-08-22 신설)
//
//  ⚠️⚠️ **앱 코드가 아니다.** 랩이다.
//
//  ── 왜 (사용자 2026-08-22) ─────────────────────────────────────
//  *"canPreviewItem은 따로 쓸 값이 있다 — 「기타」의 미리보기 가능 여부를 묻는 데만.
//    뷰어를 안 쓰는 것과 별개다."*
//
//  ── 무엇을 갈라 재나 ────────────────────────────────────────────
//  ① **파일이 없어도 답하나** — 답하면 **확장자/UTI만 보는 것**이고, 그러면 **dataless 파일에도 물을 수 있다**
//     (맥미니의 iCloud 사본 119개가 그 상태다). 안 답하면 **바이트가 있어야** 물을 수 있다.
//  ② **어느 확장자가 되나** — 특히 「기타」에 들어올 것들(zip·docx·pages·csv·확장자 없음·모르는 확장자).
//  ③ ★ **`canPreviewItem`과 「썸네일이 나오나」는 다른 물음이다.** 그림을 만드는 것은
//     `QLThumbnailGenerator`이고, 그것은 **아이콘/썸네일 중 무엇을 줬는지**까지 답한다.
//     **`.icon`이 오면 그것은 「그림을 못 만들었다」이지 「됐다」가 아니다** —
//     그 갈림이 문구 ①(못 만들었다)과 ③(원래 안 된다)의 갈림과 같은 자리다.
//
struct CanPreviewProbe: View {
    @State private var extRows: [(String, Bool, Bool)] = []      // 확장자, 없는 파일, 있는 파일
    @State private var thumbRows: [(String, String)] = []        // 이름, 결과
    @State private var note = "재는 중…"

    private let exts = ["jpg", "heic", "png", "pdf", "m4a", "mp3", "mov", "mp4", "txt",
                        "csv", "json", "html", "zip", "docx", "xlsx", "pages", "key", "xyz", "(없음)"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("canPreviewItem — 파일이 없을 때 / 있을 때")
                    .font(.system(size: 13, weight: .bold))
                Text(note).font(.system(size: 10)).foregroundStyle(.secondary)

                HStack(spacing: 0) {
                    Text("확장자").frame(width: 90, alignment: .leading)
                    Text("파일 없음").frame(width: 80, alignment: .leading)
                    Text("파일 있음").frame(width: 80, alignment: .leading)
                }
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)

                ForEach(Array(extRows.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 0) {
                        Text(".\(r.0)").frame(width: 90, alignment: .leading)
                        Text(r.1 ? "✅ true" : "⛔ false").frame(width: 80, alignment: .leading)
                            .foregroundStyle(r.1 ? .green : .red)
                        Text(r.2 ? "✅ true" : "⛔ false").frame(width: 80, alignment: .leading)
                            .foregroundStyle(r.2 ? .green : .red)
                    }
                    .font(.system(size: 12).monospaced())
                }

                Divider().padding(.vertical, 4)
                Text("QLThumbnailGenerator — 무엇을 돌려주나")
                    .font(.system(size: 13, weight: .bold))
                Text("★ .icon = 파일 종류 아이콘(그림을 못 만든 것) · .thumbnail = 진짜 미리보기")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
                ForEach(Array(thumbRows.enumerated()), id: \.offset) { _, r in
                    HStack(spacing: 0) {
                        Text(r.0).frame(width: 150, alignment: .leading)
                        Text(r.1).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 11).monospaced())
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task { await run() }
    }

    private func run() async {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("canprev-\(UUID().uuidString.prefix(8))")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        var rows: [(String, Bool, Bool)] = []
        for e in exts {
            let name = e == "(없음)" ? "sample" : "sample.\(e)"
            let missing = tmp.appendingPathComponent("missing-" + name)
            let present = tmp.appendingPathComponent(name)
            // 있는 파일 — **바이트는 진짜가 아니다**(확장자만 진짜). 그 갈림도 결과에 남는다.
            try? Data("hello".utf8).write(to: present)
            rows.append((e,
                         QLPreviewController.canPreview(missing as NSURL),
                         QLPreviewController.canPreview(present as NSURL)))
        }
        extRows = rows

        // 썸네일 — **내용이 진짜인 것과 가짜인 것을 갈라** 넣는다.
        var files: [(String, URL)] = []
        files.append(("사진 jpg (내용 진짜)", makeJPEG(in: tmp)))
        files.append(("PDF (내용 진짜)", makePDF(in: tmp)))
        let txt = tmp.appendingPathComponent("real.txt")
        try? Data("두 번째 뇌\n자료 확장 실험".utf8).write(to: txt)
        files.append(("txt (내용 진짜)", txt))
        let zip = tmp.appendingPathComponent("real.zip")     // 빈 zip(유효): PK\05\06 + 0 18개
        try? Data([0x50,0x4B,0x05,0x06] + [UInt8](repeating: 0, count: 18)).write(to: zip)
        files.append(("zip (빈 것 · 유효)", zip))
        let fakeM4A = tmp.appendingPathComponent("fake.m4a")
        try? Data("not audio".utf8).write(to: fakeM4A)
        files.append(("m4a (내용 가짜)", fakeM4A))
        let unknown = tmp.appendingPathComponent("thing.xyz")
        try? Data("hello".utf8).write(to: unknown)
        files.append(("xyz (모르는 확장자)", unknown))

        var out: [(String, String)] = []
        for (label, url) in files {
            let req = QLThumbnailGenerator.Request(fileAt: url,
                                                   size: CGSize(width: 62, height: 62),
                                                   scale: 3,
                                                   representationTypes: .all)
            do {
                let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: req)
                let kind: String
                switch rep.type {
                case .icon: kind = ".icon ⛔ 그림 아님"
                case .lowQualityThumbnail: kind = ".lowQuality ✅"
                case .thumbnail: kind = ".thumbnail ✅"
                @unknown default: kind = "알 수 없음"
                }
                out.append((label, "\(kind) · \(Int(rep.uiImage.size.width))×\(Int(rep.uiImage.size.height))"))
            } catch {
                out.append((label, "⛔ 실패 — \((error as NSError).code)"))
            }
        }
        thumbRows = out
        note = "잰 곳: \(tmp.lastPathComponent) · 「파일 있음」의 바이트는 확장자만 진짜다"
    }

    private func makeJPEG(in dir: URL) -> URL {
        let size = CGSize(width: 900, height: 1200)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.systemTeal.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
        }
        let u = dir.appendingPathComponent("real.jpg")
        try? img.jpegData(compressionQuality: 0.9)?.write(to: u)
        return u
    }

    private func makePDF(in dir: URL) -> URL {
        let u = dir.appendingPathComponent("real.pdf")
        let b = CGRect(x: 0, y: 0, width: 595, height: 842)
        try? UIGraphicsPDFRenderer(bounds: b).writePDF(to: u) { c in
            c.beginPage(); UIColor.white.setFill(); c.fill(b)
            ("PDF" as NSString).draw(at: CGPoint(x: 60, y: 80),
                                     withAttributes: [.font: UIFont.systemFont(ofSize: 64, weight: .bold)])
        }
        return u
    }
}
