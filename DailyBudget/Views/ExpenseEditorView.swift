import SwiftUI
import DailyBudgetCore

/// 支出登録・編集モーダルの対象。
enum ExpenseEditorTarget: Identifiable {
    case new(defaultDate: CalendarDay)
    case existing(ExpenseEntity)

    var id: String {
        switch self {
        case .new(let defaultDate): "new-\(defaultDate.iso)"
        case .existing(let expense): "existing-\(expense.uuid.uuidString)"
        }
    }
}

/// 画面C：支出登録・編集モーダル。少ないタップ数で保存できることを重視する（PRD §5.4）。
struct ExpenseEditorView: View {
    let store: BudgetStore
    let target: ExpenseEditorTarget

    @Environment(\.dismiss) private var dismiss

    @State private var amountText = ""
    @State private var spentOn = CalendarDay(Date(), in: AppConstants.budgetTimeZone)
    @State private var category: ExpenseCategoryEntity?
    @State private var memo = ""
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var isConfirmingDelete = false
    @FocusState private var amountFocused: Bool

    private var editingExpense: ExpenseEntity? {
        if case .existing(let expense) = target { return expense }
        return nil
    }

    /// 0円・負数は登録できない（PRD §5.4）。
    private var amountYen: Int64? {
        guard let value = Int64(amountText.trimmingCharacters(in: .whitespaces)), value >= 1 else {
            return nil
        }
        return value
    }

    private var canSave: Bool { amountYen != nil && !isSaving }

    /// 支出日として選べる範囲。利用開始日より前と未来日は登録できない（PRD §5.4）。
    private var selectableDateRange: ClosedRange<Date>? {
        guard let range = store.selectableExpenseDateRange else { return nil }
        let lower = range.lowerBound.noonDate(in: AppConstants.budgetTimeZone)
        let upper = range.upperBound.noonDate(in: AppConstants.budgetTimeZone)
        return lower <= upper ? lower...upper : nil
    }

    private var spentOnBinding: Binding<Date> {
        Binding(
            get: { spentOn.noonDate(in: AppConstants.budgetTimeZone) },
            set: { spentOn = CalendarDay($0, in: AppConstants.budgetTimeZone) }
        )
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("金額") {
                    HStack {
                        Text("¥")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField("0", text: $amountText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .font(.title2.monospacedDigit())
                            .focused($amountFocused)
                            .accessibilityLabel("金額")
                    }
                }

                Section("支出日") {
                    if let range = selectableDateRange {
                        DatePicker(
                            "支出日",
                            selection: spentOnBinding,
                            in: range,
                            displayedComponents: .date
                        )
                    } else {
                        Text(spentOn.japaneseLongText)
                    }
                }

                Section("カテゴリ") {
                    Picker("カテゴリ", selection: $category) {
                        ForEach(store.selectableCategories) { candidate in
                            Text(candidate.name).tag(Optional(candidate))
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    TextField("メモ（任意）", text: $memo, axis: .vertical)
                        .lineLimit(1...4)
                        .onChange(of: memo) { _, newValue in
                            if newValue.count > AppConstants.memoMaxLength {
                                memo = String(newValue.prefix(AppConstants.memoMaxLength))
                            }
                        }
                } header: {
                    Text("メモ")
                } footer: {
                    Text("\(memo.count) / \(AppConstants.memoMaxLength)文字")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }

                if editingExpense != nil {
                    Section {
                        Button("この支出を削除", role: .destructive) {
                            isConfirmingDelete = true
                        }
                        .disabled(isSaving)
                    }
                }
            }
            .navigationTitle(editingExpense == nil ? "支出を記録" : "支出を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    // 保存中はボタンを無効化し、二重タップでの重複登録を防ぐ（PRD §5.4）。
                    Button("保存") { save() }
                        .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "この支出を削除しますか？",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) { delete() }
                Button("キャンセル", role: .cancel) {}
            }
            .onAppear(perform: prepare)
        }
    }

    private func prepare() {
        switch target {
        case .new(let defaultDate):
            spentOn = defaultDate
            // 前回選択したカテゴリを初期値に使う（PRD §5.4）。
            category = store.currentMonthExpenses.first?.category ?? store.selectableCategories.first
        case .existing(let expense):
            amountText = String(expense.amountYen)
            spentOn = CalendarDay(iso: expense.spentOnISO) ?? store.today
            category = expense.category ?? store.selectableCategories.first
            memo = expense.memo ?? ""
        }
        amountFocused = true
    }

    private func save() {
        guard let amountYen, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            try store.saveExpense(
                editing: editingExpense,
                amountYen: amountYen,
                spentOn: spentOn,
                category: category,
                memo: memo
            )
            dismiss()
        } catch {
            // 保存失敗時は成功したように見せず、入力内容を保持して再試行できるようにする（PRD §8.2）。
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }

    private func delete() {
        guard let editingExpense, !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            try store.deleteExpense(editingExpense)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isSaving = false
    }
}
