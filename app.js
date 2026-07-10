// app.js — 세컨드 브레인 1층 검토 앱 (UI + 상태)
// 원칙: inbox.md는 읽기만 한다. 확인/점 등 상태는 이 기기(localStorage)에만 저장.
// 데이터는 파일 선택기로 각 기기에서 직접 로드 → 어디로도 전송하지 않는다.
(() => {
  "use strict";
  const { parseInbox } = window.SBParser;

  // ---------- 종류(카테고리) 정의 ----------
  const CATS = [
    { key: "action", label: "행동 필요", color: "var(--c-action)", icon: "✅" },
    { key: "think", label: "생각·고민", color: "var(--c-think)", icon: "💭" },
    { key: "principle", label: "원칙", color: "var(--c-principle)", icon: "🌅" },
    { key: "info", label: "정보·참고", color: "var(--c-info)", icon: "🔖" },
    { key: "todo", label: "정리 필요", color: "var(--c-todo)", icon: "🗂️" },
    { key: "discard", label: "버림", color: "var(--c-discard)", icon: "🗑️" },
  ];
  const CAT_MAP = Object.fromEntries(CATS.map((c) => [c.key, c]));

  const SOURCES = {
    voice: "🎙️", web: "🌐", image: "🖼️", mail: "✉️",
    doc: "📄", chat: "💬", meeting: "🗓️",
  };
  const srcIcon = (s) => SOURCES[s] || "•";

  // ---------- 로컬 상태 (이 기기 전용) ----------
  const LS = {
    confirmed: "sb_confirmed_dues",
    dismissed: "sb_dismissed_dots",
    theme: "sb_theme",
    cachedText: "sb_cached_inbox",
    cachedMeta: "sb_cached_meta",
  };
  const loadSet = (k) => new Set(JSON.parse(localStorage.getItem(k) || "[]"));
  const saveSet = (k, set) => localStorage.setItem(k, JSON.stringify([...set]));
  const confirmed = loadSet(LS.confirmed);
  const dismissed = loadSet(LS.dismissed);

  const state = {
    items: [],
    query: "",
    cat: "all",
    src: "all",
    fileName: "",
    loadedAt: null,
  };

  // ---------- 파일 핸들 IndexedDB (데스크톱 재사용) ----------
  const IDB_NAME = "second-brain", IDB_STORE = "handles";
  function idb() {
    return new Promise((res, rej) => {
      const r = indexedDB.open(IDB_NAME, 1);
      r.onupgradeneeded = () => r.result.createObjectStore(IDB_STORE);
      r.onsuccess = () => res(r.result);
      r.onerror = () => rej(r.error);
    });
  }
  async function idbSet(key, val) {
    try {
      const db = await idb();
      await new Promise((res, rej) => {
        const tx = db.transaction(IDB_STORE, "readwrite");
        tx.objectStore(IDB_STORE).put(val, key);
        tx.oncomplete = res; tx.onerror = () => rej(tx.error);
      });
    } catch (e) { /* IDB 불가 시 무시 */ }
  }
  async function idbGet(key) {
    try {
      const db = await idb();
      return await new Promise((res, rej) => {
        const tx = db.transaction(IDB_STORE, "readonly");
        const g = tx.objectStore(IDB_STORE).get(key);
        g.onsuccess = () => res(g.result); g.onerror = () => rej(g.error);
      });
    } catch (e) { return null; }
  }

  // ---------- 유틸 ----------
  const $ = (s, r = document) => r.querySelector(s);
  const el = (tag, cls, txt) => { const e = document.createElement(tag); if (cls) e.className = cls; if (txt != null) e.textContent = txt; return e; };
  const esc = (s) => s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const linkify = (s) => esc(s).replace(/(https?:\/\/[^\s<]+)/g, '<a href="$1" target="_blank" rel="noopener">$1</a>');

  function toDate(s) {
    if (!s || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return null;
    const [y, m, d] = s.split("-").map(Number);
    return new Date(y, m - 1, d);
  }
  const midnight = (d) => { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; };
  const daysBetween = (a, b) => Math.round((midnight(b) - midnight(a)) / 86400000);

  let toastTimer;
  function toast(msg) {
    const t = $("#toast"); t.textContent = msg; t.classList.add("show");
    clearTimeout(toastTimer); toastTimer = setTimeout(() => t.classList.remove("show"), 2200);
  }

  // ---------- push: "곧 닥칠 것" 판정 (§4 매일 다이제스트) ----------
  function isImminent(it) {
    const today = new Date();
    const due = toDate(it.due);
    if (due && daysBetween(today, due) <= 3) return true; // due 3일 전~지남
    const rs = toDate(it.resurface);
    if (rs && daysBetween(today, rs) <= 0) return true;    // resurface 도래
    return false;
  }

  // ---------- 렌더 ----------
  function renderMeta() {
    const m = $("#metaLine");
    if (!state.loadedAt) { m.textContent = ""; return; }
    const t = state.loadedAt;
    const hh = String(t.getHours()).padStart(2, "0"), mm = String(t.getMinutes()).padStart(2, "0");
    m.textContent = `${state.fileName || "inbox.md"} · ${state.items.length}개 항목 · ${hh}:${mm} 기준`;
  }

  function matchesQuery(it, q) {
    if (!q) return true;
    const hay = (it.raw + " " + it.why + " " + it.url + " " + it.notes.join(" ")).toLowerCase();
    return q.toLowerCase().split(/\s+/).every((w) => hay.includes(w));
  }

  function cardEl(it) {
    const cat = CAT_MAP[it.category] || CAT_MAP.todo;
    const card = el("div", "card");
    card.style.setProperty("--cat-color", cat.color);
    card.style.setProperty("--info", "var(--c-info)");
    card.dataset.id = it.id;

    // 묶음 점 ● (일회성 확인, 클릭 시 소멸)
    if (it.grouped && !dismissed.has(it.id)) {
      const dot = el("button", "groupdot");
      dot.title = "묶음 확인 (클릭하면 사라짐)";
      dot.setAttribute("aria-label", "묶음 확인");
      dot.addEventListener("click", () => {
        dismissed.add(it.id); saveSet(LS.dismissed, dismissed);
        card.classList.add("dismissing");
        setTimeout(() => dot.remove(), 320);
        toast("묶음 확인됨");
      });
      card.appendChild(dot);
    }

    const body = el("div", "body");
    body.innerHTML = linkify(it.body || it.raw);
    card.appendChild(body);

    if (it.why) {
      const w = el("div", "why");
      w.innerHTML = "<b>왜</b> · " + linkify(it.why);
      card.appendChild(w);
    }
    for (const n of it.notes) {
      const nn = el("div", "why"); nn.innerHTML = linkify(n); card.appendChild(nn);
    }

    const meta = el("div", "metarow");
    const src = el("span", "src");
    src.innerHTML = `<span class="em">${srcIcon(it.source)}</span> ${esc(it.source)}`;
    meta.appendChild(src);
    meta.appendChild(el("span", "when", `${it.date} ${it.time}`));

    // 시점 "~까지 ?" (재확인) — 확정 아님. 클릭하면 확인됨 표시(로컬).
    if (it.dueHint) {
      const isConfirmed = confirmed.has(it.id);
      const chip = el("button", "duechip" + (isConfirmed ? " confirmed" : ""));
      const setLabel = () => {
        chip.innerHTML = confirmed.has(it.id)
          ? `${esc(it.dueHint.label)}까지 <span>✓</span>`
          : `${esc(it.dueHint.label)}까지 <span class="q">?</span>`;
        chip.classList.toggle("confirmed", confirmed.has(it.id));
      };
      setLabel();
      chip.title = "시점 재확인 (클릭하면 확인 처리)";
      chip.addEventListener("click", () => {
        if (confirmed.has(it.id)) confirmed.delete(it.id); else confirmed.add(it.id);
        saveSet(LS.confirmed, confirmed); setLabel();
        toast(confirmed.has(it.id) ? "시점 확인됨" : "재확인 필요로 되돌림");
      });
      meta.appendChild(chip);
    }
    if (it.status && it.status !== "open") meta.appendChild(el("span", "statuschip", it.status));

    card.appendChild(meta);
    return card;
  }

  function renderAmbient() {
    const principles = state.items.filter((it) => it.category === "principle");
    const sec = $("#ambientSec");
    if (!principles.length) { sec.hidden = true; return; }
    sec.hidden = false;
    const list = $("#ambientList"); list.innerHTML = "";
    principles.forEach((it) => list.appendChild(el("div", "principle-item", it.body || it.raw)));
  }

  function renderDigest() {
    const imm = state.items.filter(isImminent);
    $("#digestCount").textContent = imm.length;
    const root = $("#digestList"); root.innerHTML = "";
    if (!imm.length) {
      const e = el("div", "hint-empty",
        "지금 임박한 항목이 없습니다. 분류(자동 분류 단계)에서 due·resurface가 붙으면 마감·재확인할 것이 여기 먼저 올라옵니다.");
      root.appendChild(e);
      return;
    }
    imm.sort((a, b) => (toDate(a.due) || toDate(a.resurface) || 0) - (toDate(b.due) || toDate(b.resurface) || 0));
    imm.forEach((it) => root.appendChild(cardEl(it)));
  }

  function renderChips() {
    // 종류 칩
    const counts = {};
    state.items.forEach((it) => { counts[it.category] = (counts[it.category] || 0) + 1; });
    const catRoot = $("#catChips"); catRoot.innerHTML = "";
    const mkChip = (key, label, color, n, group, active) => {
      const c = el("button", "chip"); c.setAttribute("aria-pressed", active ? "true" : "false");
      if (color) { const d = el("span", "dot"); d.style.background = color; c.appendChild(d); }
      c.appendChild(el("span", null, label));
      if (n != null) c.appendChild(el("span", "n", String(n)));
      c.addEventListener("click", () => { state[group] = active ? "all" : key; render(); });
      return c;
    };
    catRoot.appendChild(mkChip("all", "전체", null, state.items.length, "cat", state.cat === "all"));
    CATS.forEach((cat) => {
      const n = counts[cat.key] || 0;
      if (cat.key === "discard" && n === 0) return; // 버림 없으면 숨김
      catRoot.appendChild(mkChip(cat.key, cat.label, cat.color, n, "cat", state.cat === cat.key));
    });

    // 출처(source) 칩
    const scount = {};
    state.items.forEach((it) => { scount[it.source] = (scount[it.source] || 0) + 1; });
    const srcRoot = $("#srcChips"); srcRoot.innerHTML = "";
    const srcs = Object.keys(scount).sort((a, b) => scount[b] - scount[a]);
    if (srcs.length > 1) {
      srcRoot.hidden = false;
      const all = el("button", "chip"); all.setAttribute("aria-pressed", state.src === "all" ? "true" : "false");
      all.innerHTML = `<span>모든 출처</span>`;
      all.addEventListener("click", () => { state.src = "all"; render(); });
      srcRoot.appendChild(all);
      srcs.forEach((s) => {
        const c = el("button", "chip"); c.setAttribute("aria-pressed", state.src === s ? "true" : "false");
        c.innerHTML = `<span class="em">${srcIcon(s)}</span><span>${esc(s)}</span><span class="n">${scount[s]}</span>`;
        c.addEventListener("click", () => { state.src = state.src === s ? "all" : s; render(); });
        srcRoot.appendChild(c);
      });
    } else { srcRoot.hidden = true; }
  }

  function renderList() {
    const root = $("#listRoot"); root.innerHTML = "";
    let items = state.items.filter((it) => matchesQuery(it, state.query));
    if (state.cat !== "all") items = items.filter((it) => it.category === state.cat);
    else items = items.filter((it) => it.category !== "discard"); // 전체에선 버림 제외
    if (state.src !== "all") items = items.filter((it) => it.source === state.src);

    if (!items.length) { makeEmpty(root); return; }

    // 종류별 그룹으로 묶어 표시(검토가 종류 단위로 이뤄지도록)
    const order = CATS.map((c) => c.key);
    const groups = {};
    items.forEach((it) => { (groups[it.category] = groups[it.category] || []).push(it); });
    order.forEach((key) => {
      const arr = groups[key]; if (!arr || !arr.length) return;
      const cat = CAT_MAP[key];
      const g = el("div", "cat-group");
      const head = el("div", "cat-head");
      const d = el("span", "dot"); d.style.background = cat.color; head.appendChild(d);
      head.appendChild(el("span", null, `${cat.icon} ${cat.label}`));
      head.appendChild(el("span", "n", String(arr.length)));
      g.appendChild(head);
      const cards = el("div", "cards");
      // 최신 항목이 위로
      arr.sort((a, b) => (b.date + b.time).localeCompare(a.date + a.time));
      arr.forEach((it) => cards.appendChild(cardEl(it)));
      g.appendChild(cards);
      root.appendChild(g);
    });
  }

  function makeEmpty(root) {
    const e = el("div", "empty");
    e.innerHTML = `<div class="big">🔍</div><h2>결과 없음</h2><p>검색어나 필터를 바꿔 보세요.</p>`;
    root.appendChild(e);
    return true;
  }

  function render() {
    renderMeta();
    renderAmbient();
    renderDigest();
    renderChips();
    renderList();
  }

  // ---------- 데이터 로드 ----------
  function applyText(text, fileName) {
    state.items = parseInbox(text);
    state.fileName = fileName || state.fileName || "inbox.md";
    state.loadedAt = new Date();
    localStorage.setItem(LS.cachedText, text);
    localStorage.setItem(LS.cachedMeta, JSON.stringify({ fileName: state.fileName, at: state.loadedAt.toISOString() }));
    $("#loaderScreen").hidden = true;
    $("#appBody").hidden = false;
    $("#reloadBtn").hidden = false;
    render();
  }

  const supportsFSA = "showOpenFilePicker" in window;

  async function pickFile() {
    if (supportsFSA) {
      try {
        const [handle] = await window.showOpenFilePicker({
          types: [{ description: "Markdown", accept: { "text/markdown": [".md"], "text/plain": [".txt", ".md"] } }],
          excludeAcceptAllOption: false,
        });
        await idbSet("inboxHandle", handle);
        const file = await handle.getFile();
        applyText(await file.text(), file.name);
        toast("불러왔습니다");
      } catch (e) { if (e.name !== "AbortError") toast("불러오기 취소/실패"); }
    } else {
      $("#filePick").click();
    }
  }

  async function reload() {
    if (supportsFSA) {
      const handle = await idbGet("inboxHandle");
      if (handle) {
        try {
          const perm = await handle.queryPermission({ mode: "read" });
          if (perm !== "granted") {
            const req = await handle.requestPermission({ mode: "read" });
            if (req !== "granted") { toast("권한이 필요합니다 — 다시 불러오기"); return pickFile(); }
          }
          const file = await handle.getFile();
          applyText(await file.text(), file.name);
          toast("최신 상태로 갱신");
          return;
        } catch (e) { /* 핸들 무효 → 다시 선택 */ }
      }
      return pickFile();
    }
    // FSA 미지원(iOS 등): 다시 파일 선택
    pickFile();
  }

  // iOS/미지원용 fallback input
  function setupFallbackInput() {
    const input = el("input"); input.type = "file"; input.id = "filePick";
    input.accept = ".md,.txt,text/markdown,text/plain"; input.hidden = true;
    input.addEventListener("change", async () => {
      const f = input.files[0]; if (!f) return;
      applyText(await f.text(), f.name); toast("불러왔습니다"); input.value = "";
    });
    document.body.appendChild(input);
  }

  // ---------- 테마 토글 ----------
  function initTheme() {
    const saved = localStorage.getItem(LS.theme);
    if (saved) document.documentElement.dataset.theme = saved;
    $("#themeBtn").addEventListener("click", () => {
      const cur = document.documentElement.dataset.theme;
      const isDark = cur ? cur === "dark" : matchMedia("(prefers-color-scheme: dark)").matches;
      const next = isDark ? "light" : "dark";
      document.documentElement.dataset.theme = next;
      localStorage.setItem(LS.theme, next);
    });
  }

  // ---------- 검색 입력 ----------
  function initSearch() {
    const input = $("#search"), clear = $("#clearSearch");
    input.addEventListener("input", () => {
      state.query = input.value.trim();
      clear.hidden = !input.value;
      renderList();
    });
    clear.addEventListener("click", () => { input.value = ""; state.query = ""; clear.hidden = true; input.focus(); renderList(); });
  }

  // ---------- 시작 ----------
  async function init() {
    initTheme();
    setupFallbackInput();
    initSearch();
    $("#loadBtn").addEventListener("click", pickFile);
    $("#loadBtn2").addEventListener("click", pickFile);
    $("#reloadBtn").addEventListener("click", reload);

    // 1) 데스크톱: 저장된 파일 핸들로 자동 재읽기 시도 (권한 granted일 때만 조용히)
    if (supportsFSA) {
      const handle = await idbGet("inboxHandle");
      if (handle) {
        try {
          const perm = await handle.queryPermission({ mode: "read" });
          if (perm === "granted") {
            const file = await handle.getFile();
            applyText(await file.text(), file.name);
            return;
          }
        } catch (e) { /* 무시 → 캐시로 */ }
      }
    }
    // 2) 캐시된 내용이 있으면 그것으로 먼저 보여주기(오프라인/재선택 전)
    const cached = localStorage.getItem(LS.cachedText);
    if (cached) {
      const meta = JSON.parse(localStorage.getItem(LS.cachedMeta) || "{}");
      applyText(cached, meta.fileName);
      if (meta.at) { state.loadedAt = new Date(meta.at); renderMeta(); }
      toast("저장된 사본 표시 — 최신은 다시 불러오기");
      return;
    }
    // 3) 아무것도 없으면 로더 화면 유지
  }

  // 디버그/스크립팅 훅 — 콘솔이나 이후 단계(자동 분류)에서 데이터 주입·재렌더용.
  // 예: SBApp.applyText(markdownText, "inbox.md")
  window.SBApp = { applyText, render, state, parseInbox };

  // 서비스워커 등록 (PWA)
  if ("serviceWorker" in navigator) {
    window.addEventListener("load", () => navigator.serviceWorker.register("sw.js").catch(() => {}));
  }

  init();
})();
