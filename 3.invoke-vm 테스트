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
