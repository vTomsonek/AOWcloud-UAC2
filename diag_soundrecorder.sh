#!/system/bin/sh
# Diagnostyka dlaczego com.android.soundrecorder nagrywa cisze podczas call.
# Uruchom: adb shell "su -c 'sh /data/local/tmp/diag.sh'"

PKG=com.android.soundrecorder
REC_DIR=/sdcard/MIUI/sound_recorder/call_rec

echo "===== T1: pakiet soundrecorder ====="
pm path $PKG
echo "--- dumpsys package $PKG (filtrowane) ---"
dumpsys package $PKG 2>/dev/null | grep -E "codePath|pkgFlags|privateFlags|versionName|firstInstallTime|lastUpdateTime|PRIVILEGED|granted=true" | head -20

echo
echo "===== T2: AppOps soundrecorder ====="
dumpsys appops $PKG 2>/dev/null | head -50
echo "--- raw RECORD_AUDIO + RECORD_AUDIO_OUTPUT (op 27, 86) ---"
appops get $PKG 2>/dev/null | head -30

echo
echo "===== T3: mount + priv-app + soundrecorder APK ====="
echo "--- nasze tmpfs binds: ---"
mount | grep -E "aow_|priv-app|/system/etc/permissions|/system/xbin" 2>/dev/null
echo "--- znajdujemy SoundRecorder APK w systemie: ---"
find /system /product /system_ext /vendor /apex -iname "*soundrecord*" 2>/dev/null | head -10
find /system /product /system_ext /vendor /apex -iname "*recorder*.apk" 2>/dev/null | head -10
echo "--- czy nasz tmpfs przesłonił /system/priv-app? ---"
ls /system/priv-app/ 2>/dev/null | head -20

echo
echo "===== T4: HyperOS / MIUI props i settings ====="
echo "--- props (record/callrec): ---"
getprop 2>/dev/null | grep -iE "record|callrec|miui.*call" | head -20
echo "--- settings system: ---"
settings list system 2>/dev/null | grep -iE "record|call" | head -10
echo "--- settings global: ---"
settings list global 2>/dev/null | grep -iE "record|call" | head -10
echo "--- settings secure: ---"
settings list secure 2>/dev/null | grep -iE "record|call" | head -10

echo
echo "===== T5: chronologia (kiedy soundrecorder przestal nagrywac vs kiedy nasz modul) ====="
echo "--- modtime naszego modulu KSU: ---"
stat -c "%y %n" /data/adb/modules/aowcloud_uac2 2>/dev/null
stat -c "%y %n" /data/adb/modules/aowcloud_uac2/module.prop 2>/dev/null
echo "--- ostatnie 15 plikow nagran (sortowane po dacie): ---"
ls -lat $REC_DIR 2>/dev/null | head -16

echo
echo "===== T6: rozmiar plikow - cisza vs voice ====="
echo "--- najmniejsze 5 (potencjalna cisza, dane same metadata): ---"
ls -laS $REC_DIR 2>/dev/null | tail -5
echo "--- najwieksze 5 (gdy dziala): ---"
ls -laS $REC_DIR 2>/dev/null | head -6
echo "--- ile plikow >100KB (= prawdziwe nagrania) vs <30KB (= cisza/glitch): ---"
COUNT_OK=$(find $REC_DIR -size +100k 2>/dev/null | wc -l)
COUNT_BAD=$(find $REC_DIR -size -30k 2>/dev/null | wc -l)
echo "  >100 KB: $COUNT_OK plikow"
echo "  <30  KB: $COUNT_BAD plikow"

echo
echo "===== T7: czy soundrecorder ma signature CAPTURE_AUDIO_OUTPUT ====="
dumpsys package $PKG 2>/dev/null | grep -E "CAPTURE_AUDIO_OUTPUT|MODIFY_PHONE_STATE|RECORD_AUDIO_OUTPUT" | head -10

echo
echo "===== KONIEC DIAG ====="
