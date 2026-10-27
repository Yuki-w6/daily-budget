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
                HistoryView(store: store)
            }
            Tab("レポート", systemImage: "chart.xyaxis.line") {
                MonthlyReportView(store: store)
            }
            Tab("設定", systemImage: "gearshape") {
                SettingsView(store: store)
            }
        }
    }
}
