<#
.SYNOPSIS
    NetApp ONTAP Report Generator v1.0.0

.DESCRIPTION
    NetApp ONTAP環境のレポートを生成するモダンなPowerShellスクリプト
    モジュール化された設計で、複数の出力形式（JSON、HTML、CSV）をサポート

.PARAMETER Filer
    NetAppファイラー名（オプション、環境変数・設定ファイルより優先）

.PARAMETER Username
    NetApp接続ユーザー名（オプション、環境変数より優先）

.PARAMETER Password
    NetApp接続パスワード（SecureString形式、オプション、環境変数より優先）

.PARAMETER ConfigFile
    設定ファイルのパス（デフォルト: ./config/default-config.json）

.PARAMETER OutputFormats
    出力形式の配列（例: json, html, csv）

.PARAMETER OutputDirectory
    レポート出力ディレクトリ

.PARAMETER Sections
    収集するセクション（例: cluster, node, aggregate, volume, lif, disk）

.PARAMETER Verbose
    詳細情報を表示

.EXAMPLE
    # 環境変数から認証情報を使用（推奨）
    $env:NETAPP_FILER = "netapp01.example.com"
    $env:NETAPP_USERNAME = "admin"
    $env:NETAPP_PASSWORD = "SecurePassword123"
    ./netapp-report.ps1

.EXAMPLE
    # パラメータで認証情報を指定（SecureString使用）
    $securePass = ConvertTo-SecureString "YourPassword" -AsPlainText -Force
    ./netapp-report.ps1 -Filer netapp01.example.com -Username admin -Password $securePass

.EXAMPLE
    # インタラクティブにパスワードを入力
    $securePass = Read-Host "パスワードを入力" -AsSecureString
    ./netapp-report.ps1 -Filer netapp01.example.com -Username admin -Password $securePass

.EXAMPLE
    # 特定の出力形式とセクションを指定
    ./netapp-report.ps1 -OutputFormats json,html -Sections aggregate,volume

.EXAMPLE
    # カスタム設定ファイルを使用
    ./netapp-report.ps1 -ConfigFile ./my-config.json

.NOTES
    Version: 1.0.0
    Author: nxstg
    Requires: NetApp.ONTAP module
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$Filer,
    
    [Parameter(Mandatory = $false)]
    [string]$Username,
    
    [Parameter(Mandatory = $false)]
    [SecureString]$Password,
    
    [Parameter(Mandatory = $false)]
    [string]$ConfigFile = "./config/default-config.json",
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('json', 'html', 'csv')]
    [string[]]$OutputFormats,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('cluster', 'node', 'aggregate', 'volume', 'lif', 'port', 'disk', 'alldisk')]
    [string[]]$Sections
)

#Requires -Version 5.1

# スクリプトのバージョン
$ScriptVersion = "1.0.0"

# エラーアクションの設定
$ErrorActionPreference = "Stop"

# スクリプトのルートディレクトリを取得
$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

# ログ関数の定義
function Write-Log {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $false)]
        [ValidateSet('Info', 'Warning', 'Error')]
        [string]$Level = 'Info',
        
        [Parameter(Mandatory = $false)]
        [string]$LogFile
    )
    
    $timestamp = Get-Date -Format 'yyyy/MM/dd HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    
    if ($LogFile -and (Test-Path (Split-Path $LogFile -Parent))) {
        Add-Content -Path $LogFile -Value $logEntry -Encoding UTF8
    }
    
    switch ($Level) {
        'Info' { Write-Verbose $Message }
        'Warning' { Write-Warning $Message }
        'Error' { Write-Error $Message }
    }
}

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "  NetApp ONTAP Report v$ScriptVersion" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

# ログファイルパスの初期化（設定読み込み後に再設定）
$script:LogFile = $null

try {
    # モジュールのインポート
    Write-Verbose "モジュールを読み込んでいます..."
    
    $modulePath = Join-Path $ScriptRoot "modules"
    
    Import-Module (Join-Path $modulePath "NetAppConnection.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulePath "DataCollector.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulePath "OutputFormatter.psm1") -Force -ErrorAction Stop
    Import-Module (Join-Path $modulePath "EmailSender.psm1") -Force -ErrorAction Stop
    
    Write-Verbose "✓ モジュールの読み込みが完了しました"
    
    # 設定ファイルの読み込み
    Write-Host "📋 設定ファイルを読み込んでいます: $ConfigFile"
    
    if (-not (Test-Path $ConfigFile)) {
        throw "設定ファイルが見つかりません: $ConfigFile"
    }
    
    $configContent = Get-Content -Path $ConfigFile -Raw -Encoding UTF8
    $config = $configContent | ConvertFrom-Json
    
    Write-Verbose "✓ 設定ファイルの読み込みが完了しました"
    
    # ログ設定の初期化
    if ($config.logging -and $config.logging.enabled) {
        $logDir = if ($config.logging.logDirectory) {
            if ([System.IO.Path]::IsPathRooted($config.logging.logDirectory)) {
                $config.logging.logDirectory
            } else {
                Join-Path $ScriptRoot $config.logging.logDirectory
            }
        } else {
            Join-Path $ScriptRoot "logs"
        }
        
        if (-not (Test-Path $logDir)) {
            New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        }
        
        $logFileName = "netapp-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
        $script:LogFile = Join-Path $logDir $logFileName
        
        Write-Log -Message "NetApp ONTAP Report v$ScriptVersion 開始" -Level Info -LogFile $script:LogFile
        Write-Log -Message "設定ファイル: $ConfigFile" -Level Info -LogFile $script:LogFile
        Write-Host "📝 ログファイル: $script:LogFile" -ForegroundColor Gray
    }
    
    # 認証情報の取得
    Write-Host "🔐 認証情報を取得しています..."
    
    $credentialInfo = Get-NetAppCredential -Config $config -Filer $Filer -Username $Username -Password $Password
    Write-Log -Message "認証情報を取得: ファイラー=$($credentialInfo.Filer)" -Level Info -LogFile $script:LogFile
    
    Write-Host "✓ 認証情報を取得しました（ファイラー: $($credentialInfo.Filer)）"
    
    # NetApp ONTAPクラスターへの接続
    Write-Host "🔌 NetApp ONTAPクラスターへ接続しています..."
    Write-Log -Message "NetApp ONTAPクラスターへ接続開始: $($credentialInfo.Filer)" -Level Info -LogFile $script:LogFile
    
    $connectionInfo = Connect-NetAppSecure -Config $config -CredentialInfo $credentialInfo
    Write-Log -Message "NetApp接続成功: クラスター=$($connectionInfo.ClusterName) バージョン=$($connectionInfo.Version)" -Level Info -LogFile $script:LogFile
    
    Write-Host "✓ NetApp ONTAPクラスターへの接続に成功しました" -ForegroundColor Green
    Write-Host "   ファイラー: $($connectionInfo.Filer)" -ForegroundColor Gray
    Write-Host "   クラスター名: $($connectionInfo.ClusterName)" -ForegroundColor Gray
    Write-Host "   ONTAP バージョン: $($connectionInfo.Version)" -ForegroundColor Gray
    Write-Host ""
    
    # データ収集
    Write-Host "📊 データを収集しています..."
    
    $collectionParams = @{
        ConnectionInfo = $connectionInfo
        Config = $config
    }
    
    if ($Sections) {
        $collectionParams.Sections = $Sections
    }
    
    $collectedData = Invoke-DataCollection @collectionParams
    Write-Log -Message "データ収集完了: 所要時間=$($collectedData.Metadata.CollectionDuration)秒" -Level Info -LogFile $script:LogFile
    
    Write-Host "✓ データ収集が完了しました（所要時間: $($collectedData.Metadata.CollectionDuration)秒）" -ForegroundColor Green
    
    # 収集結果のサマリー表示
    Write-Host ""
    Write-Host "📈 収集結果サマリー:" -ForegroundColor Cyan
    
    if ($collectedData.Nodes) {
        Write-Host "   ノード: $($collectedData.Nodes.Count) 件"
        
        $unhealthyNodes = $collectedData.Nodes | Where-Object { -not $_.IsNodeHealthy }
        if ($unhealthyNodes) {
            Write-Host "     ⚠️  異常状態のノード: $($unhealthyNodes.Count) 件" -ForegroundColor Red
        }
    }
    if ($collectedData.Aggregates) {
        Write-Host "   アグリゲート: $($collectedData.Aggregates.Count) 件"
        
        $criticalAggr = $collectedData.Aggregates | Where-Object { $_.Status -eq 'Critical' }
        if ($criticalAggr) {
            Write-Host "     ⚠️  Critical状態のアグリゲート: $($criticalAggr.Count) 件" -ForegroundColor Red
        }
    }
    if ($collectedData.Volumes) {
        Write-Host "   ボリューム: $($collectedData.Volumes.Count) 件"
        
        $criticalVol = $collectedData.Volumes | Where-Object { $_.Status -eq 'Critical' }
        if ($criticalVol) {
            Write-Host "     ⚠️  Critical状態のボリューム: $($criticalVol.Count) 件" -ForegroundColor Red
        }
    }
    if ($collectedData.NetworkInterfaces) {
        Write-Host "   LIF: $($collectedData.NetworkInterfaces.Count) 件"
        
        $downLifs = $collectedData.NetworkInterfaces | Where-Object { $_.OpStatus -ne 'up' }
        if ($downLifs) {
            Write-Host "     ⚠️  Down状態のLIF: $($downLifs.Count) 件" -ForegroundColor Red
        }
    }
    if ($collectedData.NonZeroedDisks) {
        if ($collectedData.NonZeroedDisks.Count -gt 0) {
            Write-Host "   ゼロイング未完了ディスク: $($collectedData.NonZeroedDisks.Count) 件" -ForegroundColor Yellow
        } else {
            Write-Host "   ✓ すべてのスペアディスクがゼロイング済み" -ForegroundColor Green
        }
    }
    
    Write-Host ""
    
    # レポート出力
    Write-Host "💾 レポートを出力しています..."
    
    $exportParams = @{
        Data = $collectedData
        Config = $config
    }
    
    if ($OutputFormats) {
        $exportParams.OutputFormats = $OutputFormats
    }
    
    if ($OutputDirectory) {
        $exportParams.OutputDirectory = $OutputDirectory
    }
    
    $exportedFiles = Export-Report @exportParams
    Write-Log -Message "レポート出力完了: $($exportedFiles.Count)ファイル" -Level Info -LogFile $script:LogFile
    
    # 古いレポートのクリーンアップ
    Write-Host ""
    try {
        $outDir = if ($OutputDirectory) {
            $OutputDirectory
        } else {
            $config.report.outputDirectory
        }
        
        Remove-OldReports -OutputDirectory $outDir -Config $config
    } catch {
        Write-Warning "レポートクリーンアップ中にエラーが発生しました: $($_.Exception.Message)"
    }
    
    # 古いログのクリーンアップ
    if ($script:LogFile) {
        try {
            $logDir = Split-Path $script:LogFile -Parent
            Remove-OldLogs -LogDirectory $logDir -Config $config
        } catch {
            Write-Warning "ログクリーンアップ中にエラーが発生しました: $($_.Exception.Message)"
        }
    }
    
    # メール送信
    if ($config.email -and $config.email.enabled) {
        Write-Host ""
        Write-Host "📧 レポートをメール送信しています..."
        
        try {
            $emailResult = Send-ReportEmail -Config $config -ReportFiles $exportedFiles -Data $collectedData
            
            if (-not $emailResult) {
                Write-Host "   ℹ️  メール送信がスキップされました" -ForegroundColor Yellow
            }
        } catch {
            Write-Warning "メール送信中にエラーが発生しました: $($_.Exception.Message)"
            Write-Host "   レポートファイルは正常に生成されています" -ForegroundColor Gray
        }
    }
    
    # 完了メッセージ
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Green
    Write-Host "  ✅ レポート生成が完了しました！" -ForegroundColor Green
    Write-Host "=========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "実行時間: $([math]::Round(((Get-Date) - $connectionInfo.ConnectedAt).TotalSeconds, 2))秒" -ForegroundColor Gray
    Write-Host ""
    
    Write-Log -Message "レポート生成完了" -Level Info -LogFile $script:LogFile
    
} catch {
    Write-Log -Message "エラー発生: $($_.Exception.Message)" -Level Error -LogFile $script:LogFile
    Write-Host ""
    Write-Host "=========================================" -ForegroundColor Red
    Write-Host "  ❌ エラーが発生しました" -ForegroundColor Red
    Write-Host "=========================================" -ForegroundColor Red
    Write-Host ""
    Write-Error $_.Exception.Message
    Write-Host ""
    Write-Host "詳細なエラー情報:" -ForegroundColor Yellow
    Write-Host $_.Exception.ToString() -ForegroundColor Gray
    
    exit 1
    
} finally {
    # NetApp ONTAPクラスターからの切断
    if ($connectionInfo) {
        Write-Host ""
        Write-Host "🔌 NetApp ONTAPクラスターから切断しています..."
        Disconnect-NetAppSafe -ConnectionInfo $connectionInfo
        Write-Host "✓ 切断が完了しました"
    }
}

Write-Host ""
Write-Host "ログを確認するには、-Verbose パラメータを使用してください" -ForegroundColor Gray
Write-Host ""
