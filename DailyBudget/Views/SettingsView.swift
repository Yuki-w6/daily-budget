import SwiftUI
import DailyBudgetCore

/// 画面F：設定。日額予算の変更とデータの管理（PRD §5.7）。
struct SettingsView: View {
    let store: BudgetStore

    @State private var isChangingBudget = false
    @State private var isConfirmingDelete = false
    @State private var isConfirmingDeleteAgain = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("1日の予算") {
                    LabeledContent("1日の予算") {
                        Text(verbatim: store.currentDailyAmountYen.map(Yen.amount) ?? "—")
                            .monospacedDigit()
                    }
                    Button("金額を変更") { isChangingBudget = true }
                        .disabled(store.currentDailyAmountYen == nil)
                }

                if !store.budgetRuleHistory().isEmpty {
                    Section {
                        ForEach(store.budgetRuleHistory()) { rule in
                            LabeledContent(rule.effectiveFrom.japaneseLongText) {
                                Text(verbatim: Yen.amount(rule.dailyAmountYen) + " / 日")
                                    .monospacedDigit()
                            }
                            .accessibilityElement(children: .combine)
                        }
                    } header: {
                        Text("変更履歴")
                    } footer: {
                        Text("適用を始めた日ごとに記録しています。過去の予算は後から変わりません。")
                    }
                }

                Section("通貨と日付") {
                    LabeledContent("通貨", value: "日本円（JPY）")
                    LabeledContent("タイムゾーン", value: AppConstants.timeZoneIdentifier)
                    if let activeStartDate = store.activeStartDate {
                        LabeledContent("使い始めた日", value: activeStartDate.japaneseLongText)
                    }
                }

                Section {
                    // #13 ではじめる画面から移した案内。PRD §9 が画面上での明示を求めている。
                    Text("記録はこの端末の中にだけ保存されます。第三者へ送信されることはありません。機種変更・端末の故障・アプリの削除では記録を引き継げません。")
                        .font(.footnote)
                    LabeledContent("データの書き出し", value: "今後のアップデートで対応")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("データの取り扱い")
                }

                Section("アプリについて") {
                    LabeledContent("バージョン", value: Self.versionText)
                }

                Section {
                    Button("すべてのデータを削除", role: .destructive) {
                        isConfirmingDelete = true
                    }
                } footer: {
                    Text("予算の設定、支出の記録、月末の確定結果をすべて消します。元に戻せません。")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("設定")
            .sheet(isPresented: $isChangingBudget) {
                BudgetChangeView(store: store)
            }
            // 全データ削除の確認は2段階にする（PRD §5.7）。
            .confirmationDialog(
                "すべてのデータを削除しますか？",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("削除に進む", role: .destructive) { isConfirmingDeleteAgain = true }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("予算の設定、支出の記録、月末の確定結果がすべて消えます。")
            }
            .alert("本当に削除しますか？", isPresented: $isConfirmingDeleteAgain) {
                Button("すべて削除", role: .destructive) { deleteAll() }
                Button("キャンセル", role: .cancel) {}
            } message: {
                Text("この操作は元に戻せません。削除後は初期設定からやり直します。")
            }
        }
    }

    private func deleteAll() {
        errorMessage = nil
        do {
            try store.deleteAllData()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }
}

/// 日額予算の変更。適用日を選び、計算への影響を確認してから保存する（PRD §5.7 / §6.1）。
struct BudgetChangeView: View {
    let store: BudgetStore

    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var timing: BudgetChangeTiming = .tomorrow
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var amountFocused: Bool

    private var dailyAmountYen: Int64? {
        guard let value = Int64(amountText.trimmingCharacters(in: .whitespaces)), value >= 1 else {
            return nil
        }
        return value
    }

    private var impact: BudgetChangeImpact? {
        guard let dailyAmountYen else { return nil }
        return store.previewBudgetChange(to: dailyAmountYen, timing: timing)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("新しい1日の予算") {
                    HStack {
                        Text("¥")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField("0", text: $amountText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.title2.monospacedDigit())
                            .focused($amountFocused)
                            .accessibilityLabel("新しい1日の予算")
                    }
                }

                Section {
                    Picker("適用日", selection: $timing) {
                        Text("今日から").tag(BudgetChangeTiming.today)
                        Text("明日から").tag(BudgetChangeTiming.tomorrow)
                        Text("翌月1日から").tag(BudgetChangeTiming.nextMonth)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("いつから適用するか")
                } footer: {
                    Text("昨日以前の予算は変更されません。確定済みの月にも影響しません。")
                }

                if let impact {
                    Section {
                        LabeledContent("適用開始日") {
                            Text(verbatim: impact.effectiveFrom.japaneseLongText)
                        }
                        LabeledContent("今日使える金額") {
                            Text(verbatim: impact.changesToday
                                ? "\(Yen.amount(impact.todayAvailableBeforeYen)) → "
                                    + Yen.amount(impact.todayAvailableAfterYen)
                                : "変わりません")
                                .monospacedDigit()
                        }
                        LabeledContent("今月の予算") {
                            Text(verbatim: impact.changesThisMonth
                                ? "\(Yen.amount(impact.monthBudgetBeforeYen)) → "
                                    + Yen.amount(impact.monthBudgetAfterYen)
                                : "変わりません")
                                .monospacedDigit()
                        }
                    } header: {
                        Text("この変更の影響")
                    } footer: {
                        Text("前の日までの残りは、そのまま引き継がれます。")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("1日の予算を変更")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(dailyAmountYen == nil || isSaving)
                }
            }
            .onAppear {
                amountText = store.currentDailyAmountYen.map(String.init) ?? ""
                amountFocused = true
            }
        }
    }

    private func save() {
        guard let dailyAmountYen, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            try store.changeDailyBudget(to: dailyAmountYen, timing: timing)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
