import SwiftUI

/// 初期設定の完了状況で入口を振り分ける（PRD §5.1 のフロー）。
struct RootView: View {
    let store: BudgetStore

    var body: some View {
        if store.isOnboardingCompleted {
            MainTabView(store: store)
        } else {
            OnboardingView(store: store)
        }
    }
}

/// 下部タブ。PRD §5.1 の4タブ構成。履歴・レポート・設定は Phase 2 で実装する。
struct MainTabView: View {
    let store: BudgetStore

    var body: some View {
        TabView {
            Tab("ホーム", systemImage: "yensign.circle") {
                HomeView(store: store)
            }
            Tab("履歴", systemImage: "calendar") {
                ComingSoonView(
                    title: "履歴",
                    detail: "カレンダーと日別明細は Phase 2 で実装します。"
                )
            }
            Tab("レポート", systemImage: "chart.xyaxis.line") {
                ComingSoonView(
                    title: "月次レポート",
                    detail: "累積余剰の折れ線グラフとカテゴリ別支出は Phase 2 で実装します。"
                )
            }
            Tab("設定", systemImage: "gearshape") {
                ComingSoonView(
                    title: "設定",
                    detail: "日額予算の変更と変更履歴は Phase 2 で実装します。"
                )
            }
        }
    }
}

/// 未実装タブの代替表示。実装済みに見せないことを目的とする。
struct ComingSoonView: View {
    let title: String
    let detail: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView {
                Label(title, systemImage: "hammer")
            } description: {
                Text(detail)
            }
            .navigationTitle(title)
        }
    }
}
