# CLAUDE.md — AOWcloud UAC2 KSU module

**Updated:** 2026-05-03 (release v4.0.4)
**Status:** v4.0.4 = OFFICIAL RELEASE z dokumentowanym call-center mode trade-off
**User:** Tomasz (tomasz@jiko.pl) — embedded/kernel-level Android dev, polski. Oczekuje zwięzłych technicznych odpowiedzi po polsku.

## Cel projektu

Call-center setup na Xiaomi 12 Pro (zeus/taro/waipio, HyperOS Android 14 xiaomi.eu). Telefon = tygrysik audio hub: rozmowa GSM/VoLTE → komputer (Voicemeeter Banana → Razer Kraken słuchawki). KSU module dostarcza:

- **USB Audio Class 2 + ADB composite gadget** (telefon jako USB headset+mic dla PC)
- **ALSA bridge daemon** `/system/xbin/bridge` (snd-aloop loopback path)
- **Companion app** `pl.aowcloud.bridge` z `AudioRecord(VOICE_DOWNLINK)` + `CAPTURE_AUDIO_OUTPUT` permission
- **WebUI panel** `pl.aowcloud.mi` parsuje nagrania MP3 z `/sdcard/MIUI/sound_recorder/call_rec/` i mapuje do rozmów

## KRYTYCZNE wymaganie #1 (non-negotiable)

**HyperOS soundrecorder MUSI nagrywać każdą rozmowę normalnie.** Nazewnictwo `recording_<phone>_<date>.mp3` jest parsowane przez `pl.aowcloud.mi` panel app — JAKAKOLWIEK zmiana nazewnictwa lub brak nagrań rozwala panel.

## KRYTYCZNE wymaganie #2

**Bridge musi streamować voice DL+UL do PC równolegle z soundrecorderem.** Nie alternatywa — RÓWNOLEGLE każda rozmowa.

User: "nie no jesteśmy profesjonalistami, mamy ludzi którzy oczekują godnego rozwiązania... oczekuję pełnego bridga dzwięku oraz nieprzerwanej pracy soundrecordera"

## Architektura HyperOS audio (potwierdzona)

```
audioserver (PID e.g. 11792, system process)
   - libaudioflingerimpl.so (Xiaomi modified, klasa AudioFlingerImpl)
     - voiceProcess(IAfRecordTrack, ...)
     - longTimeSilent / reportMicSilence / setSilenceParameter
     - YouMeMagicVoice (Xiaomi voice changer)
   - libaudiopolicymanagerimpl.so (Xiaomi modified, AudioPolicyManagerImpl)
     - isReuseInput / inputReuse / setReuseInputInfo (struct audio_reuse_input)
     - getAppMaskByNameImpl (whitelist lookup)
   - libaudiohalvendorextn.so (Xiaomi extension)
   - NIE loaduje /vendor/ libow
   |
   v IHwBinder (HIDL audio v7.0, NIE AIDL)
android.hardware.audio.service_64 (PID e.g. 11793, vendor process)
   - /vendor/lib64/hw/audio.primary.taro.so (760 KB) - HAL primary
   - /vendor/lib64/hw/android.hardware.audio@7.0-impl.so (250 KB) - HIDL impl
   - /vendor/lib64/libar-pal.so (3.15 MB) - PAL library, klasy StreamInCall/StreamPCM
   - /vendor/lib64/vendor.qti.hardware.pal@1.0-impl.so (88 KB) - HIDL service
   - /vendor/lib64/vendor.qti.hardware.pal@1.0.so (291 KB) - HIDL interface
   - /vendor/lib64/hw/audio.usb.default.so - USB audio HAL
   |
   v ioctl
ADSP firmware (Qualcomm waipio, compressed offload + voice tap)
```

**PAL stream types (relevantne):** `PAL_STREAM_VOICE_CALL_RECORD`, `PAL_STREAM_VOICE_CALL_RX_TX`
**ALSA use cases:** `incall-rec-uplink`, `incall-rec-downlink`, `incall-rec-uplink-and-downlink`

## Kluczowy mechanizm "first-wins-forever" (zidentyfikowany)

**Plik:** `/vendor/etc/audio_cloud_control_white_list.xml` (3021 B)
**Fragment:**
```xml
<record_unsilence_app_name_list>
    <com.android.soundrecorder/>     <-- HyperOS soundrecorder
    <com.tencent.mm/>                <-- WeChat
    <com.whatsapp/>
    <com.skype.raider/>
    <com.google.android.dialer/>
    ... (28 aplikacji total)
</record_unsilence_app_name_list>
```

**Mechanizm:**
1. Aplikacja otwiera `AudioRecord(VOICE_DOWNLINK)`
2. AudioPolicyManager szuka package name w whitelist
3. JEŻELI w whitelist → `AudioFlinger::setRecordSilenced(portId, false)` — dostaje real samples
4. JEŻELI NIE w whitelist → `setRecordSilenced(portId, true)` — dostaje zera

**Strings dowodzące:** `setRecordSilenced(general), portId:%d, silenced %d` w `libaudioflingerimpl.so`

**Plik writeable backup:** `/data/vendor/audio/cloud_control_white_list.xml` (3147 B placeholder spaces, cloud-sync target — currently unused).

## Status po v4.1.0 (2026-05-01)

### Co już zrobione

- v4.0.0 patch: `audio_policy_configuration.xml` voice_rx mixPort `maxOpenCount=2 maxActiveCount=2` (oba sku_taro i sku_taro_qssi)
- v4.1.0 patch: dodane `<pl.aowcloud.bridge/>` do `record_unsilence_app_name_list` w `audio_cloud_control_white_list.xml`
- Bind-mount overlay przez post-fs-data.sh:
  - `/vendor/etc/audio/sku_taro/audio_policy_configuration.xml` (single-file mount --bind)
  - `/vendor/etc/audio/sku_taro_qssi/audio_policy_configuration.xml`
  - `/vendor/etc/audio_cloud_control_white_list.xml` (NOWE w v4.1.0)
- `killall -9 audioserver` w post-fs-data żeby przeładował patched XML
- ZIP: `S:\AOWcloud-UAC2\AOWcloud_UAC2_v4.1.0.zip` (170568 B, MD5 `d578383adfe4a1b1aef35d8fc02bb844`)

### Wynik testu v4.1.0

**Bridge: ✓ DZIAŁA** — Voicemeeter dostaje voice DL przy odebraniu rozmowy, mic source/sink czasowo czerwony (normalne — przełączenie trybu głośnomówiącego)

**Soundrecorder: ✗ NIE STARTUJE** — przycisk nagraj podświetla się 0.5s i sam wyłącza, nagranie nie powstaje

**Hipoteza:** HyperOS soundrecorder ma **app-side guard** który wykrywa że inny klient już ma voice DOWNLINK aktywny i sam się terminuje. Whitelist tylko sprawia że oba MOGĄ otworzyć — nie wymusza że oba MUSZĄ czytać. Soundrecorder zachowuje się obronnie.

## Plan F4 — POTWIERDZONA HIPOTEZA A (2026-05-02 dekompilacja)

**ZNALEZIONO guard w `com.android.soundrecorder` APK:**

`Lj1/U;->K0(Context)Z` = `isOtherAppRecording`:
```java
public static boolean K0(Context p4) {
    AudioRecordingConfiguration[] configs = audioManager.getActiveRecordingConfigurations();
    return !configs.isEmpty();  // !empty → "other app recording" → abort
}
```

Callers (3): `LO0/B;::b4`, `Lcom/android/soundrecorder/SoundRecorder;::p5`, `SoundRecorder;::o5`.

Plus pomocnicze: `Lj1/U;->v0` = `isInCall` (sprawdza `getMode() == 2 = MODE_IN_CALL`).

Pliki dec: `tools/hal/dec_main.txt`, `dec2.txt` (RecorderService methods), `dec3.txt` (K0+v0+pomocnicze), `dec_xref.txt` (callers).

### Strategia F4b: LSPosed/Zygisk hook (RECOMMENDED, ~1 dzień)

Hook `AudioManager.getActiveRecordingConfigurations()` w procesie `com.android.soundrecorder`, filtruj `pl.aowcloud.bridge`:

```java
@XposedHook(target="android.media.AudioManager")
public List<AudioRecordingConfiguration> getActiveRecordingConfigurations() {
    return origMethod().stream()
        .filter(c -> !"pl.aowcloud.bridge".equals(c.getClientPackageName()))
        .toList();
}
```

KSU-Next ma wbudowany Zygisk-Next — można dołączyć Zygisk module do KSU pakietu (`/data/adb/modules/aowcloud_uac2/zygisk/arm64-v8a.so`). Filter inject only do `com.android.soundrecorder`.

### Strategia F4c: Bridge przez AAudio/Oboe zamiast AudioRecord (~2 dni, niepewne)

AAudio API (NDK) nie rejestruje się w `getActiveRecordingConfigurations()`. Jeśli Bridge przepisany na AAudio, soundrecorder K0 zwraca pustą listę → startuje OK.

**Risk:** AAudio może nie obsługiwać `AudioSource.VOICE_DOWNLINK` (to Java-only platform extension). Test wymaga prototypowania.

### Strategia F4a: Patch APK (NIE - signature problem)

System app, podpisany kluczem Xiaomi. Re-sign nie wystarczy bo system permissions wymagają oryginalnej sygnatury. Wymaga disable signature check (LSPosed/Riru hook na `PackageManager`).

### Strategia F4d: Bridge ma timing PO soundrecorder (niewystarczajacy)

Bridge nasłuchuje PHONE_STATE_CHANGED→OFFHOOK, czeka 2s, potem startuje. Soundrecorder K0 → empty → starts OK. Ale wraca first-wins-forever — soundrecorder ma DL, Bridge silenced. Stare problemy v3.x. Nieakceptowalne.

### REKOMENDACJA: F4b

LSPosed module + zachowane patche v4.1.0 (whitelist + audio_policy).
Jeden Java hook, mała powierzchnia, łatwy debug. Czas: 1-2 dni.

### Hipoteza B: capture_app_name_list to osobny gate

W `wl_static.xml` jest też `capture_app_name_list` (różna od `record_unsilence_app_name_list`). Może ona kontroluje **kto może RZECZYWIŚCIE czytać** vs whitelist która tylko zwalnia silence flag.

**Sprawdz:** `strings libapm_impl_64 | grep -B2 -A2 capture_app_name_list` — co kod robi z tą listą.

### Hipoteza C: Property `persist.voice_bridge.capture: off`

Property o tej nazwie istnieje. Test: `setprop persist.voice_bridge.capture on` przed rozmową, sprawdź czy zmienia zachowanie. Jeśli tak → dodać do post-fs-data.sh.

### Hipoteza D: AudioFlinger replaceTrack

W `libaudioflingerimpl.so` jest funkcja `AudioFlingerImpl::replaceTrack(AudioFlinger, AudioParameter, int)`. Ta funkcja może podmieniać aktywny RecordTrack na nowy gdy widzi konflikt — wybierając first-come-first-served. Decompile w Ghidra (1.5 MB plik, symbols not stripped).

## Kluczowe pliki w `S:\AOWcloud-UAC2\tools\hal\`

```
hal_taro_64           760 KB  audio.primary.taro.so (HAL)
hal_taro_32           611 KB  audio.primary.taro.so 32-bit
hal_impl_70           250 KB  android.hardware.audio@7.0-impl.so
hal_rsub               32 KB  r_submix HAL
libar_pal_64          3.15 MB libar-pal.so (PAL library, StreamInCall etc.)
pal_impl_64            88 KB  vendor.qti.hardware.pal@1.0-impl.so (HIDL service)
pal_iface_64          291 KB  vendor.qti.hardware.pal@1.0.so (HIDL interface)
libaf_impl_64         1.5 MB  libaudioflingerimpl.so (Xiaomi AudioFlinger) - NEXT TARGET
libapm_impl_64        568 KB  libaudiopolicymanagerimpl.so (Xiaomi APM)
libahv_64              53 KB  libaudiohalvendorextn.so (Xiaomi extension)
libacc_64              69 KB  libaudiocloudctrl.so (whitelist parser)
audioserver_maps.txt  137 KB  /proc/<pid>/maps audioserver process
halservice_maps.txt    89 KB  /proc/<pid>/maps android.hardware.audio.service_64
wl_static.xml         2.99 KB /vendor/etc/audio_cloud_control_white_list.xml ORIGINAL
wl_cloud.xml          3.14 KB /data/vendor/audio/cloud_control_white_list.xml (placeholder spaces)
audio_props.txt        4 KB   getprop output - audio related
cloud_files.txt       11 KB   find list of cloud config files
soundrecorder_pkg.txt          pm list packages | grep recorder
PHASE1_RECON.md       5 KB    Plan F Phase 1 recon report
```

## Cowork mount issues (workarounds)

- **Bash mount cache stale** — po Write/Edit przez Read tool, bash przez `/sessions/.../mnt/...` pokazuje stary content. Workaround: `Read` tool zawsze widzi aktualne. Build ZIP: kopiuj plik osobno do `/tmp` przez heredoc, potem `cp` z powrotem.
- **PowerShell `>` redirect z adb shell truncuje text na ~6.7 KB** — używaj `cat > /sdcard/file && adb pull` zamiast `adb shell ... > local`.
- **PowerShell `findstr` nie radzi z UTF-16** generowanym przez PS redirect — użyj `Read`/`Grep` Cowork tools zamiast.
- **PowerShell `$pid` to read-only built-in** (PID samego PowerShella) — używaj `$asPid` lub innej nazwy.
- **`adb pull` plików binarnych zachowuje rozmiar OK**; tekstowych z `>` często nie.

## Kluczowe komendy diagnostyczne

```powershell
# Znajdź procesy audio
.\adb.exe shell su -c "ps -A -o PID,NAME | grep -iE 'audio|qti'"

# audioserver maps z aktualnym PID
$asPid = (.\adb.exe shell su -c "pidof audioserver").Trim()
.\adb.exe shell su -c "cat /proc/$asPid/maps > /sdcard/maps.txt"
.\adb.exe pull /sdcard/maps.txt S:\AOWcloud-UAC2\tools\hal\

# Property audio
.\adb.exe shell "getprop | grep -iE 'audio|record|silenc|capture|unsilence'"

# Logcat audio decyzji (uruchom PRZED rozmową)
.\adb.exe logcat -c
.\adb.exe logcat -v time *:V > S:\AOWcloud-UAC2\tools\hal\logcat_full.txt
# Mów ~15s, ctrl+C
```

## KSU bind-mount pattern (working)

```sh
# /vendor (vendor_configs_file context):
chcon u:object_r:vendor_configs_file:s0 "$SRC"
mount --bind "$SRC" "$TARGET"

# /system (tmpfs + cp -ar bo OverlayFS xattr broken na tym kernelu):
mount -t tmpfs -o size=16M,mode=755,context=u:object_r:system_file:s0 tmpfs /dev/aow_xbin
cp -ar /system/xbin/. /dev/aow_xbin/
cp -ar $MODDIR/system/xbin/. /dev/aow_xbin/
mount --bind /dev/aow_xbin /system/xbin
restorecon -R /system/xbin
```

## Próby wcześniejsze (NIE działają samodzielnie)

- **Plan A:** maxActiveCount=2 w audio_policy XML — tylko otwiera gate na poziomie policy, ale framework wciąż silencuje drugi klient
- **Plan B:** AudioRecord delay (3s) żeby soundrecorder pierwszy złapał — nie działa, AudioFlinger silenctuje sequentialnie
- **Plan C:** Odwrotnie - Bridge pierwszy — jeden TEST to udowodnił że "first wins" ale nie było reproducible
- **Plan D:** Earpiece mute przez setStreamVolume(STREAM_VOICE_CALL, 0) — HAL ma osobny gain, mute nie działał i zaburzał voice routing — patch wycofany v3.0.7
- **Plan E (v4.0.0):** Single-file bind audio_policy + maxActiveCount=2 — opens gate ale framework wciąż silencuje
- **Plan F (porzucone):** Binary patch HAL audio.primary.taro.so — porzucone bo decompile złożony, plus konflikt nie żyje w HAL tylko w AudioFlinger
- **Plan F2 (porzucone):** Zygisk hook na pal_stream_open/read — porzucone bo PAL widzi tylko 1 IPC client (audioserver)
- **Plan F3 (v4.1.0):** Whitelist patch — Bridge OK ale soundrecorder się sam terminuje (test 2026-05-01)

## Repo info

- **GitHub:** https://github.com/vTomsonek/AOWcloud-UAC2 (KSU module)
- **GitHub:** https://github.com/vTomsonek/AOWcloud-Bridge (Android app `pl.aowcloud.bridge`)
- **GitHub:** https://github.com/vTomsonek/AOWcloud-Mi (panel app `pl.aowcloud.mi`)
- **Last release on GitHub:** v3.1.0 (release pending od dawna, task #27)
- **Local builds:** v3.0.x→v3.1.0→v4.0.x→v4.1.0 (najnowszy)

## Repo struktura (S:\AOWcloud-UAC2\)

```
S:\AOWcloud-UAC2\
├── module.prop                                      v4.1.0
├── post-fs-data.sh                                  v4.1.0 (4395 B)
├── service.sh
├── uninstall.sh
├── system/xbin/bridge                               binary daemon
├── modules/snd-aloop.ko
├── vendor/etc/
│   ├── audio_cloud_control_white_list.xml           PATCHED z pl.aowcloud.bridge
│   └── audio/
│       ├── sku_taro/audio_policy_configuration.xml  PATCHED maxActiveCount=2
│       └── sku_taro_qssi/audio_policy_configuration.xml  PATCHED
├── webroot/index.html
├── tools/hal/                                       analiza decompile + recon
├── AOWcloud_UAC2_v4.1.0.zip                         170568 B, MD5 d578383ad...
└── CLAUDE.md                                        TEN PLIK
```

## Następne kroki priorytetowo

1. **GitHub release v4.0.4** (manualnie z `AOWcloud_UAC2_v4.0.4.zip` jako asset) — task #54
2. **Bridge app UI** (osobne repo `AOWcloud-Bridge`): wyrazne dokumentowanie toggle "Bridge ON/OFF" trade-off w UI/about. User musi swiadomie wybierac per use case.
3. **Plan G-revised** (na pozniej, jezeli ambitnie): binary patch `libaudioflingerimpl.so` (1.5 MB Xiaomi mod) zeby pominac `setRecordSilenced(true)` na drugim VOICE_DOWNLINK kliencie. Ghidra decompile + bind-mount overlay. 2-3 dni iteracji + risk bootloop. Decyzja zostaje dla przyszlej sesji - na razie v4.0.4 jest stable release.

## Co bylo testowane i jak (historia decyzji)

- v4.1.0 z whitelist patch → tryb głośnomowiacy wymuszony, soundrecorder nie startuje. WYCOFANE.
- v4.0.3 baseline (audio_policy patch only) → routing OK, soundrecorder OK, ale Bridge ON = MP3 cichy (first-wins-forever). DZIAŁA jako baseline.
- v4.0.4 bump = v4.0.3 + uczciwy opis trade-off w module.prop + README/CHANGELOG dokumentacja. RELEASED.

## Konwencje code w projekcie

- **Wersjonowanie:** semver, każdy bump = ZIP w S:\ root + commit + tag + release
- **Budowanie ZIPa:** ZAWSZE w `/tmp/build_<ver>/`, potem `cp` na S:\ (Cowork mount workaround)
- **Build content:** `module.prop`, `post-fs-data.sh`, `service.sh`, `uninstall.sh`, `system/xbin/bridge`, `modules/snd-aloop.ko`, `vendor/etc/...`, `webroot/index.html`
- **Customize.sh:** był obecny do v3.x, w v4.x usunięty (pure-module mode)
- **Bridge binary:** statycznie linkowany ARM64, wstrzykuje się do `/system/xbin/` przez tmpfs+bind
- **SELinux contexts:** `system_file:s0` dla `/system/xbin/bridge`, `vendor_configs_file:s0` dla `/vendor/etc/audio*xml`

## Memory (persistent across sessions)

Memory files w `C:\Users\Tomeuq\AppData\Roaming\Claude\local-agent-mode-sessions\.../memory/`:
- `MEMORY.md` (index)
- `aowcloud_uac2_project.md`
- `xiaomi_12_pro_kernel.md` (OverlayFS quirks, voice path NOT ALSA-tappable)
- `cowork_mount_limits.md` (truncation patterns)
- `user_tomasz.md` (concise polish replies)
- `reference_aowcloud.md` (repo links)
- `hyperos_audio_arch.md` (split AIDL audio HAL — NOWE)

## TL;DR dla kontynuacji z innego komputera

```
Wczytaj ten CLAUDE.md → przejdź do sekcji "Plan F4" → dekompiluj soundrecorder APK
żeby ustalić dlaczego sam się wyłącza po starcie nagrywania w v4.1.0.

Test v4.1.0 wynik: Bridge dziala, soundrecorder NIE startuje (button 0.5s i off).
Plan F3 (whitelist patch) niewystarczajacy bo soundrecorder ma app-side guard.
Trzeba znalezc i obejsc ten guard, zachowując krytyczne wymaganie #1 (nagrania
muszą trafiac do /sdcard/MIUI/sound_recorder/call_rec/ z konwencja nazewnictwa).
```
