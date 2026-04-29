#!/system/bin/sh
# Generuje JSON status do pliku

GADGET=/config/usb_gadget/g1
CONFIG=$GADGET/configs/b.1
OUT=/data/local/tmp/uac2_status.json

STATE=$(cat /sys/class/udc/a600000.dwc3/state 2>/dev/null || echo "unknown")
FUNCTION=$(cat /sys/class/udc/a600000.dwc3/function 2>/dev/null || echo "")
PID=$(cat $GADGET/idProduct 2>/dev/null || echo "")
VID=$(cat $GADGET/idVendor 2>/dev/null || echo "")
FUNCS=$(ls $CONFIG/ 2>/dev/null | tr "\n" "," | sed "s/,\$//")

HAS_UAC2="false"
HAS_ADB="false"
[ -L "$CONFIG/uac2.0" ] && HAS_UAC2="true"
[ -L "$CONFIG/ffs.adb" ] || [ -L "$CONFIG/f1" ] && HAS_ADB="true"

HAS_UAC2_CARD="false"
[ -d /proc/asound/UAC2Gadget ] && HAS_UAC2_CARD="true"

HAS_ALOOP="false"
lsmod | grep -q snd_aloop && HAS_ALOOP="true"

ALL_OK="false"
if [ "$STATE" = "configured" ] && [ "$PID" = "0x4ee5" ] && [ "$HAS_UAC2" = "true" ] && [ "$HAS_ADB" = "true" ]; then
  ALL_OK="true"
fi

# Zapisz JSON jednolinijkowy do pliku
printf "{\"state\":\"%s\",\"function\":\"%s\",\"vid\":\"%s\",\"pid\":\"%s\",\"functions\":\"%s\",\"has_uac2\":%s,\"has_adb\":%s,\"has_uac2_card\":%s,\"has_aloop\":%s,\"all_ok\":%s,\"timestamp\":\"%s\"}" \
  "$STATE" "$FUNCTION" "$VID" "$PID" "$FUNCS" \
  "$HAS_UAC2" "$HAS_ADB" "$HAS_UAC2_CARD" "$HAS_ALOOP" "$ALL_OK" "$(date)" > $OUT

# Wypisz tez na stdout (na wypadek bez pipe-a)
cat $OUT
