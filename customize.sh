#!/system/bin/sh
# AOWcloud UAC2 - install customization
# Wykonywany przez KSU przy install zipa
# Ustawia uprawnienia + weryfikuje strukture

ui_print " "
ui_print "============================================"
ui_print " AOWcloud UAC2 - USB Audio Class 2 module"
ui_print "============================================"
ui_print " "

# Sprawdz device
ui_print "- Checking device compatibility..."
DEVICE=$(getprop ro.product.device)
if [ "$DEVICE" != "zeus" ]; then
  ui_print "  WARNING: Module designed for zeus (Xiaomi 12 Pro)"
  ui_print "  Your device: $DEVICE"
  ui_print "  Module may not work correctly"
else
  ui_print "  OK: Xiaomi 12 Pro (zeus) detected"
fi

# Sprawdz kernel
ui_print "- Checking kernel..."
KERNEL=$(uname -r)
ui_print "  $KERNEL"

# Sprawdz UAC2 function
if [ -d /config/usb_gadget/g1/functions/uac2.0 ]; then
  ui_print "  OK: UAC2 function available in kernel"
else
  ui_print "  WARNING: UAC2 function NOT found in kernel"
  ui_print "  Module requires CONFIG_USB_CONFIGFS_F_UAC2=y"
fi

# Set permissions
ui_print "- Setting permissions..."
chmod 755 "$MODPATH/post-fs-data.sh"
chmod 755 "$MODPATH/service.sh"
chmod 755 "$MODPATH/action.sh"
chmod 755 "$MODPATH/status.sh"
chmod 755 "$MODPATH/uninstall.sh"

# Webroot
if [ -d "$MODPATH/webroot" ]; then
  chmod 755 "$MODPATH/webroot"
  if [ -f "$MODPATH/webroot/index.html" ]; then
    chmod 644 "$MODPATH/webroot/index.html"
    ui_print "  OK: WebUI dashboard ready"
  else
    ui_print "  WARNING: webroot/index.html missing!"
  fi
fi

# Modules folder
if [ -f "$MODPATH/modules/snd-aloop.ko" ]; then
  ui_print "  OK: snd-aloop.ko found"
else
  ui_print "  WARNING: modules/snd-aloop.ko missing!"
fi

ui_print " "
ui_print "Installation complete!"
ui_print " "
ui_print "After reboot, the module will auto-activate"
ui_print "UAC2 + ADB after about 75 seconds."
ui_print " "
ui_print "Open KernelSU Manager > Modules > AOWcloud UAC2"
ui_print "to access the WebUI dashboard."
ui_print " "