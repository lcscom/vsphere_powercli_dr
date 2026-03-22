# ========================================================================
# 1. 환경 설정 및 접속
# ========================================================================
$vCenterServer = "vc-wld02-a.site-a.vcf.lab"
$ReportPath    = "$env:USERPROFILE\Desktop\VCF_Infrastructure_DeepReport.html"

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
Write-Host "vCenter ($vCenterServer) 연결 및 데이터 수집 시작..." -ForegroundColor Cyan
Connect-VIServer -Server $vCenterServer -User "administrator@vsphere.local" -Password "VMware123!VMware123!" | Out-Null

# HTML CSS 스타일 정의 (에러 발생 시 행 전체 강조)
$Header = @"
<style>
    body { font-family: 'Segoe UI', sans-serif; margin: 20px; background-color: #f4f6f9; }
    h1 { color: #004b87; text-align: center; }
    h2 { background-color: #0078d4; color: white; padding: 10px; border-radius: 4px; }
    table { border-collapse: collapse; width: 100%; margin-bottom: 25px; background: white; }
    th { background-color: #e9ecef; color: #333; padding: 12px; border: 1px solid #dee2e6; text-align: left; }
    td { padding: 10px; border: 1px solid #dee2e6; font-size: 13px; }
    .PowerOn { color: #28a745; font-weight: bold; }
    .PowerOff { color: #dc3545; font-weight: bold; }
    .IssueRow { background-color: #fff3cd; color: #856404; font-weight: bold; }  /* Warning 배경 */
    .ErrorRow { background-color: #f8d7da; color: #721c24; font-weight: bold; }  /* Error 배경 */
</style>
"@

# ========================================================================
# 2. 데이터 수집 및 CLI 출력용 가공
# ========================================================================
Write-Host "`n[1/2] 가상 머신(VM) 정밀 진단 중..." -ForegroundColor Yellow

$VmHtmlRows = New-Object System.Collections.Generic.List[string]
$VmCliTable = New-Object System.Collections.Generic.List[PSObject]

$AllVMs = Get-VM | Sort-Object Name
foreach ($vm in $AllVMs) {
    # CLI 로직과 동일하게 에러/경고/실패 로그 추출 (최근 24시간)
    $events = Get-VIEvent -Entity $vm -MaxSamples 5 -Start (Get-Date).AddDays(-1) | 
              Where-Object { $_.FullFormattedMessage -match "error|fail|warning|alarm|red" }
    
    $recentIssue = if($events) { $events[0].FullFormattedMessage } else { "Clean" }
    $uptimeMin = if($vm.PowerState -eq "PoweredOn") { [Math]::Round($vm.ExtensionData.Summary.QuickStats.UptimeSeconds / 60, 0) } else { 0 }
    
    # [A] CLI 출력용 객체 생성
    $VmCliTable.Add([PSCustomObject]@{
        Name        = $vm.Name
        Power       = $vm.PowerState
        OS          = $vm.Guest.OSDescription
        IP          = $vm.Guest.IPAddress[0]
        Uptime_Min  = $uptimeMin
        RecentIssue = $recentIssue
    })

    # [B] HTML용 행(Row) 생성 및 클래스 부여
    $rowClass = ""
    if ($recentIssue -match "error|fail|red") { $rowClass = "ErrorRow" }
    elseif ($recentIssue -match "warning|alarm") { $rowClass = "IssueRow" }

    $VmHtmlRows.Add("<tr class='$rowClass'>
        <td>$($vm.Name)</td>
        <td class='$($vm.PowerState)'>$($vm.PowerState)</td>
        <td>$($vm.Guest.OSDescription)</td>
        <td>$($vm.Guest.IPAddress[0])</td>
        <td>$($vm.ExtensionData.Guest.ToolsStatus)</td>
        <td>$uptimeMin</td>
        <td>$recentIssue</td>
    </tr>")
}

# CLI 화면 출력 (1번 항목)
$VmCliTable | Format-Table -AutoSize

# ========================================================================
# 3. 인프라 전체 로그 수집 (2번 항목)
# ========================================================================
Write-Host "[2/2] 인프라 전체 에러 로그 추출 중..." -ForegroundColor Yellow
$GlobalEvents = Get-VIEvent -MaxSamples 50 -Start (Get-Date).AddHours(-2) | 
                Where-Object { $_.FullFormattedMessage -match "error|failed|alarm|red|warning" }

# CLI 화면 출력 (2번 항목)
$GlobalEvents | Select-Object CreatedTime, @{N="Target"; E={$_.Entity.Name}}, FullFormattedMessage | Format-Table -AutoSize

# ========================================================================
# 4. HTML 파일 조립 및 저장
# ========================================================================
$HtmlBody = @"
<h1>VCF 인프라 통합 점검 리포트 (CLI & Event 연동)</h1>
<p style='text-align:right;'>리포트 생성 시간: $(Get-Date)</p>

<h2>1. 가상 머신(VM) 및 OS 상세 상태 (이벤트 동기화)</h2>
<table>
    <tr>
        <th>Name</th><th>Power</th><th>Guest OS</th><th>IP</th><th>Tools</th><th>Uptime(Min)</th><th>Recent Log/Issue</th>
    </tr>
    $($VmHtmlRows -join "")
</table>

<h2>2. 최근 2시간 내 인프라 주요 경고/에러 로그</h2>
$($GlobalEvents | Select-Object CreatedTime, @{N="Target"; E={$_.Entity.Name}}, FullFormattedMessage | ConvertTo-Html -Fragment)
"@

ConvertTo-Html -Head $Header -Body $HtmlBody -Title "VCF Deep Check" | Out-File $ReportPath -Encoding utf8
Write-Host "`n리포트 생성이 완료되었습니다: $ReportPath" -ForegroundColor Green

# 파일 열기 및 연결 종료
Invoke-Item $ReportPath
Disconnect-VIServer -Confirm:$false | Out-Null
