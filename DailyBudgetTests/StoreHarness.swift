import Foundation
import SwiftData
@testable import DailyBudget
import DailyBudgetCore

/// テスト用の時計。`BudgetStore` に任意の「今日」を渡すために使う。
final class TestClock {
    var now: Date

    init(_ day: CalendarDay) {
        now = day.noonDate(in: AppConstants.budgetTimeZone)
    }
}

/// In-memory の SwiftData と `BudgetStore` を組み立てる。
///
/// 端末のデータベースを使わないので、テストごとに完全に独立した状態から始められる。
/// CloudKit の設定は付けない。同期は in-memory では意味がなく、
/// 重複の解消はレコードを直接作れば再現できるため。
@MainActor
final class StoreHarness {
    let container: ModelContainer
    let context: ModelContext
    let store: BudgetStore
    private let clock: TestClock

    init(today: CalendarDay) throws {
        let schema = Schema([
            AppSettingsEntity.self,
            BudgetRuleEntity.self,
            ExpenseCategoryEntity.self,
            ExpenseEntity.self,
            MonthlySettlementEntity.self
        ])
        container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
        context = container.mainContext
        let clock = TestClock(today)
        self.clock = clock
        store = BudgetStore(context: context, clock: { clock.now })
        store.bootstrap()
    }

    /// 注入している現在時刻。別の端末から流れ込んだレコードを作るときに使う。
    /// 実時刻を使うと、進めた日付より古い扱いになってしまう。
    var now: Date { clock.now }

    /// 日付を進める。進めたあとは起動時と同じ処理を走らせる。
    func travel(to day: CalendarDay) {
        clock.now = day.noonDate(in: AppConstants.budgetTimeZone)
        store.bootstrap()
    }

    /// 初期設定を終えた状態にする。
    func start(dailyAmountYen: Int64 = 2_000) throws {
        try store.completeOnboarding(dailyAmountYen: dailyAmountYen)
    }

    func category(named name: String) -> ExpenseCategoryEntity? {
        store.selectableCategories.first { $0.name == name }
    }

    @discardableResult
    func addExpense(
        _ amountYen: Int64,
        on day: CalendarDay,
        categoryName: String = "食費",
        memo: String? = nil
    ) throws -> ExpenseEntity {
        try store.saveExpense(
            amountYen: amountYen,
            spentOn: day,
            category: category(named: categoryName),
            memo: memo
        )
        return store.currentMonthExpenses.first {
            $0.spentOnISO == day.iso && $0.amountYen == amountYen
        }!
    }

    func fetchAll<T: PersistentModel>(_ type: T.Type) -> [T] {
        (try? context.fetch(FetchDescriptor<T>())) ?? []
    }
}

extension CalendarDay {
    /// テストで日付を書きやすくするための補助。
    static func of(_ year: Int, _ month: Int, _ day: Int) -> CalendarDay {
        CalendarDay(year: year, month: month, day: day)
    }
}
