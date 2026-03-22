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
