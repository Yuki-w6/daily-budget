import SwiftUI
import DailyBudgetCore

/// 画面D：日別明細。支出リストとその日の集計を出し、ここから編集・削除・追加ができる（PRD §5.5）。
struct DayDetailView: View {
    let store: BudgetStore
    let day: CalendarDay

    @State private var detail: MonthDetail?
    @State private var editorTarget: ExpenseEditorTarget?
    @State private var errorMessage: String?

    /// 確定済みの月、未到来の日、利用開始日より前は編集できない（PRD §5.4 / §5.5）。
    private var isEditable: Bool { store.isEditable(day) }

    private var expenses: [ExpenseEntity] {
        detail?.expenses(on: day) ?? []
    }

    var body: some View {
        List {
            if let summary = detail?.dailySummary(on: day) {
                Section("この日の集計") {
                    row("日次予算", Yen.amount(summary.budgetYen))
                    row("日次支出", Yen.amount(summary.expenseYen))
                    row("終了時点の累積余剰", Yen.signedAmount(summary.cumulativeSurplusYen))
                    if summary.cumulativeSurplusYen < 0 {
                        Label(
                            "予算を\(Yen.amount(abs(summary.cumulativeSurplusYen)))超過しています",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.red)
                    }
                }
            }

            Section("支出") {
                if expenses.isEmpty {
                    // 未記録の日は支出0円として扱う（PRD §5.5）。
                    Text("この日の支出はありません。")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(expenses) { expense in
                        expenseRow(expense)
                    }
                }
            }

            if let detail, detail.isClosed {
                Section {
                    Label(
                        "この月は確定済みのため閲覧専用です。訂正するには確定を解除します。",
                        systemImage: "lock"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(day.japaneseLongText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditable {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editorTarget = .new(defaultDate: day)
                    } label: {
                        Label("支出を記録", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(item: $editorTarget) { target in
            ExpenseEditorView(store: store, target: target)
        }
        .onAppear(perform: refresh)
        .onChange(of: store.dataVersion) { _, _ in refresh() }
    }

    private func refresh() {
        detail = store.monthDetail(for: day.yearMonth)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func expenseRow(_ expense: ExpenseEntity) -> some View {
        let content = HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.category?.name ?? "その他")
                if let memo = expense.memo, !memo.isEmpty {
                    Text(memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            Text(Yen.amount(expense.amountYen)).monospacedDigit()
        }

        if isEditable {
            Button {
                editorTarget = .existing(expense)
            } label: {
                content.contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .swipeActions(edge: .trailing) {
                Button("削除", role: .destructive) {
                    delete(expense)
                }
            }
        } else {
            content
        }
    }

    private func delete(_ expense: ExpenseEntity) {
        errorMessage = nil
        do {
            try store.deleteExpense(expense)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
