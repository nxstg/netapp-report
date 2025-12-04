<#
.SYNOPSIS
    メール送信モジュール

.DESCRIPTION
    レポートをSMTP経由でメール送信します
#>

function Send-ReportEmail {
    <#
    .SYNOPSIS
        HTMLレポートをメールで送信
    
    .PARAMETER Config
        設定オブジェクト
    
    .PARAMETER ReportFiles
        送信するレポートファイルのパス配列
    
    .PARAMETER Data
        レポートデータ（サマリー生成用）
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $true)]
        [string[]]$ReportFiles,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Data
    )
    
    try {
        Write-Verbose "メール送信の準備をしています..."
        
        # メール設定の取得
        $emailConfig = $Config.email
        
        if (-not $emailConfig.enabled) {
            Write-Verbose "メール送信は無効化されています（設定ファイルで enabled = false）"
            return $false
        }
        
        # SMTP設定の取得（環境変数で上書き可能）
        $smtpServer = if ($env:SMTP_SERVER) { $env:SMTP_SERVER } else { $emailConfig.smtpServer }
        $smtpPort = if ($env:SMTP_PORT) { [int]$env:SMTP_PORT } else { $emailConfig.smtpPort }
        $from = if ($env:SMTP_FROM) { $env:SMTP_FROM } else { $emailConfig.from }
        $to = if ($env:SMTP_TO) { $env:SMTP_TO -split ',' } else { $emailConfig.to }
        
        # SMTP認証情報の取得
        $smtpCredential = $null
        if ($emailConfig.useAuthentication) {
            $smtpUsername = if ($env:SMTP_USERNAME) { $env:SMTP_USERNAME } else { $emailConfig.username }
            $smtpPassword = if ($env:SMTP_PASSWORD) { $env:SMTP_PASSWORD } else { $emailConfig.password }
            
            if ($smtpUsername -and $smtpPassword) {
                $securePassword = ConvertTo-SecureString -String $smtpPassword -AsPlainText -Force
                $smtpCredential = New-Object System.Management.Automation.PSCredential($smtpUsername, $securePassword)
                Write-Verbose "SMTP認証を使用します"
            } else {
                Write-Warning "SMTP認証が有効ですが、認証情報が不足しています"
            }
        }
        
        # 件名の生成
        $subject = $emailConfig.subject -replace '\{FilerName\}', $Data.Metadata.Filer
        $subject = $subject -replace '\{Date\}', (Get-Date -Format 'yyyy/MM/dd')
        
        # サマリー情報の生成
        $summary = @"
NetApp ONTAP Report

ファイラー: $($Data.Metadata.Filer)
クラスター名: $($Data.Metadata.ClusterName)
レポート日時: $($Data.Metadata.CollectionTime.ToString('yyyy/MM/dd HH:mm:ss'))
収集時間: $($Data.Metadata.CollectionDuration)秒

=== サマリー ===
"@
        
        if ($Data.Nodes) {
            $summary += "`nノード: $($Data.Nodes.Count) 件"
            $unhealthyNodes = @($Data.Nodes | Where-Object { -not $_.IsNodeHealthy })
            if ($unhealthyNodes.Count -gt 0) {
                $summary += "`n  ⚠ 異常状態: $($unhealthyNodes.Count) 件"
            }
        }
        if ($Data.Aggregates) {
            $summary += "`nアグリゲート: $($Data.Aggregates.Count) 件"
            $criticalAggr = @($Data.Aggregates | Where-Object { $_.Status -eq 'Critical' })
            if ($criticalAggr.Count -gt 0) {
                $summary += "`n  ⚠ Critical状態: $($criticalAggr.Count) 件"
            }
        }
        if ($Data.Volumes) {
            $summary += "`nボリューム: $($Data.Volumes.Count) 件"
            $criticalVol = @($Data.Volumes | Where-Object { $_.Status -eq 'Critical' })
            if ($criticalVol.Count -gt 0) {
                $summary += "`n  ⚠ Critical状態: $($criticalVol.Count) 件"
            }
        }
        if ($Data.NetworkInterfaces) {
            $summary += "`nLIF: $($Data.NetworkInterfaces.Count) 件"
            $downLifs = @($Data.NetworkInterfaces | Where-Object { $_.OpStatus -ne 'up' })
            if ($downLifs.Count -gt 0) {
                $summary += "`n  ⚠ Down状態: $($downLifs.Count) 件"
            }
        }
        if ($Data.NonZeroedDisks) {
            if ($Data.NonZeroedDisks.Count -gt 0) {
                $summary += "`n`n⚠ ゼロイング未完了ディスク: $($Data.NonZeroedDisks.Count) 件"
            } else {
                $summary += "`n`n✓ すべてのスペアディスクがゼロイング済み"
            }
        }
        
        $summary += "`n`n詳細はレポートファイルをご確認ください。"
        
        # HTMLファイルを探す
        $htmlFile = $ReportFiles | Where-Object { $_ -match '\.html$' } | Select-Object -First 1
        
        # メール本文の決定
        $body = $summary
        $bodyAsHtml = $false
        $attachments = @()
        
        if ($emailConfig.attachReports) {
            # レポートを添付
            $attachments = $ReportFiles | Where-Object { Test-Path $_ }
            Write-Verbose "添付ファイル数: $($attachments.Count)"
        } elseif ($htmlFile -and $emailConfig.includeHtmlInBody) {
            # HTMLを本文に含める
            $body = Get-Content -Path $htmlFile -Raw -Encoding UTF8
            $bodyAsHtml = $true
            Write-Verbose "HTML本文を使用します"
        }
        
        # MailMessageオブジェクトの作成
        $mailMessage = New-Object System.Net.Mail.MailMessage
        $mailMessage.From = $from
        $mailMessage.Subject = $subject
        $mailMessage.Body = $body
        $mailMessage.IsBodyHtml = $bodyAsHtml
        $mailMessage.BodyEncoding = [System.Text.Encoding]::UTF8
        $mailMessage.SubjectEncoding = [System.Text.Encoding]::UTF8
        
        # 送信先の追加
        foreach ($recipient in $to) {
            $mailMessage.To.Add($recipient)
        }
        
        # CC/BCCの追加
        if ($emailConfig.cc -and $emailConfig.cc.Count -gt 0) {
            foreach ($ccRecipient in $emailConfig.cc) {
                $mailMessage.CC.Add($ccRecipient)
            }
        }
        if ($emailConfig.bcc -and $emailConfig.bcc.Count -gt 0) {
            foreach ($bccRecipient in $emailConfig.bcc) {
                $mailMessage.Bcc.Add($bccRecipient)
            }
        }
        
        # 添付ファイルの追加
        if ($attachments.Count -gt 0) {
            foreach ($attachmentPath in $attachments) {
                $attachment = New-Object System.Net.Mail.Attachment($attachmentPath)
                $mailMessage.Attachments.Add($attachment)
            }
        }
        
        # SmtpClientの設定
        $smtpClient = New-Object System.Net.Mail.SmtpClient($smtpServer, $smtpPort)
        
        # 暗号化タイプの決定（環境変数で上書き可能）
        $encryptionType = if ($env:SMTP_ENCRYPTION) {
            $env:SMTP_ENCRYPTION
        } elseif ($emailConfig.encryptionType) {
            $emailConfig.encryptionType
        } else {
            "StartTLS"  # デフォルト
        }
        
        # 暗号化設定
        switch ($encryptionType.ToLower()) {
            "ssl" {
                $smtpClient.EnableSsl = $true
                Write-Verbose "暗号化: SSL/TLS（ポート ${smtpPort}）"
            }
            "starttls" {
                $smtpClient.EnableSsl = $true
                Write-Verbose "暗号化: STARTTLS（ポート ${smtpPort}）"
            }
            "none" {
                $smtpClient.EnableSsl = $false
                Write-Verbose "暗号化: なし（ポート ${smtpPort}）"
            }
            default {
                $smtpClient.EnableSsl = $true
                Write-Verbose "暗号化: STARTTLS（デフォルト、ポート ${smtpPort}）"
            }
        }
        
        if ($smtpCredential) {
            $smtpClient.Credentials = $smtpCredential.GetNetworkCredential()
        }
        
        Write-Verbose "メールを送信しています..."
        Write-Verbose "  送信先: $($to -join ', ')"
        Write-Verbose "  SMTPサーバー: ${smtpServer}:${smtpPort}"
        
        try {
            # メール送信
            $smtpClient.Send($mailMessage)
            
            Write-Host "`n✅ メールを送信しました" -ForegroundColor Green
            Write-Host "   送信先: $($to -join ', ')" -ForegroundColor Gray
            if ($attachments.Count -gt 0) {
                Write-Host "   添付ファイル: $($attachments.Count) 件" -ForegroundColor Gray
            }
            
            return $true
            
        } finally {
            # リソースのクリーンアップ
            if ($mailMessage.Attachments.Count -gt 0) {
                foreach ($attachment in $mailMessage.Attachments) {
                    $attachment.Dispose()
                }
            }
            $mailMessage.Dispose()
            $smtpClient.Dispose()
        }
        
    } catch {
        Write-Error "メール送信中にエラーが発生しました: $($_.Exception.Message)"
        Write-Warning "メールの送信に失敗しましたが、レポート生成は完了しています"
        return $false
    }
}

# モジュールメンバーのエクスポート
Export-ModuleMember -Function @(
    'Send-ReportEmail'
)
