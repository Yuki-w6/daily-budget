import SwiftUI

/// 画面A：初期設定。ひとつの金額を決めるだけの画面なので、1画面の流れとして組み、
/// 金額入力を主役にする（PRD §5.2）。
struct OnboardingView: View {
    let store: BudgetStore

    @State private var amountText = String(AppConstants.suggestedDailyAmountYen)
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var amountFocused: Bool

    /// 1円以上の整数のみ受け付ける（PRD §5.2）。
    private var dailyAmountYen: Int64? {
        guard let value = Int64(amountText.trimmingCharacters(in: .whitespaces)), value >= 1 else {
            return nil
        }
        return value
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 40) {
                VStack(spacing: 14) {
                    Text("今日、いくら使える？")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("1日に使ってよい金額を決めます。使わなかった分はその月のあいだ、翌日に繰り越されます。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                amountField

                Text("家賃や光熱費などの固定費は含めず、日々の変動費だけを記録します。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 28)
            .padding(.top, 48)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) { startButton }
        .onAppear { amountFocused = true }
    }

    private var amountField: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("¥")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("2000", text: $amountText)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .keyboardType(.numberPad)
                    .focused($amountFocused)
                    .accessibilityLabel("1日の予算")
            }
            Divider()
            Text("1日の予算")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var startButton: some View {
        VStack(spacing: 10) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            } else if dailyAmountYen == nil && !amountText.isEmpty {
                Text("1円以上の整数で入力してください。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button {
                start()
            } label: {
                Text(isSaving ? "保存中…" : "はじめる")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(dailyAmountYen == nil || isSaving)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func start() {
        guard let dailyAmountYen, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            // 端末内保存を完了してからホームへ遷移する（PRD §5.2）。
            try store.completeOnboarding(dailyAmountYen: dailyAmountYen)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
