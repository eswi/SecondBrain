// app.js — 세컨드 브레인 1층 검토 앱 (UI + 상태)
// 원칙: inbox.md는 읽기만 한다. 확인/점 등 상태는 이 기기(localStorage)에만 저장.
// 데이터는 파일 선택기로 각 기기에서 직접 로드 → 어디로도 전송하지 않는다.
(() => {
  "use strict";
  const { parseInbox, applyDueToText } = window.SBParser;

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
    dismissed: "sb_dismissed_dots",
    pending: "sb_pending_dues",     // 폰에서 찍은 "임시" 시점 (아직 파일에 안 남은 것)
    theme: "sb_theme",
    cachedText: "sb_cached_inbox",
    cachedMeta: "sb_cached_meta",
    backup: "sb_backup_before_write", // 파일 쓰기 직전 원문 스냅샷(되돌리기용 안전망)
  };
  const loadSet = (k) => new Set(JSON.parse(localStorage.getItem(k) || "[]"));
  const saveSet = (k, set) => localStorage.setItem(k, JSON.stringify([...set]));
  const dismissed = loadSet(LS.dismissed);

  // pending: { [id]: { due, resurface, pickedAt, key:{date,time,source,raw} } }
  // 직렬화 가능한 평면 객체 — 나중에 "텍스트 전달"로 데스크톱에 넘길 여지를 열어둔다.
  const pending = JSON.parse(localStorage.getItem(LS.pending) || "{}");
  const savePending = () => localStorage.setItem(LS.pending, JSON.stringify(pending));

  // 쓰기 가능 = File System Access API가 있는 기기(데스크톱 Chrome/Edge).
  // iOS Safari 등은 false → 시점 지정이 "임시(pending)"로만 저장된다(§0-A: 쓰기=데스크톱).
  const CAN_WRITE = "showOpenFilePicker" in window;

  // 터치 기기(아이폰 등)는 날짜 입력을 탭하면 네이티브 피커가 자동으로 열린다.
  // 그 위에 showPicker()를 또 부르면 iOS에서 "열렸다 즉시 닫힘"이 발생하므로,
  // showPicker는 데스크톱(비터치)에서만 보강 호출한다.
  const IS_TOUCH = matchMedia("(hover: none) and (pointer: coarse)").matches;

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

  const ISO = /^\d{4}-\d{2}-\d{2}$/;

  // 유효 시점: 파일에 확정된 due가 있으면 그것(source:"file"),
  // 없고 이 기기에서 찍은 임시가 있으면 그것(source:"pending"), 둘 다 없으면 null.
  function effectiveDue(it) {
    if (it.due && it.due !== "none" && ISO.test(it.due)) {
      return { date: it.due, source: "file" };
    }
    const p = pending[it.id];
    if (p && ISO.test(p.due)) return { date: p.due, source: "pending" };
    return null;
  }

  // D-day 배지: 지남(D+n·경고) / 오늘(D-DAY) / 남음(D-n)
  function dday(dateStr) {
    const d = toDate(dateStr);
    if (!d) return null;
    const n = daysBetween(new Date(), d); // 남은 일수(음수=지남)
    if (n < 0) return { text: `D+${-n}`, kind: "over", n };
    if (n === 0) return { text: "D-DAY", kind: "today", n };
    return { text: `D-${n}`, kind: "soon", n };
  }

  // ---------- push: "곧 닥칠 것" 판정 (§4·§5) ----------
  // 확정/임시 유효 시점이 이번 주(7일) 안이거나 지났으면 임박. resurface 도래도 포함.
  const IMMINENT_DAYS = 7;
  function isImminent(it) {
    const eff = effectiveDue(it);
    if (eff && daysBetween(new Date(), toDate(eff.date)) <= IMMINENT_DAYS) return true;
    const rs = toDate(it.resurface);
    if (rs && daysBetween(new Date(), rs) <= 0) return true; // resurface 도래
    return false;
  }

  // ---------- 시점 지정 컨트롤 ----------
  // 카드마다: 유효 시점이 있으면 D-day 칩(파일=실선·임시=점선⏳), 없으면 "＋ 시점" 버튼.
  // 탭하면 네이티브 달력. 데스크톱은 고르는 즉시 파일에 확정, 폰은 임시(pending)로 저장.
  function makeDueControl(it) {
    const wrap = el("span", "duewrap");
    const eff = effectiveDue(it);

    // 시각 요소(칩/버튼)는 표시만 담당 — 실제 탭은 아래 투명 오버레이 입력이 받는다.
    if (eff) {
      const b = dday(eff.date);
      const chip = el("span", "duechip " + (eff.source === "pending" ? "pending" : "confirmed"));
      chip.title = eff.source === "pending"
        ? "임시 시점 (이 기기에만) — 탭하면 변경. 데스크톱에서 확정하세요."
        : "확정된 시점 (파일에 기록됨) — 탭하면 변경";
      chip.innerHTML =
        `<span class="dday ${b.kind}">${b.text}</span>` +
        `<span class="dtxt">${esc(eff.date)}</span>` +
        (eff.source === "pending" ? `<span class="pendtag">⏳ 미확정</span>` : ``);
      wrap.appendChild(chip);
    } else {
      if (it.dueHint) {
        const hint = el("span", "duehint", `추정 ${it.dueHint.label}?`);
        hint.title = "원문에서 추정한 시점(확정 아님). 탭해서 날짜를 지정하세요.";
        wrap.appendChild(hint);
      }
      wrap.appendChild(el("span", "setduebtn", "＋ 시점"));
    }

    // 네이티브 달력 입력을 컨트롤 전체에 투명 오버레이한다. "진짜 탭"이 입력에
    // 직접 닿으므로 iOS Safari에서도 네이티브 피커가 열린다(숨긴 입력 + showPicker
    // 폴백은 iOS에서 동작하지 않던 문제를 우회). 데스크톱은 클릭 시 showPicker로 보강.
    const input = el("input", "dateinput");
    input.type = "date";
    input.setAttribute("aria-label", "시점 지정");
    if (eff && ISO.test(eff.date)) input.value = eff.date; // 기존값 프리필
    if (IS_TOUCH) {
      // iOS 네이티브 달력은 "확인"이든 "바깥 탭"이든 똑같이 수락으로 처리하고 기본값이
      // 늘 오늘이라, 닫히자마자 반영하면 실수로 오늘이 들어간다(둘을 코드로 구분 불가).
      // 또 달력이 열린 동안 render()가 돌면 달력이 닫혀버린다.
      // → change에선 값만 기억(달력은 열린 채 유지)하고, 달력이 닫히면(blur) 곧바로
      //   확정하지 않고 "적용/취소"를 띄운다. [적용]을 눌러야만 반영, [취소]/무시는 변화 없음.
      let picked = null;
      input.addEventListener("change", () => { picked = input.value || null; });
      input.addEventListener("blur", () => {
        if (!picked) return;
        const v = picked; picked = null;
        wrap.innerHTML = "";
        wrap.appendChild(el("span", "duestaged", `📅 ${v}`));
        const apply = el("button", "mini primary", "적용");
        const cancel = el("button", "mini", "취소");
        apply.addEventListener("click", () => setDate(it, v)); // 반영 → 재렌더
        cancel.addEventListener("click", () => render());      // 폐기 → 원래대로 복원
        wrap.appendChild(apply);
        wrap.appendChild(cancel);
      });
    } else {
      // 데스크톱: 클릭 시 달력을 띄우고, 고르면 즉시 반영(드롭다운이라 재렌더가 방해 안 됨).
      input.addEventListener("click", () => { try { input.showPicker(); } catch (e) {} });
      input.addEventListener("change", () => { if (input.value) setDate(it, input.value); });
    }
    wrap.appendChild(input);
    return wrap;
  }

  function stashPending(it, due, resurface) {
    pending[it.id] = {
      due, resurface, pickedAt: new Date().toISOString(),
      key: { date: it.date, time: it.time, source: it.source, raw: it.raw },
    };
    savePending();
  }

  async function setDate(it, value) {
    if (!ISO.test(value)) return;
    const resurface = value; // v0: 임박(7일) 창이 조기 노출을 담당하므로 resurface=due로 단순화
    if (CAN_WRITE) {
      const ok = await writeToFile(it, value, resurface);
      if (!ok) { stashPending(it, value, resurface); render(); } // 실패해도 유실 방지
    } else {
      stashPending(it, value, resurface);
      toast("임시 시점 저장 — 데스크톱에서 확정하세요");
      render();
    }
  }

  // 데스크톱 전용: 최신 원문을 다시 읽어 해당 블록에만 due/resurface를 써넣고 원자적 저장.
  async function writeToFile(it, due, resurface) {
    try {
      let handle = await idbGet("inboxHandle");
      if (!handle) { toast("먼저 파일을 불러오세요"); await pickFile(); handle = await idbGet("inboxHandle"); }
      if (!handle) return false;
      let perm = await handle.queryPermission({ mode: "readwrite" });
      if (perm !== "granted") perm = await handle.requestPermission({ mode: "readwrite" });
      if (perm !== "granted") { toast("쓰기 권한이 필요합니다"); return false; }

      const file = await handle.getFile();
      const fresh = await file.text(); // 다른 writer·동기화 반영을 위해 최신본에 적용
      const key = { date: it.date, time: it.time, source: it.source, raw: it.raw };
      const { text, changed } = applyDueToText(fresh, key, { due, resurface });
      if (!changed) { toast("항목을 파일에서 못 찾음 — 다시 불러오기 후 시도"); return false; }

      localStorage.setItem(LS.backup, JSON.stringify({ at: new Date().toISOString(), text: fresh }));
      const w = await handle.createWritable();
      await w.write(text); await w.close();

      delete pending[it.id]; savePending();
      applyText(text, file.name); // 파일이 진실원 → 재파싱·재렌더
      toast("파일에 확정했습니다");
      return true;
    } catch (e) {
      if (e && e.name === "AbortError") return false;
      toast("파일 쓰기 실패"); return false;
    }
  }

  async function confirmAllPending() {
    const ids = Object.keys(pending);
    let ok = 0;
    for (const id of ids) {
      const it = state.items.find((x) => x.id === id);
      const p = pending[id];
      if (it && p && await writeToFile(it, p.due, p.resurface)) ok++;
    }
    toast(ok ? `${ok}개 확정했습니다` : "확정할 항목이 없습니다");
    render();
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

    // 시점: D-day 배지 + 날짜 지정. 파일 확정(실선)과 임시(점선·⏳)를 확연히 구분.
    meta.appendChild(makeDueControl(it));
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

  // 임박 항목의 정렬·버킷 기준 일수(유효 시점 우선, 없으면 resurface)
  function urgencyDays(it) {
    const e = effectiveDue(it);
    if (e) return daysBetween(new Date(), toDate(e.date));
    const rs = toDate(it.resurface);
    return rs ? daysBetween(new Date(), rs) : 9999;
  }

  function renderDigest() {
    const imm = state.items.filter(isImminent).sort((a, b) => urgencyDays(a) - urgencyDays(b));
    $("#digestCount").textContent = imm.length;
    const root = $("#digestList"); root.innerHTML = "";
    if (!imm.length) {
      root.appendChild(el("div", "hint-empty",
        "지금 챙길 것이 없습니다. 항목에 ＋ 시점으로 날짜를 지정하거나 분류가 due를 채우면, 때가 임박할 때 여기 맨 위로 올라옵니다."));
      return;
    }
    // 지남 → 오늘 → 이번 주 버킷
    const buckets = [
      { key: "over", label: "지난 것", cls: "b-over", arr: [] },
      { key: "today", label: "오늘", cls: "b-today", arr: [] },
      { key: "week", label: "이번 주", cls: "b-week", arr: [] },
    ];
    imm.forEach((it) => {
      const n = urgencyDays(it);
      (n < 0 ? buckets[0] : n === 0 ? buckets[1] : buckets[2]).arr.push(it);
    });
    buckets.forEach((b) => {
      if (!b.arr.length) return;
      const head = el("div", "digest-bucket " + b.cls);
      head.appendChild(el("span", "bk-label", b.label));
      head.appendChild(el("span", "bk-n", String(b.arr.length)));
      root.appendChild(head);
      b.arr.forEach((it) => root.appendChild(cardEl(it)));
    });
  }

  // ---------- 확정 대기(임시 시점) 패널 ----------
  function renderPending() {
    const sec = $("#pendingSec"); if (!sec) return;
    const ids = Object.keys(pending);
    if (!ids.length) { sec.hidden = true; return; }
    sec.hidden = false;
    $("#pendingCount").textContent = ids.length;
    $("#pendingNote").textContent = CAN_WRITE
      ? "이 기기에서 찍은 임시 시점입니다. ‘확정’을 누르면 inbox.md에 기록됩니다."
      : "이 기기에서 찍은 임시 시점 — 아직 파일에 없습니다. 데스크톱에서 확정하세요. (이 목록은 저절로 사라지지 않습니다.)";
    $("#confirmAllBtn").hidden = !CAN_WRITE || ids.length < 2;

    const list = $("#pendingList"); list.innerHTML = "";
    ids.sort((a, b) => (pending[a].due || "").localeCompare(pending[b].due || ""));
    ids.forEach((id) => {
      const p = pending[id];
      const it = state.items.find((x) => x.id === id);
      const raw = it ? (it.body || it.raw) : (p.key ? p.key.raw : id);
      const b = dday(p.due);
      const row = el("div", "pending-row");
      const info = el("div", "pending-info");
      info.innerHTML =
        `<span class="dday ${b ? b.kind : ""}">${b ? b.text : ""}</span>` +
        `<span class="pd-date">${esc(p.due)}</span> <span class="pd-raw">${esc(raw)}</span>`;
      row.appendChild(info);
      const actions = el("div", "pending-actions");
      if (CAN_WRITE && it) {
        const c = el("button", "mini primary", "확정");
        c.addEventListener("click", () => writeToFile(it, p.due, p.resurface));
        actions.appendChild(c);
      }
      const del = el("button", "mini", "지우기");
      del.addEventListener("click", () => { delete pending[id]; savePending(); render(); toast("임시 시점 지움"); });
      actions.appendChild(del);
      row.appendChild(actions);
      list.appendChild(row);
    });
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
    renderPending();
    renderChips();
    renderList();
  }

  // ---------- 데이터 로드 ----------
  function applyText(text, fileName) {
    state.items = parseInbox(text);
    // 파일에 due가 확정된 임시 항목은 정리(다른 데스크톱/동기화로 확정된 경우 포함) → 파일이 진실원
    let pendingChanged = false;
    for (const it of state.items) {
      if (pending[it.id] && it.due && it.due !== "none" && ISO.test(it.due)) {
        delete pending[it.id]; pendingChanged = true;
      }
    }
    if (pendingChanged) savePending();
    state.fileName = fileName || state.fileName || "inbox.md";
    state.loadedAt = new Date();
    localStorage.setItem(LS.cachedText, text);
    localStorage.setItem(LS.cachedMeta, JSON.stringify({ fileName: state.fileName, at: state.loadedAt.toISOString() }));
    $("#loaderScreen").hidden = true;
    $("#appBody").hidden = false;
    $("#reloadBtn").hidden = false;
    render();
  }

  const supportsFSA = CAN_WRITE;

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
    const confirmAll = $("#confirmAllBtn");
    if (confirmAll) confirmAll.addEventListener("click", confirmAllPending);

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
  window.SBApp = {
    applyText, render, state, parseInbox,
    effectiveDue, isImminent, dday, setDate, writeToFile,
    pending, CAN_WRITE,
  };

  // 서비스워커 등록 (PWA)
  if ("serviceWorker" in navigator) {
    window.addEventListener("load", () => navigator.serviceWorker.register("sw.js").catch(() => {}));
  }

  init();
})();
