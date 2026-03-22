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
