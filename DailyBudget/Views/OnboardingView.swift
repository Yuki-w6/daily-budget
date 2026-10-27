import SwiftUI

/// 画面A：初期設定。最初の操作だけで使い始められるようにする（PRD §5.2）。
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
        NavigationStack {
            Form {
                Section {
                    Text("1日に使ってよい金額を決めます。使わなかった分はその月のあいだ翌日に繰り越されます。")
                } header: {
                    Text("このアプリの使い方")
                }

                Section {
                    HStack {
                        Text("円")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField("2000", text: $amountText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($amountFocused)
                            .accessibilityLabel("日額予算")
                    }
                } header: {
                    Text("日額予算")
                } footer: {
                    Text("1円以上の整数で入力します。あとから変更できます。")
                }

                Section {
                    Text("家賃・水道光熱費・通信費・保険・借入返済などの固定費は、この日額予算に含めません。日々の変動費だけを記録します。")
                } header: {
                    Text("記録するもの")
                }

                Section {
                    Text("記録は端末内にのみ保存されます。機種変更やアプリの削除では引き継げません。")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("データの保存")
                }
            }
            .navigationTitle("はじめる")
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
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
                .padding()
                .background(.bar)
            }
            .onAppear { amountFocused = true }
        }
    }

    private func start() {
        guard let dailyAmountYen, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            // 保存が完了してからホームへ遷移する（PRD §5.2）。
            try store.completeOnboarding(dailyAmountYen: dailyAmountYen)
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
