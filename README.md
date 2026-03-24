**[실습환경 VPN 접속]**
https://cmail.kakao.com/v2/mails/0000000000008w4/attachments/MjoxLjI6MTI1NDoyOTUyOTYwOmFwcGxpY2F0aW9uL3ppcDpiYXNlNjQ6WG5JbXB3MWZjQ2U3cDNEMU5SSWRoQQ/download/FortiClientMiniSetup-Windows-x64-Enterprise-7.4.3%20(1).zip

**[vCenter 실습 환경 접속]**

**1. PowerCLI 실습용 (vSphere 8 Workload Domain)**
**vCenter Server : vc-wld02-a.site-a.vcf.lab**

**계정 정보 : vcf01@vsphere.local (또는 지정된 실습 계정)**

**2. VMware Live Site Recovery (SRM) 실습용**

**[VCF9 Management Domain]**

**vCenter Server : vc-mgmt-a.site-a.vcf.lab**

**SRM Appliance : vlr-mgmt-a.site-a.vcf.lab (계정: admin / 패스워드: VMware123!VMware123!)**

**[VCF9 Workload Domain]****

**vCenter Server : vc-wld01-a.site-a.vcf.lab**

**SRM Appliance : vlr-wld01-a.site-a.vcf.lab (계정: admin / 패스워드: VMware123!VMware123!)**



---
```markdown
# VCF PowerCLI 실습 가이드 (Hands-on Lab)

본 저장소는 VMware vSphere 및 VCF(VMware Cloud Foundation) 환경을 자동화하고 점검하기 위한 PowerCLI 실습 스크립트를 포함하고 있습니다. 각 스크립트는 인프라 운영, 상태 점검, 리소스 최적화, 보안 점검, 재해 복구(DR) 자동화 등의 목적을 가지고 있습니다.

## 📋 목차
1. [01. BASIC](#01-basic)
2. [02. HC (Health Check)](#02-hc)
3. [02-1. HC-HTML 리포트](#02-1-hc-htmlps1)
4. [03. Invoke-VM](#03-invoke-vmps1)
5. [04. Snapshot & Orphaned VM](#04-snapshot_orphanedvmps1)
6. [05. vMotion 자동화](#05-vmotion-targethostps1)
7. [06. Cluster 설정 점검](#06-check_clusterps1)
8. [07. 성능 데이터 수집](#07-perf_dataps1)
9. [08. 보안 및 SSH 점검](#08-security_sshps1)
10. [09. Inventory Tree](#09-inventory_treeps1)
11. [10. DR 자동화 패널](#10-dr_automationps1)

---

## 01. BASIC
기본적인 vCenter 연결, VM 조회, 필터링 및 연결 해제를 수행하는 기본 스크립트입니다.

```powershell
# [보안 설정] 신뢰되지 않는 SSL 인증서 경고 무시
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

# [변수 설정] 환경에 맞게 수정하세요
$vCenterServer = "vc-wld02-a.site-a.vcf.lab"
$vCenterUser   = "administrator@vsphere.local"
$vCenterPass   = "VMware123!VMware123!"

# [연결 실행]
Connect-VIServer -Server $vCenterServer -User $vCenterUser -Password $vCenterPass

# 모든 vCenter 서버 연결 해제
Disconnect-VIServer -Confirm:$false

# 모든 VM의 이름, 전원 상태, CPU, 메모리 정보 출력
Get-VM | Select-Object Name, PowerState, NumCpu, MemoryGB

# 이름에 "DEF"가 포함된 VM 찾기
Get-VM -Name "DEF*"

# 전원이 켜진 VM만 리스트업
Get-VM | Where-Object { $_.PowerState -eq "PoweredOn" }

# 이름, 호스트명, IP 주소(VMware Tools 필요) 조회
Get-VM | Select-Object Name, VMHost, @{N="IPAddress"; E={$_.Guest.IPAddress[0]}}
```

---

## 02. HC
가상 머신(VM)의 상세 상태, Guest OS 버전, 최근 에러 로그 등을 콘솔 화면에서 확인하는 인프라 헬스체크 스크립트입니다.

```powershell
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
```

---

## 02-1. HC-HTML.ps1
인프라 전체(Compute, Storage, Network, VM)의 건강 상태를 가독성 높은 HTML 리포트로 추출합니다.

```powershell
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
```

---

## 03. Invoke-VM.ps1
VMware Tools를 활용하여 네트워크 접근 없이(또는 원격에서) Guest OS 내부에 직접 명령(Bash 등)을 실행하는 스크립트입니다.

```powershell
# ========================================================================
# 1. 접속 및 대상 정의
# ========================================================================
$vCenterServer = "vc-wld02-a.site-a.vcf.lab"
$GuestUser     = "ocuser"
$GuestPass     = "VMware123!" 
$TargetPattern = "DEF-*"  # DEF-로 시작하는 VM 패턴

Connect-VIServer -Server $vCenterServer -User "administrator@vsphere.local" -Password "VMware123!VMware123!" | Out-Null

# ========================================================================
# 2. 대상 VM 조회 및 명령 실행
# ========================================================================
# 켜져 있는(PoweredOn) VM 중 이름이 DEF-로 시작하는 것들만 필터링
$VMs = Get-VM -Name $TargetPattern | Where-Object { $_.PowerState -eq "PoweredOn" }

Write-Host "`n[대상 VM 수: $($VMs.Count)대]" -ForegroundColor Cyan
Write-Host "------------------------------------------------------------"

foreach ($vm in $VMs) {
    Write-Host "[$($vm.Name)] 명령 실행 중..." -ForegroundColor Yellow
    
    try {
        # 실행할 특정 명령어 (예: df -h /)
        $Script = "df -h /"
        
        # ScriptType은 리눅스일 경우 Bash, 윈도우일 경우 Powershell 또는 Bat 사용
        $Result = Invoke-VMScript -VM $vm -ScriptText $Script `
                  -GuestUser $GuestUser -GuestPassword $GuestPass `
                  -ScriptType Bash -ErrorAction Stop
        
        # 결과값 출력
        Write-Host ">> 결과:" -ForegroundColor Green
        Write-Host $Result.ScriptOutput.Trim()
    }
    catch {
        Write-Host ">> 에러 발생: $($_.Exception.Message)" -ForegroundColor Red
    }
    Write-Host "------------------------------------------------------------"
}

# 세션 종료
Disconnect-VIServer -Confirm:$false | Out-Null
```

---

## 04. Snapshot_OrphanedVM.PS1
디스크 공간 낭비 및 성능 저하의 주범인 '오래된 스냅샷'과 비정상 상태인 'Orphaned VM'을 찾아내는 리소스 최적화 스크립트입니다.

```powershell
# ========================================================================
# 1. 환경 설정 및 vCenter 접속
# ========================================================================
$vCenterServer = "vc-wld02-a.site-a.vcf.lab"
$DaysOld       = 0  # 7일 이상 된 스냅샷을 '오래된 것'으로 간주

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
Write-Host "VCF 리소스 최적화 점검 시작..." -ForegroundColor Cyan
Connect-VIServer -Server $vCenterServer -User "administrator@vsphere.local" -Password "VMware123!VMware123!" | Out-Null

# ========================================================================
# 2. 오래된 스냅샷(Old Snapshots) 확인 및 정리
# ========================================================================
Write-Host "`n[1] $DaysOld`일 이상 된 스냅샷 점검 중..." -ForegroundColor Yellow
$OldSnapshots = Get-VM | Get-Snapshot | Where-Object { $_.Created -lt (Get-Date).AddDays(-$DaysOld) }

if ($OldSnapshots) {
    $OldSnapshots | Select-Object VM, Name, Created, SizeGB | Format-Table -AutoSize
    
    # 실무 팁: 자동 삭제를 원하면 아래 주석을 해제하세요. (주의 필요)
    # Write-Host "오래된 스냅샷 삭제 중..." -ForegroundColor Red
    # $OldSnapshots | Remove-Snapshot -Confirm:$false
} else {
    Write-Host "-> 정리할 오래된 스냅샷이 없습니다." -ForegroundColor Green
}

# ========================================================================
# 3. Orphaned VM (인벤토리 유령 VM) 확인
# ========================================================================
# vCenter 인벤토리에는 등록되어 있지만, 실제 파일 연결이 끊기거나 비정상적인 상태
Write-Host "`n[2] Orphaned / Inaccessible VM 점검 중..." -ForegroundColor Yellow
$OrphanedVMs = Get-VM | Where-Object { $_.ExtensionData.Summary.Runtime.ConnectionState -eq "orphaned" -or $_.ExtensionData.Summary.Runtime.ConnectionState -eq "inaccessible" }

if ($OrphanedVMs) {
    $OrphanedVMs | Select-Object Name, PowerState, @{N="Status";E={$_.ExtensionData.Summary.Runtime.ConnectionState}} | Format-Table -AutoSize
    
    # 정리 로직: 인벤토리에서 제거 (데이터 삭제 아님, 등록 해제)
    # Write-Host "Orphaned VM 인벤토리 제거 중..." -ForegroundColor Red
    # $OrphanedVMs | Remove-VM -Confirm:$false
} else {
    Write-Host "-> Orphaned 상태의 VM이 없습니다." -ForegroundColor Green
}

# ========================================================================
# 4. 데이터스토어에 남겨진 좀비 폴더(Zombies) 확인 (고급)
# ========================================================================
# VM은 삭제되었으나 데이터스토어에 폴더만 남은 경우를 찾는 로직은 복잡하므로 
# 우선적으로 위 2가지(Snap/Orphan) 정리가 선행되어야 합니다.
Write-Host "`n[3] 점검 완료. 보고서를 확인하세요." -ForegroundColor Cyan

Disconnect-VIServer -Confirm:$false | Out-Null
```

---

## 05. vMotion-targethost.ps1
특정 패턴의 VM들을 지정한 타겟 ESXi 호스트로 일괄 vMotion(마이그레이션)하는 자동화 스크립트입니다. 호스트 점검 전 유지보수 모드 작업 등에 유용합니다.

```powershell
# ========================================================================
# 1. 환경 설정 및 접속
# ========================================================================
$vCenterServer = "vc-wld02-a.site-a.vcf.lab"
$TargetPattern = "DEF-*"  # 이동할 VM 패턴
$TargetHostName = "esx-22a.site-a.vcf.lab"  # 목적지 호스트명 (여기에 입력!)

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
Write-Host "특정 호스트($TargetHostName)로의 vMotion 자동화 시작..." -ForegroundColor Cyan
Connect-VIServer -Server $vCenterServer -User "administrator@vsphere.local" -Password "VMware123!VMware123!" | Out-Null

# ========================================================================
# 2. 대상 검증 (VM 및 목적지 호스트)
# ========================================================================
# 목적지 호스트 객체 가져오기
$DestHost = Get-VMHost -Name $TargetHostName -ErrorAction SilentlyContinue

if (-not $DestHost) {
    Write-Host "[에러] 목적지 호스트($TargetHostName)를 찾을 수 없습니다. 이름을 확인하세요." -ForegroundColor Red
    Disconnect-VIServer -Confirm:$false | Out-Null
    exit
}

# 이동할 VM들 조회 (켜져 있는 것만)
$VMsToMove = Get-VM -Name $TargetPattern | Where-Object { $_.PowerState -eq "PoweredOn" }

if ($VMsToMove.Count -eq 0) {
    Write-Host "이동할 대상 VM($TargetPattern)이 없습니다." -ForegroundColor Yellow
    Disconnect-VIServer -Confirm:$false | Out-Null
    exit
}

Write-Host "[대상 확인] 총 $($VMsToMove.Count)대의 VM을 $($DestHost.Name)으로 이동합니다." -ForegroundColor Green
Write-Host "------------------------------------------------------------"

# ========================================================================
# 3. 일괄 vMotion 실행
# ========================================================================
foreach ($vm in $VMsToMove) {
    # 현재 이미 목적지에 있는 경우는 제외
    if ($vm.VMHost.Name -eq $DestHost.Name) {
        Write-Host "-> [$($vm.Name)] 이미 목적지 호스트에 있습니다. 건너뜁니다." -ForegroundColor Gray
        continue
    }

    Write-Host "-> [$($vm.Name)] 이동 중: $($vm.VMHost.Name) ==> $($DestHost.Name)" -ForegroundColor Yellow
    
    try {
        # -RunAsync:$false 로 설정하여 한 대씩 안정적으로 이동 (순차 실행)
        $vm | Move-VM -Destination $DestHost -RunAsync:$false -Confirm:$false -ErrorAction Stop | Out-Null
        Write-Host "   [완료] 성공" -ForegroundColor Green
    }
    catch {
        Write-Host "   [실패] $($_.Exception.Message)" -ForegroundColor Red
    }
}

Write-Host "------------------------------------------------------------"
Write-Host "모든 마이그레이션 작업이 종료되었습니다." -ForegroundColor Cyan

# 세션 종료
Disconnect-VIServer -Confirm:$false | Out-Null
```

---

## 06. Check_Cluster.ps1
클러스터 내 호스트들의 빌드 일관성(Drift), DNS, NTP 서비스 설정 등을 검증하여 구성 오류를 찾아내는 스크립트입니다.

```powershell
# ========================================================================
# 1. 환경 설정 및 접속
# ========================================================================
$vCenterServer = "vc-wld02-a.site-a.vcf.lab"

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
Write-Host "VCF 핵심 인프라 설정 전수 수집 시작..." -ForegroundColor Cyan
Connect-VIServer -Server $vCenterServer -User "administrator@vsphere.local" -Password "VMware123!VMware123!" | Out-Null

# ========================================================================
# 2. vCenter 상세 정보 (버전 및 빌드)
# ========================================================================
Write-Host "`n[1] vCenter Server 상세 정보" -ForegroundColor Yellow
$vcInstance = Get-View ServiceInstance
$vcAbout = $vcInstance.RetrieveServiceContent().About

[PSCustomObject]@{
    VC_Name    = $vCenterServer
    Version    = $vcAbout.Version
    Build      = $vcAbout.Build  # vCenter 빌드
    FullName   = $vcAbout.FullName
} | Format-Table -AutoSize

# ========================================================================
# 3. vDS (가상 분산 스위치) 상세 정보
# ========================================================================
Write-Host "[2] 가상 분산 스위치(vDS) 구성 현황" -ForegroundColor Yellow
$vdsList = Get-VDSwitch
if ($vdsList) {
    $vdsList | ForEach-Object {
        $uplinks = ($_ | Get-VDUplinkTeamingPolicy).ActiveUplinkPort -join ", "
        [PSCustomObject]@{
            VDS_Name     = $_.Name
            Version      = $_.Version
            MTU          = $_.Mtu
            ActiveUplink = $uplinks
        }
    } | Format-Table -AutoSize
} else { Write-Host "-> 감지된 vDS가 없습니다." -ForegroundColor Gray }

# ========================================================================
# 4. 클러스터별 호스트 서비스 점검 (빌드 번호 포함)
# ========================================================================
$AllClusters = Get-Cluster
foreach ($Cluster in $AllClusters) {
    Write-Host "`n------------------------------------------------------------" -ForegroundColor White
    Write-Host " 클러스터: [$($Cluster.Name)]" -ForegroundColor Magenta
    
    $Hosts = $Cluster | Get-VMHost | Sort-Object Name
    $HostReport = foreach ($h in $Hosts) {
        # DNS 정보 추출 (네트워크 설정 하위)
        $dns = ($h.ExtensionData.Config.Network.DnsConfig.Address) -join ", "
        
        # NTP 서버 및 서비스 상태
        $ntp = (Get-VMHostNtpServer -VMHost $h) -join ", "
        $ntpService = Get-VMHostService -VMHost $h | Where-Object {$_.Key -eq "ntpd"}
        
        # [핵심] 빌드 번호 직접 추출
        $buildNum = $h.ExtensionData.Config.Product.Build

        [PSCustomObject]@{
            HostName   = $h.Name
            Version    = $h.Version
            Build      = $buildNum  # <--- 여기서 빌드 번호가 확실히 나옵니다
            DNS_Server = if($dns) { $dns } else { "N/A" }
            NTP_Server = if($ntp) { $ntp } else { "N/A" }
            NTP_Status = if($ntpService.Running) { "Running" } else { "Stopped" }
        }
    }
    $HostReport | Format-Table -AutoSize

    # 일관성 요약 (Drift)
    $UniqueBuilds = $HostReport.Build | Select-Object -Unique
    if ($UniqueBuilds.Count -gt 1) {
        Write-Host "!! 경고: 클러스터 내 호스트 빌드 버전이 일치하지 않습니다! ($($UniqueBuilds -join ', '))" -ForegroundColor Red
    }
}

# ========================================================================
# 5. 세션 종료
# ========================================================================
Write-Host "`n전수 점검이 완료되었습니다." -ForegroundColor Cyan
Disconnect-VIServer -Confirm:$false | Out-Null
```

---

## 07. Perf_Data.ps1
최근 1시간 동안의 CPU 및 Memory 평균 사용률 통계 데이터를 추출하는 스크립트입니다. vCenter 통계 레벨에 따라 데이터가 출력됩니다.

```powershell
# ========================================================================
# 1. 환경 설정 및 접속 (손상된 설정 파일 무시)
# ========================================================================
$vCenterServer = "vc-wld02-a.site-a.vcf.lab"

# PowerCLI 경고 메시지 끄기
$ErrorActionPreference = "SilentlyContinue" 
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

Connect-VIServer -Server $vCenterServer -User "administrator@vsphere.local" -Password "VMware123!VMware123!" | Out-Null
Write-Host "가용한 성능 데이터 수집 중... (최근 1시간)" -ForegroundColor Cyan

# ========================================================================
# 2. 메트릭 정의 (가장 안전한 기본 메트릭 위주로 구성)
# ========================================================================
# vCenter 기본 설정(Level 1)에서도 수집되는 메트릭만 선택
$Metrics = "cpu.usage.average", "mem.usage.average"

# ========================================================================
# 3. 데이터 추출 및 분석
# ========================================================================
$VMs = Get-VM * | Where-Object { $_.PowerState -eq "PoweredOn" }

$PerformanceReport = foreach ($vm in $VMs) {
    # 특정 VM의 통계 수집
    $Stats = Get-Stat -Entity $vm -Stat $Metrics -Start (Get-Date).AddHours(-1) -ErrorAction SilentlyContinue

    if ($Stats) {
        $avgCpu = ($Stats | Where-Object {$_.MetricId -eq "cpu.usage.average"} | Measure-Object Value -Average).Average
        $avgMem = ($Stats | Where-Object {$_.MetricId -eq "mem.usage.average"} | Measure-Object Value -Average).Average
        
        [PSCustomObject]@{
            VM_Name      = $vm.Name
            CPU_Usage_Avg = "$([Math]::Round($avgCpu, 1)) %"
            MEM_Usage_Avg = "$([Math]::Round($avgMem, 1)) %"
            Status        = if ($avgCpu -gt 80) { "High CPU" } else { "Normal" }
        }
    } else {
        [PSCustomObject]@{
            VM_Name      = $vm.Name
            CPU_Usage_Avg = "No Data"
            MEM_Usage_Avg = "No Data"
            Status        = "Check Statistics Level"
        }
    }
}

# ========================================================================
# 4. 결과 출력
# ========================================================================
$ErrorActionPreference = "Continue" # 에러 설정 복구
Write-Host "`n[성능 요약 리포트]" -ForegroundColor Yellow
$PerformanceReport | Format-Table -AutoSize

# 최근 서버 리스트 파일 경고 해결법 안내
Write-Host "`n[Tip] 'Recent servers file is corrupt' 경고가 계속 나오면 아래 경로의 파일을 삭제하세요:" -ForegroundColor Gray
Write-Host "C:\Users\Administrator\AppData\Roaming\VMware\PowerCLI\RecentServerList.xml" -ForegroundColor Gray

Disconnect-VIServer -Confirm:$false | Out-Null
```

---

## 08. Security_SSH.ps1
vCenter(VCSA), 개별 가상 머신(VM), 그리고 ESXi 호스트에 대해 불필요하게 SSH 서비스(포트 22)가 열려 있는지 스캔하고 리포트합니다.

```powershell
# ========================================================================
# 1. 환경 설정 및 접속 (비밀번호 수정 완료)
# ========================================================================
$vCenterServer = "vc-wld02-a.site-a.vcf.lab"
$AdminUser     = "administrator@vsphere.local"
$AdminPass     = "VMware123!VMware123!"  # 사용자 요청에 따라 수정 완료

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
Write-Host "vCenter 접속 중..." -ForegroundColor Cyan
$vcConn = Connect-VIServer -Server $vCenterServer -User $AdminUser -Password $AdminPass -ErrorAction Stop

Write-Host "`n" + "="*70 -ForegroundColor White
Write-Host " [vCenter & VM SSH 보안 통합 점검 리포트] " -ForegroundColor Red -BackgroundColor Black
Write-Host "="*70 -ForegroundColor White

# ========================================================================
# ITEM 1: vCenter Server Appliance (VCSA) SSH 상태
# ========================================================================
Write-Host "`n[TASK 1] vCenter Appliance (VCSA) SSH 상태" -ForegroundColor Yellow
try {
    # OptionManager를 통해 SSH 관련 고급 설정값 추출
    $optMgr = Get-View -Id 'OptionManager-VpxSettings'
    $sshSetting = $optMgr.SupportedOption | Where-Object { $_.Key -match "ssh" }
    
    # 더 직관적인 방법으로 vCenter 22번 포트 자체를 스캔 (실제 활성화 여부 확인)
    $vcSshTest = Test-NetConnection -ComputerName $vCenterServer -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue

    [PSCustomObject]@{
        vCenter_FQDN = $vCenterServer
        SSH_Status   = if($vcSshTest){ "Enabled (⚠)" } else { "Disabled (Safe)" }
        Check_Method = "Network Port Scan (Port 22)"
    } | Format-Table -AutoSize
} catch {
    Write-Host "-> vCenter SSH 상태를 가져오는 중 오류 발생" -ForegroundColor Gray
}

# ========================================================================
# ITEM 2: 개별 가상머신(VM) SSH 포트(22) 응답 체크
# ========================================================================
Write-Host "[TASK 2] 개별 VM SSH(Port 22) 네트워크 응답 점검 (DEF-* 패턴)" -ForegroundColor Yellow
$TargetVMs = Get-VM -Name "DEF-*" | Where-Object { $_.PowerState -eq "PoweredOn" }

if ($TargetVMs) {
    $VmSshReport = foreach ($vm in $TargetVMs) {
        # 첫 번째 유효한 IPv4 주소 찾기
        $ip = $vm.Guest.IPAddress | Where-Object { $_ -match "^\d{1,3}(\.\d{1,3}){3}$" } | Select-Object -First 1
        $sshOpen = $false
        
        if ($ip) {
            $sshOpen = Test-NetConnection -ComputerName $ip -Port 22 -InformationLevel Quiet -WarningAction SilentlyContinue
        }

        [PSCustomObject]@{
            VM_Name    = $vm.Name
            IP_Address = if($ip){$ip}else{"No IP/Tools Not Running"}
            SSH_Port22 = if($sshOpen){ "OPEN (⚠)" } else { "Closed" }
            OS_Family  = $vm.Guest.OSFullName
        }
    }
    $VmSshReport | Sort-Object SSH_Port22 -Descending | Format-Table -AutoSize
} else {
    Write-Host "-> 점검 대상 VM이 없습니다.`n" -ForegroundColor Gray
}

# ========================================================================
# ITEM 3: 호스트(ESXi) SSH 서비스 상태
# ========================================================================
Write-Host "[TASK 3] ESXi 호스트 SSH 서비스 상태" -ForegroundColor Yellow
Get-VMHost | Sort-Object Name | Select-Object Name, 
    @{N="SSH_Running"; E={(Get-VMHostService -VMHost $_ | Where-Object {$_.Key -eq "TSM-SSH"}).Running}},
    @{N="Security_Status"; E={ if((Get-VMHostService -VMHost $_ | Where-Object {$_.Key -eq "TSM-SSH"}).Running){ "⚠ Risk" } else { "✔ Safe" } }} | 
    Format-Table -AutoSize

Write-Host "="*70 -ForegroundColor White

# 세션 종료
Disconnect-VIServer -Confirm:$false | Out-Null
```

---

## 09. Inventory_Tree.ps1
Datacenter -> Cluster -> Host -> VM 으로 이어지는 계층형 인벤토리 구조를 CLI 화면에 트리 형태로 그려주는 시각화 스크립트입니다.

```powershell
# ========================================================================
# 1. 환경 설정 및 접속
# ========================================================================
$vCenterServer = "vc-wld02-a.site-a.vcf.lab"

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
Write-Host "인벤토리 데이터를 분석 중입니다..." -ForegroundColor Cyan
Connect-VIServer -Server $vCenterServer -User "administrator@vsphere.local" -Password "VMware123!VMware123!" | Out-Null

# ========================================================================
# 2. 인벤토리 트리 출력 함수
# ========================================================================
function Show-VCFInventoryTree {
    $Datacenters = Get-Datacenter | Sort-Object Name
    
    foreach ($dc in $Datacenters) {
        Write-Host "`n[DataCenter] $($dc.Name)" -ForegroundColor Cyan -Bold
        
        # 클러스터 탐색
        $Clusters = $dc | Get-Cluster | Sort-Object Name
        foreach ($cluster in $Clusters) {
            $clusterVMs = ($cluster | Get-VM).Count
            Write-Host "  ┣━━ [Cluster] $($cluster.Name) (Total VMs: $clusterVMs)" -ForegroundColor Yellow
            
            # 호스트 탐색
            $Hosts = $cluster | Get-VMHost | Sort-Object Name
            foreach ($h in $Hosts) {
                $hStatus = if ($h.ConnectionState -eq "Connected") { "OK" } else { "ISSUE" }
                $hColor = if ($hStatus -eq "OK") { "Gray" } else { "Red" }
                
                Write-Host "  ┃    ┣━━ [Host] $($h.Name)" -ForegroundColor $hColor -NoNewline
                Write-Host " [$hStatus]" -ForegroundColor $hColor
                
                # VM 탐색 (교육용이므로 상위 5대만 샘플링하거나 패턴 필터링 권장)
                $VMs = $h | Get-VM | Sort-Object Name | Select-Object -First 5
                foreach ($vm in $VMs) {
                    $pState = if ($vm.PowerState -eq "PoweredOn") { "▶" } else { "■" }
                    $pColor = if ($vm.PowerState -eq "PoweredOn") { "Green" } else { "DarkGray" }
                    
                    Write-Host "  ┃    ┃    ┗━━ [VM] " -ForegroundColor DarkGray -NoNewline
                    Write-Host "$pState $($vm.Name)" -ForegroundColor $pColor
                }
                
                # VM이 더 많을 경우 생략 표시
                $totalVMs = ($h | Get-VM).Count
                if ($totalVMs -gt 5) {
                    Write-Host "  ┃    ┃    ┗━━ ... (and $($totalVMs - 5) more VMs)" -ForegroundColor DarkGray
                }
            }
        }
    }
    Write-Host "`n------------------------------------------------------------"
    Write-Host " 트리 생성 완료: $(Get-Date)" -ForegroundColor Cyan
}

# 실행
Show-VCFInventoryTree

# ========================================================================
# 3. 세션 종료 (교육 시에는 주석 처리하고 결과를 보여준 뒤 끊으세요)
# ========================================================================
Disconnect-VIServer -Confirm:$false | Out-Null
```

---

## 10. dr_automation.ps1
대화형(Interactive) 메뉴 패널을 통해 NFS 데이터스토어 마운트부터 VM 등록, 네트워크 VDS 할당, OS 내부의 IP/Netplan 변경(DR 전환)까지 일괄 수행할 수 있는 스크립트입니다.

```powershell
# ========================================================================
# 1. 환경 변수 설정 (업데이트됨)
# ========================================================================
$vCenterServer = "vc-wld02-a.site-a.vcf.lab"
$vCenterUser   = "administrator@vsphere.local"
$vCenterPass   = "VMware123!VMware123!"

$TargetHosts   = @("esx-20a.site-a.vcf.lab", "esx-21a.site-a.vcf.lab", "esx-22a.site-a.vcf.lab")
$DatastoreName = "NFS_Datastore"
$NfsIp         = "10.1.1.221"
$NfsPath       = "/mnt/nfs_share"

$VmNames       = @("DEF-DB", "DEF-WEB")
$PgName        = "wld02-pg"

$GuestUser     = "ocuser"
$GuestPass     = "VMware123!"
$ScriptCmd     = "echo '$GuestPass' | sudo -S /home/ocuser/mysql_backup.sh"

# ------------------------------------------------------------------------
# [네트워크 설정 값]
# ------------------------------------------------------------------------
$IpMapping     = @{ "DEF-DB" = "10.1.10.209"; "DEF-WEB" = "10.1.10.210" }
$DrGateway     = "10.1.10.129"
$DrDns         = "10.1.1.1"  # <--- 요청하신 DNS 주소로 업데이트 완료

$ErrorActionPreference = "Stop"

# 공통 함수
Function Pause-Screen {
    Write-Host "`n================================================================" -ForegroundColor DarkCyan
    Read-Host "작업이 완료되었습니다. 메인 메뉴로 돌아가려면 Enter를 누르세요"
}

# ========================================================================
# 메인 루프
# ========================================================================
$isRunning = $true
while ($isRunning) {
    Clear-Host
    Write-Host "================ [ VCF DR 초정밀 제어 패널 ] ================" -ForegroundColor Cyan
    Write-Host " [준비 단계]"
    Write-Host "  1. vCenter 로그인"
    Write-Host "  2. NFS 데이터스토어 마운트 (대상 호스트 전체)"
    Write-Host "  3. VM 인벤토리 등록 (Register VM)"
    Write-Host "  4. 네트워크 어댑터 연결 상태 확인 및 활성화 (Connect NIC)"
    Write-Host "  5. VDS 포트그룹 강제 할당 (Set Network)"
    
    Write-Host "`n [실행 단계]"
    Write-Host "  6. VM 전원 켜기 (Power On - Async)"
    Write-Host "  7. VMware Tools 응답 대기 (Heartbeat 체크)"
    Write-Host "  8. OS 내부 IP 자동 변경 (Netplan 주입)"
    Write-Host "  9. 검증용 백업 쉘 스크립트 실행 (Invoke-VMScript)"
    
    Write-Host "`n [정리 단계]"
    Write-Host "  10. VM 전원 강제 차단 (Power Off)"
    Write-Host "  11. VM 인벤토리 등록 해제 (Unregister)"
    Write-Host "  12. NFS 데이터스토어 언마운트 (Unmount)"
    Write-Host "  13. vCenter 세션 로그아웃"
    
    Write-Host "------------------------------------------------------------"
    Write-Host "  0. 프로그램 종료"
    Write-Host "============================================================" -ForegroundColor Cyan
    
    $choice = Read-Host "수행할 작업 번호를 입력하세요"
    Write-Host ""

    switch ($choice) {
        "1" {
            Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
            Try { Connect-VIServer -Server $vCenterServer -User $vCenterUser -Password $vCenterPass | Out-Null; Write-Host "✅ 연결 성공" -ForegroundColor Green } 
            Catch { Write-Host "❌ 실패: $($_.Exception.Message)" -ForegroundColor Red }
            Pause-Screen
        }

        "2" {
            foreach ($esxi in $TargetHosts) {
                Try { New-Datastore -Nfs -Name $DatastoreName -Path $NfsPath -NfsHost $NfsIp -VMHost $esxi | Out-Null; Write-Host "✅ [$esxi] 마운트 완료" -ForegroundColor Green }
                Catch { Write-Host "⚠️ [$esxi] 이미 존재하거나 실패: $($_.Exception.Message)" -ForegroundColor Yellow }
            }
            Pause-Screen
        }

        "3" {
            foreach ($VmName in $VmNames) {
                Try { New-VM -VMFilePath "[$DatastoreName] $VmName/$VmName.vmx" -VMHost $TargetHosts[0] | Out-Null; Write-Host "✅ $VmName 등록 완료" -ForegroundColor Green }
                Catch { Write-Host "⚠️ $VmName 등록 건너뜀: $($_.Exception.Message)" -ForegroundColor Yellow }
            }
            Pause-Screen
        }

        "4" {
            Get-VM -Name $VmNames | Get-NetworkAdapter | Set-NetworkAdapter -Connected $true -StartConnected $true -Confirm:$false | Out-Null
            Write-Host "✅ 모든 VM의 네트워크 어댑터 '연결' 상태 활성화 완료" -ForegroundColor Green
            Pause-Screen
        }

        "5" {
            $netObj = Get-VDPortgroup -Name $PgName -ErrorAction SilentlyContinue
            if (-not $netObj) { $netObj = Get-VirtualPortGroup -Name $PgName }
            Get-VM -Name $VmNames | Get-NetworkAdapter | Set-NetworkAdapter -Portgroup $netObj -Confirm:$false | Out-Null
            Write-Host "✅ 모든 VM에 [$PgName] 포트그룹 할당 완료" -ForegroundColor Green
            Pause-Screen
        }

        "6" {
            Get-VM -Name $VmNames | Start-VM -RunAsync | Out-Null
            Write-Host "✅ 전원 켜기 신호 송신 완료 (부팅 진행 중...)" -ForegroundColor Green
            Pause-Screen
        }

        "7" {
            Write-Host "VMware Tools 응답 대기 중 (최대 5분)..."
            foreach ($vmName in $VmNames) {
                do {
                    $status = (Get-VM -Name $vmName).ExtensionData.Guest.ToolsStatus
                    Write-Host " -> $vmName 상태: $status"
                    Start-Sleep -Seconds 5
                } until ($status -match "toolsOk|toolsOld")
                Write-Host "✅ $vmName 준비 완료" -ForegroundColor Green
            }
            Pause-Screen
        }

        "8" {
            foreach ($vm in (Get-VM -Name $VmNames)) {
                $targetIp = $IpMapping[$vm.Name]
                
                # @' ... '@ (작은따옴표)를 사용하면 내부의 $나 ()를 PowerShell이 절대 해석하지 않습니다.
                # 다만, 외부 변수인 $targetIp, $DrGateway 등은 문자열 치환이 안 되므로 
                # PowerShell의 -f (포맷 연산자)를 사용하여 값을 주입합니다.
                
                $bashTemplate = @'
echo '{0}' | sudo -S bash -c "
IFACE=\$(ip -o link show | awk -F': ' '{print \$2}' | grep -v lo | head -n 1 | tr -d ' ')
cat <<EOF > /etc/netplan/99-dr-ip.yaml
network:
  version: 2
  ethernets:
    \${IFACE}:
      dhcp4: no
      addresses: [{1}/24]
      gateway4: {2}
      nameservers:
        addresses: [{3}]
EOF
netplan apply
"
'@ -f $GuestPass, $targetIp, $DrGateway, $DrDns

                Try { 
                    Invoke-VMScript -VM $vm -GuestUser $GuestUser -GuestPassword $GuestPass -ScriptText $bashTemplate -ScriptType Bash | Out-Null
                    Write-Host "✅ $($vm.Name) IP 변경 완료 ($targetIp / GW: $DrGateway / DNS: $DrDns)" -ForegroundColor Green 
                }
                Catch { Write-Host "❌ $($vm.Name) 실패: $($_.Exception.Message)" -ForegroundColor Red }
            }
            Pause-Screen
        }

        "9" {
            Try {
                $res = Invoke-VMScript -VM (Get-VM -Name "DEF-DB") -GuestUser $GuestUser -GuestPassword $GuestPass -ScriptText $ScriptCmd -ScriptType Bash
                Write-Host "✅ 결과:`n$($res.ScriptOutput)" -ForegroundColor Green
            } Catch { Write-Host "❌ 실행 실패: $($_.Exception.Message)" -ForegroundColor Red }
            Pause-Screen
        }

        "10" {
            Get-VM -Name $VmNames | Stop-VM -Confirm:$false | Out-Null
            Write-Host "✅ 전원 차단 완료" -ForegroundColor Green
            Pause-Screen
        }

        "11" {
            Get-VM -Name $VmNames | Remove-VM -DeletePermanently:$false -Confirm:$false | Out-Null
            Write-Host "✅ 인벤토리 등록 해제 완료" -ForegroundColor Green
            Pause-Screen
        }

        "12" {
            foreach ($esxi in $TargetHosts) {
                $ds = Get-Datastore -Name $DatastoreName -VMHost $esxi -ErrorAction SilentlyContinue
                if ($ds) { Remove-Datastore -Datastore $ds -VMHost $esxi -Confirm:$false | Out-Null; Write-Host "✅ [$esxi] 분리 완료" -ForegroundColor Green }
            }
            Pause-Screen
        }

        "13" {
            Disconnect-VIServer -Confirm:$false; Write-Host "✅ 로그아웃 완료" -ForegroundColor Green; Pause-Screen
        }

        "0" { $isRunning = $false }
    }
}
```
```

---
깃허브에 올리실 때 스크립트 용도에 대한 간단한 설명을 추가하거나, 파일별로 각각 업로드하는 것도 좋은 구조가 될 수 있습니다. 실습과 관련해서 추가로 수정할 내용이나 필요한 커맨드가 있다면 편하게 말씀해주세요!
