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

# Tylko 15 sek po boot_completed (probowalismy 30, dziala wiec moze mniej)
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

echo "=== service.sh DONE $(date) ===" >> "$LOG"
