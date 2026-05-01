# build_bridge.ps1 - kompiluje bridge.c przez NDK r26d na ARM64 Android
# Uruchamiaj z dowolnego miejsca:  powershell -ExecutionPolicy Bypass -File S:\AOWcloud-UAC2\build_bridge.ps1
#
# Wymaga, zeby na Pulpicie istnialy:
#   - bridge.c   (Twoj kod, opcjonalnie zastapiony bridge.c.proposed - patrz flaga -UseProposed)
#   - tinyalsa\  (subfolder z source tinyalsa)

param(
    [switch]$UseProposed = $false,  # jesli podasz, podmieni bridge.c na bridge.c.proposed z workspace
    [switch]$V306        = $false   # jesli podasz, podmieni bridge.c na bridge.c.v306 z workspace
)

$ErrorActionPreference = 'Stop'

$Pulpit  = "C:\Users\Tomeuq\OneDrive\Pulpit"
$Workspace = "S:\AOWcloud-UAC2"
$Clang   = "C:\android-ndk\android-ndk-r26d\toolchains\llvm\prebuilt\windows-x86_64\bin\aarch64-linux-android30-clang.cmd"
$BridgeC = Join-Path $Pulpit "bridge.c"
$Tinyalsa = Join-Path $Pulpit "tinyalsa"

Write-Host "=== Bridge build ($(Get-Date)) ===" -ForegroundColor Cyan

# 1. Sanity
if (-not (Test-Path $Clang))    { throw "Brak NDK clang: $Clang" }
if (-not (Test-Path $Tinyalsa)) { throw "Brak folderu tinyalsa: $Tinyalsa" }
if (-not (Test-Path $BridgeC) -and -not $UseProposed) { throw "Brak bridge.c: $BridgeC (uzyj -UseProposed lub utworz plik)" }

# 2. Backup oryginalu
if (Test-Path $BridgeC) {
    $Backup = "$BridgeC.bak.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $BridgeC $Backup
    Write-Host "Backup: $Backup" -ForegroundColor Gray
}

# 3. Opcjonalnie podmien na bridge.c.proposed lub bridge.c.v306 z workspace
if ($UseProposed) {
    $Proposed = Join-Path $Workspace "bridge.c.proposed"
    if (-not (Test-Path $Proposed)) { throw "Brak $Proposed" }
    Copy-Item $Proposed $BridgeC -Force
    Write-Host "Podmieniono bridge.c na propozycje z workspace" -ForegroundColor Yellow
}
if ($V306) {
    $Src306 = Join-Path $Workspace "bridge.c.v306"
    if (-not (Test-Path $Src306)) { throw "Brak $Src306" }
    Copy-Item $Src306 $BridgeC -Force
    Write-Host "Podmieniono bridge.c na v3.0.6 z workspace (XRUN recovery + better logging)" -ForegroundColor Yellow
}

# 4. Kompilacja - jedna linia, zero backtickow
Push-Location $Pulpit
try {
    Write-Host "Kompiluje..." -ForegroundColor Cyan
    & $Clang -O2 -I "tinyalsa\include" "bridge.c" "tinyalsa\src\pcm.c" "tinyalsa\src\pcm_hw.c" "tinyalsa\src\pcm_plugin.c" "tinyalsa\src\mixer.c" "tinyalsa\src\mixer_hw.c" "tinyalsa\src\mixer_plugin.c" "tinyalsa\src\snd_card_plugin.c" "tinyalsa\src\limits.c" -o "bridge" -ldl
    if ($LASTEXITCODE -ne 0) { throw "Kompilacja zwrocila $LASTEXITCODE" }

    if (-not (Test-Path "bridge")) { throw "Clang zwrocil 0 ale brak pliku bridge" }
    $sz = (Get-Item "bridge").Length
    Write-Host "OK: bridge ($sz bytes)" -ForegroundColor Green

    # 5. Skopiuj do workspace
    $Out = Join-Path $Workspace "bridge_prebuilt"
    Copy-Item "bridge" $Out -Force
    Write-Host "Skopiowano do $Out" -ForegroundColor Green
}
finally {
    Pop-Location
}

Write-Host "=== Done ===" -ForegroundColor Cyan
Write-Host "Zaraz wroc do Claude i powiedz 'gotowe' - wstawi bridge_prebuilt do system/xbin/bridge i zbuduje ZIP v3.0.5" -ForegroundColor Cyan
