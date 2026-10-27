import Foundation

/// MVPで固定する値。PRD §5.7「タイムゾーンは Asia/Tokyo 固定、通貨は日本円固定」に対応する。
enum AppConstants {
    static let timeZoneIdentifier = "Asia/Tokyo"
    static let currencyCode = "JPY"

    /// 日次・月次の境界を判定するタイムゾーン（PRD §6.4）。
    static let budgetTimeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current

    /// 初期設定の候補額（PRD §5.2）。
    static let suggestedDailyAmountYen: Int64 = 2_000

    /// メモの最大文字数（PRD §5.4）。
    static let memoMaxLength = 200

    /// 初期カテゴリ（PRD §7.3）。
    static let defaultCategoryNames = ["食費", "日用品", "交通費", "娯楽・交際", "その他"]
}
