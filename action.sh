#!/system/bin/sh
# Action: Activate UAC2 + ADB composite gadget
# PROVEN sequence with adbd restart

LOG=/data/local/tmp/uac2_action.log
GADGET=/config/usb_gadget/g1
CONFIG=$GADGET/configs/b.1

echo "=== ACTION RUN $(date) ===" >> "$LOG"

# === KROK 1: setprop none zwalnia UDC ===
setprop sys.usb.config none
sleep 3

# === KROK 2: Konfiguruj uac2.0 (jesli brak) ===
if [ ! -L "$CONFIG/uac2.0" ]; then
  echo 48000 > $GADGET/functions/uac2.0/c_srate
  echo 48000 > $GADGET/functions/uac2.0/p_srate
  echo 3 > $GADGET/functions/uac2.0/c_chmask
  echo 3 > $GADGET/functions/uac2.0/p_chmask
  echo 2 > $GADGET/functions/uac2.0/c_ssize
  echo 2 > $GADGET/functions/uac2.0/p_ssize
  
  cd $CONFIG
  ln -s ../../../../usb_gadget/g1/functions/uac2.0 uac2.0
  echo "  uac2.0 ln: $?" >> "$LOG"
fi

# === KROK 3: Dodaj ffs.adb (jesli brak) ===
if [ ! -L "$CONFIG/ffs.adb" ] && [ ! -L "$CONFIG/f1" ]; then
  cd $CONFIG
  ln -s ../../../../usb_gadget/g1/functions/ffs.adb ffs.adb
  echo "  ffs.adb ln: $?" >> "$LOG"
fi

# === KROK 4: Zmien idProduct (cache busting Windows) ===
echo 0x4ee5 > $GADGET/idProduct
echo "  idProduct: $(cat $GADGET/idProduct)" >> "$LOG"

# === KROK 5: KRYTYCZNE - restart adbd ===
# Bez tego kernel odmowi bind UDC bo ffs.adb nie ma descriptors
stop adbd
sleep 1
start adbd

# === KROK 6: Czekaj az adbd przygotuje descriptors ===
for i in 1 2 3 4 5 6 7 8 9 10; do
  if [ "$(getprop sys.usb.ffs.ready)" = "1" ]; then
    echo "  ffs.ready=1 after ${i}s" >> "$LOG"
    break
  fi
  sleep 1
done

# === KROK 7: Reczny bind UDC ===
echo "a600000.dwc3" > $GADGET/UDC
echo "  rebind: $?" >> "$LOG"
sleep 3

# === Status ===
STATE=$(cat /sys/class/udc/a600000.dwc3/state)
PID=$(cat $GADGET/idProduct)
FUNCS=$(ls $CONFIG/)

echo "  Final: state=$STATE PID=$PID" >> "$LOG"
echo "  Functions: $FUNCS" >> "$LOG"

echo "UAC2 + ADB ACTIVATED!"
echo "  PID: $PID"
echo "  State: $STATE"

echo "=== ACTION DONE $(date) ===" >> "$LOG"
