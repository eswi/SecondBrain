// ⛔⛔ 웹 v0 — **지금은 쓰지 않는 세대다** (2026-08-21 표시)
//    이 저장소는 두 층이다: **웹 v0(PWA · 이 파일)** 와 **네이티브 v1(`native/`, Swift)**.
//    실사용은 **네이티브 v1로 넘어갔다.** 웹 v0는 **이전 세대**이고 유지되지 않는다.
//    ⛔ **열어서 쓰지 말 것** — 아래 「왜 위험한가」를 먼저 볼 것. 지우지도 말 것(표시만 해 둔다).
//    세대 전체 표시 → 저장소 루트 `README.md` 맨 위 · 근거 → CLAUDE.md 항시 규칙 8
//
// sw.js — 앱 셸 오프라인 캐시 (PWA)
// 개인 데이터는 캐시하지 않는다. inbox.md는 네트워크가 아니라 파일 선택기로 로드되므로
// 여기 캐시엔 정적 셸(코드/아이콘)만 담긴다. 파일 변경 시 CACHE 버전을 올린다.
const CACHE = "second-brain-v7";
const SHELL = [
  "./",
  "./index.html",
  "./app.css",
  "./app.js",
  "./parser.js",
  "./manifest.webmanifest",
  "./icons/icon-192.png",
  "./icons/icon-512.png",
  "./icons/apple-touch-icon.png",
];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  const req = e.request;
  if (req.method !== "GET" || new URL(req.url).origin !== location.origin) return;
  // 셸은 캐시 우선, 없으면 네트워크(그리고 캐시에 채움)
  e.respondWith(
    caches.match(req).then((hit) =>
      hit ||
      fetch(req).then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
        return res;
      }).catch(() => hit)
    )
  );
});
