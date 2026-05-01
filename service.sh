#!/system/bin/sh
MODDIR=${0%/*}
LOG=/data/local/tmp/uac2_callcenter.log

echo "=== service.sh START $(date) ===" >> "$LOG"

# Czekaj na boot_completed (do 60 sek)
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
  if [ "$(getprop sys.boot_completed)" = "1" ]; then
    echo "  boot_completed after ${i}*5s" >> "$LOG"
    break
  fi
  sleep 5
done

sleep 15

echo "  Calling action.sh..." >> "$LOG"
sh "$MODDIR/action.sh" >> "$LOG" 2>&1
echo "  action.sh exit: $?" >> "$LOG"

# Sprawdz wynik - jesli nie udalo sie, retry raz
STATE=$(cat /sys/class/udc/a600000.dwc3/state 2>/dev/null)
if [ "$STATE" != "configured" ]; then
  echo "  State is $STATE, retrying after 10s..." >> "$LOG"
  sleep 10
  sh "$MODDIR/action.sh" >> "$LOG" 2>&1
  echo "  Retry exit: $?" >> "$LOG"
fi

# === v3.0.5: auto-grant signature|privileged for pl.aowcloud.bridge ===
# App is installed as user-app (Android Studio Run) but cmd package grant succeeds
# for these permissions on this KSU-Next device, giving same effective access as priv-app.
echo "  === auto-grant Bridge permissions ===" >> "$LOG"
sleep 3
if pm path pl.aowcloud.bridge >/dev/null 2>&1; then
  cmd package grant pl.aowcloud.bridge android.permission.CAPTURE_AUDIO_OUTPUT 2>>"$LOG"
  echo "    grant CAPTURE_AUDIO_OUTPUT: $?" >> "$LOG"
  cmd package grant pl.aowcloud.bridge android.permission.MODIFY_PHONE_STATE 2>>"$LOG"
  echo "    grant MODIFY_PHONE_STATE: $?" >> "$LOG"
else
  echo "    pl.aowcloud.bridge NOT installed - skip grant" >> "$LOG"
  echo "    (zainstaluj przez Android Studio Run)" >> "$LOG"
fi

echo "=== service.sh DONE $(date) ===" >> "$LOG"
