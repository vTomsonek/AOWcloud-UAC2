# AOWcloud UAC2

> KernelSU module for Xiaomi 12 Pro: USB Audio Class 2 + ADB composite gadget + ALSA bridge daemon. Turns the phone into a bidirectional USB soundcard (48 kHz, 16-bit, stereo). Companion Android app for HAL-bypassed voice-call capture is in a separate repo: **[github.com/vTomsonek/AOWcloud-Bridge](https://github.com/vTomsonek/AOWcloud-Bridge)**.

[![Module](https://img.shields.io/badge/KernelSU--Next-Module-blue)](https://github.com/rifsxd/KernelSU-Next)
[![Version](https://img.shields.io/badge/version-v4.0.4-green)](#)
[![Device](https://img.shields.io/badge/device-Xiaomi%2012%20Pro%20(zeus)-orange)](#)
[![Kernel](https://img.shields.io/badge/kernel-GKI%205.10-purple)](#)
[![App](https://img.shields.io/badge/app-AOWcloud--Bridge-blue)](https://github.com/vTomsonek/AOWcloud-Bridge)

---

## What it does

After installing this module and rebooting, your phone will automatically:

1. ✅ Load the `snd-aloop` kernel module (ALSA loopback for `bridge` classic mode)
2. ✅ Add a UAC2 (USB Audio Class 2) function to the active USB gadget
3. ✅ Keep ADB working in parallel (composite gadget: ADB + UAC2)
4. ✅ Set a fresh `idProduct` (`0x4ee5`) so Windows re-enumerates the device cleanly
5. ✅ Install the ALSA bridge daemon at `/system/xbin/bridge` (capture↔playback / `--stdin` / `--stdout` modes, callable via `su -c` or directly by privileged apps)
6. ✅ Auto-grant `CAPTURE_AUDIO_OUTPUT` + `MODIFY_PHONE_STATE` for `pl.aowcloud.bridge` if installed (companion app from [AOWcloud-Bridge](https://github.com/vTomsonek/AOWcloud-Bridge))
7. ✅ Expose a real-time status dashboard via KernelSU WebUI

The `/system/xbin/` overlay is built at boot via `tmpfs` + `mount --bind` (this kernel doesn't support OverlayFS xattr fallbacks).

**v3.1.0 split**: the Android app `pl.aowcloud.bridge` (Kotlin source + APK) lives in a separate repo. Install it manually via Android Studio Run or `adb install` from [AOWcloud-Bridge releases](https://github.com/vTomsonek/AOWcloud-Bridge/releases). The module by itself provides a complete USB Audio + ADB setup for any PC-side software (Voicemeeter, OBS, Audacity, etc.) — the app is only needed for in-call audio routing (HAL voice-mute bypass).

**v4.0.4 call-center mode** — added `voice_rx` mixPort patch (`maxOpenCount=2 maxActiveCount=2`) in `audio_policy_configuration.xml` for both SKU variants (`sku_taro`, `sku_taro_qssi`). KSU module bind-mounts the patched XMLs at boot. This lets two `AudioRecord(VOICE_DOWNLINK)` clients coexist on the audio policy level (the default `maxOpenCount=1` would reject the second open). See **Call-center mode** section below for the documented trade-off.

---

## Call-center mode (v4.0.4)

The module enables a call-center setup where the phone acts as an audio hub: GSM/VoLTE conversation → PC (Voicemeeter Banana → headphones).

**Important trade-off** — Bridge and HyperOS soundrecorder do NOT capture voice in parallel during the same call. User toggles Bridge ON/OFF per use case in the companion app UI:

| Bridge state | HyperOS soundrecorder MP3 | PC (Voicemeeter via UAC2) |
|---|---|---|
| **OFF** (default) | ✅ records voice normally to `/sdcard/MIUI/sound_recorder/call_rec/recording_<phone>_<date>.mp3` | ❌ silent |
| **ON** | ❌ silent (zero-filled samples) | ✅ receives voice DOWNLINK (and UL via mic) |

**Why this trade-off exists.** Even with the audio_policy `maxActiveCount=2` patch (which opens the policy-level gate), Google AOSP `AudioFlinger::setRecordSilenced(portId, true)` is invoked on the second `VOICE_DOWNLINK` client. The first client wins voice samples; the second receives zeros. This is enforced at the framework level, below `libaudioflingerimpl.so` (Xiaomi extension) — bypassing it requires either binary patching `libaudioflingerimpl.so` or hooking `audioserver` (which is a native daemon, not Zygote-forked, so standard Zygisk cannot inject).

For most call-center workflows the toggle is a non-issue: when actively in a call you typically want either the live PC stream (taking calls in headphones) or the local MP3 recording (archive/QA review), not both simultaneously. The toggle is a deliberate, documented user choice — see Bridge app UI.

---

When connected to a PC over USB-C, Windows will see:

```
USB Composite Device (Xiaomi 12 Pro)
├── Source/Sink         ← USB Audio Class 2 (capture + playback)
└── ADB Interface       ← for scrcpy, adb shell, etc.
```

The audio device shows up in Windows Sound panel as **"Speakers (Source/Sink)"** and **"Microphone (Source/Sink)"** — fully bidirectional, 48 kHz, 16-bit, 2-channel stereo. No drivers needed, native USBAUDIO2.sys.

---

---

## Why this is hard (and why this module exists)

Modern Android (12+) on Qualcomm chipsets uses a complicated USB stack:

- `init.usb.configfs.rc` is a reactive script that **fights** any change you make to the gadget
- The `adbd` daemon owns the FunctionFS descriptors for ADB; if you don't restart it after manipulating the config, the kernel refuses to bind the UDC
- Windows aggressively caches device descriptors per VID:PID — even if you correctly reconfigure the gadget, Windows won't notice unless the PID changes
- The configfs symlink syntax is picky (`Invalid argument` for the wrong relative path)
- `setprop sys.usb.config none` followed by `setprop sys.usb.config adb` is the only reliable way to release the UDC, but Android's init reactor will overwrite your `idProduct` the moment it re-binds

This module encodes the **proven sequence** that survives all of those traps. It took hundreds of iterations to find it.

---

## Compatibility

| | |
|---|---|
| **Device**         | Xiaomi 12 Pro (`zeus`, `waipio` platform) |
| **Chipset**        | Qualcomm Snapdragon 8 Gen 1 |
| **Android**        | 12+ (tested on MIUI/HyperOS Android 15) |
| **Kernel**         | GKI 5.10 with the modules below built in/loadable |
| **Root**           | KernelSU-Next 3.2.0+ |

### Kernel requirements

Your kernel must have:

- `CONFIG_USB_CONFIGFS_F_UAC2=y` — UAC2 function builtin
- `CONFIG_SND_ALOOP=m` (or `=y`) — ALSA loopback driver
- `CONFIG_USB_GADGET=y`, `CONFIG_USB_LIBCOMPOSITE=m`
- `TRIM_NONLISTED_KMI=0`, `KMI_SYMBOL_LIST_STRICT_MODE=0` (during build)

If you build a custom kernel, the `snd-aloop.ko` module shipped here may not match your kernel's KMI — rebuild it for your kernel and replace `modules/snd-aloop.ko` before zipping.

> Other devices on Snapdragon 8 Gen 1 with `a600000.dwc3` UDC may work with minimal tweaks, but this is **not** tested. The UDC name and gadget paths are hardcoded.

---

## Installation

1. **Build / install a compatible kernel** (GKI 5.10 with the configs above) and root with KernelSU-Next.
2. **Download** the latest [`AOWcloud_UAC2_vX.Y.Z.zip`](../../releases) from Releases.
3. **Flash via KernelSU Manager**: Modules → Install from storage → pick the zip.
4. **Reboot.**
5. Wait ~75 seconds after the home screen appears. The module auto-activates UAC2 + ADB.
6. Open **KernelSU Manager → Modules → AOWcloud UAC2 → WebUI** to verify status.

That's it. After every boot the module re-runs and the phone is ready.

---

## WebUI Dashboard

<p align="center">
  <em>Real-time status panel accessible from KernelSU Manager</em>
</p>

The dashboard shows:

- **Banner**: green when everything works, yellow for partial config, red when inactive
- **UDC State** & **VID:PID** — quick glance
- **6 health checks**:
  - UAC2Gadget card present in ALSA
  - `uac2.0` linked into the gadget config
  - ADB linked into the gadget config
  - `snd-aloop` module loaded
  - `idProduct` is `0x4ee5` (Windows cache-busting value)
  - UDC is in `configured` state
- **Aktywuj UAC2** button — manually re-runs the activation sequence (useful if Windows lost the device)
- **Auto-refresh** every 3 seconds

---

## How it works (the proven sequence)

The activation flow that finally worked, after fighting Android's USB HAL for a long time:

```sh
# 1. Release the UDC without letting Android re-bind in a loop
setprop sys.usb.config none
sleep 3

# 2. Add uac2.0 to the live config (path must be exactly this many "../"s)
ln -s ../../../../usb_gadget/g1/functions/uac2.0 \
      /config/usb_gadget/g1/configs/b.1/uac2.0

# 3. Add ADB function back (Android will fight us if we use setprop)
ln -s ../../../../usb_gadget/g1/functions/ffs.adb \
      /config/usb_gadget/g1/configs/b.1/ffs.adb

# 4. Set our idProduct BEFORE binding so Windows sees a "new" device
echo 0x4ee5 > /config/usb_gadget/g1/idProduct

# 5. CRITICAL: restart adbd so it remounts /dev/usb-ffs/adb
#    and writes fresh FunctionFS descriptors. Without this,
#    kernel rejects the UDC bind with "Device or resource busy"
stop adbd
start adbd

# 6. Wait for FunctionFS descriptors to be ready
while [ "$(getprop sys.usb.ffs.ready)" != "1" ]; do sleep 1; done

# 7. Bind the UDC manually (NOT through setprop, or Android overwrites idProduct)
echo "a600000.dwc3" > /config/usb_gadget/g1/UDC
```

The trick that finally cracked it: **`stop adbd && start adbd` after re-linking `ffs.adb`**, then waiting for `sys.usb.ffs.ready=1`. Without that step the bind fails with `Device or resource busy`, because the kernel won't bind a FunctionFS function whose userspace half hasn't written its descriptors yet.

---

## Troubleshooting

### "After reboot Windows only sees ADB, no audio"

The auto-start usually takes ~75 seconds. If after a few minutes audio still isn't there:

1. Open **KernelSU Manager → AOWcloud UAC2 → WebUI**
2. Tap **Aktywuj UAC2** (manual re-run)
3. If the dashboard goes green but Windows still sees only ADB:
   - In Device Manager → View → **Show hidden devices**
   - Find old `Source/Sink` entries (greyed out) under **Sound, video and game controllers**
   - Right-click → Uninstall (and remove the driver if asked)
   - Re-plug the cable

### "Bootloop after install"

Older versions of this module attempted to manipulate the UDC during early boot, which caused bootloops on some firmwares. v2.x onwards waits for `sys.boot_completed=1` plus an extra ~30 s before doing anything risky.

If you somehow do get a bootloop:

1. Power off, hold **Volume Down** while booting → Safe Mode (modules disabled)
2. Open KernelSU Manager → disable AOWcloud UAC2
3. Reboot normally → manage the module from there

### "ADB stops working after Aktywuj"

This was a v1.x bug — the action would drop `ffs.adb` from the config. The current version always re-links both `uac2.0` **and** `ffs.adb` before re-binding. Make sure you're on v2.2.1 or newer.

### "I want to record/play audio from the phone, what's the device?"

On the phone: ALSA card `UAC2Gadget`, device `0`. Quick test:

```sh
# capture what the PC is sending us (5 s, stereo, 48 kHz)
tinycap /sdcard/test.wav -D <card_num> -d 0 -c 2 -r 48000 -b 16 -t 5
```

Find `<card_num>` from `cat /proc/asound/cards`.

---

## Module structure (v3.1.0)

```
aowcloud_uac2/
├── module.prop                metadata for KernelSU
├── update.json                auto-update notifier endpoint
├── post-fs-data.sh            loads snd-aloop, bind-mounts /system/xbin/ for bridge daemon
├── service.sh                 waits for boot_completed, runs action.sh, auto-grants perms (if app installed)
├── action.sh                  proven UAC2 + ADB activation sequence (idempotent)
├── status.sh                  emits status JSON to /data/local/tmp/uac2_status.json
├── uninstall.sh               cleans up logs
├── modules/
│   └── snd-aloop.ko           ALSA loopback kernel module
├── system/
│   └── xbin/
│       └── bridge             ALSA bridge daemon (capture↔playback / stdin / stdout modes)
└── webroot/
    └── index.html             KernelSU WebUI dashboard (3 sections)
```

**Removed in v3.1.0** (vs v3.0.6): `system/priv-app/AOWcloudBridge/`, `system/etc/permissions/privapp-permissions-pl.aowcloud.bridge.xml`, `customize.sh`. The companion Android app is now distributed via the [AOWcloud-Bridge](https://github.com/vTomsonek/AOWcloud-Bridge) repo and installed by the user (Android Studio Run or `adb install`), not bundled with the module.

Logs:
- `/data/local/tmp/uac2_callcenter.log` — boot + service runs
- `/data/local/tmp/uac2_action.log` — every activation
- `/data/local/tmp/uac2_status.json` — current status (regenerated on every dashboard refresh)

---

## Use case: call center on Xiaomi phones

This module was built for a 4-station call-center setup:

- **4× Xiaomi 12 Pro** with this module, each connected to its own PC over a single USB-C cable
- The PC hears the GSM call audio through `Source/Sink` and routes it (via Voicemeeter) into the agent's HyperX headset, mixed with browser/YouTube audio
- The agent's microphone goes back through `Source/Sink` to the phone, which forwards it into the live call
- ADB stays available for `scrcpy`, dial-pad automation, etc., on the same cable

The module solves the hardest, most invisible piece — getting Android to actually expose itself as a USB Audio Class 2 device while keeping ADB. Everything else (audio routing on the PC, mixing, GSM call audio plumbing on the phone) sits on top.

---

## Building from source

If you want to rebuild `snd-aloop.ko` for a different kernel:

1. Set up the AOSP/GKI build env, fetch your kernel sources
2. In your kernel `defconfig` (or fragment):
   ```
   CONFIG_SND_ALOOP=m
   ```
3. Build with `TRIM_NONLISTED_KMI=0` so the symbols you need aren't stripped
4. Replace `modules/snd-aloop.ko` in this module with your build
5. Re-zip and flash

---

## Credits & references

- [KernelSU-Next](https://github.com/rifsxd/KernelSU-Next) — the root framework this module runs on
- [WildKernels/GKI_KernelSU_SUSFS](https://github.com/WildKernels/GKI_KernelSU_SUSFS) — kernel build pipeline (forked for this project)
- The Linux kernel `gadget/configfs` documentation
- A *lot* of `dmesg` reading

Author: **vTomsonek** ([@vTomsonek](https://github.com/vTomsonek))

---

## License

MIT — do whatever you want with it, but no warranty. If you brick your phone you keep the pieces.

If this saved you a week of fighting USB descriptors, a star on the repo is appreciated.
