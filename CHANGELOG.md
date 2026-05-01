## v3.0.6 (2026-05-01)

### Fixed
- **Bridge daemon `--stdin` / `--stdout` modes no longer XRUN after ~2 sec.** Root cause: `start_threshold=0` w `pcm_config` powodowało, ze ALSA startowala PCM_OUT przed wypelnieniem bufora, wiec UAC2 USB endpoint zaczynal ssac dane natychmiast po pierwszym `pcm_write` i po ~2 sec (czas wypelnienia bufora gadgetu) kernel zwracal `-EPIPE` z `pcm_write`.
- Test deterministyczny: `bridge --stdin 2 0 < /dev/zero` przez 10 sec -> 487424 frames bez ani jednego bledu (poprzednio: 101376 frames i `Write error:` po dokladnie 2.11 sec).

### Changed
- `bridge.c`: `make_config()` rozdzielone na `make_config_in()` (capture, bez zmian) i `make_config_out()` (playback) z prawidlowymi thresholds: `start_threshold = period_size`, `stop_threshold = period_size * period_count`, `avail_min = period_size`.
- `bridge.c`: petla `pcm_write` w trzech trybach (`run_loopback`, `run_stdin_mode`, `run_stdout_mode`) ma `pcm_prepare()` recovery na `-EPIPE` zamiast `break`. W trybie `--stdin` re-write tej samej ramki po recovery (bez ubytku 21 ms w sciezce voice).
- `bridge.c`: lepszy error log - `rc + errno + strerror(errno) + pcm_get_error()` zamiast samego (czesto pustego) `pcm_get_error()`. Plus licznik `xrun_recoveries=N` w komunikacie koncowym.

## v3.0.5 (2026-05-01)

### Added
- **Bridge daemon binary mounted at `/system/xbin/bridge`** via tmpfs + bind-mount in `post-fs-data.sh`. Same pattern as priv-app injection (this kernel can't do OverlayFS xattr fallbacks).
- System priv-app `pl.aowcloud.bridge` can now `Runtime.exec("/system/xbin/bridge ...")` directly — **no `su`, no manual KSU root-list configuration**.
- Bridge binary survives reboots (replaces v3.0.4 workflow that left bridge in `/data/local/tmp/`, which was wiped on reboot).
- WebUI dashboard "SEKCJA 3. Bridge Binary" — shows status (ok/missing/bad_perms/bad_context), file permissions, SELinux context.
- `status.sh` JSON now includes `bridge_binary`, `bridge_path`, `bridge_perms`, `bridge_context`.

### Changed
- `module.prop` bumped to `version=v3.0.5 / versionCode=305`. Renamed to "AOWcloud UAC2 Call Center", author "Tomeuq".
- `post-fs-data.sh` adds third bind_inject call for `/system/xbin/` with explicit `chmod 755` + `chcon u:object_r:system_file:s0` on the bridge binary after restorecon (since `/system/xbin/` may not have a file_contexts.bin rule on Android 12+).

## v3.0.4 (2026-04-30)

### Fixed
- **HAL voice-mute bypass works.** `mount -t overlay` was rejected on this kernel for every fallback (no trusted xattr on F2FS or tmpfs, kernel <5.11 lacks `userxattr`). Switched to `mount -t tmpfs -o context=u:object_r:system_file:s0` with full `cp -ar` of `/system/priv-app/` (53 MB) and `/system/etc/permissions/` (120 KB), then `mount --bind`. After bind, `restorecon -R` restores per-file SELinux contexts according to `file_contexts.bin`.
- Result: `pl.aowcloud.bridge` is `pkgFlags=PRIVILEGED`, `CAPTURE_AUDIO_OUTPUT` and `MODIFY_PHONE_STATE` both `granted=true`.

## v3.0.3 (2026-04-30) — superseded by v3.0.4
- Tried tmpfs as OverlayFS upper layer with `userxattr` fallback. Kernel didn't recognize `userxattr` mount option ("unrecognized mount option"). All overlay attempts failed.

## v3.0.2 (2026-04-30) — superseded by v3.0.4
- Tried OverlayFS with `lowerdir=/system/priv-app, upperdir=/data/adb/modules/...`. Kernel logged `overlayfs: filesystem on '/data/.../up' not supported` (F2FS doesn't expose trusted xattr).

## v3.0.1 (2026-04-30) — superseded by v3.0.4
- Tried explicit `mount --bind` fallback with `mkdir -p /system/priv-app/AOWcloudBridge`. Failed because `/system` is RO with dm-verity.

## v3.0.0 (2026-04-30)

### Major
- **Integrated `pl.aowcloud.bridge` Android app as a system priv-app** via systemless overlay (`system/priv-app/AOWcloudBridge/AOWcloudBridge.apk`).
- **Added `system/etc/permissions/privapp-permissions-pl.aowcloud.bridge.xml`** whitelisting the three `signature|privileged` permissions the bridge needs:
  - `android.permission.CAPTURE_AUDIO_OUTPUT` - without this the Audio HAL silently mutes any `VOICE_DOWNLINK` / `VOICE_CALL` capture during a GSM call (the v2.x blocker - 9 sec recording arrived as 960 KB of pure silence, `m:9039` mute frames).
  - `android.permission.MODIFY_PHONE_STATE` - needed for `TelephonyManager` audio routing during calls.
  - `android.permission.DUMP` - for the bridge daemon's diagnostic commands.

### Why this works
- Priv-app + privapp-permissions XML is the documented Android 12 path to grant `signature|privileged` permissions without re-signing the APK with the platform key. Debug-signed APK is fine here - the privilege flag comes from the install location (`/system/priv-app`), not the signature.
- This bypasses the HAL mute on `AudioSource.VOICE_DOWNLINK` and `VOICE_CALL` that user apps cannot avoid even with `RECORD_AUDIO` granted.

### Added
- `customize.sh` is back: sets correct chmod (755 dirs / 644 APK + XML) on the new `system/` overlay tree and runs `restorecon` on it. (v2.2.4 removed it because of an unrelated `Error code: 1` on KSU-Next; restored cleanly here.)
- `status.sh` reports priv-app state (`app_installed`, `app_is_priv`, `app_has_capture`, `app_has_modify_phone`, `app_version`) by parsing `dumpsys package pl.aowcloud.bridge`.
- WebUI dashboard has a new "Bridge App" section showing version, priv/user-app status, and live grant state for the two key permissions.

### Install notes
- **REQUIRES uninstall of any existing user-installed `pl.aowcloud.bridge` before flashing**, otherwise PackageManager will reject the priv-app on first boot due to signature mismatch:
  ```
  adb shell pm uninstall pl.aowcloud.bridge
  ```
- After flashing this module + reboot, verify with:
  ```
  adb shell dumpsys package pl.aowcloud.bridge | grep -E "PRIVILEGED|CAPTURE_AUDIO_OUTPUT|MODIFY_PHONE_STATE"
  ```

### Bumped
- `version=v3.0.0`, `versionCode=30`.

## v2.2.4

### Fixed
- Removed `customize.sh` that was causing install failures with `Error code: 1` on KernelSU-Next
- Permissions now handled in `post-fs-data.sh` on every boot (more reliable)
- ZIP install now completes cleanly without error

### Changed
- Simpler module structure - no install-time scripts that can fail

## v2.2.3

### Added
- `update.json` for automatic update notifications via KernelSU Manager
- `updateJson` field in `module.prop` pointing to GitHub raw URL

## v2.2.2

### Added
- `customize.sh` for install-time setup (later removed in v2.2.4 due to KSU-Next compatibility issues)
- Comprehensive `README.md` with troubleshooting and technical details
- `CHANGELOG.md` for tracking changes

## v2.2.1

### Features
- Auto-start UAC2 + ADB after boot (~75s)
- WebUI dashboard with live status (banner, checks, manual activation button)
- Manual activation via KernelSU Manager Action button
- PROVEN activation sequence with `adbd` restart trick
- `setprop sys.usb.config none` + manual UDC bind to bypass Android init reactor
- `idProduct=0x4ee5` cache-busting for Windows USB stack
- Auto-load `snd-aloop` kernel module
