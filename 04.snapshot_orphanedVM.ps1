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
