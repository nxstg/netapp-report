<#
.SYNOPSIS
    NetApp ONTAPデータ収集モジュール

.DESCRIPTION
    NetApp ONTAPクラスターからノード、アグリゲート、ボリューム、LIF、ディスク情報を収集します
#>

function ConvertTo-ReadableSize {
    <#
    .SYNOPSIS
        バイト数を読みやすいサイズに変換
    
    .PARAMETER Bytes
        バイト数
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [double]$Bytes
    )
    
    if ($Bytes -eq 0) {
        return "0.00 Bytes"
    }
    
    $sizes = @("Bytes", "KB", "MB", "GB", "TB", "PB")
    $order = [Math]::Floor([Math]::Log($Bytes, 1024))
    
    if ($order -ge $sizes.Count) {
        $order = $sizes.Count - 1
    }
    
    $num = [Math]::Round($Bytes / [Math]::Pow(1024, $order), 2)
    return "$($num.ToString('0.00')) $($sizes[$order])"
}

function Get-ClusterInfo {
    <#
    .SYNOPSIS
        クラスター情報を収集
    
    .PARAMETER Connection
        NetApp接続オブジェクト
    
    .PARAMETER Config
        設定オブジェクト
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Connection,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    Write-Verbose "クラスター情報を収集しています..."
    
    try {
        $cluster = Get-NcCluster -Controller $Connection -ErrorAction Stop
        $version = Get-NcSystemVersion -Controller $Connection -ErrorAction Stop
        
        $clusterInfo = [PSCustomObject]@{
            ClusterName = $cluster.ClusterName
            ClusterUuid = $cluster.ClusterUuid
            Version = $version.ToString()
            ClusterSerialNumber = $cluster.ClusterSerialNumber
            Location = $cluster.Location
            Contact = $cluster.Contact
        }
        
        Write-Verbose "クラスター情報の収集が完了しました"
        return $clusterInfo
        
    } catch {
        Write-Error "クラスター情報の収集中にエラーが発生しました: $($_.Exception.Message)"
        throw
    }
}

function Get-NodeMetrics {
    <#
    .SYNOPSIS
        ノードのメトリクス情報を収集
    
    .PARAMETER Connection
        NetApp接続オブジェクト
    
    .PARAMETER Config
        設定オブジェクト
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Connection,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    Write-Verbose "ノードメトリクスを収集しています..."
    
    try {
        $nodes = Get-NcNode -Controller $Connection -ErrorAction Stop | Sort-Object Node
        $nodeMetrics = @()
        
        foreach ($node in $nodes) {
            try {
                # アップタイムを人間が読みやすい形式に変換
                $uptimeReadable = "N/A"
                if ($node.NodeUptime) {
                    try {
                        # NodeUptimeは秒数の場合が多い
                        $uptimeSeconds = [long]$node.NodeUptime
                        $days = [Math]::Floor($uptimeSeconds / 86400)
                        $hours = [Math]::Floor(($uptimeSeconds % 86400) / 3600)
                        $minutes = [Math]::Floor(($uptimeSeconds % 3600) / 60)
                        
                        if ($days -gt 0) {
                            $uptimeReadable = "${days}日 ${hours}時間 ${minutes}分"
                        } elseif ($hours -gt 0) {
                            $uptimeReadable = "${hours}時間 ${minutes}分"
                        } else {
                            $uptimeReadable = "${minutes}分"
                        }
                    } catch {
                        # 秒数でない場合はそのまま表示
                        $uptimeReadable = $node.NodeUptime.ToString()
                    }
                }
                
                $nodeMetrics += [PSCustomObject]@{
                    Node = $node.Node
                    IsEpsilonNode = $node.IsEpsilonNode
                    IsNodeHealthy = $node.IsNodeHealthy
                    NodeSerialNumber = $node.NodeSerialNumber
                    ProductVersion = $node.ProductVersion
                    NodeModel = $node.NodeModel
                    NodeSystemId = $node.NodeSystemId
                    NodeUptime = $node.NodeUptime
                    NodeUptimeReadable = $uptimeReadable
                    NvramBatteryStatus = $node.NvramBatteryStatus
                    IsNodeEligible = $node.IsNodeEligible
                }
            } catch {
                Write-Warning "ノード $($node.Node) のメトリクス収集に失敗しました: $($_.Exception.Message)"
            }
        }
        
        Write-Verbose "ノードメトリクスの収集が完了しました（$($nodeMetrics.Count) 件）"
        return $nodeMetrics
        
    } catch {
        Write-Error "ノードメトリクスの収集中にエラーが発生しました: $($_.Exception.Message)"
        throw
    }
}

function Get-AggregateMetrics {
    <#
    .SYNOPSIS
        アグリゲートのメトリクス情報を収集
    
    .PARAMETER Connection
        NetApp接続オブジェクト
    
    .PARAMETER Config
        設定オブジェクト
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Connection,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    Write-Verbose "アグリゲートメトリクスを収集しています..."
    
    try {
        $aggregates = Get-NcAggr -Controller $Connection -ErrorAction Stop | Sort-Object Name
        $aggrMetrics = @()
        
        foreach ($aggr in $aggregates) {
            try {
                $totalSize = $aggr.TotalSize
                $used = $totalSize - $aggr.Available
                $usedPercent = if ($totalSize -gt 0) {
                    [math]::Round(($used / $totalSize) * 100, 2)
                } else { 0 }
                
                # ステータス判定
                $status = if ($usedPercent -ge $Config.report.thresholds.aggregate.critical) {
                    "Critical"
                } elseif ($usedPercent -ge $Config.report.thresholds.aggregate.warning) {
                    "Warning"
                } else {
                    "OK"
                }
                
                $aggrMetrics += [PSCustomObject]@{
                    Name = $aggr.Name
                    State = $aggr.State
                    TotalSize = $totalSize
                    TotalSizeReadable = ConvertTo-ReadableSize -Bytes $totalSize
                    Used = $used
                    UsedReadable = ConvertTo-ReadableSize -Bytes $used
                    Available = $aggr.Available
                    AvailableReadable = ConvertTo-ReadableSize -Bytes $aggr.Available
                    UsedPercent = $usedPercent
                    Status = $status
                    OwnerName = $aggr.AggrOwnershipAttributes.OwnerName
                    RaidType = $aggr.AggrRaidAttributes.RaidType
                    RaidStatus = $aggr.AggrRaidAttributes.RaidStatus
                    DiskCount = $aggr.AggrRaidAttributes.DiskCount
                }
            } catch {
                Write-Warning "アグリゲート $($aggr.Name) のメトリクス収集に失敗しました: $($_.Exception.Message)"
            }
        }
        
        Write-Verbose "アグリゲートメトリクスの収集が完了しました（$($aggrMetrics.Count) 件）"
        return $aggrMetrics
        
    } catch {
        Write-Error "アグリゲートメトリクスの収集中にエラーが発生しました: $($_.Exception.Message)"
        throw
    }
}

function Get-VolumeMetrics {
    <#
    .SYNOPSIS
        ボリュームのメトリクス情報を収集
    
    .PARAMETER Connection
        NetApp接続オブジェクト
    
    .PARAMETER Config
        設定オブジェクト
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Connection,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    Write-Verbose "ボリュームメトリクスを収集しています..."
    
    try {
        $volumes = Get-NcVol -Controller $Connection -ErrorAction Stop | Sort-Object Name
        $volumeMetrics = @()
        
        foreach ($vol in $volumes) {
            try {
                $totalSize = $vol.TotalSize
                $used = $totalSize - $vol.Available
                $usedPercent = if ($totalSize -gt 0) {
                    [math]::Round(($used / $totalSize) * 100, 2)
                } else { 0 }
                
                # ステータス判定
                $status = if ($usedPercent -ge $Config.report.thresholds.volume.critical) {
                    "Critical"
                } elseif ($usedPercent -ge $Config.report.thresholds.volume.warning) {
                    "Warning"
                } else {
                    "OK"
                }
                
                $volumeMetrics += [PSCustomObject]@{
                    Name = $vol.Name
                    State = $vol.State
                    TotalSize = $totalSize
                    TotalSizeReadable = ConvertTo-ReadableSize -Bytes $totalSize
                    Used = $used
                    UsedReadable = ConvertTo-ReadableSize -Bytes $used
                    Available = $vol.Available
                    AvailableReadable = ConvertTo-ReadableSize -Bytes $vol.Available
                    UsedPercent = $usedPercent
                    Status = $status
                    Aggregate = $vol.Aggregate
                    Vserver = $vol.Vserver
                    VolumeType = $vol.VolumeIdAttributes.Type
                    JunctionPath = $vol.VolumeIdAttributes.JunctionPath
                }
            } catch {
                Write-Warning "ボリューム $($vol.Name) のメトリクス収集に失敗しました: $($_.Exception.Message)"
            }
        }
        
        Write-Verbose "ボリュームメトリクスの収集が完了しました（$($volumeMetrics.Count) 件）"
        return $volumeMetrics
        
    } catch {
        Write-Error "ボリュームメトリクスの収集中にエラーが発生しました: $($_.Exception.Message)"
        throw
    }
}

function Get-NetworkInterfaceMetrics {
    <#
    .SYNOPSIS
        ネットワークインターフェース（LIF）のメトリクス情報を収集
    
    .PARAMETER Connection
        NetApp接続オブジェクト
    
    .PARAMETER Config
        設定オブジェクト
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Connection,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    Write-Verbose "ネットワークインターフェースメトリクスを収集しています..."
    
    try {
        $interfaces = Get-NcNetInterface -Controller $Connection -ErrorAction Stop | Sort-Object InterfaceName
        $lifMetrics = @()
        
        foreach ($lif in $interfaces) {
            try {
                # LIFタイプの判定
                $lifType = if ($lif.Role -eq "data") {
                    "Data"
                } elseif ($lif.Role -eq "cluster_mgmt") {
                    "Cluster Management"
                } elseif ($lif.Role -eq "node_mgmt") {
                    "Node Management"
                } elseif ($lif.Role -eq "intercluster") {
                    "Intercluster"
                } else {
                    "Other"
                }
                
                $lifMetrics += [PSCustomObject]@{
                    InterfaceName = $lif.InterfaceName
                    OpStatus = $lif.OpStatus
                    IsHome = $lif.IsHome
                    HomeNode = $lif.HomeNode
                    HomePort = $lif.HomePort
                    CurrentNode = $lif.CurrentNode
                    CurrentPort = $lif.CurrentPort
                    Address = $lif.Address
                    Netmask = $lif.Netmask
                    NetmaskLength = $lif.NetmaskLength
                    AddressFamily = "$($lif.Address)/$($lif.NetmaskLength)"
                    Vserver = $lif.Vserver
                    Role = $lif.Role
                    LIFType = $lifType
                    DataProtocols = if ($lif.DataProtocols) { $lif.DataProtocols -join ', ' } else { 'N/A' }
                }
            } catch {
                Write-Warning "LIF $($lif.InterfaceName) のメトリクス収集に失敗しました: $($_.Exception.Message)"
            }
        }
        
        Write-Verbose "ネットワークインターフェースメトリクスの収集が完了しました（$($lifMetrics.Count) 件）"
        return $lifMetrics
        
    } catch {
        Write-Error "ネットワークインターフェースメトリクスの収集中にエラーが発生しました: $($_.Exception.Message)"
        throw
    }
}

function Get-PortMetrics {
    <#
    .SYNOPSIS
        ネットワークポート情報を収集
    
    .PARAMETER Connection
        NetApp接続オブジェクト
    
    .PARAMETER Config
        設定オブジェクト
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Connection,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    Write-Verbose "ネットワークポート情報を収集しています..."
    
    try {
        $ports = Get-NcNetPort -Controller $Connection -ErrorAction Stop | Sort-Object Node, Port
        $portMetrics = @()
        
        foreach ($port in $ports) {
            try {
                # リンク速度を読みやすい形式に
                $linkSpeed = if ($port.LinkSpeed) {
                    if ($port.LinkSpeed -eq "auto") {
                        "Auto"
                    } elseif ($port.LinkSpeed -match "^\d+$") {
                        "$($port.LinkSpeed) Mbps"
                    } else {
                        $port.LinkSpeed
                    }
                } else {
                    "N/A"
                }
                
                # ポートタイプの判定
                $portType = if ($port.PortType) {
                    switch ($port.PortType) {
                        "physical" { "物理" }
                        "if_group" { "IFグループ" }
                        "vlan" { "VLAN" }
                        default { $port.PortType }
                    }
                } else {
                    "N/A"
                }
                
                $portMetrics += [PSCustomObject]@{
                    Node = $port.Node
                    Port = $port.Port
                    LinkStatus = $port.LinkStatus
                    OperationalStatus = $port.OperationalStatus
                    PortType = $portType
                    LinkSpeed = $linkSpeed
                    MTU = $port.Mtu
                    AutoNegotiate = $port.AutoNegotiate
                    BroadcastDomain = $port.BroadcastDomain
                    IPSpace = $port.Ipspace
                    HealthStatus = $port.HealthStatus
                    MacAddress = $port.MacAddress
                }
            } catch {
                Write-Warning "ポート $($port.Node):$($port.Port) の情報収集に失敗しました: $($_.Exception.Message)"
            }
        }
        
        Write-Verbose "ネットワークポート情報の収集が完了しました（$($portMetrics.Count) 件）"
        return $portMetrics
        
    } catch {
        Write-Error "ネットワークポート情報の収集中にエラーが発生しました: $($_.Exception.Message)"
        throw
    }
}

function Get-DiskMetrics {
    <#
    .SYNOPSIS
        ディスクのメトリクス情報を収集（ゼロイング未完了ディスクを含む）
    
    .PARAMETER Connection
        NetApp接続オブジェクト
    
    .PARAMETER Config
        設定オブジェクト
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Connection,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    Write-Verbose "ディスクメトリクスを収集しています..."
    
    try {
        # ゼロイング未完了のディスクを取得
        $nonZeroedDisks = Get-NcDisk -Controller $Connection -ErrorAction Stop | 
            Where-Object { 
                $_.DiskRaidInfo.DiskSpareInfo -and 
                $_.DiskRaidInfo.DiskSpareInfo.IsZeroed -eq $false 
            } | Sort-Object Name
        
        $diskMetrics = @()
        
        foreach ($disk in $nonZeroedDisks) {
            try {
                $diskMetrics += [PSCustomObject]@{
                    Name = $disk.Name
                    Shelf = $disk.DiskInventoryInfo.ShelfId
                    Bay = $disk.DiskInventoryInfo.Bay
                    ContainerType = $disk.DiskRaidInfo.ContainerType
                    IsZeroed = $disk.DiskRaidInfo.DiskSpareInfo.IsZeroed
                    HomeNodeName = $disk.DiskOwnershipInfo.HomeNodeName
                    OwnerNodeName = $disk.DiskOwnershipInfo.OwnerNodeName
                    DiskType = $disk.DiskRaidInfo.DiskType
                    PhysicalSize = $disk.DiskInventoryInfo.PhysicalSize
                    PhysicalSizeReadable = ConvertTo-ReadableSize -Bytes $disk.DiskInventoryInfo.PhysicalSize
                }
            } catch {
                Write-Warning "ディスク $($disk.Name) のメトリクス収集に失敗しました: $($_.Exception.Message)"
            }
        }
        
        Write-Verbose "ディスクメトリクスの収集が完了しました（ゼロイング未完了: $($diskMetrics.Count) 件）"
        return $diskMetrics
        
    } catch {
        Write-Error "ディスクメトリクスの収集中にエラーが発生しました: $($_.Exception.Message)"
        throw
    }
}

function Get-AllDiskMetrics {
    <#
    .SYNOPSIS
        すべてのディスクの詳細情報を収集
    
    .PARAMETER Connection
        NetApp接続オブジェクト
    
    .PARAMETER Config
        設定オブジェクト
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Connection,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    Write-Verbose "全ディスク情報を収集しています..."
    
    try {
        # ディスク名を自然な順序でソート（1.0.1, 1.0.2, ... 1.0.10, 1.0.11）
        $allDisks = Get-NcDisk -Controller $Connection -ErrorAction Stop | Sort-Object {
            # ディスク名を "." で分割して各部分を数値として扱う
            $parts = $_.Name -split '\.'
            # 最大4つの部分を想定（例: 1.0.10.5）
            $shelf = if ($parts.Length -gt 0 -and $parts[0] -match '^\d+$') { [int]$parts[0] } else { 0 }
            $bay = if ($parts.Length -gt 1 -and $parts[1] -match '^\d+$') { [int]$parts[1] } else { 0 }
            $disk = if ($parts.Length -gt 2 -and $parts[2] -match '^\d+$') { [int]$parts[2] } else { 0 }
            $extra = if ($parts.Length -gt 3 -and $parts[3] -match '^\d+$') { [int]$parts[3] } else { 0 }
            # 複合キーでソート：シェルフ → ベイ → ディスク → 追加部分
            "{0:D5}.{1:D5}.{2:D5}.{3:D5}" -f $shelf, $bay, $disk, $extra
        }
        $diskMetrics = @()
        
        foreach ($disk in $allDisks) {
            try {
                # コンテナタイプの判定
                $containerType = if ($disk.DiskRaidInfo.ContainerType) {
                    switch ($disk.DiskRaidInfo.ContainerType) {
                        "aggregate" { "アグリゲート" }
                        "spare" { "スペア" }
                        "broken" { "故障" }
                        "unassigned" { "未割り当て" }
                        "shared" { "共有" }
                        default { $disk.DiskRaidInfo.ContainerType }
                    }
                } else {
                    "N/A"
                }
                
                # ディスクタイプを読みやすく
                $diskType = if ($disk.DiskRaidInfo.DiskType) {
                    switch ($disk.DiskRaidInfo.DiskType) {
                        "SSD" { "SSD" }
                        "FCAL" { "FC" }
                        "ATA" { "SATA" }
                        "BSAS" { "SAS" }
                        "FSAS" { "SAS" }
                        default { $disk.DiskRaidInfo.DiskType }
                    }
                } else {
                    "N/A"
                }
                
                # RPMの取得
                $rpm = if ($disk.DiskInventoryInfo.Rpm) {
                    "$($disk.DiskInventoryInfo.Rpm) RPM"
                } else {
                    "N/A"
                }
                
                # 物理サイズの取得（複数のプロパティをチェック）
                $physicalSize = 0
                if ($disk.DiskInventoryInfo.PhysicalSize -and $disk.DiskInventoryInfo.PhysicalSize -gt 0) {
                    $physicalSize = $disk.DiskInventoryInfo.PhysicalSize
                } elseif ($disk.DiskInventoryInfo.Capacity -and $disk.DiskInventoryInfo.Capacity -gt 0) {
                    $physicalSize = $disk.DiskInventoryInfo.Capacity
                } elseif ($disk.DiskRaidInfo.PhysicalSize -and $disk.DiskRaidInfo.PhysicalSize -gt 0) {
                    $physicalSize = $disk.DiskRaidInfo.PhysicalSize
                } elseif ($disk.DiskRaidInfo.UsableSize -and $disk.DiskRaidInfo.UsableSize -gt 0) {
                    $physicalSize = $disk.DiskRaidInfo.UsableSize
                }
                
                $diskMetrics += [PSCustomObject]@{
                    Name = $disk.Name
                    Shelf = $disk.DiskInventoryInfo.ShelfId
                    Bay = $disk.DiskInventoryInfo.Bay
                    Vendor = $disk.DiskInventoryInfo.Vendor
                    Model = $disk.DiskInventoryInfo.Model
                    SerialNumber = $disk.DiskInventoryInfo.SerialNumber
                    FirmwareRevision = $disk.DiskInventoryInfo.FirmwareRevision
                    DiskType = $diskType
                    RPM = $rpm
                    PhysicalSize = $physicalSize
                    PhysicalSizeReadable = if ($physicalSize -gt 0) { ConvertTo-ReadableSize -Bytes $physicalSize } else { "N/A" }
                    ContainerType = $containerType
                    ContainerName = $disk.DiskRaidInfo.ContainerName
                    HomeNodeName = $disk.DiskOwnershipInfo.HomeNodeName
                    OwnerNodeName = $disk.DiskOwnershipInfo.OwnerNodeName
                    Pool = $disk.DiskOwnershipInfo.Pool
                    EffectiveDiskType = $disk.DiskRaidInfo.EffectiveDiskType
                }
            } catch {
                Write-Warning "ディスク $($disk.Name) の情報収集に失敗しました: $($_.Exception.Message)"
            }
        }
        
        Write-Verbose "全ディスク情報の収集が完了しました（$($diskMetrics.Count) 件）"
        return $diskMetrics
        
    } catch {
        Write-Error "全ディスク情報の収集中にエラーが発生しました: $($_.Exception.Message)"
        throw
    }
}

function Get-ErrorEvents {
    <#
    .SYNOPSIS
        EMSイベント（エラー・警告）を収集
    
    .PARAMETER Connection
        NetApp接続オブジェクト
    
    .PARAMETER Config
        設定オブジェクト
    
    .PARAMETER HoursBack
        過去何時間分のイベントを取得するか（デフォルト: 24時間）
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Connection,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $false)]
        [int]$HoursBack = 24
    )
    
    Write-Verbose "EMSエラーイベントを収集しています（過去${HoursBack}時間）..."
    
    try {
        # EMSメッセージを取得（エラーと警告のみ）
        # 過去N時間のカットオフ時刻を計算
        $cutoffTime = (Get-Date).AddHours(-$HoursBack)
        
        $emsMessages = Get-NcEmsMessage -Controller $Connection -ErrorAction SilentlyContinue | 
            Where-Object { 
                $_.Severity -in @('error', 'alert', 'emergency', 'critical')
            } | 
            Sort-Object Time -Descending
        
        $errorEvents = @()
        $eventCount = 0
        
        foreach ($msg in $emsMessages) {
            try {
                # Timeを適切な形式に変換
                $eventTime = $null
                if ($msg.Time -is [DateTime]) {
                    $eventTime = $msg.Time
                } elseif ($msg.Time -is [int] -or $msg.Time -is [long]) {
                    # Unix timestampから変換
                    $eventTime = [DateTimeOffset]::FromUnixTimeSeconds($msg.Time).LocalDateTime
                } else {
                    # その他の形式の場合は文字列として処理
                    $eventTime = $msg.Time.ToString()
                }
                
                # 時間フィルタリング（DateTimeに変換できた場合のみ）
                if ($eventTime -is [DateTime] -and $eventTime -lt $cutoffTime) {
                    # カットオフ時刻より古いイベントは無視
                    continue
                }
                
                $errorEvents += [PSCustomObject]@{
                    Time = $eventTime
                    Severity = $msg.Severity
                    Source = $msg.Source
                    Event = $msg.Event
                    MessageName = $msg.MessageName
                    Node = $msg.Node
                    Message = $msg.Message
                }
                
                $eventCount++
                # 最大100件まで
                if ($eventCount -ge 100) {
                    break
                }
            } catch {
                Write-Verbose "EMSメッセージ処理をスキップしました: $($_.Exception.Message)"
            }
        }
        
        Write-Verbose "EMSエラーイベントの収集が完了しました（$($errorEvents.Count) 件）"
        return $errorEvents
        
    } catch {
        Write-Warning "EMSエラーイベントの収集中にエラーが発生しました: $($_.Exception.Message)"
        return @()
    }
}

function Get-HealthAlerts {
    <#
    .SYNOPSIS
        システムヘルスアラートを収集
    
    .PARAMETER Connection
        NetApp接続オブジェクト
    
    .PARAMETER Config
        設定オブジェクト
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Connection,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config
    )
    
    Write-Verbose "システムヘルスアラートを収集しています..."
    
    try {
        # Get-NcSystemHealthAlertコマンドレットが利用可能かチェック
        if (-not (Get-Command -Name Get-NcSystemHealthAlert -ErrorAction SilentlyContinue)) {
            Write-Verbose "Get-NcSystemHealthAlertコマンドレットは利用できません（ONTAPバージョンによっては未サポート）"
            return @()
        }
        
        # 未確認のヘルスアラートを取得
        $alerts = Get-NcSystemHealthAlert -Controller $Connection -ErrorAction Stop |
            Where-Object { $_.AcknowledgeState -ne 'acknowledged' } |
            Sort-Object AlertTime -Descending
        
        $healthAlerts = @()
        
        foreach ($alert in $alerts) {
            try {
                $healthAlerts += [PSCustomObject]@{
                    AlertId = $alert.AlertId
                    AlertTime = $alert.AlertTime
                    Severity = $alert.PerceivedSeverity
                    Resource = $alert.Resource
                    Subsystem = $alert.Subsystem
                    Indication = $alert.Indication
                    ProbableCause = $alert.ProbableCause
                    CorrectiveAction = $alert.CorrectiveAction
                    AcknowledgeState = $alert.AcknowledgeState
                    Node = $alert.Node
                }
            } catch {
                Write-Verbose "ヘルスアラート処理をスキップしました: $($_.Exception.Message)"
            }
        }
        
        Write-Verbose "システムヘルスアラートの収集が完了しました（$($healthAlerts.Count) 件）"
        return $healthAlerts
        
    } catch {
        Write-Verbose "システムヘルスアラートの収集中にエラーが発生しました: $($_.Exception.Message)"
        return @()
    }
}

function Invoke-DataCollection {
    <#
    .SYNOPSIS
        すべてのメトリクスを収集
    
    .PARAMETER ConnectionInfo
        NetApp接続情報
    
    .PARAMETER Config
        設定オブジェクト
    
    .PARAMETER Sections
        収集するセクション（オプション、設定ファイルより優先）
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ConnectionInfo,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$Config,
        
        [Parameter(Mandatory = $false)]
        [string[]]$Sections
    )
    
    $startTime = Get-Date
    Write-Verbose "データ収集を開始します..."
    
    # 収集するセクションの決定
    $sectionsToCollect = if ($Sections) {
        $Sections
    } else {
        $Config.report.sections
    }
    
    $collectedData = @{
        Metadata = @{
            CollectionTime = $startTime
            Filer = $ConnectionInfo.Filer
            ClusterName = $ConnectionInfo.ClusterName
            Version = $ConnectionInfo.Version
            ModuleVersion = $ConnectionInfo.ModuleVersion
            Sections = $sectionsToCollect
        }
    }
    
    try {
        # クラスター情報は常に収集
        $collectedData.Cluster = Get-ClusterInfo -Connection $ConnectionInfo.Connection -Config $Config
        
        foreach ($section in $sectionsToCollect) {
            switch ($section.ToLower()) {
                'cluster' {
                    # すでに収集済み
                }
                'node' {
                    $collectedData.Nodes = Get-NodeMetrics -Connection $ConnectionInfo.Connection -Config $Config
                }
                'aggregate' {
                    $collectedData.Aggregates = Get-AggregateMetrics -Connection $ConnectionInfo.Connection -Config $Config
                }
                'volume' {
                    $collectedData.Volumes = Get-VolumeMetrics -Connection $ConnectionInfo.Connection -Config $Config
                }
                'lif' {
                    $collectedData.NetworkInterfaces = Get-NetworkInterfaceMetrics -Connection $ConnectionInfo.Connection -Config $Config
                }
                'port' {
                    $collectedData.Ports = Get-PortMetrics -Connection $ConnectionInfo.Connection -Config $Config
                }
                'disk' {
                    $collectedData.NonZeroedDisks = Get-DiskMetrics -Connection $ConnectionInfo.Connection -Config $Config
                }
                'alldisk' {
                    $collectedData.AllDisks = Get-AllDiskMetrics -Connection $ConnectionInfo.Connection -Config $Config
                }
            }
        }
        
        # エラー情報は常に収集
        $collectedData.ErrorEvents = Get-ErrorEvents -Connection $ConnectionInfo.Connection -Config $Config
        $collectedData.HealthAlerts = Get-HealthAlerts -Connection $ConnectionInfo.Connection -Config $Config
        
        $duration = ((Get-Date) - $startTime).TotalSeconds
        $collectedData.Metadata.CollectionDuration = [math]::Round($duration, 2)
        
        Write-Verbose "データ収集が完了しました（所要時間: $duration 秒）"
        return $collectedData
        
    } catch {
        Write-Error "データ収集中にエラーが発生しました: $($_.Exception.Message)"
        throw
    }
}

# モジュールメンバーのエクスポート
Export-ModuleMember -Function @(
    'ConvertTo-ReadableSize',
    'Get-ClusterInfo',
    'Get-NodeMetrics',
    'Get-AggregateMetrics',
    'Get-VolumeMetrics',
    'Get-NetworkInterfaceMetrics',
    'Get-PortMetrics',
    'Get-DiskMetrics',
    'Get-AllDiskMetrics',
    'Get-ErrorEvents',
    'Get-HealthAlerts',
    'Invoke-DataCollection'
)
