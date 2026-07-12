// parser.js — inbox.md 파서 (순수 함수, DOM 의존 없음)
// 설계서 §1 데이터 형식을 읽는다. 원문은 절대 바꾸지 않고 읽기만 한다.
//
//   - YYYY-MM-DD HH:MM | source | 원문
//     type: promise            (분류되면 붙는 필드들 — 아직 대부분 없음)
//     due: 2026-07-03
//     resurface: 2026-07-01
//     status: open
//
// 미가공 줄(분류 전)도 우아하게 다룬다: type 없으면 category = 'todo'(정리 필요).

const KNOWN_FIELDS = new Set(["type", "due", "resurface", "status", "group", "grouped"]);

// 한 줄 항목 시작: "- 날짜 시각 | source | 나머지"
const ITEM_RE = /^-\s+(\d{4}-\d{2}-\d{2})\s+(\d{1,2}:\d{2})\s+\|\s+([^|]+?)\s+\|\s+(.*)$/;
const FIELD_RE = /^\s+([A-Za-z_]+):\s*(.*)$/;
const URL_RE = /https?:\/\/[^\s)]+/;

// "왜" 메모 추출: "— 왜: …" 또는 "왜 잡았나: …" (§1)
function extractWhy(text) {
  let m = text.match(/[—-]\s*왜\s*[:：]\s*(.+)$/);
  if (m) return { why: m[1].trim(), body: text.slice(0, m.index).replace(/[—-]\s*$/, "").trim() };
  m = text.match(/왜\s*잡았나\s*[:：]\s*(.+)$/);
  if (m) return { why: m[1].trim(), body: text.slice(0, m.index).trim() };
  return { why: "", body: text };
}

// 아주 가벼운 시점 추정(표시 전용, 확정 아님 → "~까지 ?"). 정식 추출은 분류기(목표 2)의 몫.
// 원문 음성에 흔한 명시 신호만 잡는다. 틀릴 수 있으므로 항상 "?"로 표시하고 사용자가 확인/무시.
function guessDueHint(raw) {
  const t = raw;
  if (/\b(\d{1,2})월\s*(\d{1,2})일/.test(t)) {
    const m = t.match(/\b(\d{1,2})월\s*(\d{1,2})일/);
    return { label: `${m[1]}/${m[2]}`, kind: "date" };
  }
  const rel = [
    [/오늘까지|오늘\s*중/, "오늘"],
    [/내일까지|내일\s*중|내일/, "내일"],
    [/모레/, "모레"],
    [/이번\s*주|금주/, "이번 주"],
    [/다음\s*주|담주|차주/, "다음 주"],
    [/이번\s*달|이달/, "이번 달"],
    [/빨리|서둘러|급히|시급|당장|곧/, "빨리"],
  ];
  for (const [re, label] of rel) if (re.test(t)) return { label, kind: "rel" };
  return null;
}

// type → 화면 종류(§5 프로토타입: 행동 필요 / 생각·고민 / 원칙 / 정보·참고 / 정리 필요)
function categoryOf(type) {
  switch ((type || "").toLowerCase()) {
    case "promise":
    case "event":
      return "action";
    case "idea":
      return "think";
    case "principle":
    case "ambient":
      return "principle";
    case "info-action":
    case "info":
      return "info";
    case "discard":
      return "discard";
    default:
      return "todo"; // 미분류 = 정리 필요
  }
}

// 안정적 id (로컬 상태 키용): 원문 줄 기반 간단 해시
function hashId(s) {
  let h = 5381;
  for (let i = 0; i < s.length; i++) h = ((h << 5) + h + s.charCodeAt(i)) | 0;
  return "i" + (h >>> 0).toString(36);
}

function parseInbox(text) {
  const lines = (text || "").split(/\r?\n/);
  const items = [];
  let cur = null;

  const finalize = (it) => {
    const { why, body } = extractWhy(it.raw);
    it.why = why;
    it.body = body || it.raw;
    const urlm = it.raw.match(URL_RE);
    it.url = urlm ? urlm[0] : "";
    it.category = categoryOf(it.type);
    // 시점: 분류된 due가 있으면 그것(재확인 필요 표시), 없으면 원문에서 가벼운 추정
    if (it.due && it.due !== "none") {
      it.dueHint = { label: it.due, kind: "field" };
    } else {
      it.dueHint = guessDueHint(it.raw);
    }
    it.id = hashId(`${it.date} ${it.time}|${it.source}|${it.raw}`);
    return it;
  };

  for (const line of lines) {
    const im = line.match(ITEM_RE);
    if (im) {
      if (cur) items.push(finalize(cur));
      cur = {
        date: im[1],
        time: im[2],
        source: im[3].trim().toLowerCase(),
        raw: im[4].trim(),
        type: "",
        due: "",
        resurface: "",
        status: "",
        grouped: false,
        notes: [],
        _lineNo: null,
      };
      continue;
    }
    if (cur) {
      const fm = line.match(FIELD_RE);
      if (fm && KNOWN_FIELDS.has(fm[1].toLowerCase())) {
        const key = fm[1].toLowerCase();
        const val = fm[2].trim();
        if (key === "grouped") cur.grouped = /^(true|yes|1|●)$/i.test(val);
        else if (key === "group") {
          cur.group = val;
          cur.grouped = true;
        } else cur[key] = val;
        continue;
      }
      if (line.trim() === "") continue; // 빈 줄은 구분자
      // 알 수 없는 들여쓰기 줄 = 이어지는 원문/메모(예: 여러 줄 "왜 잡았나")
      if (/^\s+\S/.test(line)) {
        cur.notes.push(line.trim());
        continue;
      }
    }
    // 항목 밖의 줄(제목 #, 빈 줄 등)은 무시
  }
  if (cur) items.push(finalize(cur));
  return items;
}

// ---------------------------------------------------------------------------
// 쓰기(데스크톱 전용): 한 항목의 due/resurface를 원문 텍스트에 안전하게 반영한다.
//   - 원문(헤더 줄과 본문)은 절대 바꾸지 않는다. 해당 블록의 필드만 교체/삽입.
//   - classify.py와 같은 형식("  key: value", 2칸 들여쓰기)을 쓴다 → 두 writer가 호환.
//   - 항목은 (date,time,source,raw)로 식별. 원문에서 그 헤더 줄을 찾아 그 블록만 손댄다.
//   - 반환: { text, changed }.  항목을 못 찾으면 changed=false, text=원본 그대로.
// 아이폰(읽기 전용)에선 호출되지 않는다(오버레이만). 데스크톱에서만 파일 확정에 쓴다.
function applyDueToText(text, key, fields) {
  const lines = (text || "").split(/\r?\n/);
  const wantSource = (key.source || "").trim().toLowerCase();
  const wantRaw = (key.raw || "").trim();

  // 대상 항목 헤더 줄 찾기
  let headerIdx = -1;
  for (let i = 0; i < lines.length; i++) {
    const m = lines[i].match(ITEM_RE);
    if (!m) continue;
    if (m[1] === key.date && m[2] === key.time &&
        m[3].trim().toLowerCase() === wantSource && m[4].trim() === wantRaw) {
      headerIdx = i;
      break;
    }
  }
  if (headerIdx === -1) return { text, changed: false };

  // 블록의 들여쓴 필드 줄 범위 파악(다음 항목/빈 줄/비들여쓰기 전까지)
  const fieldIdx = {}; // key -> line index
  let lastFieldIdx = headerIdx;
  for (let j = headerIdx + 1; j < lines.length; j++) {
    const line = lines[j];
    if (ITEM_RE.test(line) || line.trim() === "" || !/^\s+\S/.test(line)) break;
    const fm = line.match(FIELD_RE);
    if (fm) fieldIdx[fm[1].toLowerCase()] = j;
    lastFieldIdx = j;
  }

  const mkLine = (k, v) => `  ${k}: ${v}`;
  const setField = (k, v) => {
    if (fieldIdx[k] != null) {
      lines[fieldIdx[k]] = mkLine(k, v); // 기존 값 교체
      return null;
    }
    return mkLine(k, v); // 새로 삽입할 줄
  };

  const toInsert = [];
  for (const [k, v] of Object.entries(fields)) {
    if (v == null) continue;
    const ins = setField(k, String(v));
    if (ins != null) toInsert.push(ins);
  }
  if (toInsert.length) lines.splice(lastFieldIdx + 1, 0, ...toInsert);

  return { text: lines.join("\n"), changed: true };
}

// 노출(export): 브라우저(전역)와 테스트(node) 양쪽 지원
if (typeof module !== "undefined" && module.exports) {
  module.exports = { parseInbox, categoryOf, extractWhy, guessDueHint, hashId, applyDueToText };
} else {
  window.SBParser = { parseInbox, categoryOf, extractWhy, guessDueHint, hashId, applyDueToText };
}
