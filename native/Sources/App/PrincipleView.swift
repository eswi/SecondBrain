import SwiftUI
import SecondBrainCore

/// 원칙(ambient) — type=principle 항목 전체를 상시 인지용으로 크게 본다.
struct PrincipleView: View {
    @ObservedObject var model: InboxModel

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()
                if model.principles.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "star").font(.system(size: 40)).foregroundStyle(Palette.textTertiary)
                        Text("원칙이 없어요").font(.callout).foregroundStyle(Palette.textSecondary)
                        Text("항목의 종류를 '원칙'으로 바꾸면\n여기와 받은함 상단 띠에 나타나요.")
                            .font(.caption).foregroundStyle(Palette.textTertiary).multilineTextAlignment(.center)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(model.principles, id: \.id) { p in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(TypeCatalog.meta("principle").color)
                                        .padding(.top, 2)
                                    Text(p.raw ?? "")
                                        .font(.body.weight(.medium)).foregroundStyle(Palette.textPrimary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .padding(14)
                                .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.cardStroke))
                            }
                        }
                        .padding(14)
                    }
                }
            }
            .navigationTitle("원칙")
        }
    }
}
