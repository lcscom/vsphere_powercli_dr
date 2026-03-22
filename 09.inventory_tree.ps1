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
