# ========================================================================
# 1. 환경 설정 및 vCenter 접속
# ========================================================================
$vCenterServer = "vc-wld02-a.site-a.vcf.lab"
$ReportPath    = "$env:USERPROFILE\Desktop\VCF_Total_Health_Report.html"

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
Write-Host "VCF 전 영역 통합 데이터 수집 중... (잠시만 기다려주세요)" -ForegroundColor Cyan
Connect-VIServer -Server $vCenterServer -User "administrator@vsphere.local" -Password "VMware123!VMware123!" | Out-Null

# [CSS 스타일] 가시성과 로그 가독성 강조
$Header = @"
<style>
    body { font-family: 'Segoe UI', sans-serif; margin: 25px; background-color: #f4f7f9; }
    h1 { color: #004b87; text-align: center; border-bottom: 3px solid #004b87; padding-bottom: 10px; }
    h2 { background-color: #0078d4; color: white; padding: 10px 15px; border-radius: 4px; margin-top: 30px; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 20px; background: white; box-shadow: 0 2px 8px rgba(0,0,0,0.1); }
    th { background-color: #e9ecef; color: #333; padding: 10px; border: 1px solid #dee2e6; text-align: left; }
    td { padding: 8px; border: 1px solid #dee2e6; font-size: 12px; }
    .PowerOn, .Connected { color: #28a745; font-weight: bold; }
    .PowerOff, .Disconnected { color: #dc3545; font-weight: bold; }
    .ErrorRow { background-color: #f8d7da !important; color: #721c24; font-weight: bold; }
    .WarnRow { background-color: #fff3cd !important; color: #856404; font-weight: bold; }
    .LogTable td { font-family: 'Consolas', monospace; font-size: 11px; white-space: pre-wrap; }
</style>
"@

# ========================================================================
# 2. 데이터 수집 섹션
# ========================================================================

# [A] 전수 로그 미리 수집 (최근 24시간 내 에러/경고)
$GlobalEvents = Get-VIEvent -MaxSamples 500 -Start (Get-Date).AddHours(-24) | 
                Where-Object { $_.FullFormattedMessage -match "error|failed|alarm|red|warning|alert" }

# (1) 호스트 상태 (Compute)
$HostRows = foreach ($h in Get-VMHost | Sort-Object Name) {
    $hClass = if ($h.ConnectionState -ne "Connected") { "ErrorRow" } else { "" }
    "<tr class='$hClass'><td>$($h.Name)</td><td class='$($h.ConnectionState)'>$($h.ConnectionState)</td><td>$([Math]::Round($h.CpuUsageMhz / $h.CpuTotalMhz * 100, 1))%</td><td>$([Math]::Round($h.MemoryUsageGB / $h.MemoryTotalGB * 100, 1))%</td><td>$($h.Version)</td></tr>"
}

# (2) 데이터스토어 점검 (Storage)
$DsRows = foreach ($ds in Get-Datastore | Where-Object {$_.Type -match "NFS|VMFS|vSAN"} | Sort-Object Name) {
    $freePct = [Math]::Round($ds.FreeSpaceGB / $ds.CapacityGB * 100, 1)
    $dsClass = if ($freePct -lt 10) { "ErrorRow" } elseif ($freePct -lt 20) { "WarnRow" } else { "" }
    "<tr class='$dsClass'><td>$($ds.Name)</td><td>$($ds.Type)</td><td>$([Math]::Round($ds.CapacityGB, 0)) GB</td><td>$([Math]::Round($ds.FreeSpaceGB, 0)) GB</td><td>$freePct %</td></tr>"
}

# (3) 가상 분산 스위치 (Network)
$NetRows = foreach ($vds in Get-VDSwitch | Sort-Object Name) {
    $uplinks = ($vds | Get-VDUplinkTeamingPolicy).ActiveUplinkPort -join ", "
    "<tr><td>$($vds.Name)</td><td>$($vds.NumPorts)</td><td>$($vds.Version)</td><td>$uplinks</td></tr>"
}

# (4) VM 상세 자원 및 최적화 (Snap/ISO/Log)
$VmRows = foreach ($vm in Get-VM | Sort-Object Name) {
    $snaps = Get-Snapshot -VM $vm -ErrorAction SilentlyContinue
    $snapCount = if($snaps) { ($snaps | Measure-Object).Count } else { 0 }
    $cd = Get-CDDrive -VM $vm
    $isoPath = if($cd.IsoPath) { $cd.IsoPath } else { "None" }
    
    # 해당 VM 로그 매핑
    $vmEvent = $GlobalEvents | Where-Object { $_.FullFormattedMessage -match $vm.Name } | Select-Object -First 1
    $eventMsg = "Clean"
    if ($vmEvent) { $eventMsg = $vmEvent.FullFormattedMessage }

    # 클래스 결정
    $vmClass = ""
    if ($vm.ExtensionData.Summary.Runtime.ConnectionState -match "orphaned|inaccessible") { $vmClass = "ErrorRow" }
    elseif ($snapCount -gt 0 -or $eventMsg -match "error|fail") { $vmClass = "ErrorRow" }
    elseif ($isoPath -ne "None" -or $eventMsg -match "warning") { $vmClass = "WarnRow" }

    $totalDisk = ($vm | Get-HardDisk | Measure-Object -Property CapacityGB -Sum).Sum
    "<tr class='$vmClass'><td>$($vm.Name)</td><td>$($vm.NumCpu)C/$([Math]::Round($vm.MemoryGB,1))G/$([Math]::Round($totalDisk,0))G</td><td class='$($vm.PowerState)'>$($vm.PowerState)</td><td>$($vm.Guest.IPAddress[0])</td><td>$snapCount</td><td>$isoPath</td><td>$eventMsg</td></tr>"
}

# (5) 인프라 주요 실시간 로그 (최근 2시간)
$RecentLogs = $GlobalEvents | Where-Object { $_.CreatedTime -gt (Get-Date).AddHours(-2) }
$LogRows = foreach ($ev in $RecentLogs) {
    $lClass = if ($ev.FullFormattedMessage -match "error|fail|red") { "ErrorRow" } else { "WarnRow" }
    $targetName = if ($ev.Entity.Name) { $ev.Entity.Name } else { "System" }
    "<tr class='$lClass'><td>$($ev.CreatedTime)</td><td>$targetName</td><td>$($ev.FullFormattedMessage)</td></tr>"
}

# ========================================================================
# 3. HTML 리포트 조립 및 출력
# ========================================================================
$HtmlBody = @"
<h1>VCF 인프라 통합 건강검진 리포트</h1>
<p style='text-align:right;'>리포트 생성 일시: $(Get-Date)</p>

<h2>1. 호스트 및 데이터스토어 상태</h2>
<table><tr><th>호스트명</th><th>상태</th><th>CPU</th><th>MEM</th><th>버전</th></tr>$($HostRows -join "")</table>
<table><tr><th>스토리지명</th><th>유형</th><th>전체</th><th>여유</th><th>여유(%)</th></tr>$($DsRows -join "")</table>

<h2>2. 가상 네트워크 (VDS)</h2>
<table><tr><th>VDS 이름</th><th>포트</th><th>버전</th><th>활성 업링크</th></tr>$($NetRows -join "")</table>

<h2>3. VM 자원 및 최적화 (Snap/ISO/Log)</h2>
<p style='font-size:11px;'>* <b>빨간색</b>: 스냅샷/에러/Orphaned | <b>노란색</b>: ISO마운트/경고</p>
<table><tr><th>VM 이름</th><th>자원(C/M/D)</th><th>전원</th><th>IP</th><th>Snap</th><th>ISO</th><th>최근 이슈</th></tr>$($VmRows -join "")</table>

<h2>4. 인프라 주요 실시간 로그 (최근 2시간)</h2>
<table class='LogTable'>
    <tr><th style='width:150px;'>발생 시간</th><th style='width:150px;'>대상</th><th>로그 메시지</th></tr>
    $(if($LogRows) { $LogRows -join "" } else { "<tr><td colspan='3'>최근 2시간 내 감지된 에러/경고 로그가 없습니다.</td></tr>" })
</table>
"@

ConvertTo-Html -Head $Header -Body $HtmlBody -Title "VCF Total Health Report" | Out-File $ReportPath -Encoding utf8
Write-Host "`n종합 리포트 생성 완료: $ReportPath" -ForegroundColor Green

Invoke-Item $ReportPath
Disconnect-VIServer -Confirm:$false | Out-Null
