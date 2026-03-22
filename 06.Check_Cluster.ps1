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
