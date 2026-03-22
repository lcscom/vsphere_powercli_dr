# ========================================================================
# 1. 환경 접속 및 보안 설정
# ========================================================================
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
$vCenterServer = "vc-wld02-a.site-a.vcf.lab"
Connect-VIServer -Server $vCenterServer -User "administrator@vsphere.local" -Password "VMware123!VMware123!" | Out-Null

Write-Host "`n[VCF Infrastructure Health Deep-Check]" -ForegroundColor Cyan -BackgroundColor DarkBlue

# ========================================================================
# 2. VM 상세 점검 (Guest OS 및 에러 상황 추출)
# ========================================================================
Write-Host "`n[1/2] 가상 머신(VM) 상세 상태 및 Guest OS 점검" -ForegroundColor Yellow
$VmReport = Get-VM | ForEach-Object {
    $vm = $_
    # 해당 VM에 발생한 최근 24시간 내 에러/경고 이벤트 수집
    $events = Get-VIEvent -Entity $vm -MaxSamples 5 -Start (Get-Date).AddDays(-1) | 
              Where-Object { $_.FullFormattedMessage -match "error|fail|warning" }
    
    [PSCustomObject]@{
        Name        = $vm.Name
        PowerState  = $vm.PowerState
        # Guest OS 상세 버전 및 호스트명
        OS_Full     = $vm.Guest.OSDescription
        IP          = $vm.Guest.IPAddress[0]
        ToolsStatus = $vm.ExtensionData.Guest.ToolsStatus
        # 하드웨어 버전 및 업타임(분 단위 계산)
        HW_Version  = $vm.Version
        Uptime_Min  = if($vm.PowerState -eq "PoweredOn") { [Math]::Round($vm.ExtensionData.Summary.QuickStats.UptimeSeconds / 60, 0) } else { 0 }
        # 최근 이슈 요약
        RecentIssue = if($events) { $events[0].FullFormattedMessage } else { "Clean" }
    }
}
$VmReport | Format-Table -AutoSize

# ========================================================================
# 3. 인프라 전체 로그 및 에러 이벤트 (최근 2시간)
# ========================================================================
Write-Host "[2/2] 인프라 전체 주요 로그 및 에러 (최근 2시간)" -ForegroundColor Yellow
Get-VIEvent -MaxSamples 100 -Start (Get-Date).AddHours(-2) | 
    Where-Object { $_.FullFormattedMessage -match "error|failed|alarm|red" } | 
    Select-Object CreatedTime, @{N="Target"; E={$_.Entity.Name}}, FullFormattedMessage | 
    Format-Table -AutoSize

Disconnect-VIServer -Confirm:$false | Out-Null
