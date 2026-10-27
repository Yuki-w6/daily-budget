import Foundation
import SwiftData
import DailyBudgetCore

/// 永続化層と `BudgetCalculator` をつなぐリポジトリ。PRD §11 Phase 1「リポジトリ層」に対応する。
///
/// 画面に出す数字はすべてここが持つ派生状態から読む。各画面が独自に集計しないため、
/// ホーム・履歴・レポートの表示が食い違わない（PRD §8.1）。
/// 書き込みはローカルDBへの保存が成功してから派生状態を更新する（PRD §8.2）。
@MainActor
@Observable
final class BudgetStore {
    /// 保存に失敗したことを画面に伝えるためのエラー。入力内容は呼び出し側で保持する。
    enum StoreError: LocalizedError {
        case notConfigured
        case invalidAmount
        case monthClosed
        case settlementNotFound
        case saveFailed(underlying: String)

        var errorDescription: String? {
            switch self {
            case .notConfigured:
                "初期設定が完了していません。"
            case .invalidAmount:
                "金額は1円以上の整数で入力してください。"
            case .monthClosed:
                "確定済みの月です。編集するには確定を解除してください。"
            case .settlementNotFound:
                "この月の確定記録が見つかりませんでした。"
            case .saveFailed(let underlying):
                "保存できませんでした。もう一度お試しください。（\(underlying)）"
            }
        }
    }

    private let context: ModelContext
    private let timeZone: TimeZone
    /// 現在時刻の供給元。テストで任意の日付を注入できるようにする。
    private let clock: () -> Date

    // MARK: 派生状態

    private(set) var isOnboardingCompleted = false
    private(set) var activeStartDate: CalendarDay?
    private(set) var calculator: BudgetCalculator?
    /// ホームの「今日使える金額」とその内訳。
    private(set) var todayBreakdown: TodayBreakdown?
    /// 当月の実績（閲覧日まで）。
    private(set) var currentMonthSummary: MonthSummary?
    /// 当月の支出。日付の新しい順。
    private(set) var currentMonthExpenses: [ExpenseEntity] = []
    /// 新規登録で選べるカテゴリ。
    private(set) var selectableCategories: [ExpenseCategoryEntity] = []
    /// 確定レコードが `closed` の月。編集できるかの判定に使う。
    private(set) var closedMonths: Set<YearMonth> = []
    /// 保存が成功するたびに増える。表示中の月を読み直す契機として画面が監視する。
    private(set) var dataVersion = 0

    init(context: ModelContext, timeZone: TimeZone = AppConstants.budgetTimeZone, clock: @escaping () -> Date = Date.init) {
        self.context = context
        self.timeZone = timeZone
        self.clock = clock
    }

    /// 今日の暦日。`Asia/Tokyo` の暦日で判定する（PRD §6.4）。
    var today: CalendarDay { CalendarDay(clock(), in: timeZone) }

    /// 支出日として選べる範囲。判定規則は `ExpenseEditPolicy` にある（PRD §5.4）。
    var selectableExpenseDateRange: ClosedRange<CalendarDay>? {
        guard let activeStartDate else { return nil }
        return ExpenseEditPolicy.editableDateRange(
            activeStartDate: activeStartDate,
            today: today,
            closedMonths: closedMonths
        )
    }

    /// その日の支出を登録・編集できるか。
    func isEditable(_ day: CalendarDay) -> Bool {
        guard let activeStartDate else { return false }
        return ExpenseEditPolicy.isEditable(
            day,
            activeStartDate: activeStartDate,
            today: today,
            closedMonths: closedMonths
        )
    }

    /// 履歴で表示できる月の範囲。利用開始月から当月まで。
    var browsableMonths: ClosedRange<YearMonth>? {
        guard let activeStartDate else { return nil }
        let first = activeStartDate.yearMonth
        let last = today.yearMonth
        return first <= last ? first...last : nil
    }

    func isClosed(_ yearMonth: YearMonth) -> Bool {
        closedMonths.contains(yearMonth)
    }

    // MARK: - 起動時

    /// 起動・フォアグラウンド復帰時に呼ぶ。未確定の過去月を確定してから派生状態を読み直す。
    func bootstrap() {
        seedCategoriesIfNeeded()
        settlePendingMonths()
        reload()
    }

    /// 初期設定の完了。日額予算の最初のルールと設定レコードを作る（PRD §5.2）。
    func completeOnboarding(dailyAmountYen: Int64) throws {
        let startDate = today
        let settings = try fetchSettings() ?? {
            let created = AppSettingsEntity(activeStartDateISO: startDate.iso)
            context.insert(created)
            return created
        }()
        settings.activeStartDateISO = startDate.iso
        settings.onboardingCompleted = true

        context.insert(
            BudgetRuleEntity(effectiveFromISO: startDate.iso, dailyAmountYen: dailyAmountYen)
        )

        // 端末内保存を完了してからホームに遷移する（PRD §5.2）。
        try save()
        bootstrap()
    }

    // MARK: - 支出

    /// 支出を新規登録、または既存レコードを更新する。
    ///
    /// - Parameter editing: `nil` なら新規登録。渡した場合はそのレコードを書き換える。
    func saveExpense(
        editing existing: ExpenseEntity? = nil,
        amountYen: Int64,
        spentOn: CalendarDay,
        category: ExpenseCategoryEntity?,
        memo: String?
    ) throws {
        // 範囲の途中に確定済みの月が残ることがあるため、保存時にも月を確認する。
        guard isEditable(spentOn) else { throw StoreError.monthClosed }

        let trimmedMemo = memo?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMemo = (trimmedMemo?.isEmpty ?? true)
            ? nil
            : String(trimmedMemo!.prefix(AppConstants.memoMaxLength))

        if let existing {
            existing.amountYen = amountYen
            existing.spentOnISO = spentOn.iso
            existing.spentOnMonthISO = spentOn.yearMonth.iso
            existing.category = category
            existing.memo = normalizedMemo
            existing.updatedAt = clock()
        } else {
            context.insert(
                ExpenseEntity(
                    spentOnISO: spentOn.iso,
                    spentOnMonthISO: spentOn.yearMonth.iso,
                    amountYen: amountYen,
                    memo: normalizedMemo,
                    category: category
                )
            )
        }

        try save()
        reload()
    }

    func deleteExpense(_ expense: ExpenseEntity) throws {
        context.delete(expense)
        try save()
        reload()
    }

    // MARK: - 日額予算の変更

    /// 今日適用されている日額予算。
    var currentDailyAmountYen: Int64? {
        guard let calculator else { return nil }
        let amount = calculator.dailyBudget(on: today)
        return amount >= 1 ? amount : calculator.budgetRules.first?.dailyAmountYen
    }

    /// 予算変更の履歴。有効開始日の新しい順（PRD §5.7）。
    func budgetRuleHistory() -> [BudgetRule] {
        calculator?.budgetRules.sorted { $0.effectiveFrom > $1.effectiveFrom } ?? []
    }

    /// 保存前に変更の影響を試算する（PRD §5.7）。
    func previewBudgetChange(
        to dailyAmountYen: Int64,
        timing: BudgetChangeTiming
    ) -> BudgetChangeImpact? {
        guard let calculator else { return nil }
        let today = self.today
        return BudgetChangePreview.impact(
            current: calculator,
            newDailyAmountYen: dailyAmountYen,
            effectiveFrom: timing.effectiveDate(from: today),
            today: today,
            expenses: fetchExpenseEntries(in: today.yearMonth)
        )
    }

    /// 日額予算を変更する。
    ///
    /// 有効開始日ごとの履歴として保存し、昨日以前は遡及変更しない（PRD §6.1）。
    /// 同じ有効開始日のルールが既にあれば、そのレコードを更新する。`effectiveFrom` には
    /// 一意制約があるため、新しいレコードを足すと保存に失敗する。
    func changeDailyBudget(to dailyAmountYen: Int64, timing: BudgetChangeTiming) throws {
        guard dailyAmountYen >= 1 else { throw StoreError.invalidAmount }
        let effectiveFrom = timing.effectiveDate(from: today)
        let effectiveFromISO = effectiveFrom.iso
        let now = clock()

        var descriptor = FetchDescriptor<BudgetRuleEntity>(
            predicate: #Predicate { $0.effectiveFromISO == effectiveFromISO }
        )
        descriptor.fetchLimit = 1
        if let existing = (try? context.fetch(descriptor))?.first {
            existing.dailyAmountYen = dailyAmountYen
            existing.updatedAt = now
        } else {
            context.insert(
                BudgetRuleEntity(
                    effectiveFromISO: effectiveFromISO,
                    dailyAmountYen: dailyAmountYen,
                    createdAt: now,
                    updatedAt: now
                )
            )
        }

        try save()
        reload()
    }

    // MARK: - 全データ削除

    /// 記録をすべて消して初期設定前の状態に戻す（PRD §5.7）。
    func deleteAllData() throws {
        for expense in (try? context.fetch(FetchDescriptor<ExpenseEntity>())) ?? [] {
            context.delete(expense)
        }
        for rule in (try? context.fetch(FetchDescriptor<BudgetRuleEntity>())) ?? [] {
            context.delete(rule)
        }
        for settlement in (try? context.fetch(FetchDescriptor<MonthlySettlementEntity>())) ?? [] {
            context.delete(settlement)
        }
        for settings in (try? context.fetch(FetchDescriptor<AppSettingsEntity>())) ?? [] {
            context.delete(settings)
        }
        // カテゴリは初期値なので残し、次回の初期設定でそのまま使う。
        try save()
        reload()
    }

    // MARK: - 月末確定

    /// 未確定の過去月を時系列順に確定する（PRD §6.2）。
    ///
    /// 確定レコードが既にある月は対象外なので、何度呼んでも結果は同じ（冪等）。
    /// `reopened` の月も対象外にする（`SettlementPlanner` の判断）。
    @discardableResult
    func settlePendingMonths() -> [YearMonth] {
        guard let settings = try? fetchSettings(),
              settings.onboardingCompleted,
              let activeStartDate = CalendarDay(iso: settings.activeStartDateISO)
        else { return [] }

        let existing = (try? context.fetch(FetchDescriptor<MonthlySettlementEntity>())) ?? []
        let recordedMonths = Set(existing.compactMap { YearMonth(iso: $0.yearMonthISO) })
        let pending = SettlementPlanner.monthsAwaitingSettlement(
            activeStartDate: activeStartDate,
            today: today,
            recordedMonths: recordedMonths
        )
        guard !pending.isEmpty else { return [] }

        let calculator = BudgetCalculator(
            activeStartDate: activeStartDate,
            rules: fetchBudgetRules()
        )
        let closedAt = clock()
        for month in pending {
            let settlement = calculator.settlement(
                for: month,
                expenses: fetchExpenseEntries(in: month),
                closedAt: closedAt
            )
            context.insert(
                MonthlySettlementEntity(
                    uuid: settlement.id,
                    yearMonthISO: settlement.yearMonth.iso,
                    statusRaw: settlement.status.rawValue,
                    budgetTotalYen: settlement.budgetTotalYen,
                    expenseTotalYen: settlement.expenseTotalYen,
                    surplusYen: settlement.surplusYen,
                    closedAt: settlement.closedAt,
                    recloseCount: settlement.recloseCount,
                    updatedAt: closedAt
                )
            )
        }

        // 確定処理は原子的に扱う。失敗した場合は未確定のまま残し、次回起動で再試行する（PRD §8.2）。
        do {
            try save()
        } catch {
            context.rollback()
            return []
        }
        return pending
    }

    // MARK: - 任意の月の読み出し

    /// 指定した月の集計・支出・確定レコードをまとめて読み出す。履歴と月次レポートが使う。
    ///
    /// 未到来の日には実績を出さないため、当月は閲覧日までに絞る（PRD §5.5）。
    func monthDetail(for yearMonth: YearMonth) -> MonthDetail? {
        guard let calculator else { return nil }
        let today = self.today
        let expenses = fetchExpenses(in: yearMonth)
        let entries = expenses.compactMap(Self.entry(from:))
        // 月末見込みは進行中の月にだけ意味がある。実績と混同させないため別の値として持つ。
        // 経過日数が足りない月は nil が返る。
        let projection = yearMonth == today.yearMonth
            ? SpendingPace.projection(
                calculator: calculator,
                yearMonth: yearMonth,
                expenses: entries,
                asOf: today
            )
            : nil
        return MonthDetail(
            yearMonth: yearMonth,
            summary: calculator.monthSummary(
                for: yearMonth,
                expenses: entries,
                asOf: min(yearMonth.lastDay, today)
            ),
            expenses: expenses,
            settlement: fetchSettlement(for: yearMonth),
            projection: projection
        )
    }

    /// 確定済み・確定解除中の月の一覧。新しい月が先頭（PRD §5.6 過去月一覧）。
    func settlements() -> [MonthlySettlement] {
        let descriptor = FetchDescriptor<MonthlySettlementEntity>(
            sortBy: [SortDescriptor(\.yearMonthISO, order: .reverse)]
        )
        let entities = (try? context.fetch(descriptor)) ?? []
        return entities.compactMap(Self.settlement(from:))
    }

    // MARK: - 確定の解除と再確定

    /// 確定を解除して、その月の支出を編集できるようにする（PRD §6.3）。
    ///
    /// レコードは消さず `reopened` に変えるだけ。`SettlementPlanner` が
    /// `reopened` の月を自動確定の対象から外すため、次回起動で勝手に
    /// 元の値へ戻されることはない。直前の確定値は参考値として残る。
    func reopenSettlement(for yearMonth: YearMonth) throws {
        guard let entity = fetchSettlementEntity(for: yearMonth) else {
            throw StoreError.settlementNotFound
        }
        entity.statusRaw = SettlementStatus.reopened.rawValue
        entity.updatedAt = clock()
        try save()
        reload()
    }

    /// 解除した月を再確定する。最新の予算と支出から確定値を計算し直す（PRD §6.3）。
    ///
    /// レコードは増やさず同じ1件を更新し、再確定回数を1増やす。
    func recloseSettlement(for yearMonth: YearMonth) throws {
        guard let settings = try? fetchSettings(),
              let activeStartDate = CalendarDay(iso: settings.activeStartDateISO),
              let entity = fetchSettlementEntity(for: yearMonth),
              let previous = Self.settlement(from: entity)
        else { throw StoreError.settlementNotFound }

        let calculator = BudgetCalculator(
            activeStartDate: activeStartDate,
            rules: fetchBudgetRules()
        )
        let settlement = calculator.settlement(
            for: yearMonth,
            expenses: fetchExpenseEntries(in: yearMonth),
            closedAt: clock(),
            previous: previous
        )
        entity.statusRaw = settlement.status.rawValue
        entity.budgetTotalYen = settlement.budgetTotalYen
        entity.expenseTotalYen = settlement.expenseTotalYen
        entity.surplusYen = settlement.surplusYen
        entity.closedAt = settlement.closedAt
        entity.recloseCount = settlement.recloseCount
        entity.updatedAt = clock()
        try save()
        reload()
    }

    private func fetchSettlementEntity(for yearMonth: YearMonth) -> MonthlySettlementEntity? {
        let monthISO = yearMonth.iso
        var descriptor = FetchDescriptor<MonthlySettlementEntity>(
            predicate: #Predicate { $0.yearMonthISO == monthISO }
        )
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - 読み直し

    /// 永続化層から読み直し、派生状態を再計算する。
    func reload() {
        guard let settings = try? fetchSettings(),
              settings.onboardingCompleted,
              let activeStartDate = CalendarDay(iso: settings.activeStartDateISO)
        else {
            isOnboardingCompleted = false
            self.activeStartDate = nil
            calculator = nil
            todayBreakdown = nil
            currentMonthSummary = nil
            currentMonthExpenses = []
            selectableCategories = fetchCategories().filter(\.isActive)
            closedMonths = []
            dataVersion += 1
            return
        }

        let today = self.today
        let calculator = BudgetCalculator(
            activeStartDate: activeStartDate,
            rules: fetchBudgetRules()
        )
        let expenses = fetchExpenses(in: today.yearMonth)
        let entries = expenses.compactMap(Self.entry(from:))

        isOnboardingCompleted = true
        self.activeStartDate = activeStartDate
        self.calculator = calculator
        todayBreakdown = calculator.todayBreakdown(on: today, expenses: entries)
        // 当月は閲覧日までの実績を表示する（PRD §5.6）。
        currentMonthSummary = calculator.monthSummary(
            for: today.yearMonth,
            expenses: entries,
            asOf: today
        )
        currentMonthExpenses = expenses.sorted {
            ($0.spentOnISO, $0.createdAt) > ($1.spentOnISO, $1.createdAt)
        }
        selectableCategories = fetchCategories().filter(\.isActive)
        closedMonths = fetchClosedMonths()
        dataVersion += 1
    }

    // MARK: - 永続化層へのアクセス

    private func save() throws {
        do {
            try context.save()
        } catch {
            throw StoreError.saveFailed(underlying: error.localizedDescription)
        }
    }

    private func fetchSettings() throws -> AppSettingsEntity? {
        var descriptor = FetchDescriptor<AppSettingsEntity>()
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func fetchBudgetRules() -> [BudgetRule] {
        let descriptor = FetchDescriptor<BudgetRuleEntity>(
            sortBy: [SortDescriptor(\.effectiveFromISO)]
        )
        let entities = (try? context.fetch(descriptor)) ?? []
        return entities.compactMap { entity in
            guard let effectiveFrom = CalendarDay(iso: entity.effectiveFromISO),
                  entity.dailyAmountYen >= 1
            else { return nil }
            return BudgetRule(
                id: entity.uuid,
                effectiveFrom: effectiveFrom,
                dailyAmountYen: entity.dailyAmountYen,
                updatedAt: entity.updatedAt
            )
        }
    }

    private func fetchCategories() -> [ExpenseCategoryEntity] {
        let descriptor = FetchDescriptor<ExpenseCategoryEntity>(
            sortBy: [SortDescriptor(\.sortOrder)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchExpenses(in yearMonth: YearMonth) -> [ExpenseEntity] {
        let monthISO = yearMonth.iso
        let descriptor = FetchDescriptor<ExpenseEntity>(
            predicate: #Predicate { $0.spentOnMonthISO == monthISO },
            sortBy: [SortDescriptor(\.spentOnISO), SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchExpenseEntries(in yearMonth: YearMonth) -> [ExpenseEntry] {
        fetchExpenses(in: yearMonth).compactMap(Self.entry(from:))
    }

    private func fetchSettlement(for yearMonth: YearMonth) -> MonthlySettlement? {
        let monthISO = yearMonth.iso
        var descriptor = FetchDescriptor<MonthlySettlementEntity>(
            predicate: #Predicate { $0.yearMonthISO == monthISO }
        )
        descriptor.fetchLimit = 1
        guard let entity = (try? context.fetch(descriptor))?.first else { return nil }
        return Self.settlement(from: entity)
    }

    private func fetchClosedMonths() -> Set<YearMonth> {
        let descriptor = FetchDescriptor<MonthlySettlementEntity>()
        let entities = (try? context.fetch(descriptor)) ?? []
        return Set(
            entities
                .filter { $0.statusRaw == SettlementStatus.closed.rawValue }
                .compactMap { YearMonth(iso: $0.yearMonthISO) }
        )
    }

    private static func settlement(from entity: MonthlySettlementEntity) -> MonthlySettlement? {
        guard let yearMonth = YearMonth(iso: entity.yearMonthISO),
              let status = SettlementStatus(rawValue: entity.statusRaw)
        else { return nil }
        return MonthlySettlement(
            id: entity.uuid,
            yearMonth: yearMonth,
            status: status,
            budgetTotalYen: entity.budgetTotalYen,
            expenseTotalYen: entity.expenseTotalYen,
            surplusYen: entity.surplusYen,
            closedAt: entity.closedAt,
            recloseCount: entity.recloseCount
        )
    }

    /// 永続化レコードを計算用の値型へ変換する。壊れた日付や 0円以下は集計から除外する。
    private static func entry(from entity: ExpenseEntity) -> ExpenseEntry? {
        guard let spentOn = CalendarDay(iso: entity.spentOnISO), entity.amountYen >= 1 else {
            return nil
        }
        return ExpenseEntry(id: entity.uuid, spentOn: spentOn, amountYen: entity.amountYen)
    }

    /// 初期カテゴリを一度だけ作る（PRD §7.3）。
    private func seedCategoriesIfNeeded() {
        guard fetchCategories().isEmpty else { return }
        for (index, name) in AppConstants.defaultCategoryNames.enumerated() {
            context.insert(ExpenseCategoryEntity(name: name, sortOrder: index))
        }
        try? save()
    }
}

/// 1か月分の表示データ。履歴と月次レポートが同じ形で受け取る。
struct MonthDetail {
    let yearMonth: YearMonth
    /// 閲覧日までの実績。未到来の日は含まない。
    let summary: MonthSummary
    /// その月の支出。日付昇順。
    let expenses: [ExpenseEntity]
    let settlement: MonthlySettlement?
    /// 進行中の月のみ。平均支出から見積もる月末の見込み（PRD §5.6）。
    /// 経過日数が足りなければ `nil`。
    let projection: SpendingPaceProjection?

    /// 確定済みで閲覧専用か（PRD §5.5 / §6.3）。
    var isClosed: Bool { settlement?.status == .closed }

    /// 進行中の月か。確定レコードが無いか、確定を解除して編集中なら進行中。
    var isInProgress: Bool { !isClosed }

    /// 確定を解除して編集している最中か（PRD §6.3）。
    var isReopened: Bool { settlement?.status == .reopened }

    /// カテゴリ別支出。金額の降順（PRD §5.6）。
    var categoryShares: [CategoryShare] {
        var totals: [String: Int64] = [:]
        for expense in expenses {
            totals[expense.category?.name ?? "その他", default: 0] += expense.amountYen
        }
        return CategoryBreakdown.make(from: totals)
    }

    func dailySummary(on day: CalendarDay) -> DailySummary? {
        summary.days.first { $0.day == day }
    }

    func expenses(on day: CalendarDay) -> [ExpenseEntity] {
        expenses.filter { $0.spentOnISO == day.iso }
    }
}
