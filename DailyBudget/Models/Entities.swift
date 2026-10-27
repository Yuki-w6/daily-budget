import Foundation
import SwiftData

/// PRD §7 のデータモデルを SwiftData で表現する。
///
/// 金額はすべて `Int64` の円整数で保持し、浮動小数点を使わない（PRD §7 基本方針）。
/// 日付は `YYYY-MM-DD` / `YYYY-MM` の文字列で保持する。`Date` ではなく文字列にすることで、
/// 端末のタイムゾーン設定やサマータイムに保存値が影響されず、昇順ソートが辞書順と一致する。
///
/// - Important: CloudKit で同期するため、次の2つを守っている（#14）。
///   1. 一意制約（`#Unique`）を使わない。CloudKit が対応していないため。
///      一意性はアプリ側の重複排除（`BudgetStore.deduplicateRecords`）で保つ。
///   2. すべての保存プロパティに既定値を持たせる。CloudKit スキーマは
///      既定値のない必須プロパティを受け付けないため。

/// PRD §7.5 `AppSettings`。単一レコード。
@Model
final class AppSettingsEntity {
    var uuid: UUID = UUID()
    /// 初回利用開始日（`YYYY-MM-DD`）。
    var activeStartDateISO: String = ""
    /// MVPでは `Asia/Tokyo` 固定。
    var budgetTimeZoneIdentifier: String = AppConstants.timeZoneIdentifier
    /// MVPでは `JPY` 固定。
    var currencyCode: String = AppConstants.currencyCode
    var onboardingCompleted: Bool = false
    var updatedAt: Date = Date()

    init(
        uuid: UUID = UUID(),
        activeStartDateISO: String,
        budgetTimeZoneIdentifier: String = AppConstants.timeZoneIdentifier,
        currencyCode: String = AppConstants.currencyCode,
        onboardingCompleted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.uuid = uuid
        self.activeStartDateISO = activeStartDateISO
        self.budgetTimeZoneIdentifier = budgetTimeZoneIdentifier
        self.currencyCode = currencyCode
        self.onboardingCompleted = onboardingCompleted
        self.updatedAt = updatedAt
    }
}

/// PRD §7.1 `BudgetRule`。日額予算の履歴。終了日は持たず、次のルールの開始日から導出する。
@Model
final class BudgetRuleEntity {
    var uuid: UUID = UUID()
    var effectiveFromISO: String = ""
    var dailyAmountYen: Int64 = 0
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    init(
        uuid: UUID = UUID(),
        effectiveFromISO: String,
        dailyAmountYen: Int64,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.uuid = uuid
        self.effectiveFromISO = effectiveFromISO
        self.dailyAmountYen = dailyAmountYen
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// PRD §7.3 `ExpenseCategory`。MVPでは作成・並べ替えUIを持たず、初期値のみを使う。
@Model
final class ExpenseCategoryEntity {
    var uuid: UUID = UUID()
    var name: String = ""
    var sortOrder: Int = 0
    /// 新規登録時に選択できるか。過去の履歴を失わずに選択肢から外すために使う（PRD §7.3）。
    var isActive: Bool = true
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \ExpenseEntity.category)
    var expenses: [ExpenseEntity]? = []

    init(
        uuid: UUID = UUID(),
        name: String,
        sortOrder: Int,
        isActive: Bool = true,
        updatedAt: Date = Date()
    ) {
        self.uuid = uuid
        self.name = name
        self.sortOrder = sortOrder
        self.isActive = isActive
        self.updatedAt = updatedAt
    }
}

/// PRD §7.2 `Expense`。1日に複数レコードを許可する。
@Model
final class ExpenseEntity {
    var uuid: UUID = UUID()
    /// 利用日（`YYYY-MM-DD`）。月次集計とグラフはこの値で集約する。
    var spentOnISO: String = ""
    /// `spentOnISO` の年月（`YYYY-MM`）。月単位の取得を文字列の等価比較だけで行うための冗長な列。
    /// 書き込み時に必ず `spentOnISO` から導出する。
    var spentOnMonthISO: String = ""
    var amountYen: Int64 = 0
    var memo: String?
    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    /// PRD §7.2 の `categoryID` に対応。カテゴリを選択肢から外しても支出履歴が残るよう省略可にしている。
    var category: ExpenseCategoryEntity?

    init(
        uuid: UUID = UUID(),
        spentOnISO: String,
        spentOnMonthISO: String,
        amountYen: Int64,
        memo: String? = nil,
        category: ExpenseCategoryEntity? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.uuid = uuid
        self.spentOnISO = spentOnISO
        self.spentOnMonthISO = spentOnMonthISO
        self.amountYen = amountYen
        self.memo = memo
        self.category = category
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// PRD §7.4 `MonthlySettlement`。対象月の支出を集計したスナップショット。
@Model
final class MonthlySettlementEntity {
    var uuid: UUID = UUID()
    /// `YYYY-MM`。一意性はアプリ側の重複排除で保つ（CloudKit に一意制約が無いため）。
    var yearMonthISO: String = ""
    /// `SettlementStatus` の生値。
    var statusRaw: String = ""
    var budgetTotalYen: Int64 = 0
    var expenseTotalYen: Int64 = 0
    /// 予算 − 支出。負値を許可する。
    var surplusYen: Int64 = 0
    var closedAt: Date?
    var recloseCount: Int = 0
    var updatedAt: Date = Date()

    init(
        uuid: UUID = UUID(),
        yearMonthISO: String,
        statusRaw: String,
        budgetTotalYen: Int64,
        expenseTotalYen: Int64,
        surplusYen: Int64,
        closedAt: Date?,
        recloseCount: Int,
        updatedAt: Date = Date()
    ) {
        self.uuid = uuid
        self.yearMonthISO = yearMonthISO
        self.statusRaw = statusRaw
        self.budgetTotalYen = budgetTotalYen
        self.expenseTotalYen = expenseTotalYen
        self.surplusYen = surplusYen
        self.closedAt = closedAt
        self.recloseCount = recloseCount
        self.updatedAt = updatedAt
    }
}
