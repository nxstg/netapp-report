# NetApp ONTAP Report Generator v1.0.0

[![Code Quality](https://github.com/nxstg/netapp-report/actions/workflows/code-quality.yml/badge.svg)](https://github.com/nxstg/netapp-report/actions/workflows/code-quality.yml)
[![Security Scan](https://github.com/nxstg/netapp-report/actions/workflows/security-scan.yml/badge.svg)](https://github.com/nxstg/netapp-report/actions/workflows/security-scan.yml)
[![Release](https://github.com/nxstg/netapp-report/actions/workflows/release.yml/badge.svg)](https://github.com/nxstg/netapp-report/actions/workflows/release.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

NetApp ONTAP環境のレポートを生成するPowerShellスクリプトです。
レポートは複数の出力形式（JSON、HTML、CSV）をサポートしています。

## 🎯 主な特徴

- ✅ **包括的な情報収集** - クラスター、ノード、アグリゲート、ボリューム、LIF、ポート、ディスク情報を収集
- ✅ **健全性チェック** - リソースの閾値ベースの状態判定と異常検知
- ✅ **ディスク情報レポート** - 全ディスク情報の取得、スペアディスクのゼロイング状態確認
- ✅ **複数出力形式** - JSON、HTML、CSV形式でのレポート出力
- ✅ **メール送信機能** - HTMLレポートの自動メール送信
- ✅ **モジュール化設計** - 保守性と拡張性に優れた構造

## 📋 必要要件

- PowerShell 5.1 以上
- NetApp.ONTAP モジュール
- NetApp ONTAP クラスターへのアクセス権限

### NetApp.ONTAP モジュールのインストール

```powershell
Install-Module -Name NetApp.ONTAP -Scope CurrentUser
```

## 🚀 クイックスタート

### 1. 環境変数の設定（推奨）

```powershell
# Windows
$env:NETAPP_FILER = "netapp01.example.com"
$env:NETAPP_USERNAME = "admin"
$env:NETAPP_PASSWORD = "YourSecurePassword"

# Linux/macOS
export NETAPP_FILER="netapp01.example.com"
export NETAPP_USERNAME="admin"
export NETAPP_PASSWORD="YourSecurePassword"
```

### 2. スクリプトの実行

```powershell
./netapp-report.ps1
```

## 📁 ディレクトリ構造

```
netapp-report/
├── netapp-report.ps1            # メインスクリプト
├── config/
│   └── default-config.json      # デフォルト設定
├── modules/
│   ├── NetAppConnection.psm1    # 接続管理モジュール
│   ├── DataCollector.psm1       # データ収集モジュール
│   ├── OutputFormatter.psm1     # 出力フォーマットモジュール
│   └── EmailSender.psm1         # メール送信モジュール
├── reports/                     # レポート出力ディレクトリ（自動生成）
└── logs/                        # ログディレクトリ（自動生成）
```

## 🔧 使用方法

### 基本的な使用例

```powershell
# デフォルト設定で実行
./netapp-report.ps1

# 詳細ログを表示
./netapp-report.ps1 -Verbose

# 特定のファイラーを指定
./netapp-report.ps1 -Filer netapp01.example.com
```

### 出力形式の指定

```powershell
# JSON形式のみ
./netapp-report.ps1 -OutputFormats json

# HTMLとCSV形式
./netapp-report.ps1 -OutputFormats html,csv

# すべての形式
./netapp-report.ps1 -OutputFormats json,html,csv
```

### レポートセクションの選択

```powershell
# アグリゲートとボリューム情報のみ
./netapp-report.ps1 -Sections aggregate,volume

# ノードとLIF情報
./netapp-report.ps1 -Sections node,lif

# すべてのセクション（デフォルト）
./netapp-report.ps1 -Sections cluster,node,aggregate,volume,lif,disk
```

### カスタム設定ファイルの使用

```powershell
# サンプルをコピーして編集
cp config/default-config.json config/my-config.json

# カスタム設定で実行
./netapp-report.ps1 -ConfigFile ./config/my-config.json
```

### 出力ディレクトリの指定

```powershell
./netapp-report.ps1 -OutputDirectory /path/to/reports
```

## ⚙️ 設定ファイル

`config/default-config.json` をベースにカスタマイズできます。

```json
{
  "netapp": {
    "filer": "",
    "timeout": 50000,
    "retryAttempts": 3,
    "retryDelaySeconds": 5
  },
  "report": {
    "sections": ["cluster", "node", "aggregate", "volume", "lif", "disk"],
    "outputFormats": ["json", "html"],
    "outputDirectory": "./reports",
    "includeTimestamp": true,
    "thresholds": {
      "aggregate": { "warning": 80, "critical": 90 },
      "volume": { "warning": 80, "critical": 90 }
    }
  },
  "logging": {
    "enabled": true,
    "level": "Info",
    "logDirectory": "./logs"
  }
}
```

### 設定項目の説明

#### NetApp 設定
- `filer`: ファイラー名（環境変数で上書き可能）
- `timeout`: 接続タイムアウト（ミリ秒）
- `retryAttempts`: 接続リトライ回数
- `retryDelaySeconds`: リトライ間隔（秒）

#### レポート設定
- `sections`: 収集するセクション
- `outputFormats`: 出力形式
- `outputDirectory`: 出力ディレクトリ
- `includeTimestamp`: ファイル名にタイムスタンプを含める
- `thresholds`: 各リソースの警告・クリティカル閾値（%）

#### ログ設定
- `enabled`: ログ出力の有効化
- `level`: ログレベル（Info, Warning, Error）
- `logDirectory`: ログディレクトリ
- `retentionDays`: ログファイル保持日数（デフォルト: 30日）

### ファイル世代管理

レポートファイルとログファイルは自動的にローテーション（世代管理）されます。

#### レポートの世代管理

```json
{
  "report": {
    "retention": {
      "enabled": true,
      "days": 30,
      "maxGenerations": 50
    }
  }
}
```

**設定項目:**
- `enabled`: 世代管理の有効化（true/false）
- `days`: レポート保持日数（デフォルト: 30日）
- `maxGenerations`: ファイラーごとの最大保持世代数（デフォルト: 50世代）

**削除ロジック:**
1. **日数ベース**: 指定日数（例: 30日）より古いファイルを削除
2. **世代数ベース**: ファイラーごとに最大世代数（例: 50）を超えるファイルを削除
3. **ファイラー別管理**: 異なるファイラーのレポートは別々に管理

**例:**
```
reports/
├── netapp01-20231103-120000.json  ← 30日以前 → 削除
├── netapp01-20231103-120000.html  ← 30日以前 → 削除
├── netapp01-20231201-120000.json  ← 51世代目 → 削除
├── netapp01-20231202-120000.json  ← 50世代目（保持）
├── netapp01-20231203-120000.json  ← 最新（保持）
└── csv-20231103-120000/           ← 30日以前 → 削除
```

#### ログの世代管理

ログファイルは`logging.retentionDays`設定に基づいて自動削除されます。

```json
{
  "logging": {
    "enabled": true,
    "retentionDays": 30
  }
}
```

**動作:**
- 指定日数（デフォルト: 30日）より古いログファイル（.log）を削除
- 実行中のログファイルは保持される
- スクリプト実行時に自動的にクリーンアップ

**例:**
```
logs/
├── netapp-report-20231103-120000.log  ← 30日以前 → 削除
├── netapp-report-20231104-120000.log  ← 30日以前 → 削除
├── netapp-report-20231203-120000.log  ← 保持
└── netapp-report-20231203-150000.log  ← 実行中（保持）
```

**無効化:**
世代管理を無効にする場合は設定ファイルで:
```json
{
  "report": {
    "retention": {
      "enabled": false
    }
  }
}
```

## 📧 メール送信機能

レポートを自動的にメールで送信できます。HTMLレポートを本文に含めるか、添付ファイルとして送信できます。

### メール設定

設定ファイルにメール設定を追加：

```json
{
  "email": {
    "enabled": true,
    "smtpServer": "smtp.example.com",
    "smtpPort": 587,
    "encryptionType": "StartTLS",
    "useAuthentication": true,
    "username": "report@example.com",
    "password": "",
    "from": "netapp-report@example.com",
    "to": ["admin@example.com", "team@example.com"],
    "cc": [],
    "bcc": [],
    "subject": "NetApp Daily Report - {FilerName} ({Date})",
    "includeHtmlInBody": true,
    "attachReports": false
  }
}
```

### 環境変数でのメール設定（推奨）

SMTP認証情報は環境変数で管理することを推奨します：

```powershell
# Windows
$env:SMTP_SERVER = "smtp.example.com"
$env:SMTP_PORT = "587"
$env:SMTP_USERNAME = "report@example.com"
$env:SMTP_PASSWORD = "YourSMTPPassword"
$env:SMTP_FROM = "netapp-report@example.com"
$env:SMTP_TO = "admin@example.com,team@example.com"

# Linux/macOS
export SMTP_SERVER="smtp.example.com"
export SMTP_PORT="587"
export SMTP_USERNAME="report@example.com"
export SMTP_PASSWORD="YourSMTPPassword"
export SMTP_FROM="netapp-report@example.com"
export SMTP_TO="admin@example.com,team@example.com"
```

### 暗号化タイプ

| タイプ | 説明 | 推奨ポート |
|--------|------|-----------|
| `StartTLS` | STARTTLS（推奨） | 587 |
| `SSL` | 明示的SSL/TLS | 465 |
| `None` | 暗号化なし | 25 |

## 📊 出力形式

### JSON形式
```
reports/netapp01-example-com-20231202-143000.json
```
- プログラムでの処理に最適
- API連携やデータベース投入に使用
- すべてのデータを含む

### HTML形式
```
reports/netapp01-example-com-20231202-143000.html
```
- ブラウザで視覚的に確認
- サマリーカード、テーブル表示
- 色分けされたステータス表示

### CSV形式
```
reports/csv-20231202-143000/
├── nodes.csv
├── aggregates.csv
├── volumes.csv
├── network-interfaces.csv
└── non-zeroed-disks.csv
```
- Excelでの分析に最適
- 各リソースタイプごとに個別のCSVファイル

## 🔐 セキュリティベストプラクティス

### 1. 環境変数の使用（推奨）

```powershell
# 環境変数に認証情報を設定
$env:NETAPP_FILER = "netapp01.example.com"
$env:NETAPP_USERNAME = "admin"
$env:NETAPP_PASSWORD = "SecurePassword"

# スクリプト実行（パスワードをコマンドラインに含めない）
./netapp-report.ps1
```

### 2. 設定ファイルでの認証情報管理

平文パスワードを設定ファイルに保存しないでください。環境変数を使用してください。

### 3. 最小権限の原則

レポート生成には読み取り専用権限で十分です。専用の読み取り専用アカウントを作成することを推奨します。

## 🔧 トラブルシューティング

### NetApp.ONTAP モジュールが見つからない

```powershell
Install-Module -Name NetApp.ONTAP -Scope CurrentUser -Force
```

### 接続タイムアウト

`config/default-config.json` の `timeout` 値を増やしてください：

```json
{
  "netapp": {
    "timeout": 100000
  }
}
```

### 権限エラー

使用しているアカウントに十分な読み取り権限があることを確認してください。

## 📝 ログ

詳細なログを表示するには `-Verbose` パラメータを使用：

```powershell
./netapp-report.ps1 -Verbose
```

ログファイルは `logs/` ディレクトリに保存されます（設定による）。

## 🛡️ コード品質とセキュリティ

このプロジェクトは、コードの品質とセキュリティを確保するために、複数の自動チェックを実装しています。

### 自動チェック項目

すべてのプッシュとプルリクエストで以下のチェックが自動実行されます：

#### 1. PowerShell 静的解析
- **ツール**: PSScriptAnalyzer
- **チェック内容**:
  - コーディング規約の遵守
  - ベストプラクティスの確認
  - 潜在的なバグの検出
  - パフォーマンス上の問題

#### 2. セキュリティスキャン
- **ツール**: Trivy
- **チェック内容**:
  - 脆弱性スキャン
  - 設定ファイルのセキュリティチェック
  - シークレット情報の検出

#### 3. CodeQL 解析
- **ツール**: GitHub CodeQL
- **チェック内容**:
  - セキュリティパターンの検出
  - コード品質の問題

#### 4. Markdown Lint
- **チェック内容**:
  - ドキュメントの一貫性
  - Markdownの構文チェック

#### 5. JSON 検証
- **チェック内容**:
  - 設定ファイルの構文検証
  - JSONフォーマットの正当性

### ローカルでの実行

プッシュ前にローカルで品質チェックを実行することを推奨します：

```powershell
# PSScriptAnalyzer のインストール
Install-Module -Name PSScriptAnalyzer -Scope CurrentUser

# スクリプトの解析
Invoke-ScriptAnalyzer -Path . -Recurse
```

### 貢献ガイドライン

プルリクエストを作成する際は、以下を確認してください：

- [ ] すべての自動チェックがパスしている
- [ ] PSScriptAnalyzerでエラーがない
- [ ] セキュリティスキャンで問題が検出されていない
- [ ] ドキュメントが更新されている（必要な場合）

## 📚 参考資料

- [NetApp PowerShell Toolkit Documentation](https://docs.netapp.com/us-en/ontap-automation/index.html)
- [NetApp ONTAP REST API](https://docs.netapp.com/us-en/ontap-automation/rest/overview.html)
- [PowerShell Documentation](https://docs.microsoft.com/powershell/)
- [PSScriptAnalyzer Rules](https://github.com/PowerShell/PSScriptAnalyzer/tree/master/docs/Rules)

## 🚀 リリース管理

このプロジェクトは GitHub Actions を使用して自動的にリリースを作成します。

### クイックスタート

```bash
# バージョンを更新してコミット
git add README.md
git commit -m "Bump version to 1.1.0"

# タグを作成してプッシュ（これだけでリリースが自動作成されます）
git tag -a v1.1.0 -m "Release v1.1.0"
git push origin v1.1.0
```

タグをプッシュすると、GitHub Actions が自動的に以下を実行します：
- リリースパッケージの作成（ZIP/tar.gz形式）
- リリースノートの自動生成
- GitHub Releaseの作成とファイル添付

### リリース情報

- **バージョニング**: [セマンティックバージョニング](https://semver.org/) (v1.0.0形式)
- **リリースページ**: https://github.com/nxstg/netapp-report/releases

## 📄 ライセンス

このプロジェクトは MIT ライセンスの下で公開されています。

---

**Note:** このスクリプトは読み取り専用の操作のみを行います。NetApp ONTAP環境に変更を加えることはありません。
