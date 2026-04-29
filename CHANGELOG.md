# Changelog

## v2.2.4 - 2026-04-29

### Fixed
- Removed `customize.sh` that was causing install failures with `Error code: 1` on KernelSU-Next
- Permissions now handled in `post-fs-data.sh` on every boot (more reliable)
- ZIP install now completes cleanly without error

### Changed
- Simpler module structure - no install-time scripts that can fail

## v2.2.3 - 2026-04-29

### Added
- `update.json` for automatic update notifications via KernelSU Manager
- `updateJson` field in `module.prop` pointing to GitHub raw URL

## v2.2.2 - 2026-04-29

### Added
- `customize.sh` for install-time setup (later removed in v2.2.4 due to KSU-Next compatibility issues)
- Comprehensive `README.md` with troubleshooting and technical details
- `CHANGELOG.md` for tracking changes

## v2.2.1 - Initial Public Release

### Features
- Auto-start UAC2 + ADB after boot (~75s)
- WebUI dashboard with live status (banner, checks, manual activation button)
- Manual activation via KernelSU Manager Action button
- PROVEN activation sequence with `adbd` restart trick
- `setprop sys.usb.config none` + manual UDC bind to bypass Android init reactor
- `idProduct=0x4ee5` cache-busting for Windows USB stack
- Auto-load `snd-aloop` kernel module