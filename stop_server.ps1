# Stop all processes and terminals related to KernalLink Controller

$currentPid = [System.Diagnostics.Process]::GetCurrentProcess().Id

Write-Host "======================================================================" -ForegroundColor Yellow
Write-Host "            KERNALLINK - FORCE STOP ALL PROCESSES" -ForegroundColor Yellow
Write-Host "======================================================================" -ForegroundColor Yellow
Write-Host ""

# 1. Terminate Terminal Windows
Write-Host "[*] Terminating KernalLink terminal windows..." -ForegroundColor Cyan
taskkill /F /FI "WINDOWTITLE eq KernalLink*" /T >$null 2>&1
taskkill /F /FI "WINDOWTITLE eq Touch PC Controller*" /T >$null 2>&1

# 2. Terminate Standalone Executables
Write-Host "[*] Terminating standalone executables..." -ForegroundColor Cyan
$exes = @("KernalLink.exe", "TouchPCServer.exe", "TouchPCServer_Console.exe", "TouchPC_Console.exe")
foreach ($exe in $exes) {
    taskkill /F /IM $exe >$null 2>&1
}

# 3. Terminate Port 8889 (TCP WebSocket) & Port 8890 (UDP Beacon) listeners
Write-Host "[*] Terminating processes bound to port 8889 and 8890..." -ForegroundColor Cyan
$ports = @(8889, 8890)
foreach ($port in $ports) {
    $lines = netstat -ano | Select-String ":$port\s"
    foreach ($line in $lines) {
        $parts = ($line.ToString().Trim() -split '\s+')
        if ($parts.Length -ge 4) {
            $p = $parts[-1]
            if ($p -match '^\d+$' -and $p -ne '0' -and $p -ne $currentPid) {
                Write-Host "   -> Terminating port $port process (PID: $p)..." -ForegroundColor Yellow
                Stop-Process -Id $p -Force -ErrorAction SilentlyContinue
                taskkill /F /T /PID $p >$null 2>&1
            }
        }
    }
}

# 4. Terminate any Python / CMD processes running server.py, pc_console.py, or start_server.bat
Write-Host "[*] Scanning for lingering project Python processes..." -ForegroundColor Cyan
$projProcs = Get-CimInstance Win32_Process | Where-Object {
    ($_.ProcessId -ne $currentPid) -and (
        ($_.CommandLine -and (
            $_.CommandLine -match 'server\.py' -or
            $_.CommandLine -match 'pc_console\.py' -or
            $_.CommandLine -match 'start_server\.bat'
        )) -or
        ($_.Name -in @('KernalLink.exe', 'TouchPCServer.exe', 'TouchPCServer_Console.exe', 'TouchPC_Console.exe'))
    )
}

foreach ($proc in $projProcs) {
    Write-Host "   -> Terminating $($proc.Name) (PID: $($proc.ProcessId))..." -ForegroundColor Yellow
    taskkill /F /T /PID $proc.ProcessId >$null 2>&1
}

# 5. Clear ADB Reverse Port Mappings
Write-Host "[*] Resetting ADB reverse port rules..." -ForegroundColor Cyan
$adbPaths = @(
    "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe",
    "C:\platform-tools\adb.exe",
    "adb"
)
$adbCmd = ""
foreach ($p in $adbPaths) {
    if ($p -eq "adb" -or (Test-Path $p)) {
        $adbCmd = $p
        break
    }
}
if ($adbCmd) {
    & $adbCmd reverse --remove tcp:8889 >$null 2>&1
    & $adbCmd reverse --remove-all >$null 2>&1
}

# 6. Detach secondary monitor & play disconnect chime
Write-Host "[*] Detaching secondary monitor & reverting to primary display..." -ForegroundColor Cyan
DisplaySwitch.exe /internal >$null 2>&1
try {
    $player = New-Object System.Media.SoundPlayer("C:\Windows\Media\Windows Hardware Remove.wav")
    $player.Play()
} catch {}

Write-Host ""
Write-Host "======================================================================" -ForegroundColor Green
Write-Host " [SUCCESS] All KernalLink processes stopped & ports released!" -ForegroundColor Green
Write-Host "  * Ports 8889 (TCP) & 8890 (UDP) released." -ForegroundColor Green
Write-Host "  * Display reverted to PC screen (Hardware disconnect chime played)." -ForegroundColor Green
Write-Host "  * Ready for fresh launch with: start_server.bat" -ForegroundColor Green
Write-Host "======================================================================" -ForegroundColor Green
