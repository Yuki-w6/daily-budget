import SwiftUI
import DailyBudgetCore

/// 画面B：ホーム。アプリを開いた瞬間に今日いくら使えるかがわかることを最優先にする（PRD §5.3）。
///
/// 月次の累積はレポートタブに集約し、ここでは今日の金額と直近の支出だけを出す。
struct HomeView: View {
    let store: BudgetStore

    @State private var editorTarget: ExpenseEditorTarget?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    if let breakdown = store.todayBreakdown {
                        availableSection(breakdown)
                    }
                    recordButton
                    recentExpensesSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .navigationTitle("Daily Budget")
            .sheet(item: $editorTarget) { target in
                ExpenseEditorView(store: store, target: target)
            }
        }
    }

    // MARK: 今日使える金額

    private func availableSection(_ breakdown: TodayBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(breakdown.day.japaneseLongText)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("今日使える金額")
                .font(.headline)

            Text(verbatim: Yen.amount(breakdown.availableYen))
                .font(.system(size: 52, weight: .bold, design: .rounded))
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

            Text(verbatim: Self.breakdownLine(breakdown))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Self.breakdownAccessibilityLabel(breakdown))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 内訳は1行にまとめる。
    ///
    /// 「予算」は1日の予算と前日までの繰越を足した額。この額から支出を引くと
    /// 大きな数字と一致するので、計算が追える。繰越が0円の日は括弧を出さない。
    private static func breakdownLine(_ breakdown: TodayBreakdown) -> String {
        let budget = breakdown.dailyBudgetYen + breakdown.carryOverYen
        var line = "予算 " + Yen.amount(budget)
        if breakdown.carryOverYen != 0 {
            line += "（繰越 " + Yen.signedAmount(breakdown.carryOverYen) + "）"
        }
        if breakdown.todayExpenseYen > 0 {
            line += " ・ 支出 −" + Yen.amount(breakdown.todayExpenseYen)
        }
        return line
    }

    private static func breakdownAccessibilityLabel(_ breakdown: TodayBreakdown) -> String {
        let budget = breakdown.dailyBudgetYen + breakdown.carryOverYen
        var parts = ["予算 \(Yen.spoken(budget))"]
        if breakdown.carryOverYen != 0 {
            parts.append("うち繰越 \(Yen.spoken(breakdown.carryOverYen))")
        }
        if breakdown.todayExpenseYen > 0 {
            parts.append("支出 \(Yen.spoken(breakdown.todayExpenseYen))")
        }
        return parts.joined(separator: "、")
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
        VStack(alignment: .leading, spacing: 4) {
            Text("最近の支出")
                .font(.headline)
                .padding(.bottom, 4)

            if store.currentMonthExpenses.isEmpty {
                Text("今月の支出はまだありません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(store.currentMonthExpenses.prefix(8)) { expense in
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(verbatim: CalendarDay(iso: expense.spentOnISO)?.shortText ?? expense.spentOnISO)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(expense.category?.name ?? "その他")
                if let memo = expense.memo, !memo.isEmpty {
                    Text(memo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(verbatim: Yen.amount(expense.amountYen))
                .monospacedDigit()
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}
