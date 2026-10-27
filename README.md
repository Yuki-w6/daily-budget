# Daily Budget (iOS)

「今日あといくら使えるか」を毎日確認し、使わなかった予算を同じ月の中で繰り越す日額予算管理アプリ。
仕様は Notion の PRD `daily_budget_ios_prd`（v1.0 / MVP仕様案、2026-10-27）に準拠する。

## 構成

```
daily-budget/
├─ DailyBudgetCore/          # 予算計算ロジック（SPMパッケージ、iOS/macOS両対応）
│  ├─ Sources/DailyBudgetCore/
│  │  ├─ CalendarDay.swift        # 時刻を持たない暦日
│  │  ├─ YearMonth.swift          # 年月・暦日数
│  │  ├─ BudgetDomain.swift       # PRD §7 のデータモデル（値型）
│  │  ├─ BudgetCalculator.swift   # PRD §8.1「単一の計算サービス」
│  │  └─ SettlementPlanner.swift  # PRD §6.2 自動確定の対象判定
│  └─ Tests/DailyBudgetCoreTests/ # PRD §4.3 計算例・§10 受け入れ条件
├─ DailyBudget.xcodeproj
└─ DailyBudget/              # SwiftUI + SwiftData のアプリ層
   ├─ DailyBudgetApp.swift
   ├─ Models/Entities.swift  # SwiftData モデル（PRD §7）
   ├─ Store/                 # リポジトリ層・表示整形
   └─ Views/                 # 画面A/B/C（PRD §5）
```

計算ロジックは SwiftUI にも SwiftData にも依存しないため、Simulator を起動せずに
`swift test` だけで検証できる。画面に出る数字はすべて `BudgetStore` 経由で
`BudgetCalculator` の結果を読むため、画面ごとに集計が食い違わない（PRD §8.1）。

## 開発コマンド

`xcode-select` が Command Line Tools を指している環境では `DEVELOPER_DIR` を明示する。

```bash
# 計算ロジックのテスト（Simulator不要、数秒で終わる）
cd DailyBudgetCore && swift test

# アプリのビルド
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -scheme DailyBudget \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug build
```

初回のみ Xcode のライセンス同意が必要：`sudo xcodebuild -license accept`

## 実装状況

PRD §11 の開発順序に沿って進める。

| Phase | 内容 | 状態 |
| --- | --- | --- |
| 1 | 予算と支出のコア（モデル・リポジトリ層・初期設定・支出CRUD・集計ロジック・ホーム画面） | 実装済み |
| 2 | 履歴（カレンダー・日別明細）・月次レポート・予算変更履歴・確定解除と再確定 | 履歴のみ実装済み |
| 3 | 境界値テスト・アクセシビリティ確認・エラー処理の確認 | 未着手 |

未実装のタブ（レポート・設定）は、実装済みに見せないため
`ComingSoonView` で未実装であることを明示している。

月末自動確定（PRD §6.2）は Phase 2 の項目だが、「端末を起動していない間でも過去月の
集計が失われてはならない」という要件のため、計算とストア処理を Phase 1 に前倒しして
実装している。確定結果を表示する月次レポートUIは Phase 2。

## PRDから変更した点

実装にあたって、PRD の記述どおりでは成立しない箇所を2つ調整した。
いずれも PRD 本体（Notion `daily_budget_ios_prd`）に反映済み（v1.1 / §6.2 を改訂）。

### 1. 自動確定は `reopened` の月を対象にしない

PRD §6.2 は「起動時に未確定の過去月を自動確定する」、§6.3 は「`reopened` 中は未確定と
表示する」と書いている。字面どおり実装すると、訂正のため確定解除した月が次回起動で
編集前の状態のまま再確定されてしまう。

確定解除はユーザーの明示的な操作なので自動処理より優先し、自動確定の対象は
「確定レコードがまだ存在しない月」だけに限定した。再確定は §6.3 の明示的な操作で行う。
`SettlementPlanner.monthsAwaitingSettlement` のコメントとテスト
`reopenedMonthIsExcludedFromAutoSettlement` に固定している。

### 2. 初回利用月の月間予算は利用開始日以降だけを合計する

PRD §4.2 は `periodStart(d) = max(monthStart(d), activeStart)` と定義する一方、
§6.2 の確定処理は「当月の日額予算の合計」と書いており、月途中に使い始めた月の
扱いが2通りに読める。AC-16「初回利用開始日より前の予算は加算されない」に合わせ、
`activeStart` 以降のみを合計する実装にした。

## MVPの制約

記録は端末ローカルにのみ保存され、サーバー同期やバックアップは持たない（PRD §9）。
機種変更・端末故障・アプリ削除で記録を失う。初期設定画面でこの制約を明示している。
長期運用の前にエクスポート機能（PRD §13）の前倒しを検討する。
