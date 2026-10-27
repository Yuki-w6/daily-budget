import SwiftUI
import DailyBudgetCore

/// 画面D：履歴。月単位のカレンダーから日別明細へ辿る（PRD §5.5）。
struct HistoryView: View {
    let store: BudgetStore

    private static let weekdaySymbols = ["日", "月", "火", "水", "木", "金", "土"]

    @State private var displayedMonth: YearMonth?
    @State private var detail: MonthDetail?
    @State private var selectedDay: CalendarDay?

    var body: some View {
        NavigationStack {
            Group {
                if let detail, let displayedMonth {
                    ScrollView {
                        VStack(spacing: 16) {
                            monthHeader(displayedMonth)
                            if detail.isClosed {
                                closedNotice(detail)
                            }
                            calendar(detail, month: displayedMonth)
                            monthSummaryLine(detail)
                        }
                        .padding()
                    }
                } else {
                    ContentUnavailableView(
                        "履歴はまだありません",
                        systemImage: "calendar",
                        description: Text("支出を記録すると、ここで日ごとの推移を振り返れます。")
                    )
                }
            }
            .navigationTitle("履歴")
            .navigationDestination(item: $selectedDay) { day in
                DayDetailView(store: store, day: day)
            }
        }
        .onAppear {
            if displayedMonth == nil { displayedMonth = store.today.yearMonth }
            refresh()
        }
        .onChange(of: displayedMonth) { _, _ in refresh() }
        // 支出の追加・編集・削除が保存されたら、表示中の月を読み直す。
        .onChange(of: store.dataVersion) { _, _ in refresh() }
    }

    private func refresh() {
        guard let displayedMonth else { return }
        detail = store.monthDetail(for: displayedMonth)
    }

    // MARK: 月の切り替え

    private func monthHeader(_ month: YearMonth) -> some View {
        HStack {
            Button {
                displayedMonth = month.previous
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!canShow(month.previous))
            .accessibilityLabel("前の月")

            Spacer()

            // Text のリテラル補間は LocalizedStringKey 扱いになり、年が「2,026年」と
            // 桁区切りされてしまう。組み立てた文字列をそのまま渡す。
            Text(verbatim: "\(month.year)年\(month.month)月")
                .font(.headline)
                .monospacedDigit()

            Spacer()

            Button {
                displayedMonth = month.next
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!canShow(month.next))
            .accessibilityLabel("次の月")
        }
        .buttonStyle(.bordered)
    }

    private func canShow(_ month: YearMonth) -> Bool {
        store.browsableMonths?.contains(month) ?? false
    }

    private func closedNotice(_ detail: MonthDetail) -> some View {
        // 確定済みの月は閲覧専用。色だけでなく文字で状態を伝える（PRD §5.5 / §9）。
        Label {
            Text("この月は確定済みです。支出の編集はできません。")
        } icon: {
            Image(systemName: "lock")
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: カレンダー

    private func calendar(_ detail: MonthDetail, month: YearMonth) -> some View {
        let days = month.allDays
        let leadingBlanks = days.first?.weekdayIndex ?? 0
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { index, symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity)
                    .id("weekday-\(index)")
            }
            ForEach(0..<leadingBlanks, id: \.self) { index in
                Color.clear
                    .frame(height: 1)
                    .id("blank-\(index)")
            }
            ForEach(days, id: \.self) { day in
                dayCell(day, detail: detail)
            }
        }
    }

    private func dayCell(_ day: CalendarDay, detail: MonthDetail) -> some View {
        // 未到来の日と利用開始日より前の日には実績がない（PRD §5.5）。
        let summary = detail.dailySummary(on: day)
        let isToday = day == store.today

        return Button {
            selectedDay = day
        } label: {
            VStack(spacing: 2) {
                Text(verbatim: "\(day.day)")
                    .font(.caption.weight(isToday ? .bold : .regular))
                    .monospacedDigit()

                if let summary {
                    // その日の終わりの残りだけを出す。符号で色を変える。
                    Text(verbatim: Yen.compactSigned(summary.cumulativeSurplusYen))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Self.surplusColor(summary.cumulativeSurplusYen))
                } else {
                    Text(" ").font(.system(size: 10))
                }
            }
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isToday ? Color.accentColor.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(.quaternary, lineWidth: summary == nil ? 0 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(summary == nil)
        .accessibilityLabel(accessibilityLabel(day, summary: summary, isToday: isToday))
    }

    private func accessibilityLabel(
        _ day: CalendarDay,
        summary: DailySummary?,
        isToday: Bool
    ) -> String {
        var parts = ["\(day.month)月\(day.day)日"]
        if isToday { parts.append("今日") }
        guard let summary else {
            parts.append("実績なし")
            return parts.joined(separator: "、")
        }
        parts.append("残り \(Yen.spoken(summary.cumulativeSurplusYen))")
        return parts.joined(separator: "、")
    }

    /// 残りの符号で色を変える。余りは青、超過は赤。
    private static func surplusColor(_ yen: Int64) -> Color {
        if yen < 0 { return .red }
        if yen == 0 { return .secondary }
        return .blue
    }

    // MARK: 月の合計

    /// 詳しい内訳は月次レポートにあるので、ここは1行にとどめる。
    private func monthSummaryLine(_ detail: MonthDetail) -> some View {
        HStack {
            Text("残り")
            Spacer()
            Text(verbatim: Yen.signedAmount(detail.summary.surplusYen))
                .monospacedDigit()
                .fontWeight(.medium)
                .foregroundStyle(detail.summary.surplusYen < 0 ? .red : .primary)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "この月の残り \(Yen.spoken(detail.summary.surplusYen))"
        )
    }

}
