# 12. Interactive_ScaleOut.ps1 (대화형 스케일아웃 & 클린업 패널 - 지정 스토리지 적용)

## 📖 시나리오
콘솔 창에서 대화형 메뉴를 통해 vCenter에 로그인하고, 조건에 맞춰 최대 20대의 VM을 안전하게 배포하거나 일괄 삭제합니다.
배포되는 모든 VM은 지정된 스토리지(`esx-22a-ds01`)에 저장되며, 사용자의 잘못된 입력(문자 입력 등)이나 중복 VM 생성 에러를 방지하는 강력한 방어 로직이 포함되어 있습니다.

---

```powershell
# ========================================================================
# [전역 변수 설정] 
# ========================================================================
$vCenterServer = "vc-wld02-a.site-a.vcf.lab"
$vCenterUser   = "administrator@vsphere.local"
$vCenterPass   = "VMware123!VMware123!"

$TargetHost    = "esx-22a.site-a.vcf.lab"  # 기본 배포 타겟 호스트
$DatastoreName = "esx-22a-ds01"            # <--- 요청하신 데이터스토어로 변경 완료

# [고정 네트워크 설정]
$BaseIp        = "10.1.10."
$StartIpRange  = 49                        # 50번부터 부여 (49 + 1)
$SubnetMask    = "255.255.255.0"
$Gateway       = "10.1.10.129"
$Dns           = "10.1.1.1"

$ErrorActionPreference = "Continue"

# ========================================================================
# [헬퍼 함수] 화면 일시 정지 및 연결 상태 체크
# ========================================================================
Function Pause-Screen {
    Write-Host "`n================================================================" -ForegroundColor DarkCyan
    Read-Host "작업이 완료되었습니다. 메인 메뉴로 돌아가려면 Enter를 누르세요"
}

Function Check-Connection {
    if (-not $global:DefaultVIServer) {
        Write-Host "⚠️ vCenter에 연결되어 있지 않습니다. [1]번 메뉴를 통해 먼저 로그인해 주세요." -ForegroundColor Yellow
        Pause-Screen
        return $false
    }
    return $true
}

# ========================================================================
# [메인 루프] 인터랙티브 패널
# ========================================================================
$isRunning = $true
while ($isRunning) {
    Clear-Host
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "      [ VCF Interactive Scale-Out & Clean-up Panel ]        " -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " 현재 접속 상태: $(if($global:DefaultVIServer){$global:DefaultVIServer.Name + " (Connected)" -ForegroundColor Green}else{"Disconnected" -ForegroundColor Red})"
    Write-Host " 타겟 스토리지:  $DatastoreName"
    Write-Host "------------------------------------------------------------"
    Write-Host "  1. vCenter 로그인 (세션 연결)"
    Write-Host "  2. 🚀 대규모 VM 배포 (템플릿 기반 Scale-Out)"
    Write-Host "  3. 🧹 지정 폴더 VM 일괄 삭제 (Scale-In / Clean-Up)"
    Write-Host "------------------------------------------------------------"
    Write-Host "  0. 프로그램 종료"
    Write-Host "============================================================" -ForegroundColor Cyan
    
    $choice = Read-Host "수행할 작업 번호를 입력하세요"
    Write-Host ""

    switch ($choice) {
        # ----------------------------------------------------------------
        # 1. 로그인
        # ----------------------------------------------------------------
        "1" {
            Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null
            try {
                Connect-VIServer -Server $vCenterServer -User $vCenterUser -Password $vCenterPass -ErrorAction Stop | Out-Null
                Write-Host "✅ [$vCenterServer] 로그인 성공!" -ForegroundColor Green
            } catch {
                Write-Host "❌ 접속 실패: $($_.Exception.Message)" -ForegroundColor Red
            }
            Pause-Screen
        }

        # ----------------------------------------------------------------
        # 2. VM 배포
        # ----------------------------------------------------------------
        "2" {
            if (-not (Check-Connection)) { continue }

            Write-Host "[STEP 1] 템플릿 현황 조회 중..." -ForegroundColor Yellow
            $Templates = Get-Template | Sort-Object Name
            if ($Templates.Count -eq 0) {
                Write-Host "❌ 배포 가능한 템플릿이 없습니다." -ForegroundColor Red
                Pause-Screen; continue
            }

            for ($i=0; $i -lt $Templates.Count; $i++) {
                Write-Host "  [$i] $($Templates[$i].Name)"
            }
            
            # 템플릿 선택 (숫자 검증)
            $TplIndex = -1
            while ($TplIndex -lt 0 -or $TplIndex -ge $Templates.Count) {
                $inputIdx = Read-Host "`n배포할 템플릿의 번호를 선택하세요"
                if ([int]::TryParse($inputIdx, [ref]$TplIndex) -and $TplIndex -ge 0 -and $TplIndex -lt $Templates.Count) { break }
                Write-Host "⚠️ 유효한 번호를 입력해주세요." -ForegroundColor Red
            }
            $SelectedTemplate = $Templates[$TplIndex]

            Write-Host "`n[STEP 2] 배포 설정" -ForegroundColor Yellow
            $FolderName = Read-Host "1) 생성할 VM 폴더 이름을 입력하세요 (예: Web-Event)"
            $BaseName   = Read-Host "2) VM 기본 이름을 지정하세요 (예: AppNode)"
            
            # 수량 입력 (1~20 검증)
            $VmCount = 0
            while ($VmCount -lt 1 -or $VmCount -gt 20) {
                $inputCount = Read-Host "3) 배포할 수량을 입력하세요 (1~20)"
                if ([int]::TryParse($inputCount, [ref]$VmCount) -and $VmCount -ge 1 -and $VmCount -le 20) { break }
                Write-Host "⚠️ 1에서 20 사이의 숫자로 입력해주세요." -ForegroundColor Red
            }

            # CPU 입력 검증
            $CpuCount = 0
            while ($CpuCount -le 0) {
                $inputCpu = Read-Host "4) 할당할 CPU 코어 수를 입력하세요 (예: 2)"
                if ([int]::TryParse($inputCpu, [ref]$CpuCount) -and $CpuCount -gt 0) { break }
                Write-Host "⚠️ 올바른 숫자를 입력해주세요." -ForegroundColor Red
            }

            # Memory 입력 검증
            $MemGB = 0
            while ($MemGB -le 0) {
                $inputMem = Read-Host "5) 할당할 Memory(GB) 크기를 입력하세요 (예: 4)"
                if ([int]::TryParse($inputMem, [ref]$MemGB) -and $MemGB -gt 0) { break }
                Write-Host "⚠️ 올바른 숫자를 입력해주세요." -ForegroundColor Red
            }

            $TargetNet = Read-Host "6) 연결할 VDS 포트그룹을 입력하세요 (예: wld02-pg)"

            # 폴더 확인 및 생성 로직
            $dc = Get-Datacenter | Select-Object -First 1
            $VmRootFolder = $dc | Get-Folder -Name "vm"
            $TargetFolder = Get-Folder -Name $FolderName -Location $VmRootFolder -ErrorAction SilentlyContinue
            if (-not $TargetFolder) {
                Write-Host "-> [$FolderName] 폴더가 존재하지 않아 새로 생성합니다." -ForegroundColor Gray
                $TargetFolder = New-Folder -Name $FolderName -Location $VmRootFolder
            }

            # 포트그룹 객체 추출
            $NetObj = Get-VDPortgroup -Name $TargetNet -ErrorAction SilentlyContinue
            if (-not $NetObj) { $NetObj = Get-VirtualPortGroup -Name $TargetNet -ErrorAction SilentlyContinue }
            if (-not $NetObj) {
                Write-Host "⚠️ [$TargetNet] 포트그룹을 찾을 수 없습니다. 배포를 취소합니다." -ForegroundColor Red
                Pause-Screen; continue
            }

            Write-Host "`n🚀 총 $VmCount 대의 배포를 시작합니다... (IP 범위: 10.1.10.$($StartIpRange+1) ~ 10.1.10.$($StartIpRange+$VmCount))" -ForegroundColor Cyan
            Write-Host "------------------------------------------------------------"

            for ($i = 1; $i -le $VmCount; $i++) {
                $NodeNum = "{0:D2}" -f $i
                $VMName  = "$BaseName-$NodeNum"
                $NodeIP  = "$BaseIp$($StartIpRange + $i)" # 50번부터 순차 할당
                $SpecName = "TempSpec-$VMName"

                Write-Host "▶ [$NodeNum/$VmCount] $VMName (IP: $NodeIP) 배포 진행 중..." -ForegroundColor Yellow

                # 1. 중복 VM 체크
                if (Get-VM -Name $VMName -ErrorAction SilentlyContinue) {
                    Write-Host "   ⚠️ 이미 동일한 이름($VMName)의 VM이 존재합니다. 건너뜁니다." -ForegroundColor DarkYellow
                    continue
                }

                try {
                    # 2. OS Customization 임시 생성 및 IP 주입
                    $TempSpec = New-OSCustomizationSpec -Name $SpecName -OSType Linux -Domain "vcf.lab" -NamingScheme Fixed -NamingPrefix $VMName -DnsServer $Dns -ErrorAction Stop
                    $TempSpec | Get-OSCustomizationNicMapping | Set-OSCustomizationNicMapping -IpMode UseStaticIp -IpAddress $NodeIP -SubnetMask $SubnetMask -DefaultGateway $Gateway | Out-Null

                    # 3. VM 복제 (템플릿 사이즈 유지, 데이터스토어 명시)
                    $NewVM = New-VM -Name $VMName -Template $SelectedTemplate -Location $TargetFolder -VMHost $TargetHost -Datastore $DatastoreName -OSCustomizationSpec $TempSpec -Confirm:$false -ErrorAction Stop

                    # 4. CPU, Memory 사양 변경
                    $NewVM | Set-VM -NumCpu $CpuCount -MemoryGB $MemGB -Confirm:$false | Out-Null

                    # 5. 첫 번째 네트워크 어댑터에 타겟 포트그룹 연결
                    $NewVM | Get-NetworkAdapter | Select-Object -First 1 | Set-NetworkAdapter -Portgroup $NetObj -Confirm:$false | Out-Null

                    # 6. 전원 켜기 (비동기로 진행하여 속도 향상)
                    $NewVM | Start-VM -RunAsync -Confirm:$false | Out-Null

                    Write-Host "   ✅ 배포 완료 (네트워크/사양 변경 적용 및 부팅 중)" -ForegroundColor Green
                }
                catch {
                    Write-Host "   ❌ 배포 실패: $($_.Exception.Message)" -ForegroundColor Red
                }
                finally {
                    # 7. 사용된 임시 Spec 삭제
                    Remove-OSCustomizationSpec -CustomizationSpec $SpecName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
                }
            }
            Write-Host "------------------------------------------------------------"
            Write-Host "🎉 모든 배포 작업 명령이 성공적으로 전달되었습니다." -ForegroundColor Cyan
            Pause-Screen
        }

        # ----------------------------------------------------------------
        # 3. VM 삭제
        # ----------------------------------------------------------------
        "3" {
            if (-not (Check-Connection)) { continue }

            Write-Host "[🧹 지정 폴더 VM 일괄 삭제 (Scale-In)]" -ForegroundColor Yellow
            $DelFolderName = Read-Host "1) 삭제할 VM들이 있는 폴더 이름을 입력하세요"
            $DelFolder = Get-Folder -Name $DelFolderName -ErrorAction SilentlyContinue

            if (-not $DelFolder) {
                Write-Host "❌ [$DelFolderName] 폴더를 찾을 수 없습니다." -ForegroundColor Red
                Pause-Screen; continue
            }

            $DelPrefix = Read-Host "2) 삭제할 VM 이름의 패턴(접두사)을 입력하세요 (예: AppNode 입력 시 AppNode* 일괄 조회)"
            
            $TargetVMs = Get-VM -Location $DelFolder -Name "$DelPrefix*" -ErrorAction SilentlyContinue

            if (-not $TargetVMs) {
                Write-Host "⚠️ 조건에 맞는 VM을 찾을 수 없습니다." -ForegroundColor Yellow
                Pause-Screen; continue
            }

            Write-Host "`n⚠️ [경고] 다음 $($TargetVMs.Count)대의 VM이 영구 삭제됩니다:" -ForegroundColor Red
            $TargetVMs | Select-Object Name, PowerState | Format-Table -AutoSize
            
            $Confirm = Read-Host "정말 삭제하시겠습니까? (Y/N)"
            if ($Confirm -match "^[Yy]$") {
                foreach ($vm in $TargetVMs) {
                    Write-Host "▶ [$($vm.Name)] 삭제 진행 중..." -ForegroundColor Yellow
                    try {
                        if ($vm.PowerState -eq "PoweredOn") {
                            $vm | Stop-VM -Confirm:$false -ErrorAction Stop | Out-Null
                        }
                        $vm | Remove-VM -DeletePermanently:$true -Confirm:$false -ErrorAction Stop | Out-Null
                        Write-Host "   ✅ 디스크까지 영구 삭제 완료" -ForegroundColor Green
                    } catch {
                        Write-Host "   ❌ 삭제 실패: $($_.Exception.Message)" -ForegroundColor Red
                    }
                }
                Write-Host "🎉 클린업이 완료되었습니다." -ForegroundColor Cyan
            } else {
                Write-Host "작업이 취소되었습니다." -ForegroundColor Gray
            }
            Pause-Screen
        }

        # ----------------------------------------------------------------
        # 0. 종료
        # ----------------------------------------------------------------
        "0" {
            Write-Host "👋 프로그램을 종료합니다." -ForegroundColor Cyan
            if ($global:DefaultVIServer) {
                Disconnect-VIServer -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
            }
            $isRunning = $false
        }

        default {
            Write-Host "⚠️ 잘못된 입력입니다. 메뉴 번호(0~3)를 선택해주세요." -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
}
