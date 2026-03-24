# 1. 인증서 오류 무시 및 vCenter 연결
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false -Scope Session | Out-Null

if (-not $global:DefaultVIServer -or $global:DefaultVIServer.Name -ne 'vc-wld02-a.site-a.vcf.lab') {
    Write-Host "vCenter에 연결을 시도합니다..." -ForegroundColor Cyan
    Connect-VIServer -Server 'vc-wld02-a.site-a.vcf.lab' -User 'administrator@vsphere.local' -Password 'VMware123!VMware123!' | Out-Null
}

# 💡 CSV 파일 저장 경로 설정 (PC 사용자명 + 타임스탬프)
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$localUser = $env:USERNAME # 현재 스크립트를 실행 중인 PC의 윈도우 접속 계정명
# 저장 경로: 각 사용자의 바탕화면 (예: C:\Users\Hong\Desktop\vSphere_Event_History_Hong_20260324_103000.csv)
$csvPath = "$env:USERPROFILE\Desktop\vSphere_Event_History_${localUser}_$timestamp.csv"

$interval = 3
$maxHistory = 15
$maxLoginHistory = 5
$eventHistory = @()
$loginHistory = @()

while ($true) {
    Clear-Host
    Write-Host "=====================================================================" -ForegroundColor Cyan
    Write-Host "     vSphere 종합 관제 대시보드 (실시간 CSV 로깅 동작 중 💾)       " -ForegroundColor Cyan
    Write-Host "     vCenter: vc-wld02-a.site-a.vcf.lab | 현재 시간: $(Get-Date)       " -ForegroundColor Cyan
    Write-Host "     저장 경로: $csvPath " -ForegroundColor Yellow
    Write-Host "=====================================================================" -ForegroundColor Cyan

    <# 0. 인벤토리 헬스 체크 #>
    Write-Host "`n[ 🏥 인벤토리 헬스 상태 (Host / VM / Datastore) ]" -ForegroundColor Cyan
    try {
        $hosts = Get-View -ViewType HostSystem -Property Name, Runtime.ConnectionState
        $badHosts = $hosts | Where-Object { $_.Runtime.ConnectionState -match "disconnected|notResponding" }
        $hostStr = "▶ 호스트 (총 $($hosts.Count)대) : "
        if ($badHosts) { Write-Host "$hostStr $($badHosts.Count)대 통신 단절 ❌" -ForegroundColor Red }
        else { Write-Host "$hostStr 전체 정상 통신 중 🟢" -ForegroundColor Green }

        $vms = Get-View -ViewType VirtualMachine -Property Name, Runtime.ConnectionState
        $badVms = $vms | Where-Object { $_.Runtime.ConnectionState -match "disconnected|orphaned|invalid" }
        $vmStr = "▶ 가상머신 (총 $($vms.Count)대) : "
        if ($badVms) { Write-Host "$vmStr $($badVms.Count)대 비정상 ❌" -ForegroundColor Red }
        else { Write-Host "$vmStr 전체 정상 통신 중 🟢" -ForegroundColor Green }

        $datastores = Get-View -ViewType Datastore -Property Name, Summary.Accessible
        $badDs = $datastores | Where-Object { $_.Summary.Accessible -eq $false }
        $dsStr = "▶ 데이터스토어 (총 $($datastores.Count)개) : "
        if ($badDs) { Write-Host "$dsStr $($badDs.Count)개 접근 불가 ❌" -ForegroundColor Red }
        else { Write-Host "$dsStr 전체 접근 가능 🟢" -ForegroundColor Green }
    } catch { }

    <# 1. 접속 중인 사용자 #>
    Write-Host "`n[ 👤 현재 접속 중인 사용자 (Active Sessions) ]" -ForegroundColor Magenta
    try {
        $sessionMgr = Get-View SessionManager
        $activeSessions = $sessionMgr.SessionList 
        if ($activeSessions) {
            $activeSessions | Sort-Object LastActiveTime -Descending | Select-Object `
                @{N="사용자"; E={if($_.UserName){$_.UserName}else{"(System)"}}},
                @{N="접속 IP"; E={$_.IpAddress}},
                @{N="클라이언트"; E={$_.UserAgent}} | Format-Table -AutoSize
        } else { Write-Host "현재 조회되는 세션이 없습니다.`n" -ForegroundColor Gray }
    } catch { }

    <# 2. 실시간 실행 중인 작업 #>
    Write-Host "`n[ ⚙️ 현재 실행 중 / 대기 중인 작업 (Tasks) ]" -ForegroundColor Green
    try {
        $runningTasks = Get-Task -State Running, Queued -ErrorAction SilentlyContinue
        if ($runningTasks) {
            $runningTasks | Select-Object `
                @{N="상태"; E={$_.State}},
                @{N="작업명"; E={$_.Name}},
                @{N="대상"; E={$_.ObjectId.Split('-')[1..2] -join '-'}},
                @{N="실행자"; E={$_.RequestedBy}},
                @{N="진행률(%)"; E={if($_.PercentComplete){$_.PercentComplete}else{"-"}}} | Format-Table -AutoSize
        } else { Write-Host "현재 진행 중이거나 대기 중인 작업이 없습니다.`n" -ForegroundColor DarkGray }
    } catch { }

    <# 3. 활성화된 알람 #>
    Write-Host "`n[ 🔴 현재 활성화된 알람 (Warning / Red) ]" -ForegroundColor Yellow
    try {
        $activeAlarms = @()
        $entitiesWithAlarms = Get-View -ViewType VirtualMachine, HostSystem -Property Name, TriggeredAlarmState | 
                              Where-Object { $_.TriggeredAlarmState -ne $null }
        foreach ($entity in $entitiesWithAlarms) {
            foreach ($alarmState in $entity.TriggeredAlarmState) {
                if ($alarmState.OverallStatus -match "yellow|red") {
                    $alarmDef = Get-View $alarmState.Alarm -Property Info.Name
                    $activeAlarms += [PSCustomObject]@{
                        상태 = $alarmState.OverallStatus.ToString().ToUpper()
                        대상 = $entity.Name
                        알람명 = $alarmDef.Info.Name
                    }
                }
            }
        }
        if ($activeAlarms.Count -gt 0) { $activeAlarms | Format-Table -AutoSize } 
        else { Write-Host "현재 활성화된 경고나 위험 알람이 없습니다. (All Green)`n" -ForegroundColor DarkGreen }
    } catch { }

    <# 4 & 5. 이벤트 수집 및 CSV 실시간 로깅 #>
    $recentEvents = Get-VIEvent -MaxSamples 40

    foreach ($evt in $recentEvents) {
        $isNewEvent = $false 
        $evtCategory = "General"

        $evtType = $evt.GetType().Name
        $msg = $evt.FullFormattedMessage
        if ([string]::IsNullOrWhiteSpace($msg)) { $msg = "[$($evtType.Replace('Event',''))] 시스템 이벤트 발생" }
        $user = if ($evt.UserName) { $evt.UserName } else { "System" }
        
        $isSystemAccount = ($user -match "vpxd|machine-|vsphere-webclient|vsan-health|com.vmware|wcp")
        $isAuthEvent = $false
        $authStatus = ""
        $authColor = "White"

        if ($evtType -match "UserLoginSessionEvent") { $isAuthEvent = $true; $authStatus = "로그인 성공 🔓"; $authColor = "Cyan" } 
        elseif ($evtType -match "BadUsernameSessionEvent|AlreadyAuthenticatedSessionEvent") { $isAuthEvent = $true; $authStatus = "로그인 실패 🚫"; $authColor = "Red" } 
        elseif ($evtType -match "UserLogoutSessionEvent|SessionTerminatedEvent") { $isAuthEvent = $true; $authStatus = "로그아웃 🔒"; $authColor = "DarkGray" }

        # --- [ 배열 누적 및 새 이벤트 감지 ] ---
        if ($isAuthEvent -and -not $isSystemAccount) {
            if (-not ($loginHistory.Key -contains $evt.Key)) {
                $isNewEvent = $true
                $evtCategory = "Security"
                $loginHistory += [PSCustomObject]@{
                    Key = $evt.Key; RawTime = $evt.CreatedTime; TimeStr = $evt.CreatedTime.ToString("HH:mm:ss")
                    User = $user; IP = if($evt.IpAddress){$evt.IpAddress}else{"-"}; Status = $authStatus; Color = $authColor
                }
            }
        } else {
            if (-not ($eventHistory.Key -contains $evt.Key)) {
                $isNewEvent = $true
                $evtColor = "White"
                if ($evtType -match "Error" -or $msg -match "failed|error") { $evtColor = "Red" } 
                elseif ($evtType -match "Warning" -or $msg -match "Alarm|Warning") { $evtColor = "Yellow" } 
                elseif ($evtType -match "Task" -or $msg -match "Task:|completed") { $evtColor = "Green" } 
                elseif ($msg -match "logged in|logged out|ticket|acquired|performance") { $evtColor = "DarkGray" }

                $eventHistory += [PSCustomObject]@{
                    Key = $evt.Key; RawTime = $evt.CreatedTime; TimeStr = $evt.CreatedTime.ToString("HH:mm:ss")
                    User = $user; Message = $msg; Color = $evtColor
                }
            }
        }

        # 💡 [ CSV 저장 로직 ] : 새 이벤트 발생 시 파일에 즉시 기록
        if ($isNewEvent) {
            $csvData = [PSCustomObject]@{
                수집PC계정 = $localUser  # CSV 내용 안에도 누가 수집했는지 명시적으로 남깁니다
                발생시간 = $evt.CreatedTime.ToString("yyyy-MM-dd HH:mm:ss")
                분류 = $evtCategory
                사용자 = $user
                메시지 = $msg
            }
            try {
                $csvData | Export-Csv -Path $csvPath -Append -NoTypeInformation -Encoding UTF8 -Force
            } catch {
                # 파일 접근 에러 발생 시 무시
            }
        }
    }

    <# 4. 접속 이력 출력 #>
    Write-Host "`n[ 🔐 최근 계정 접속 이력 (Login Audit) ]" -ForegroundColor DarkCyan
    $loginHistory = $loginHistory | Sort-Object RawTime -Descending | Select-Object -First $maxLoginHistory
    
    if ($loginHistory.Count -gt 0) {
        $loginHistory | Select-Object `
            @{N="시간"; E={$_.TimeStr}},
            @{N="상태"; E={$_.Status}},
            @{N="사용자"; E={$_.User}},
            @{N="접속 IP"; E={$_.IP}} | Format-Table -AutoSize
    } else { Write-Host "최근 관리자 접속 이력이 없습니다." -ForegroundColor DarkGray }

    <# 5. 일반 이벤트 히스토리 출력 #>
    Write-Host "`n[ 📝 이벤트 및 작업 히스토리 (최근 $($maxHistory)건 누적) ]" -ForegroundColor Cyan
    $eventHistory = $eventHistory | Sort-Object RawTime -Descending | Select-Object -First $maxHistory

    if ($eventHistory.Count -gt 0) {
        foreach ($item in $eventHistory) {
            Write-Host "[$($item.TimeStr)] [사용자: $($item.User)] $($item.Message)" -ForegroundColor $item.Color
        }
    } else { Write-Host "발생한 이벤트가 없습니다." -ForegroundColor DarkGray }

    Write-Host "`n종료하려면 [Ctrl + C]를 누르세요. $($interval)초 후 갱신..." -ForegroundColor DarkGray
    Start-Sleep -Seconds $interval
}
