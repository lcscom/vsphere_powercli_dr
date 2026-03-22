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
