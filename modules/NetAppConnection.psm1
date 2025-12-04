<#
.SYNOPSIS
    NetApp ONTAP接続管理モジュール

.DESCRIPTION
    NetApp ONTAPクラスターへのセキュアな接続、切断、認証情報管理を提供します
#>

function Get-NetAppCredential {
    <#
    .SYNOPSIS
        NetApp ONTAP認証情報を取得
    
    .PARAMETER Config
        設定オブジェクト
    
    .PARAMETER Filer
        ファイラー名（オプション、環境変数より優先）
    
    .PARAMETER Username
        ユーザー名（オプション、環境変数より優先）
    
    .PARAMETER Password
        パスワード（SecureString形式、オプション、環境変数より優先）
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $false)]
        [string]$Filer,
        
        [Parameter(Mandatory = $false)]
        [string]$Username,
        
        [Parameter(Mandatory = $false)]
        [SecureString]$Password
    )
    
    Write-Verbose "認証情報を取得しています..."
    
    # ファイラー名の決定（優先順位: パラメータ > 環境変数 > 設定ファイル）
    $netappFiler = if ($Filer) {
        $Filer
    } elseif ($env:NETAPP_FILER) {
        $env:NETAPP_FILER
    } elseif ($Config.netapp.filer) {
        $Config.netapp.filer
    } else {
        throw "NetAppファイラー名が指定されていません。-Filer パラメータ、NETAPP_FILER環境変数、または設定ファイルで指定してください。"
    }
    
    # ユーザー名の決定
    $netappUsername = if ($Username) {
        $Username
    } elseif ($env:NETAPP_USERNAME) {
        $env:NETAPP_USERNAME
    } else {
        throw "ユーザー名が指定されていません。-Username パラメータまたはNETAPP_USERNAME環境変数で指定してください。"
    }
    
    # パスワードの決定（SecureString形式で取得）
    $securePassword = if ($Password) {
        # パラメータで渡された場合は既にSecureString形式
        $Password
    } elseif ($env:NETAPP_PASSWORD) {
        # 環境変数から取得した場合はSecureStringに変換
        ConvertTo-SecureString -String $env:NETAPP_PASSWORD -AsPlainText -Force
    } else {
        throw "パスワードが指定されていません。-Password パラメータまたはNETAPP_PASSWORD環境変数で指定してください。"
    }
    
    # PSCredentialオブジェクトの作成
    $credential = New-Object System.Management.Automation.PSCredential($netappUsername, $securePassword)
    
    return @{
        Filer = $netappFiler
        Credential = $credential
        Username = $netappUsername
    }
}

function Connect-NetAppSecure {
    <#
    .SYNOPSIS
        NetApp ONTAPクラスターへセキュアに接続
    
    .PARAMETER Config
        設定オブジェクト
    
    .PARAMETER CredentialInfo
        Get-NetAppCredentialから取得した認証情報
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$CredentialInfo
    )
    
    Write-Verbose "NetApp ONTAPクラスターへ接続しています: $($CredentialInfo.Filer)"
    
    try {
        # NetApp.ONTAPモジュールの読み込み
        $ontapModule = Get-Module -Name NetApp.ONTAP -ListAvailable | Select-Object -First 1
        
        if (-not $ontapModule) {
            throw "NetApp.ONTAPモジュールがインストールされていません。`n" +
                  "以下のコマンドでインストールしてください：`n" +
                  "  Install-Module -Name NetApp.ONTAP -Scope CurrentUser"
        }
        
        Write-Verbose "NetApp.ONTAPモジュールを使用します (Version: $($ontapModule.Version))"
        Import-Module NetApp.ONTAP -ErrorAction Stop
        
        # リトライロジックを使用した接続
        $maxAttempts = $Config.netapp.retryAttempts
        $retryDelay = $Config.netapp.retryDelaySeconds
        $timeout = $Config.netapp.timeout
        
        $attempt = 1
        $connection = $null
        $lastError = $null
        
        while ($attempt -le $maxAttempts -and -not $connection) {
            try {
                Write-Verbose "接続試行 $attempt/$maxAttempts..."
                
                $connectParams = @{
                    Name = $CredentialInfo.Filer
                    Credential = $CredentialInfo.Credential
                    Timeout = $timeout
                    ErrorAction = 'Stop'
                }
                
                $connection = Connect-NcController @connectParams
                
                if ($connection) {
                    # クラスター情報の取得
                    $clusterInfo = Get-NcCluster -ErrorAction Stop
                    $versionInfo = Get-NcSystemVersion -ErrorAction Stop
                    
                    Write-Verbose "NetApp ONTAPクラスターへの接続に成功しました: $($CredentialInfo.Filer)"
                    Write-Verbose "クラスター名: $($clusterInfo.ClusterName)"
                    Write-Verbose "ONTAP バージョン: $($versionInfo.ToString())"
                    Write-Verbose "NetApp.ONTAP モジュールバージョン: $($ontapModule.Version)"
                    
                    return @{
                        Connection = $connection
                        Filer = $CredentialInfo.Filer
                        Username = $CredentialInfo.Username
                        ClusterName = $clusterInfo.ClusterName
                        Version = $versionInfo.ToString()
                        ModuleVersion = $ontapModule.Version.ToString()
                        ConnectedAt = Get-Date
                    }
                }
            } catch {
                $lastError = $_
                Write-Warning "接続試行 $attempt/$maxAttempts が失敗しました: $($_.Exception.Message)"
                
                if ($attempt -lt $maxAttempts) {
                    Write-Verbose "${retryDelay}秒後に再試行します..."
                    Start-Sleep -Seconds $retryDelay
                }
            }
            
            $attempt++
        }
        
        # すべての試行が失敗した場合
        throw "NetApp ONTAPクラスターへの接続に失敗しました（$maxAttempts 回試行）: $($lastError.Exception.Message)"
        
    } catch {
        Write-Error "NetApp接続エラー: $($_.Exception.Message)"
        throw
    }
}

function Test-NetAppConnection {
    <#
    .SYNOPSIS
        NetApp接続のテスト
    
    .PARAMETER ConnectionInfo
        Connect-NetAppSecureから取得した接続情報
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ConnectionInfo
    )
    
    try {
        $connection = $ConnectionInfo.Connection
        
        if (-not $connection) {
            return $false
        }
        
        # 簡単なクエリで接続をテスト
        $null = Get-NcCluster -Controller $connection -ErrorAction Stop
        
        Write-Verbose "NetApp接続は有効です"
        return $true
        
    } catch {
        Write-Warning "NetApp接続テストが失敗しました: $($_.Exception.Message)"
        return $false
    }
}

function Disconnect-NetAppSafe {
    <#
    .SYNOPSIS
        NetApp ONTAPクラスターから安全に切断
    
    .PARAMETER ConnectionInfo
        Connect-NetAppSecureから取得した接続情報
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [hashtable]$ConnectionInfo
    )
    
    try {
        if ($ConnectionInfo -and $ConnectionInfo.Connection) {
            Write-Verbose "NetApp ONTAPクラスターから切断しています: $($ConnectionInfo.Filer)"
            
            # NetApp接続の切断を試みる
            # 注: NetApp.ONTAPモジュールによっては明示的な切断コマンドが不要な場合があります
            if (Get-Command -Name Disconnect-NcController -ErrorAction SilentlyContinue) {
                try {
                    $null = Disconnect-NcController -Controller $ConnectionInfo.Connection -ErrorAction Stop
                    Write-Verbose "Disconnect-NcControllerで切断しました"
                } catch {
                    Write-Verbose "Disconnect-NcController実行時の警告: $($_.Exception.Message)"
                }
            } else {
                Write-Verbose "Disconnect-NcControllerコマンドレットは利用できません（セッション自動クリーンアップ）"
            }
            
            $duration = ((Get-Date) - $ConnectionInfo.ConnectedAt).TotalSeconds
            Write-Verbose "接続時間: $([math]::Round($duration, 2))秒"
        }
    } catch {
        Write-Verbose "NetApp切断処理中の警告: $($_.Exception.Message)"
    }
}

# モジュールメンバーのエクスポート
Export-ModuleMember -Function @(
    'Get-NetAppCredential',
    'Connect-NetAppSecure',
    'Test-NetAppConnection',
    'Disconnect-NetAppSafe'
)
