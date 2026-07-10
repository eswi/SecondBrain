// sw.js — 앱 셸 오프라인 캐시 (PWA)
// 개인 데이터는 캐시하지 않는다. inbox.md는 네트워크가 아니라 파일 선택기로 로드되므로
// 여기 캐시엔 정적 셸(코드/아이콘)만 담긴다. 파일 변경 시 CACHE 버전을 올린다.
const CACHE = "second-brain-v1";
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
