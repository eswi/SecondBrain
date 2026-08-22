import SwiftUI
import UIKit
import QuickLook

//
//  QuickLookProbe — **`QLPreviewController`가 무엇을 주고 무엇을 빼앗나**를 화면으로 본다 (2026-08-22 신설)
//
//  ⚠️⚠️ **앱 코드가 아니다.** 랩이다.
//
//  ── 왜 만들었나 (`media-expansion-design.md` §3-A-6 ①) ────────────────
//  사용자: *"직접 만들 것 대비 무엇을 잃는지 조사해줘. … 「쓸 수 있다」가 아니라 「무엇을 잃나」가 답이어야 한다."*
//  **헤더를 읽어서 알 수 있는 것**(API가 있나 없나)과 **눌러야 아는 것**(화면이 어떻게 생겼나)이 갈린다.
//  ⛔ 이 프로젝트가 27일 묵은 지도 핀으로 배운 것이 그것이다 — **코드가 완벽해도 화면은 봐야 안다.**
//
//  ── 실물을 안 쓴다 ──────────────────────────────────────────────
//  표본 `82B1044B`는 이 기기에서 dataless이고 **파일은 받지 않는다**(사용자 2026-08-22).
//  그래서 **이 프로브가 그 자리에서 JPEG 둘과 PDF 하나를 만들어** 쓴다.
//  ★ 「같은 종류 안에서만 `<` `>`가 돈다」(§3-A-4)를 시험하려고 **사진 둘만** 데이터 소스에 넣는다 —
//    PDF는 만들어 두고 **일부러 안 넣는다.** 넘겨서 PDF로 갈 수 있으면 그 규칙이 깨지는 것이다.
//
final class QLHostController: UIViewController, QLPreviewControllerDataSource, QLPreviewControllerDelegate {

    /// 데이터 소스에 **넣은 것** — 사진 둘뿐이다.
    private var shown: [URL] = []
    /// 만들었지만 **안 넣은 것** — 이것이 뷰어에서 보이면 「종류 안에서만」이 깨진다.
    private var hidden: [URL] = []
    private var presented = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0x13/255.0, green: 0x12/255.0, blue: 0x18/255.0, alpha: 1)
        shown = [makeJPEG(name: "photo-1", tint: UIColor.systemTeal, text: "사진 1"),
                 makeJPEG(name: "photo-2", tint: UIColor.systemIndigo, text: "사진 2")]
        hidden = [makePDF(name: "doc-1")]
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !presented else { return }
        presented = true
        let ql = QLPreviewController()
        ql.dataSource = self
        ql.delegate = self
        ql.currentPreviewItemIndex = 0
        ql.modalPresentationStyle = .fullScreen
        present(ql, animated: false)
    }

    // MARK: QLPreviewControllerDataSource — **범위를 우리가 정한다**
    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { shown.count }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        shown[index] as NSURL
    }

    // MARK: 만드는 것 (실물 파일 대신)
    private func tmp(_ name: String, _ ext: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(name).\(ext)")
    }

    private func makeJPEG(name: String, tint: UIColor, text: String) -> URL {
        let size = CGSize(width: 1200, height: 1600)     // 세로 사진 — 정사각형이 아니다(일부러)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            tint.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 140, weight: .heavy),
                .foregroundColor: UIColor.white,
            ]
            (text as NSString).draw(at: CGPoint(x: 90, y: 700), withAttributes: attrs)
        }
        let url = tmp(name, "jpg")
        try? img.jpegData(compressionQuality: 0.9)?.write(to: url)
        return url
    }

    private func makePDF(name: String) -> URL {
        let url = tmp(name, "pdf")
        let bounds = CGRect(x: 0, y: 0, width: 595, height: 842)     // A4 @72dpi
        let r = UIGraphicsPDFRenderer(bounds: bounds)
        try? r.writePDF(to: url) { ctx in
            ctx.beginPage()
            UIColor.white.setFill(); ctx.fill(bounds)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 44, weight: .bold),
                .foregroundColor: UIColor.black,
            ]
            ("PDF 첫 페이지" as NSString).draw(at: CGPoint(x: 60, y: 80), withAttributes: attrs)
        }
        return url
    }
}

struct QuickLookProbe: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> QLHostController { QLHostController() }
    func updateUIViewController(_ vc: QLHostController, context: Context) {}
}

//
//  ── 꼴 U — **애플이 상단 바에 무엇을 얹나**를 보려는 변형 (2026-08-22) ──────────
//  꼴 S(전체화면 제시)는 **크롬이 안 보이는 상태로 시작**했다(실측 · 탭 없이는 못 불러낸다).
//  ⛔ 탭은 `sim-input.swift`가 필요하고 그것은 **사용자가 명시할 때만** 쓴다(계측 규칙 5).
//  그래서 **내비게이션 스택에 얹어** QL이 자기 `navigationItem`에 무엇을 넣는지 본다 —
//  탭 없이 애플의 크롬을 화면에 남기는 길이다.
//
final class QLNavHostController: UIViewController, QLPreviewControllerDataSource {
    private var shown: [URL] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        shown = [makeJPEG(name: "nav-photo-1", tint: .systemTeal, text: "사진 1"),
                 makeJPEG(name: "nav-photo-2", tint: .systemIndigo, text: "사진 2")]
        let ql = QLPreviewController()
        ql.dataSource = self
        let nav = UINavigationController(rootViewController: ql)
        addChild(nav)
        nav.view.frame = view.bounds
        nav.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(nav.view)
        nav.didMove(toParent: self)
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { shown.count }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        shown[index] as NSURL
    }

    private func makeJPEG(name: String, tint: UIColor, text: String) -> URL {
        let size = CGSize(width: 1200, height: 1600)
        let img = UIGraphicsImageRenderer(size: size).image { ctx in
            tint.setFill(); ctx.fill(CGRect(origin: .zero, size: size))
            (text as NSString).draw(at: CGPoint(x: 90, y: 700), withAttributes: [
                .font: UIFont.systemFont(ofSize: 140, weight: .heavy),
                .foregroundColor: UIColor.white,
            ])
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).jpg")
        try? img.jpegData(compressionQuality: 0.9)?.write(to: url)
        return url
    }
}

struct QuickLookNavProbe: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> QLNavHostController { QLNavHostController() }
    func updateUIViewController(_ vc: QLNavHostController, context: Context) {}
}
