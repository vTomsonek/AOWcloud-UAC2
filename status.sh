#!/system/bin/sh
# AOWcloud UAC2 v3.1.0 - status JSON
# Module-only release: app pl.aowcloud.bridge jest OPTIONAL
# (osobny pakiet: github.com/vTomsonek/AOWcloud-Bridge).
# Wykrywamy jej obecnosc, ale nie wymagamy w ALL_OK.

GADGET=/config/usb_gadget/g1
CONFIG=$GADGET/configs/b.1
OUT=/data/local/tmp/uac2_status.json

STATE=$(cat /sys/class/udc/a600000.dwc3/state 2>/dev/null || echo "unknown")
FUNCTION=$(cat /sys/class/udc/a600000.dwc3/function 2>/dev/null || echo "")
PID=$(cat $GADGET/idProduct 2>/dev/null || echo "")
VID=$(cat $GADGET/idVendor 2>/dev/null || echo "")
FUNCS=$(ls $CONFIG/ 2>/dev/null | tr "\n" "," | sed "s/,\$//")

HAS_UAC2="false"; HAS_ADB="false"
[ -L "$CONFIG/uac2.0" ] && HAS_UAC2="true"
[ -L "$CONFIG/ffs.adb" ] || [ -L "$CONFIG/f1" ] && HAS_ADB="true"

HAS_UAC2_CARD="false"
[ -d /proc/asound/UAC2Gadget ] && HAS_UAC2_CARD="true"

HAS_ALOOP="false"
lsmod | grep -q snd_aloop && HAS_ALOOP="true"

# Bridge App (user-app with auto-granted perms)
APP_INSTALLED="false"
APP_IS_PRIV="false"
APP_HAS_CAPTURE="false"
APP_HAS_MODIFY_PHONE="false"
APP_VERSION=""
APP_CODEPATH=""

if pm path pl.aowcloud.bridge >/dev/null 2>&1; then
  APP_INSTALLED="true"
  APP_CODEPATH=$(pm path pl.aowcloud.bridge | head -1 | sed 's/package://')

  PRIV_LINE=$(dumpsys package pl.aowcloud.bridge 2>/dev/null | grep -E "pkgFlags|privateFlags|PRIVILEGED" | head -3 | tr "\n" " ")
  echo "$PRIV_LINE" | grep -q "PRIVILEGED" && APP_IS_PRIV="true"

  # NOTE: granted=true line appears for each user; we accept any "granted=true"
  PERMS=$(dumpsys package pl.aowcloud.bridge 2>/dev/null | grep -E "android.permission.(CAPTURE_AUDIO_OUTPUT|MODIFY_PHONE_STATE):.*granted=true")
  echo "$PERMS" | grep -q "CAPTURE_AUDIO_OUTPUT" && APP_HAS_CAPTURE="true"
  echo "$PERMS" | grep -q "MODIFY_PHONE_STATE" && APP_HAS_MODIFY_PHONE="true"

  APP_VERSION=$(dumpsys package pl.aowcloud.bridge 2>/dev/null | grep -m1 "versionName=" | sed "s/.*versionName=//" | tr -d " ")
fi

# Bridge binary
BRIDGE_BINARY="missing"
BRIDGE_PATH="/system/xbin/bridge"
BRIDGE_PERMS=""
BRIDGE_CONTEXT=""
if [ -f "$BRIDGE_PATH" ]; then
  BRIDGE_PERMS=$(stat -c '%a' "$BRIDGE_PATH" 2>/dev/null)
  BRIDGE_CONTEXT=$(ls -lZ "$BRIDGE_PATH" 2>/dev/null | awk '{print $5}')
  if [ ! -x "$BRIDGE_PATH" ]; then
    BRIDGE_BINARY="bad_perms"
  elif [ -n "$BRIDGE_CONTEXT" ] && ! echo "$BRIDGE_CONTEXT" | grep -q "system_file:s0"; then
    BRIDGE_BINARY="bad_context"
  else
    BRIDGE_BINARY="ok"
  fi
fi

# v3.1.0: ALL_OK = UAC2 + ADB + bridge daemon. App jest OPTIONAL.
# Module sam zapewnia voice path infrastructure - app to client opt-in.
ALL_OK="false"
if [ "$STATE" = "configured" ] && [ "$PID" = "0x4ee5" ] && [ "$HAS_UAC2" = "true" ] && [ "$HAS_ADB" = "true" ] \
   && [ "$BRIDGE_BINARY" = "ok" ]; then
  ALL_OK="true"
fi

printf "{\"state\":\"%s\",\"function\":\"%s\",\"vid\":\"%s\",\"pid\":\"%s\",\"functions\":\"%s\",\"has_uac2\":%s,\"has_adb\":%s,\"has_uac2_card\":%s,\"has_aloop\":%s,\"app_installed\":%s,\"app_is_priv\":%s,\"app_has_capture\":%s,\"app_has_modify_phone\":%s,\"app_version\":\"%s\",\"app_codepath\":\"%s\",\"bridge_binary\":\"%s\",\"bridge_path\":\"%s\",\"bridge_perms\":\"%s\",\"bridge_context\":\"%s\",\"all_ok\":%s,\"timestamp\":\"%s\"}" \
  "$STATE" "$FUNCTION" "$VID" "$PID" "$FUNCS" \
  "$HAS_UAC2" "$HAS_ADB" "$HAS_UAC2_CARD" "$HAS_ALOOP" \
  "$APP_INSTALLED" "$APP_IS_PRIV" "$APP_HAS_CAPTURE" "$APP_HAS_MODIFY_PHONE" "$APP_VERSION" "$APP_CODEPATH" \
  "$BRIDGE_BINARY" "$BRIDGE_PATH" "$BRIDGE_PERMS" "$BRIDGE_CONTEXT" \
  "$ALL_OK" "$(date)" > $OUT

cat $OUT
