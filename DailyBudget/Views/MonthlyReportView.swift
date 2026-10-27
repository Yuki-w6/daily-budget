import SwiftUI
import Charts
import DailyBudgetCore

/// 画面E：月次レポート。月を選んで実績・推移・カテゴリ別支出を振り返る（PRD §5.6）。
///
/// 数字を並べるのではなく、「本日までの累積余剰」を1つの大きな数字として出し、
/// その根拠と月末の見込みを文章で添える。
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
                        VStack(alignment: .leading, spacing: 28) {
                            monthPicker(selectedMonth)
                            summarySection(detail)
                            Divider()
                            surplusChart(detail)
                            Divider()
                            categorySection(detail)
                            if !settlements.isEmpty {
                                Divider()
                                pastMonthsSection()
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
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

        return HStack {
            Menu {
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
                HStack(spacing: 4) {
                    Text(verbatim: monthText(month))
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
            }
            .accessibilityLabel("表示する月。現在 \(monthText(month))")

            Spacer()

            if let detail {
                Text(detail.isClosed ? "確定済み" : "進行中")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())
            }
        }
    }

    private func monthText(_ month: YearMonth) -> String {
        "\(month.year)年\(month.month)月"
    }

    // MARK: 要点

    private func summarySection(_ detail: MonthDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("累計")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(verbatim: Yen.signedAmount(detail.summary.surplusYen))
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .foregroundStyle(detail.summary.surplusYen < 0 ? .red : .primary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("累計 " + Yen.spoken(detail.summary.surplusYen))

            Text(verbatim: contextLine(detail))
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let projection = detail.projection, detail.isInProgress {
                // 今月の平均支出が続いた場合の月末（PRD §5.6）。経過日数が足りない月は出ない。
                Text(verbatim: Self.projectionText(projection))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Self.projectionColor(projection.projectedSurplusYen))
                    .accessibilityLabel(Self.projectionAccessibilityLabel(projection))
            }

            if detail.isClosed {
                // 確定した余剰は過去の実績であって残高ではない（PRD §6.2）。
                Text("この月の結果です。翌月には繰り越されません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 大きな数字の根拠を1行で示す。
    private func contextLine(_ detail: MonthDetail) -> String {
        let days = detail.isClosed
            ? "\(detail.summary.days.count)日分"
            : "\(detail.summary.days.count)日経過"
        return [
            days,
            "予算 " + Yen.amount(detail.summary.budgetTotalYen),
            "支出 " + Yen.amount(detail.summary.expenseTotalYen)
        ].joined(separator: " ・ ")
    }

    // MARK: 累積余剰グラフ

    private func surplusChart(_ detail: MonthDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("累計の推移")
                .font(.headline)

            if detail.summary.days.isEmpty {
                Text("この月の実績はまだありません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart {
                    // 0円の基準線（PRD §5.6）。
                    RuleMark(y: .value("0円", 0))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.secondary)
                    ForEach(detail.summary.days, id: \.day) { summary in
                        LineMark(
                            x: .value("日", summary.day.day),
                            y: .value("残り", summary.cumulativeSurplusYen)
                        )
                    }
                }
                .chartXAxis {
                    AxisMarks(values: xAxisValues(detail)) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let day = value.as(Int.self) {
                                Text(verbatim: "\(day)")
                            }
                        }
                    }
                }
                .chartYAxis {
                    // 縦軸を左に置く。右に置くと横軸の末日のラベルが縦軸の領域に
                    // かぶって切れる。
                    AxisMarks(position: .leading) { value in
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
                .accessibilityLabel("累計の推移")
                .accessibilityValue(chartAccessibilityValue(detail))
            }
        }
    }

    /// 横軸の目盛り位置。5日おきに置くが、月末に近すぎる目盛りは外す。
    /// 描画領域の端に来るラベルはグラフ側で切り取られ、「30」が「3」に見えてしまう。
    private func xAxisValues(_ detail: MonthDetail) -> [Int] {
        let lastDay = detail.yearMonth.dayCount
        return Array(stride(from: 5, through: lastDay, by: 5)).filter { $0 <= lastDay - 2 }
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
        VStack(alignment: .leading, spacing: 4) {
            Text("内訳")
                .font(.headline)
                .padding(.bottom, 4)

            let shares = detail.categoryShares
            if shares.isEmpty {
                Text("この月の支出はありません。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(shares) { share in
                    HStack {
                        Text(share.name)
                        Spacer()
                        Text(verbatim: Yen.amount(share.amountYen))
                            .monospacedDigit()
                        Text(verbatim: Self.percentText(share.share))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                    .font(.subheadline)
                    .padding(.vertical, 6)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(
                        "\(share.name) \(Yen.spoken(share.amountYen))、"
                            + "構成比 \(Self.percentText(share.share))"
                    )
                    Divider()
                }
            }
        }
    }

    // MARK: 過去月一覧

    private func pastMonthsSection() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("これまでの月")
                .font(.headline)
                .padding(.bottom, 4)

            ForEach(settlements) { settlement in
                Button {
                    selectedMonth = settlement.yearMonth
                } label: {
                    HStack {
                        Text(verbatim: monthText(settlement.yearMonth))
                        if settlement.status == .reopened {
                            Text("編集中")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(verbatim: Yen.signedAmount(settlement.surplusYen))
                            .monospacedDigit()
                    }
                    .font(.subheadline)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider()
            }
        }
    }

    // MARK: 月末の見込みの文言

    /// 超過と余りで言い回しを変える。色が見えなくても、どちらなのかが文字で分かる（PRD §9）。
    ///
    /// 月末まで来ていれば見積もりではなく実績なので、「〜そう」を使わない。
    private static func projectionText(_ projection: SpendingPaceProjection) -> String {
        let yen = projection.projectedSurplusYen
        if yen == 0 { return "予算ピッタリ" }
        if projection.isActual {
            return yen < 0 ? "\(Yen.amount(abs(yen)))超過" : "\(Yen.amount(yen))浮いた"
        }
        return yen < 0 ? "\(Yen.amount(abs(yen)))超えちゃいそう" : "\(Yen.amount(yen))浮きそう"
    }

    private static func projectionColor(_ yen: Int64) -> Color {
        if yen < 0 { return .red }
        if yen == 0 { return .secondary }
        return .blue
    }

    private static func projectionAccessibilityLabel(_ projection: SpendingPaceProjection) -> String {
        let yen = projection.projectedSurplusYen
        if projection.isActual {
            if yen < 0 { return "月末の実績。\(Yen.spoken(abs(yen)))超過しました" }
            if yen == 0 { return "月末の実績。予算ぴったりでした" }
            return "月末の実績。\(Yen.spoken(yen))余りました"
        }
        if yen < 0 { return "今月の平均支出が続いた場合の月末。\(Yen.spoken(abs(yen)))超えそうです" }
        if yen == 0 { return "今月の平均支出が続いた場合の月末。予算ぴったりです" }
        return "今月の平均支出が続いた場合の月末。\(Yen.spoken(yen))余りそうです"
    }

    private static func percentText(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
    }
}
