import SwiftUI
import DailyBudgetCore

/// 画面B：ホーム。アプリを開いた瞬間に今日いくら使えるかがわかることを最優先にする（PRD §5.3）。
struct HomeView: View {
    let store: BudgetStore

    @State private var editorTarget: ExpenseEditorTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let breakdown = store.todayBreakdown {
                        availableSection(breakdown)
                    }
                    if let summary = store.currentMonthSummary {
                        monthSection(summary)
                    }
                    recordButton
                    recentExpensesSection
                }
                .padding()
            }
            .navigationTitle("Daily Budget")
            .sheet(item: $editorTarget) { target in
                ExpenseEditorView(store: store, target: target)
            }
        }
    }

    // MARK: 今日使える金額

    private func availableSection(_ breakdown: TodayBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(breakdown.day.japaneseLongText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("今日使える金額")
                .font(.headline)

            Text(Yen.amount(breakdown.availableYen))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .foregroundStyle(breakdown.isOverBudget ? .red : .primary)
                .accessibilityLabel("今日使える金額 \(Yen.spoken(breakdown.availableYen))")

            if breakdown.isOverBudget {
                // 色だけに頼らず文字でも伝える（PRD §5.3 / §9 アクセシビリティ）。
                Label(
                    "予算を\(Yen.amount(abs(breakdown.availableYen)))超過しています",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)
            }

            // 内訳：日額予算・前日までの繰越・今日の支出（PRD §5.3）。
            VStack(alignment: .leading, spacing: 4) {
                breakdownRow("日額予算", Yen.amount(breakdown.dailyBudgetYen))
                breakdownRow("前日までの繰越", Yen.signedAmount(breakdown.carryOverYen))
                breakdownRow("今日の支出", "−" + Yen.amount(breakdown.todayExpenseYen))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func breakdownRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 今月の実績

    private func monthSection(_ summary: MonthSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("今月の実績")
                .font(.headline)
            statRow("累積予算", Yen.amount(summary.budgetTotalYen))
            statRow("累積支出", Yen.amount(summary.expenseTotalYen))
            statRow("累積余剰", Yen.signedAmount(summary.surplusYen))
            statRow("経過日数", "\(summary.days.count)日")
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).monospacedDigit().fontWeight(.medium)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: 操作

    private var recordButton: some View {
        Button {
            editorTarget = .new(defaultDate: store.today)
        } label: {
            Label("支出を記録", systemImage: "plus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: 最近の支出

    private var recentExpensesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("最近の支出")
                .font(.headline)

            if store.currentMonthExpenses.isEmpty {
                Text("今月の支出はまだありません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.currentMonthExpenses.prefix(10)) { expense in
                    Button {
                        editorTarget = .existing(expense)
                    } label: {
                        expenseRow(expense)
                    }
                    .buttonStyle(.plain)
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func expenseRow(_ expense: ExpenseEntity) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(CalendarDay(iso: expense.spentOnISO)?.shortText ?? expense.spentOnISO)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .leading)

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

            Text(Yen.amount(expense.amountYen))
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}
