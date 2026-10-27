import SwiftUI
import Charts
import DailyBudgetCore

/// 画面E：月次レポート。月を選んで実績・推移・カテゴリ別支出を振り返る（PRD §5.6）。
struct MonthlyReportView: View {
    let store: BudgetStore

    @State private var selectedMonth: YearMonth?
    @State private var detail: MonthDetail?
    @State private var settlements: [MonthlySettlement] = []

    var body: some View {
        NavigationStack {
            Group {
                if let detail, let selectedMonth {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 24) {
                            monthPicker(selectedMonth)
                            statusAndTotals(detail)
                            if detail.isInProgress, let projection = detail.projection {
                                Divider()
                                projectionSection(projection)
                            }
                            Divider()
                            surplusChart(detail)
                            Divider()
                            categorySection(detail)
                            if !settlements.isEmpty {
                                Divider()
                                pastMonthsSection()
                            }
                        }
                        .padding()
                    }
                } else {
                    ContentUnavailableView(
                        "レポートはまだありません",
                        systemImage: "chart.xyaxis.line",
                        description: Text("支出を記録すると、月ごとの推移を振り返れます。")
                    )
                }
            }
            .navigationTitle("月次レポート")
        }
        .onAppear {
            if selectedMonth == nil { selectedMonth = store.today.yearMonth }
            refresh()
        }
        .onChange(of: selectedMonth) { _, _ in refresh() }
        .onChange(of: store.dataVersion) { _, _ in refresh() }
    }

    private func refresh() {
        guard let selectedMonth else { return }
        detail = store.monthDetail(for: selectedMonth)
        settlements = store.settlements()
    }

    // MARK: 月選択

    private func monthPicker(_ month: YearMonth) -> some View {
        // 当月および過去月から選ぶ（PRD §5.6）。新しい月を先に並べる。
        let months = (store.browsableMonths.map { Array($0.lowerBound.through($0.upperBound)) } ?? [])
            .reversed()

        return Menu {
            ForEach(Array(months), id: \.self) { candidate in
                Button {
                    selectedMonth = candidate
                } label: {
                    if candidate == month {
                        Label(monthText(candidate), systemImage: "checkmark")
                    } else {
                        Text(verbatim: monthText(candidate))
                    }
                }
            }
        } label: {
            HStack {
                Text(verbatim: monthText(month))
                    .font(.headline)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
            }
        }
        .accessibilityLabel("表示する月。現在 \(monthText(month))")
    }

    private func monthText(_ month: YearMonth) -> String {
        "\(month.year)年\(month.month)月"
    }

    // MARK: ステータスと実績

    private func statusAndTotals(_ detail: MonthDetail) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(detail.isClosed ? "確定済み" : "進行中")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
                if detail.isClosed, let closedAt = detail.settlement?.closedAt {
                    Text(verbatim: "確定日時 " + Self.dateTimeText(closedAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Text(detail.isClosed ? "確定した実績" : "今月の実績（本日まで）")
                .font(.headline)

            totalRow("月間予算", Yen.amount(detail.summary.budgetTotalYen))
            totalRow("支出総額", Yen.amount(detail.summary.expenseTotalYen))
            totalRow(
                detail.summary.surplusYen < 0 ? "超過" : "累積余剰",
                Yen.signedAmount(detail.summary.surplusYen)
            )
            // ホームから移した項目（#13）。
            totalRow("経過日数", "\(detail.summary.days.count)日")

            if detail.summary.surplusYen < 0 {
                Label(
                    "予算を\(Yen.amount(abs(detail.summary.surplusYen)))超過しています",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.red)
            }

            if detail.isClosed {
                // 確定した余剰は過去の実績であって残高ではない（PRD §6.2）。
                Text("確定した余剰は過去の実績です。翌月の予算には繰り越されません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 月末見込み。実績と混ぜず、見出しと説明文で別物だと示す（PRD §5.6）。
    private func projectionSection(_ projection: MonthEndProjection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("月末の見込み")
                .font(.headline)
            Text("残りの日に支出がなかった場合の金額です。上の実績とは別の数字です。")
                .font(.caption)
                .foregroundStyle(.secondary)
            totalRow("月間予算（月末まで）", Yen.amount(projection.budgetTotalYen))
            totalRow("本日までの支出", Yen.amount(projection.expenseTotalToDateYen))
            totalRow("見込み余剰", Yen.signedAmount(projection.projectedSurplusYen))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 累積余剰グラフ

    private func surplusChart(_ detail: MonthDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("累積余剰の推移")
                .font(.headline)

            if detail.summary.days.isEmpty {
                Text("この月の実績はまだありません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    // 0円の基準線（PRD §5.6）。
                    RuleMark(y: .value("基準", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                    ForEach(detail.summary.days, id: \.day) { summary in
                        LineMark(
                            x: .value("日", summary.day.day),
                            y: .value("累積余剰", summary.cumulativeSurplusYen)
                        )
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: 5)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let day = value.as(Int.self) {
                                Text(verbatim: "\(day)")
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let yen = value.as(Int.self) {
                                Text(verbatim: Yen.compactSigned(Int64(yen)))
                            }
                        }
                    }
                }
                // 横軸は月の1日から末日まで固定する。実績のある日だけで決めると
                // 存在しない「0日」が目盛りに出たり、月ごとに横幅の意味が変わったりする。
                .chartXScale(domain: 1...detail.yearMonth.dayCount)
                .chartYScale(domain: yAxisDomain(detail))
                .frame(height: 200)
                .accessibilityLabel("累積余剰の推移")
                .accessibilityValue(chartAccessibilityValue(detail))
            }
        }
    }

    /// 0円の基準線が必ず見えるよう、描画範囲に0を含める（PRD §5.6）。
    private func yAxisDomain(_ detail: MonthDetail) -> ClosedRange<Double> {
        let values = detail.summary.days.map(\.cumulativeSurplusYen)
        let lower = min(0, values.min() ?? 0)
        let upper = max(0, values.max() ?? 0)
        let padding = max(1_000, (upper - lower) / 10)
        return Double(lower - padding)...Double(upper + padding)
    }

    private func chartAccessibilityValue(_ detail: MonthDetail) -> String {
        guard let first = detail.summary.days.first, let last = detail.summary.days.last else {
            return "実績なし"
        }
        return "\(first.day.month)月\(first.day.day)日は \(Yen.spoken(first.cumulativeSurplusYen))、"
            + "\(last.day.month)月\(last.day.day)日は \(Yen.spoken(last.cumulativeSurplusYen))"
    }

    // MARK: カテゴリ別支出

    private func categorySection(_ detail: MonthDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("カテゴリ別支出")
                .font(.headline)

            let shares = detail.categoryShares
            if shares.isEmpty {
                Text("この月の支出はありません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(shares) { share in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(share.name)
                            Spacer()
                            Text(verbatim: Yen.amount(share.amountYen))
                                .monospacedDigit()
                            Text(verbatim: Self.percentText(share.share))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .frame(width: 52, alignment: .trailing)
                        }
                        // 構成比は数字でも示したうえで、棒は補助として添える。
                        ProgressView(value: share.share)
                            .tint(.accentColor)
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(share.name) \(Yen.spoken(share.amountYen))、"
                            + "構成比 \(Self.percentText(share.share))"
                    )
                }
            }
        }
    }

    // MARK: 過去月一覧

    private func pastMonthsSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("過去月の確定結果")
                .font(.headline)

            ForEach(settlements) { settlement in
                Button {
                    selectedMonth = settlement.yearMonth
                } label: {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: monthText(settlement.yearMonth))
                            Text(verbatim: "予算 \(Yen.amount(settlement.budgetTotalYen))"
                                + " / 支出 \(Yen.amount(settlement.expenseTotalYen))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(verbatim: Yen.signedAmount(settlement.surplusYen))
                                .monospacedDigit()
                            if settlement.status == .reopened {
                                Text("編集中")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .font(.subheadline)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    // MARK: 補助

    private func totalRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(verbatim: value).monospacedDigit().fontWeight(.medium)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

    private static func percentText(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }

    private static func dateTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = AppConstants.budgetTimeZone
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter.string(from: date)
    }
}
