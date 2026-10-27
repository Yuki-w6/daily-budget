# Daily Budget (iOS)

「今日あといくら使えるか」を毎日確認し、使わなかった予算を同じ月の中で繰り越す日額予算管理アプリ。
仕様は Notion の PRD `daily_budget_ios_prd`（v1.0 / MVP仕様案、2026-10-27）に準拠する。

## 構成

```
daily-budget/
├─ DailyBudget.entitlements  # iCloud（CloudKit）の利用宣言
├─ Info.plist                # 自動生成に足す分だけ（remote-notification）
├─ DailyBudgetCore/          # 予算計算ロジック（SPMパッケージ、iOS/macOS両対応）
│  ├─ Sources/DailyBudgetCore/
│  │  ├─ CalendarDay.swift        # 時刻を持たない暦日
│  │  ├─ YearMonth.swift          # 年月・暦日数
│  │  ├─ BudgetDomain.swift       # PRD §7 のデータモデル（値型）
│  │  ├─ BudgetCalculator.swift   # PRD §8.1「単一の計算サービス」
│  │  ├─ SettlementPlanner.swift  # PRD §6.2 自動確定の対象判定
│  │  ├─ ExpenseEditPolicy.swift  # PRD §5.4 支出を編集できる日の判定
│  │  ├─ DuplicateResolution.swift # 同期で重複したレコードの収束規則
│  │  ├─ CategoryBreakdown.swift  # PRD §5.6 カテゴリ別支出の構成比
│  │  └─ BudgetChange.swift       # PRD §6.1 予算変更の適用日と影響の試算
│  └─ Tests/DailyBudgetCoreTests/ # PRD §4.3 計算例・§10 受け入れ条件
├─ DailyBudget.xcodeproj
├─ DailyBudgetTests/         # BudgetStore のテスト（in-memory SwiftData）
└─ DailyBudget/              # SwiftUI + SwiftData のアプリ層
   ├─ DailyBudgetApp.swift
   ├─ Models/Entities.swift  # SwiftData モデル（PRD §7）
   ├─ Store/                 # リポジトリ層・表示整形
   └─ Views/                 # 画面A〜F（PRD §5）
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

# BudgetStore のテスト（Simulator が要る）
xcodebuild -scheme DailyBudget \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -configuration Debug test
```

テストは2層に分かれている。計算ロジックは `DailyBudgetCore` のテストで固め、
SwiftData を挟んでも同じ結果になるか・重複や壊れたレコードをどう扱うかは
`DailyBudgetTests` で確認する。前者は Simulator 不要で数秒、後者は
Simulator の起動を伴うので、普段の反復は前者を回せばよい。

初回のみ Xcode のライセンス同意が必要：`sudo xcodebuild -license accept`

## 実装状況

PRD §11 の開発順序に沿って進める。

| Phase | 内容 | 状態 |
| --- | --- | --- |
| 1 | 予算と支出のコア（モデル・リポジトリ層・初期設定・支出CRUD・集計ロジック・ホーム画面） | 実装済み |
| 2 | 履歴（カレンダー・日別明細）・月次レポート・予算変更履歴・確定解除と再確定 | 実装済み |
| 3 | 境界値テスト・アクセシビリティ確認・エラー処理の確認 | 未着手 |

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

## iCloud 同期

記録は SwiftData + CloudKit で iCloud の個人データベースに同期する。
同じ Apple アカウントの端末間で記録が共有され、機種変更でも引き継げる。
iCloud にサインインしていない端末では、ローカルのデータベースとして動き、
サインイン後に同期が始まる。

### 必要な準備

Apple Developer のアカウントに、次の識別子の iCloud コンテナを作っておく。

```
iCloud.com.mayamayuki.dailybudget
```

Xcode で `Signing & Capabilities` → `+ Capability` → `iCloud` → `CloudKit` を選び、
このコンテナにチェックを入れると作成できる。

### 一意制約を使っていない理由

**CloudKit は一意制約に対応していない。** そのため SwiftData のモデルから
`#Unique` を外し、代わりにアプリ側で重複を解消している。

| エンティティ | 重複を判定するキー |
| --- | --- |
| `AppSettingsEntity` | 単一レコード |
| `BudgetRuleEntity` | `effectiveFromISO` |
| `ExpenseCategoryEntity` | `name` |
| `MonthlySettlementEntity` | `yearMonthISO` |

`BudgetStore.deduplicateRecords()` が起動時に走り、`DuplicateResolution` の規則で
残すレコードを1件に絞る。規則は「最終更新が新しいものを残し、同時刻なら `id` の
小さいほうを残す」。どの端末で実行しても同じ結果になるので、取り合いにならずに
収束する。カテゴリの重複は、支出を残すほうへ付け替えてから削除する。

CloudKit はすべての保存プロパティに既定値があることも要求するため、
モデルの各プロパティに既定値を与えている。

### 未確認の事項

端末間の同期そのものは確認できていない。Simulator には iCloud アカウントが
なく（`accountStatus=No account`）、実機2台またはサインイン済みの環境が要る。
確認済みなのは、CloudKit 構成でコンテナが開けること、起動時に
`CoreData+CloudKit` のセットアップが走ること、警告が出ないことまで。
