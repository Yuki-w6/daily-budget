import SwiftUI
import SwiftData

@main
struct DailyBudgetApp: App {
    /// ローカルDBを開いた結果。失敗を黙って隠さず画面に出す（PRD §8.2）。
    private let containerResult: Result<ModelContainer, Error>

    init() {
        containerResult = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            switch containerResult {
            case .success(let container):
                AppRootView(container: container)
                    .modelContainer(container)
            case .failure(let error):
                StartupFailureView(message: error.localizedDescription)
            }
        }
    }

    private static func makeContainer() -> Result<ModelContainer, Error> {
        let schema = Schema([
            AppSettingsEntity.self,
            BudgetRuleEntity.self,
            ExpenseCategoryEntity.self,
            ExpenseEntity.self,
            MonthlySettlementEntity.self
        ])
        do {
            // iCloud の個人データベースに同期する（#14）。サインインしていない端末でも
            // ローカルのデータベースとして動き、サインイン後に同期が始まる。
            let configuration = ModelConfiguration(
                schema: schema,
                cloudKitDatabase: .private(AppConstants.iCloudContainerIdentifier)
            )
            return .success(try ModelContainer(for: schema, configurations: configuration))
        } catch {
            return .failure(error)
        }
    }
}

/// `BudgetStore` を生成し、起動・復帰・日付変更のたびに読み直す。
struct AppRootView: View {
    let container: ModelContainer

    @State private var store: BudgetStore?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let store {
                RootView(store: store)
            } else {
                ProgressView()
            }
        }
        .task {
            guard store == nil else { return }
            let created = BudgetStore(context: container.mainContext)
            created.bootstrap()
            store = created
        }
        .onChange(of: scenePhase) { _, phase in
            // フォアグラウンド復帰時に未確定の過去月を確定する（PRD §6.2）。
            if phase == .active { store?.bootstrap() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            // 日をまたいでアプリを開いたままでも表示を更新する（PRD §6.4）。
            store?.bootstrap()
        }
    }
}

/// 起動時にローカルDBを開けなかった場合の画面。記録を失わせないため、再試行を促すだけにとどめる。
struct StartupFailureView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
            Text("データを読み込めませんでした")
                .font(.headline)
            Text(message)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("アプリを再起動してください。記録は端末内に残っています。")
                .font(.footnote)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}
