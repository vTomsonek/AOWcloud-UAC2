#!/system/bin/sh
MODDIR=${0%/*}
LOG=/data/local/tmp/uac2_callcenter.log

echo "=== post-fs-data.sh START $(date) ===" > "$LOG"

# Zaladuj snd-aloop
if ! lsmod | grep -q snd_aloop; then
  insmod "$MODDIR/modules/snd-aloop.ko" 2>>"$LOG"
  echo "  insmod snd-aloop: $?" >> "$LOG"
else
  echo "  snd-aloop already loaded" >> "$LOG"
fi

echo "=== post-fs-data.sh DONE $(date) ===" >> "$LOG"
