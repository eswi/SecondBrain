import SwiftUI

// MARK: - 재설계 후보 저장소 (§2와 완전 분리 · 자동분류는 절대 안 씀)

/// "이런 분류가 있으면 좋겠다"를 떠오를 때마다 넣어두고 며칠 곱씹는 **아이디어 메모**.
/// **실제 분류 체계(§2·TypeCatalog·classify.py)와 완전히 분리된 별도 저장소**다:
/// - UserDefaults 전용 키(`reclass.candidates.v1`)에 JSON으로만 저장 — inbox 조각 파일·iCloud와 무관.
/// - 자동 분류(ClaudeClassifier·§3 프롬프트·InboxModel.validTypes)는 이 저장소를 **참조하지 않는다**.
///   (이 파일은 그쪽 어느 것도 import/호출하지 않으므로 구조적으로 샐 경로가 없다.)
/// 껐다 켜도 남는다(며칠 고민용). 여기서 추가/삭제/이름·메모 편집은 **실제 저장**된다.
struct ClassificationCandidate: Codable, Identifiable, Equatable {
    let id: String            // UUID
    var name: String          // 후보 이름 (예: "살마인드")
    var note: String          // 왜 필요한가 — 자유 메모
    let createdAt: Date       // "며칠 보며 고민" 맥락
}

/// 후보 목록의 영속 저장소. §2와 무관한 순수 사용자 메모.
@MainActor
final class CandidateStore: ObservableObject {
    /// §2/TypeCatalog와 겹치지 않는 전용 키. 이 키는 자동분류 코드 어디에서도 읽지 않는다.
    private static let key = "reclass.candidates.v1"

    @Published private(set) var candidates: [ClassificationCandidate] = []

    init() { load() }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: Self.key),
              let decoded = try? JSONDecoder().decode([ClassificationCandidate].self, from: data)
        else { candidates = []; return }
        candidates = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(candidates) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }

    /// 새 후보 추가 — 최신이 위로.
    func add(name: String, note: String = "") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let c = ClassificationCandidate(id: UUID().uuidString, name: trimmed, note: note, createdAt: Date())
        candidates.insert(c, at: 0)
        save()
    }

    func delete(_ candidate: ClassificationCandidate) {
        candidates.removeAll { $0.id == candidate.id }
        save()
    }

    func delete(atOffsets offsets: IndexSet) {
        candidates.remove(atOffsets: offsets)
        save()
    }

    /// 이름·메모 편집 저장(실제). 특성·필드·규칙 같은 구조 설계는 아직 여기 없다(껍데기).
    func update(id: String, name: String, note: String) {
        guard let idx = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[idx].name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        candidates[idx].note = note
        save()
    }
}

// MARK: - 분류 관리 화면 (§2 읽기 전용 + 재설계 후보 편집)

/// 설정 → 분류 관리. 위: 지금 실제로 쓰는 §2(읽기 전용 · 못 고침).
/// 아래: 재설계 후보(검토 중 메모 · 실제 저장 · 자동분류 비참조).
struct ClassificationManagerView: View {
    @StateObject private var store = CandidateStore()
    @State private var showAdd = false
    @State private var newName = ""

    var body: some View {
        List {
            currentSection
            candidateSection
        }
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .navigationTitle("분류 관리")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { newName = ""; showAdd = true } label: { Image(systemName: "plus") }
                    .tint(Palette.accent)
            }
        }
        .alert("후보 추가", isPresented: $showAdd) {
            TextField("후보 이름 (예: 살마인드)", text: $newName)
            Button("추가") { store.add(name: newName) }
            Button("취소", role: .cancel) { }
        } message: {
            Text("검토 중 아이디어 메모입니다 — 실제 분류가 아니고 자동 분류는 쓰지 않습니다.")
        }
    }

    // §2: 자동분류가 쓰는 실제 체계 — 읽기 전용.
    private var currentSection: some View {
        Section {
            ForEach(TypeCatalog.assignable) { meta in
                HStack(spacing: 10) {
                    Image(systemName: meta.symbol).foregroundStyle(meta.color).frame(width: 24)
                    Text(meta.label).foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Palette.textTertiary)
                }
                .listRowBackground(Palette.surface)
            }
        } header: {
            Text("현재 분류 · 자동 분류가 쓰는 실제 체계")
                .font(.caption).foregroundStyle(Palette.textTertiary).textCase(nil)
        } footer: {
            Text("여기서는 못 고칩니다 — 실제 분류 체계(§2)라 신중히 재설계 후에만 바뀝니다.")
                .font(.caption2).foregroundStyle(Palette.textTertiary)
        }
    }

    // 재설계 후보: 검토 중 메모 — 실제 저장, 자동분류 비참조.
    private var candidateSection: some View {
        Section {
            if store.candidates.isEmpty {
                Text("아직 후보가 없어요. 우측 상단 +로 아이디어를 붙잡아 두세요.")
                    .font(.callout).foregroundStyle(Palette.textSecondary)
                    .listRowBackground(Palette.surface)
            } else {
                ForEach(store.candidates) { c in
                    NavigationLink {
                        CandidateEditView(store: store, candidateID: c.id)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "lightbulb").foregroundStyle(Palette.today).frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).foregroundStyle(Palette.textPrimary)
                                if !c.note.isEmpty {
                                    Text(c.note).font(.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
                                }
                            }
                        }
                    }
                    .listRowBackground(Palette.surface)
                }
                .onDelete { store.delete(atOffsets: $0) }
            }
        } header: {
            Text("재설계 후보 · 검토 중 메모").font(.caption).foregroundStyle(Palette.textTertiary).textCase(nil)
        } footer: {
            Text("⚠️ 실제 분류가 아닙니다. 자동 분류는 이 목록을 쓰지 않아요 — 순전히 내 아이디어 메모이며, 며칠 곱씹으려고 저장만 됩니다.")
                .font(.caption2).foregroundStyle(Palette.today)
        }
    }
}

// MARK: - 후보 편집 화면 (이름·메모는 실제 저장 / 구조 설계는 껍데기)

/// 후보 하나 편집. 이름·메모는 실제 저장된다(아이디어를 다듬는 게 목적).
/// 특성·필드·자동분류 규칙 같은 **구조 설계는 아직 껍데기** — 각 분류 설계가 끝난 뒤 연결한다.
struct CandidateEditView: View {
    @ObservedObject var store: CandidateStore
    let candidateID: String
    @State private var name = ""
    @State private var note = ""
    @State private var loaded = false

    var body: some View {
        List {
            Section {
                TextField("후보 이름", text: $name)
                    .foregroundStyle(Palette.textPrimary).listRowBackground(Palette.surface)
                TextField("메모 (왜 이 분류가 필요한가)", text: $note, axis: .vertical)
                    .lineLimit(3...8)
                    .foregroundStyle(Palette.textPrimary).listRowBackground(Palette.surface)
            } header: {
                Text("아이디어 (저장됨)").font(.caption).foregroundStyle(Palette.textTertiary).textCase(nil)
            }

            Section {
                placeholderRow("특성")
                placeholderRow("추가 필드")
                placeholderRow("자동 분류 규칙")
            } header: {
                Text("구조 설계 · 준비 중").font(.caption).foregroundStyle(Palette.textTertiary).textCase(nil)
            } footer: {
                Text("특성·필드·규칙 편집은 각 분류 설계가 끝난 뒤 연결됩니다. 지금은 자리만 잡아둔 껍데기예요.")
                    .font(.caption2).foregroundStyle(Palette.textTertiary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .navigationTitle("후보 편집")
        .onAppear {
            guard !loaded, let c = store.candidates.first(where: { $0.id == candidateID }) else { return }
            name = c.name; note = c.note; loaded = true
        }
        .onDisappear { store.update(id: candidateID, name: name, note: note) }
    }

    private func placeholderRow(_ label: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.textSecondary)
            Spacer()
            Text("준비 중").font(.caption).foregroundStyle(Palette.textTertiary)
        }
        .listRowBackground(Palette.surface)
    }
}
