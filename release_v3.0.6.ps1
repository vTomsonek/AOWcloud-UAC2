# release_v3.0.6.ps1 - commit + tag + push v3.0.6
# Uruchom: powershell -ExecutionPolicy Bypass -File S:\AOWcloud-UAC2\release_v3.0.6.ps1

$ErrorActionPreference = 'Stop'
Set-Location S:\AOWcloud-UAC2

Write-Host "=== Czyszcze stale lock file ===" -ForegroundColor Cyan
if (Test-Path .git\index.lock) {
    Remove-Item -Force .git\index.lock
    Write-Host "Usunieto .git\index.lock" -ForegroundColor Green
}

Write-Host "`n=== Status PRZED commit ===" -ForegroundColor Cyan
git status --short

Write-Host "`n=== git add -A ===" -ForegroundColor Cyan
git add -A
git status --short

$msg = @"
v3.0.6: bridge XRUN fix, snd-aloop bundled, dashboard cleanup

Bridge daemon (--stdin/--stdout):
- Fix: pcm_config start_threshold = period_size (was 0 -> XRUN po ~2 sec)
- Add: pcm_prepare() recovery na -EPIPE w petlach pcm_write/pcm_read
- Add: szczegolowe error logi (rc + errno + strerror + pcm_get_error)
- Add: re-write tej samej ramki w --stdin po recovery (bez 21ms ubytku)

Module:
- Fix: ZIP zawiera modules/snd-aloop.ko (poprzednio brakowalo, UAC2 schodzilo
  z card 2 na card 1, hardcode 'card 2' w aplikacji wpadal na nieistniejacy device)
- bridge.c.v306 source + build_bridge.ps1 dla future rebuildow
- diag_soundrecorder.sh - debug script

Dashboard (webroot/index.html):
- Tytul / wersja v3.0.6
- Usunieta mylaca check 'Mounted jako priv-app' z Sekcji 2 (apka jest user-app
  z auto-grant CAPTURE_AUDIO_OUTPUT - to dziala rownowaznie z priv-app na tym
  KSU buildzie)

Tested:
- bridge --stdin 2 0 < /dev/zero przez 10s = 487424 frames, xrun_recoveries=0
- Bidirectional voice path: drugi telefon mute -> Voicemeeter cisza (DL OK);
  Razer Kraken mic mute -> drugi telefon nie slyszy (UL OK)
- 21s stabilna transmisja DL ~187 KB/s + UL ~172 KB/s przez Voicemeeter Banana
"@

Write-Host "`n=== git commit ===" -ForegroundColor Cyan
git commit -m $msg

Write-Host "`n=== git tag v3.0.6 ===" -ForegroundColor Cyan
$tagmsg = "v3.0.6 - bridge XRUN fix + snd-aloop in ZIP + dashboard cleanup"
git tag -a v3.0.6 -m $tagmsg

Write-Host "`n=== git log -5 ===" -ForegroundColor Cyan
git log --oneline -5

Write-Host "`n=== git tag list ===" -ForegroundColor Cyan
git tag -l | Select-Object -Last 10

Write-Host "`n=== git push origin main --tags ===" -ForegroundColor Cyan
Write-Host "[!] Wymaga GitHub credentials (PAT lub SSH key)" -ForegroundColor Yellow
$confirm = Read-Host "Push teraz? (T/n)"
if ($confirm -eq "" -or $confirm -eq "T" -or $confirm -eq "t") {
    git push origin main
    git push origin v3.0.6
    Write-Host "`n=== Push OK ===" -ForegroundColor Green
    Write-Host "Teraz utworz GitHub Release recznie:" -ForegroundColor Cyan
    Write-Host "  https://github.com/vTomsonek/AOWcloud-UAC2/releases/new" -ForegroundColor White
    Write-Host "  Tag: v3.0.6" -ForegroundColor White
    Write-Host "  Asset: S:\AOWcloud-UAC2\AOWcloud_UAC2_v3.0.6.zip" -ForegroundColor White
} else {
    Write-Host "`nPomijam push - wykonaj recznie:" -ForegroundColor Yellow
    Write-Host "  git push origin main" -ForegroundColor White
    Write-Host "  git push origin v3.0.6" -ForegroundColor White
}

Write-Host "`n=== DONE ===" -ForegroundColor Green
