<#
.SYNOPSIS
    レポート出力フォーマットモジュール

.DESCRIPTION
    収集したデータを様々な形式（JSON、HTML、CSV）で出力します
#>

function Export-ReportToJSON {
    <#
    .SYNOPSIS
        レポートデータをJSON形式で出力
    
    .PARAMETER Data
        レポートデータ
    
    .PARAMETER OutputPath
        出力ファイルパス
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Data,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )
    
    try {
        Write-Verbose "JSON形式でレポートを出力しています: $OutputPath"
        
        $jsonOutput = $Data | ConvertTo-Json -Depth 10
        $jsonOutput | Out-File -FilePath $OutputPath -Encoding UTF8
        
        Write-Verbose "JSONレポートを保存しました: $OutputPath"
        return $OutputPath
        
    } catch {
        Write-Error "JSON出力中にエラーが発生しました: $($_.Exception.Message)"
        throw
    }
}

function Export-ReportToHTML {
    <#
    .SYNOPSIS
        レポートデータをHTML形式で出力
    
    .PARAMETER Data
        レポートデータ
    
    .PARAMETER OutputPath
        出力ファイルパス
    
    .PARAMETER Config
        設定オブジェクト
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Data,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    try {
        Write-Verbose "HTML形式でレポートを出力しています: $OutputPath"
        
        $html = @"
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>NetApp Report - $($Data.Metadata.Filer)</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #f5f5f5;
            padding: 20px;
        }
        .container { 
            max-width: 1400px;
            margin: 0 auto;
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 { 
            color: #0066cc;
            margin-bottom: 10px;
            border-bottom: 3px solid #0066cc;
            padding-bottom: 10px;
        }
        h2 { 
            color: #333;
            margin-top: 30px;
            margin-bottom: 15px;
            padding-left: 10px;
            border-left: 4px solid #0066cc;
        }
        .metadata { 
            background: #e6f2ff;
            padding: 15px;
            border-radius: 5px;
            margin-bottom: 20px;
        }
        .metadata p { 
            margin: 5px 0;
            color: #333;
        }
        table { 
            width: 100%;
            border-collapse: collapse;
            margin-bottom: 30px;
            font-size: 14px;
        }
        th { 
            background: #0066cc;
            color: white;
            padding: 12px;
            text-align: left;
            font-weight: 600;
        }
        td { 
            padding: 10px 12px;
            border-bottom: 1px solid #ddd;
        }
        tr:hover { background: #f8f9fa; }
        .status-ok { color: #27ae60; font-weight: bold; }
        .status-warning { color: #f39c12; font-weight: bold; }
        .status-critical { color: #e74c3c; font-weight: bold; }
        .summary-card {
            background: linear-gradient(135deg, #0066cc 0%, #003d7a 100%);
            color: white;
            padding: 20px;
            border-radius: 8px;
            margin-bottom: 10px;
            display: inline-block;
            width: 23%;
            min-width: 200px;
            vertical-align: top;
            margin-right: 1%;
        }
        .summary-card h3 {
            font-size: 14px;
            opacity: 0.9;
            margin-bottom: 10px;
        }
        .summary-card .value {
            font-size: 32px;
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🗄️ NetApp ONTAP Report</h1>
        
        <div class="metadata">
            <p><strong>ファイラー:</strong> $($Data.Metadata.Filer)</p>
            <p><strong>クラスター名:</strong> $($Data.Metadata.ClusterName)</p>
            <p><strong>ONTAP バージョン:</strong> $($Data.Metadata.Version)</p>
            <p><strong>レポート日時:</strong> $($Data.Metadata.CollectionTime.ToString('yyyy/MM/dd HH:mm:ss'))</p>
            <p><strong>収集時間:</strong> $($Data.Metadata.CollectionDuration) 秒</p>
        </div>
"@

        # サマリーカード
        if ($Data.Nodes -or $Data.Aggregates -or $Data.Volumes) {
            $html += @"
        <h2>📊 サマリー</h2>
        <table cellpadding="0" cellspacing="10" border="0" style="width: 100%; margin-bottom: 30px;">
            <tr>
"@
            if ($Data.Nodes) {
                $html += @"
                <td style="background: linear-gradient(135deg, #0066cc 0%, #003d7a 100%); background-color: #0066cc; color: white; padding: 20px; border-radius: 8px; width: 23%; min-width: 200px; vertical-align: top;">
                    <div style="font-size: 14px; opacity: 0.9; margin-bottom: 10px;">ノード</div>
                    <div style="font-size: 32px; font-weight: bold;">$($Data.Nodes.Count)</div>
                </td>
"@
            }
            
            if ($Data.Aggregates) {
                $criticalAggr = @($Data.Aggregates | Where-Object { $_.Status -eq 'Critical' })
                $warningAggr = @($Data.Aggregates | Where-Object { $_.Status -eq 'Warning' })
                $statusInfo = if ($criticalAggr.Count -gt 0) { "<br/><small>⚠️ Critical: $($criticalAggr.Count)</small>" } elseif ($warningAggr.Count -gt 0) { "<br/><small>⚠️ Warning: $($warningAggr.Count)</small>" } else { "" }
                
                $html += @"
                <td style="background: linear-gradient(135deg, #0066cc 0%, #003d7a 100%); background-color: #0066cc; color: white; padding: 20px; border-radius: 8px; width: 23%; min-width: 200px; vertical-align: top;">
                    <div style="font-size: 14px; opacity: 0.9; margin-bottom: 10px;">アグリゲート</div>
                    <div style="font-size: 32px; font-weight: bold;">$($Data.Aggregates.Count)$statusInfo</div>
                </td>
"@
            }
            
            if ($Data.Volumes) {
                $criticalVol = @($Data.Volumes | Where-Object { $_.Status -eq 'Critical' })
                $warningVol = @($Data.Volumes | Where-Object { $_.Status -eq 'Warning' })
                $statusInfo = if ($criticalVol.Count -gt 0) { "<br/><small>⚠️ Critical: $($criticalVol.Count)</small>" } elseif ($warningVol.Count -gt 0) { "<br/><small>⚠️ Warning: $($warningVol.Count)</small>" } else { "" }
                
                $html += @"
                <td style="background: linear-gradient(135deg, #0066cc 0%, #003d7a 100%); background-color: #0066cc; color: white; padding: 20px; border-radius: 8px; width: 23%; min-width: 200px; vertical-align: top;">
                    <div style="font-size: 14px; opacity: 0.9; margin-bottom: 10px;">ボリューム</div>
                    <div style="font-size: 32px; font-weight: bold;">$($Data.Volumes.Count)$statusInfo</div>
                </td>
"@
            }
            
            if ($Data.NetworkInterfaces) {
                $html += @"
                <td style="background: linear-gradient(135deg, #0066cc 0%, #003d7a 100%); background-color: #0066cc; color: white; padding: 20px; border-radius: 8px; width: 23%; min-width: 200px; vertical-align: top;">
                    <div style="font-size: 14px; opacity: 0.9; margin-bottom: 10px;">LIF</div>
                    <div style="font-size: 32px; font-weight: bold;">$($Data.NetworkInterfaces.Count)</div>
                </td>
"@
            }
            
            $html += @"
            </tr>
        </table>
"@
        }

        # ディスクゼロイングセクション
        if ($Data.NonZeroedDisks) {
            $html += @"
        <h2>💿 ディスク（ゼロイング未完了）</h2>
"@
            if ($Data.NonZeroedDisks.Count -eq 0) {
                $html += @"
        <p style="padding: 15px; background: #d4edda; border: 1px solid #c3e6cb; border-radius: 5px; color: #155724;">
            ✅ すべてのスペアディスクがゼロイング済みです
        </p>
"@
            } else {
                $html += @"
        <p style="padding: 15px; background: #fff3cd; border: 1px solid #ffc107; border-radius: 5px; color: #856404; margin-bottom: 15px;">
            ⚠️ $($Data.NonZeroedDisks.Count) 個のディスクがゼロイング未完了です
        </p>
        <table>
            <thead>
                <tr>
                    <th>ディスク名</th>
                    <th>シェルフ</th>
                    <th>ベイ</th>
                    <th>タイプ</th>
                    <th>サイズ</th>
                    <th>ホームノード</th>
                    <th>オーナーノード</th>
                    <th>ゼロイング</th>
                </tr>
            </thead>
            <tbody>
"@
                foreach ($disk in $Data.NonZeroedDisks) {
                    $html += @"
                <tr>
                    <td><strong>$($disk.Name)</strong></td>
                    <td>$($disk.Shelf)</td>
                    <td>$($disk.Bay)</td>
                    <td>$($disk.DiskType)</td>
                    <td>$($disk.PhysicalSizeReadable)</td>
                    <td>$($disk.HomeNodeName)</td>
                    <td>$($disk.OwnerNodeName)</td>
                    <td class="status-warning">未完了</td>
                </tr>
"@
                }
                $html += @"
            </tbody>
        </table>
"@
            }
        }

        # ノードセクション
        if ($Data.Nodes) {
            $html += @"
        <h2>🖥️ ノード情報</h2>
        <table>
            <thead>
                <tr>
                    <th>ノード</th>
                    <th>Epsilon</th>
                    <th>正常性</th>
                    <th>シリアル番号</th>
                    <th>モデル</th>
                    <th>バージョン</th>
                    <th>アップタイム</th>
                </tr>
            </thead>
            <tbody>
"@
            foreach ($node in $Data.Nodes) {
                $healthClass = if ($node.IsNodeHealthy) { "status-ok" } else { "status-critical" }
                $healthText = if ($node.IsNodeHealthy) { "正常" } else { "異常" }
                
                # 読みやすいアップタイムを使用
                $uptimeDisplay = if ($node.NodeUptimeReadable) { $node.NodeUptimeReadable } else { $node.NodeUptime }
                
                $html += @"
                <tr>
                    <td><strong>$($node.Node)</strong></td>
                    <td>$($node.IsEpsilonNode)</td>
                    <td class="$healthClass">$healthText</td>
                    <td>$($node.NodeSerialNumber)</td>
                    <td>$($node.NodeModel)</td>
                    <td>$($node.ProductVersion)</td>
                    <td>$uptimeDisplay</td>
                </tr>
"@
            }
            $html += @"
            </tbody>
        </table>
"@
        }

        # アグリゲートセクション
        if ($Data.Aggregates) {
            $html += @"
        <h2>📦 アグリゲート情報</h2>
        <table>
            <thead>
                <tr>
                    <th>名前</th>
                    <th>状態</th>
                    <th>合計サイズ</th>
                    <th>使用量</th>
                    <th>空き容量</th>
                    <th>使用率</th>
                    <th>ステータス</th>
                    <th>オーナー</th>
                </tr>
            </thead>
            <tbody>
"@
            foreach ($aggr in $Data.Aggregates) {
                $statusClass = switch ($aggr.Status) {
                    "Critical" { "status-critical" }
                    "Warning" { "status-warning" }
                    default { "status-ok" }
                }
                
                $html += @"
                <tr>
                    <td><strong>$($aggr.Name)</strong></td>
                    <td>$($aggr.State)</td>
                    <td>$($aggr.TotalSizeReadable)</td>
                    <td>$($aggr.UsedReadable)</td>
                    <td>$($aggr.AvailableReadable)</td>
                    <td>$($aggr.UsedPercent)%</td>
                    <td class="$statusClass">$($aggr.Status)</td>
                    <td>$($aggr.OwnerName)</td>
                </tr>
"@
            }
            $html += @"
            </tbody>
        </table>
"@
        }

        # ボリュームセクション
        if ($Data.Volumes) {
            $html += @"
        <h2>📂 ボリューム情報</h2>
        <table>
            <thead>
                <tr>
                    <th>名前</th>
                    <th>状態</th>
                    <th>合計サイズ</th>
                    <th>使用量</th>
                    <th>空き容量</th>
                    <th>使用率</th>
                    <th>ステータス</th>
                    <th>アグリゲート</th>
                    <th>Vserver</th>
                </tr>
            </thead>
            <tbody>
"@
            foreach ($vol in $Data.Volumes) {
                $statusClass = switch ($vol.Status) {
                    "Critical" { "status-critical" }
                    "Warning" { "status-warning" }
                    default { "status-ok" }
                }
                
                $html += @"
                <tr>
                    <td><strong>$($vol.Name)</strong></td>
                    <td>$($vol.State)</td>
                    <td>$($vol.TotalSizeReadable)</td>
                    <td>$($vol.UsedReadable)</td>
                    <td>$($vol.AvailableReadable)</td>
                    <td>$($vol.UsedPercent)%</td>
                    <td class="$statusClass">$($vol.Status)</td>
                    <td>$($vol.Aggregate)</td>
                    <td>$($vol.Vserver)</td>
                </tr>
"@
            }
            $html += @"
            </tbody>
        </table>
"@
        }

        # 全ディスクセクション
        if ($Data.AllDisks) {
            $html += @"
        <h2>💾 全ディスク情報</h2>
        <table>
            <thead>
                <tr>
                    <th>ディスク名</th>
                    <th>シェルフ</th>
                    <th>ベイ</th>
                    <th>ベンダー</th>
                    <th>モデル</th>
                    <th>ファームウェア</th>
                    <th>タイプ</th>
                    <th>RPM</th>
                    <th>サイズ</th>
                    <th>コンテナ</th>
                    <th>コンテナ名</th>
                    <th>オーナー</th>
                </tr>
            </thead>
            <tbody>
"@
            foreach ($disk in $Data.AllDisks) {
                $html += @"
                <tr>
                    <td><strong>$($disk.Name)</strong></td>
                    <td>$($disk.Shelf)</td>
                    <td>$($disk.Bay)</td>
                    <td>$($disk.Vendor)</td>
                    <td>$($disk.Model)</td>
                    <td>$($disk.FirmwareRevision)</td>
                    <td>$($disk.DiskType)</td>
                    <td>$($disk.RPM)</td>
                    <td>$($disk.PhysicalSizeReadable)</td>
                    <td>$($disk.ContainerType)</td>
                    <td>$($disk.ContainerName)</td>
                    <td>$($disk.OwnerNodeName)</td>
                </tr>
"@
            }
            $html += @"
            </tbody>
        </table>
"@
        }

        # LIFセクション
        if ($Data.NetworkInterfaces) {
            # 管理LIFとデータLIFを分ける
            $mgmtLifs = $Data.NetworkInterfaces | Where-Object { $_.Role -ne "data" }
            $dataLifs = $Data.NetworkInterfaces | Where-Object { $_.Role -eq "data" }
            
            if ($mgmtLifs) {
                $html += @"
        <h2>🌐 LIF情報（管理）</h2>
        <table>
            <thead>
                <tr>
                    <th>インターフェース名</th>
                    <th>動作状態</th>
                    <th>ホーム</th>
                    <th>現在ポート</th>
                    <th>アドレス</th>
                    <th>Vserver</th>
                </tr>
            </thead>
            <tbody>
"@
                foreach ($lif in $mgmtLifs) {
                    $statusClass = if ($lif.OpStatus -eq "up") { "status-ok" } else { "status-warning" }
                    $homeClass = if ($lif.IsHome) { "status-ok" } else { "status-warning" }
                    
                    $html += @"
                <tr>
                    <td><strong>$($lif.InterfaceName)</strong></td>
                    <td class="$statusClass">$($lif.OpStatus)</td>
                    <td class="$homeClass">$($lif.IsHome)</td>
                    <td>$($lif.CurrentPort)</td>
                    <td>$($lif.AddressFamily)</td>
                    <td>$($lif.Vserver)</td>
                </tr>
"@
                }
                $html += @"
            </tbody>
        </table>
"@
            }
            
            if ($dataLifs) {
                $html += @"
        <h2>🌐 LIF情報（データ）</h2>
        <table>
            <thead>
                <tr>
                    <th>インターフェース名</th>
                    <th>動作状態</th>
                    <th>ホーム</th>
                    <th>現在ポート</th>
                    <th>アドレス</th>
                    <th>Vserver</th>
                    <th>プロトコル</th>
                </tr>
            </thead>
            <tbody>
"@
                foreach ($lif in $dataLifs) {
                    $statusClass = if ($lif.OpStatus -eq "up") { "status-ok" } else { "status-warning" }
                    $homeClass = if ($lif.IsHome) { "status-ok" } else { "status-warning" }
                    
                    $html += @"
                <tr>
                    <td><strong>$($lif.InterfaceName)</strong></td>
                    <td class="$statusClass">$($lif.OpStatus)</td>
                    <td class="$homeClass">$($lif.IsHome)</td>
                    <td>$($lif.CurrentPort)</td>
                    <td>$($lif.AddressFamily)</td>
                    <td>$($lif.Vserver)</td>
                    <td>$($lif.DataProtocols)</td>
                </tr>
"@
                }
                $html += @"
            </tbody>
        </table>
"@
            }
        }

        # ポートセクション
        if ($Data.Ports) {
            $html += @"
        <h2>🔌 ネットワークポート情報</h2>
        <table>
            <thead>
                <tr>
                    <th>ノード</th>
                    <th>ポート</th>
                    <th>リンク状態</th>
                    <th>動作状態</th>
                    <th>タイプ</th>
                    <th>速度</th>
                    <th>MTU</th>
                    <th>ブロードキャストドメイン</th>
                    <th>ヘルス</th>
                </tr>
            </thead>
            <tbody>
"@
            foreach ($port in $Data.Ports) {
                $linkClass = if ($port.LinkStatus -eq "up") { "status-ok" } else { "status-warning" }
                $opClass = if ($port.OperationalStatus -eq "up") { "status-ok" } else { "status-warning" }
                $healthClass = if ($port.HealthStatus -eq "healthy") { "status-ok" } else { "status-warning" }
                
                $html += @"
                <tr>
                    <td><strong>$($port.Node)</strong></td>
                    <td>$($port.Port)</td>
                    <td class="$linkClass">$($port.LinkStatus)</td>
                    <td class="$opClass">$($port.OperationalStatus)</td>
                    <td>$($port.PortType)</td>
                    <td>$($port.LinkSpeed)</td>
                    <td>$($port.MTU)</td>
                    <td>$($port.BroadcastDomain)</td>
                    <td class="$healthClass">$($port.HealthStatus)</td>
                </tr>
"@
            }
            $html += @"
            </tbody>
        </table>
"@
        }

        # ヘルスアラートセクション
        if ($Data.HealthAlerts) {
            $html += @"
        <h2>⚠️ システムヘルスアラート</h2>
"@
            if ($Data.HealthAlerts.Count -eq 0) {
                $html += @"
        <p style="padding: 15px; background: #d4edda; border: 1px solid #c3e6cb; border-radius: 5px; color: #155724;">
            ✅ アクティブなヘルスアラートはありません
        </p>
"@
            } else {
                $html += @"
        <p style="padding: 15px; background: #fff3cd; border: 1px solid #ffc107; border-radius: 5px; color: #856404; margin-bottom: 15px;">
            ⚠️ $($Data.HealthAlerts.Count) 件のアクティブなアラートがあります
        </p>
        <table>
            <thead>
                <tr>
                    <th>発生日時</th>
                    <th>重要度</th>
                    <th>リソース</th>
                    <th>サブシステム</th>
                    <th>兆候</th>
                    <th>推定原因</th>
                    <th>対処方法</th>
                </tr>
            </thead>
            <tbody>
"@
                foreach ($alert in $Data.HealthAlerts) {
                    $severityClass = switch ($alert.Severity) {
                        'critical' { "status-critical" }
                        'major' { "status-warning" }
                        default { "status-ok" }
                    }
                    
                    $html += @"
                <tr>
                    <td>$($alert.AlertTime.ToString('yyyy/MM/dd HH:mm:ss'))</td>
                    <td class="$severityClass">$($alert.Severity)</td>
                    <td><strong>$($alert.Resource)</strong></td>
                    <td>$($alert.Subsystem)</td>
                    <td>$($alert.Indication)</td>
                    <td>$($alert.ProbableCause)</td>
                    <td>$($alert.CorrectiveAction)</td>
                </tr>
"@
                }
                $html += @"
            </tbody>
        </table>
"@
            }
        }

        # EMSエラーイベントセクション
        if ($Data.ErrorEvents) {
            $html += @"
        <h2>🔴 EMSエラーイベント（過去24時間）</h2>
"@
            if ($Data.ErrorEvents.Count -eq 0) {
                $html += @"
        <p style="padding: 15px; background: #d4edda; border: 1px solid #c3e6cb; border-radius: 5px; color: #155724;">
            ✅ エラーイベントは検出されませんでした
        </p>
"@
            } else {
                $html += @"
        <p style="padding: 15px; background: #f8d7da; border: 1px solid #f5c6cb; border-radius: 5px; color: #721c24; margin-bottom: 15px;">
            ⚠️ $($Data.ErrorEvents.Count) 件のエラーイベントが検出されました（最大100件表示）
        </p>
        <table>
            <thead>
                <tr>
                    <th>発生日時</th>
                    <th>重要度</th>
                    <th>ノード</th>
                    <th>ソース</th>
                    <th>イベント</th>
                    <th>メッセージ</th>
                </tr>
            </thead>
            <tbody>
"@
                foreach ($errorEvent in $Data.ErrorEvents) {
                    $severityClass = switch ($errorEvent.Severity) {
                        'emergency' { "status-critical" }
                        'alert' { "status-critical" }
                        'critical' { "status-critical" }
                        'error' { "status-warning" }
                        default { "status-ok" }
                    }
                    
                    $html += @"
                <tr>
                    <td>$($errorEvent.Time.ToString('yyyy/MM/dd HH:mm:ss'))</td>
                    <td class="$severityClass">$($errorEvent.Severity)</td>
                    <td><strong>$($errorEvent.Node)</strong></td>
                    <td>$($errorEvent.Source)</td>
                    <td>$($errorEvent.Event)</td>
                    <td style="max-width: 400px; word-wrap: break-word;">$($errorEvent.Message)</td>
                </tr>
"@
                }
                $html += @"
            </tbody>
        </table>
"@
            }
        }

        $html += @"
        <footer style="margin-top: 40px; padding-top: 20px; border-top: 1px solid #ddd; text-align: center; color: #7f8c8d;">
            <p>Generated by NetApp Report v1.0.0</p>
            <p>$(Get-Date -Format 'yyyy/MM/dd HH:mm:ss')</p>
        </footer>
    </div>
</body>
</html>
"@

        $html | Out-File -FilePath $OutputPath -Encoding UTF8
        
        Write-Verbose "HTMLレポートを保存しました: $OutputPath"
        return $OutputPath
        
    } catch {
        Write-Error "HTML出力中にエラーが発生しました: $($_.Exception.Message)"
        throw
    }
}

function Export-ReportToCSV {
    <#
    .SYNOPSIS
        レポートデータをCSV形式で出力
    
    .PARAMETER Data
        レポートデータ
    
    .PARAMETER OutputDirectory
        出力ディレクトリ
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Data,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory
    )
    
    try {
        Write-Verbose "CSV形式でレポートを出力しています: $OutputDirectory"
        
        $exportedFiles = @()
        
        # ノードCSV
        if ($Data.Nodes) {
            $nodesPath = Join-Path $OutputDirectory "nodes.csv"
            $Data.Nodes | Export-Csv -Path $nodesPath -NoTypeInformation -Encoding UTF8
            $exportedFiles += $nodesPath
            Write-Verbose "ノードCSVを保存しました: $nodesPath"
        }
        
        # アグリゲートCSV
        if ($Data.Aggregates) {
            $aggregatesPath = Join-Path $OutputDirectory "aggregates.csv"
            $Data.Aggregates | Export-Csv -Path $aggregatesPath -NoTypeInformation -Encoding UTF8
            $exportedFiles += $aggregatesPath
            Write-Verbose "アグリゲートCSVを保存しました: $aggregatesPath"
        }
        
        # ボリュームCSV
        if ($Data.Volumes) {
            $volumesPath = Join-Path $OutputDirectory "volumes.csv"
            $Data.Volumes | Export-Csv -Path $volumesPath -NoTypeInformation -Encoding UTF8
            $exportedFiles += $volumesPath
            Write-Verbose "ボリュームCSVを保存しました: $volumesPath"
        }
        
        # LIFCSV
        if ($Data.NetworkInterfaces) {
            $lifsPath = Join-Path $OutputDirectory "network-interfaces.csv"
            $Data.NetworkInterfaces | Export-Csv -Path $lifsPath -NoTypeInformation -Encoding UTF8
            $exportedFiles += $lifsPath
            Write-Verbose "LIF CSVを保存しました: $lifsPath"
        }
        
        # ポートCSV
        if ($Data.Ports) {
            $portsPath = Join-Path $OutputDirectory "ports.csv"
            $Data.Ports | Export-Csv -Path $portsPath -NoTypeInformation -Encoding UTF8
            $exportedFiles += $portsPath
            Write-Verbose "ポートCSVを保存しました: $portsPath"
        }
        
        # ディスクCSV（ゼロイング未完了）
        if ($Data.NonZeroedDisks -and $Data.NonZeroedDisks.Count -gt 0) {
            $disksPath = Join-Path $OutputDirectory "non-zeroed-disks.csv"
            $Data.NonZeroedDisks | Export-Csv -Path $disksPath -NoTypeInformation -Encoding UTF8
            $exportedFiles += $disksPath
            Write-Verbose "ディスクCSVを保存しました: $disksPath"
        }
        
        # 全ディスクCSV
        if ($Data.AllDisks) {
            $allDisksPath = Join-Path $OutputDirectory "all-disks.csv"
            $Data.AllDisks | Export-Csv -Path $allDisksPath -NoTypeInformation -Encoding UTF8
            $exportedFiles += $allDisksPath
            Write-Verbose "全ディスクCSVを保存しました: $allDisksPath"
        }
        
        # ヘルスアラートCSV
        if ($Data.HealthAlerts -and $Data.HealthAlerts.Count -gt 0) {
            $alertsPath = Join-Path $OutputDirectory "health-alerts.csv"
            $Data.HealthAlerts | Export-Csv -Path $alertsPath -NoTypeInformation -Encoding UTF8
            $exportedFiles += $alertsPath
            Write-Verbose "ヘルスアラートCSVを保存しました: $alertsPath"
        }
        
        # EMSエラーイベントCSV
        if ($Data.ErrorEvents -and $Data.ErrorEvents.Count -gt 0) {
            $eventsPath = Join-Path $OutputDirectory "error-events.csv"
            $Data.ErrorEvents | Export-Csv -Path $eventsPath -NoTypeInformation -Encoding UTF8
            $exportedFiles += $eventsPath
            Write-Verbose "EMSエラーイベントCSVを保存しました: $eventsPath"
        }
        
        Write-Verbose "CSVレポートを保存しました（$($exportedFiles.Count) ファイル）"
        return $exportedFiles
        
    } catch {
        Write-Error "CSV出力中にエラーが発生しました: $($_.Exception.Message)"
        throw
    }
}

function Export-Report {
    <#
    .SYNOPSIS
        指定された形式でレポートを出力
    
    .PARAMETER Data
        レポートデータ
    
    .PARAMETER Config
        設定オブジェクト
    
    .PARAMETER OutputFormats
        出力形式の配列（オプション、設定ファイルより優先）
    
    .PARAMETER OutputDirectory
        出力ディレクトリ（オプション、設定ファイルより優先）
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Data,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $false)]
        [string[]]$OutputFormats,
        
        [Parameter(Mandatory = $false)]
        [string]$OutputDirectory
    )
    
    try {
        # 出力形式の決定
        $formats = if ($OutputFormats) {
            $OutputFormats
        } else {
            $Config.report.outputFormats
        }
        
        # 出力ディレクトリの決定
        $outDir = if ($OutputDirectory) {
            $OutputDirectory
        } else {
            $Config.report.outputDirectory
        }
        
        # ディレクトリの作成
        if (-not (Test-Path $outDir)) {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
            Write-Verbose "出力ディレクトリを作成しました: $outDir"
        }
        
        # タイムスタンプ付きファイル名
        $timestamp = if ($Config.report.includeTimestamp) {
            "-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        } else {
            ""
        }
        
        $baseFileName = "$($Data.Metadata.Filer -replace '\.', '-')$timestamp"
        
        $exportedFiles = @()
        
        foreach ($format in $formats) {
            switch ($format.ToLower()) {
                'json' {
                    $jsonPath = Join-Path $outDir "$baseFileName.json"
                    $null = Export-ReportToJSON -Data $Data -OutputPath $jsonPath
                    $exportedFiles += $jsonPath
                }
                'html' {
                    $htmlPath = Join-Path $outDir "$baseFileName.html"
                    $null = Export-ReportToHTML -Data $Data -OutputPath $htmlPath -Config $Config
                    $exportedFiles += $htmlPath
                }
                'csv' {
                    $csvDir = Join-Path $outDir "csv$timestamp"
                    if (-not (Test-Path $csvDir)) {
                        New-Item -ItemType Directory -Path $csvDir -Force | Out-Null
                    }
                    $csvFiles = Export-ReportToCSV -Data $Data -OutputDirectory $csvDir
                    $exportedFiles += $csvFiles
                }
            }
        }
        
        Write-Host "`n✅ レポートを出力しました:"
        foreach ($file in $exportedFiles) {
            Write-Host "   📄 $file"
        }
        
        return $exportedFiles
        
    } catch {
        Write-Error "レポート出力中にエラーが発生しました: $($_.Exception.Message)"
        throw
    }
}

function Remove-OldReports {
    <#
    .SYNOPSIS
        古いレポートファイルを削除
    
    .PARAMETER OutputDirectory
        レポート出力ディレクトリ
    
    .PARAMETER Config
        設定オブジェクト
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    try {
        if (-not $Config.report.retention -or -not $Config.report.retention.enabled) {
            Write-Verbose "レポート保持機能は無効です"
            return
        }
        
        Write-Verbose "古いレポートファイルをクリーンアップしています..."
        
        $retentionDays = $Config.report.retention.days
        $maxGenerations = $Config.report.retention.maxGenerations
        $cutoffDate = (Get-Date).AddDays(-$retentionDays)
        
        # 出力ディレクトリが存在しない場合は何もしない
        if (-not (Test-Path $OutputDirectory)) {
            Write-Verbose "出力ディレクトリが存在しません: $OutputDirectory"
            return
        }
        
        # JSON/HTMLファイルのクリーンアップ
        $reportFiles = Get-ChildItem -Path $OutputDirectory -Filter "*.json" -File -ErrorAction SilentlyContinue
        $reportFiles += Get-ChildItem -Path $OutputDirectory -Filter "*.html" -File -ErrorAction SilentlyContinue
        
        $deletedCount = 0
        
        # 日数ベースの削除
        foreach ($file in $reportFiles) {
            if ($file.LastWriteTime -lt $cutoffDate) {
                try {
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                    Write-Verbose "削除: $($file.Name) (最終更新: $($file.LastWriteTime))"
                    $deletedCount++
                } catch {
                    Write-Warning "ファイルの削除に失敗しました: $($file.Name) - $($_.Exception.Message)"
                }
            }
        }
        
        # 世代数ベースの削除（ファイラーごとに管理）
        # ファイル名パターン: {filer}-{timestamp}.{ext}
        $filesByFiler = $reportFiles | Where-Object { $_.LastWriteTime -ge $cutoffDate } | 
            Group-Object { ($_.BaseName -split '-')[0] }
        
        foreach ($filerGroup in $filesByFiler) {
            $sortedFiles = $filerGroup.Group | Sort-Object LastWriteTime -Descending
            
            if ($sortedFiles.Count -gt $maxGenerations) {
                $filesToDelete = $sortedFiles | Select-Object -Skip $maxGenerations
                
                foreach ($file in $filesToDelete) {
                    try {
                        Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                        Write-Verbose "削除（世代数超過）: $($file.Name)"
                        $deletedCount++
                    } catch {
                        Write-Warning "ファイルの削除に失敗しました: $($file.Name) - $($_.Exception.Message)"
                    }
                }
            }
        }
        
        # CSVディレクトリのクリーンアップ
        $csvDirs = Get-ChildItem -Path $OutputDirectory -Filter "csv*" -Directory -ErrorAction SilentlyContinue
        
        foreach ($dir in $csvDirs) {
            if ($dir.LastWriteTime -lt $cutoffDate) {
                try {
                    Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction Stop
                    Write-Verbose "削除（ディレクトリ）: $($dir.Name) (最終更新: $($dir.LastWriteTime))"
                    $deletedCount++
                } catch {
                    Write-Warning "ディレクトリの削除に失敗しました: $($dir.Name) - $($_.Exception.Message)"
                }
            }
        }
        
        if ($deletedCount -gt 0) {
            Write-Host "🗑️  古いレポートファイルを削除しました: $deletedCount 件" -ForegroundColor Gray
        } else {
            Write-Verbose "削除対象のファイルはありませんでした"
        }
        
    } catch {
        Write-Warning "レポートクリーンアップ中にエラーが発生しました: $($_.Exception.Message)"
    }
}

function Remove-OldLogs {
    <#
    .SYNOPSIS
        古いログファイルを削除
    
    .PARAMETER LogDirectory
        ログディレクトリ
    
    .PARAMETER Config
        設定オブジェクト
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogDirectory,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    try {
        if (-not $Config.logging -or -not $Config.logging.enabled) {
            Write-Verbose "ログ機能は無効です"
            return
        }
        
        if (-not $Config.logging.retentionDays) {
            Write-Verbose "ログ保持期間が設定されていません"
            return
        }
        
        Write-Verbose "古いログファイルをクリーンアップしています..."
        
        $retentionDays = $Config.logging.retentionDays
        $cutoffDate = (Get-Date).AddDays(-$retentionDays)
        
        # ログディレクトリが存在しない場合は何もしない
        if (-not (Test-Path $LogDirectory)) {
            Write-Verbose "ログディレクトリが存在しません: $LogDirectory"
            return
        }
        
        # ログファイルを取得（.logファイル）
        $logFiles = Get-ChildItem -Path $LogDirectory -Filter "*.log" -File -ErrorAction SilentlyContinue
        
        $deletedCount = 0
        
        # 保持期間を過ぎたログファイルを削除
        foreach ($file in $logFiles) {
            # 現在実行中のログファイルはスキップ
            if ($file.FullName -eq $script:LogFile) {
                continue
            }
            
            if ($file.LastWriteTime -lt $cutoffDate) {
                try {
                    Remove-Item -Path $file.FullName -Force -ErrorAction Stop
                    Write-Verbose "削除: $($file.Name) (最終更新: $($file.LastWriteTime))"
                    $deletedCount++
                } catch {
                    Write-Warning "ログファイルの削除に失敗しました: $($file.Name) - $($_.Exception.Message)"
                }
            }
        }
        
        if ($deletedCount -gt 0) {
            Write-Host "🗑️  古いログファイルを削除しました: $deletedCount 件" -ForegroundColor Gray
        } else {
            Write-Verbose "削除対象のログファイルはありませんでした"
        }
        
    } catch {
        Write-Warning "ログクリーンアップ中にエラーが発生しました: $($_.Exception.Message)"
    }
}

# モジュールメンバーのエクスポート
Export-ModuleMember -Function @(
    'Export-ReportToJSON',
    'Export-ReportToHTML',
    'Export-ReportToCSV',
    'Export-Report',
    'Remove-OldReports',
    'Remove-OldLogs'
)
