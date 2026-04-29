#!/system/bin/sh
# AOWcloud UAC2 - install customization
# Sets proper permissions on installed module files

ui_print " "
ui_print "============================================"
ui_print " AOWcloud UAC2"
ui_print " USB Audio Class 2 + ADB composite gadget"
ui_print " by vTomsonek"
ui_print "============================================"
ui_print " "

# Set permissions on scripts
[ -f "$MODPATH/post-fs-data.sh" ] && chmod 755 "$MODPATH/post-fs-data.sh"
[ -f "$MODPATH/service.sh" ] && chmod 755 "$MODPATH/service.sh"
[ -f "$MODPATH/action.sh" ] && chmod 755 "$MODPATH/action.sh"
[ -f "$MODPATH/status.sh" ] && chmod 755 "$MODPATH/status.sh"
[ -f "$MODPATH/uninstall.sh" ] && chmod 755 "$MODPATH/uninstall.sh"

# Webroot
if [ -d "$MODPATH/webroot" ]; then
  chmod 755 "$MODPATH/webroot"
  [ -f "$MODPATH/webroot/index.html" ] && chmod 644 "$MODPATH/webroot/index.html"
fi

# Modules folder (kernel modules)
if [ -d "$MODPATH/modules" ]; then
  chmod 755 "$MODPATH/modules"
  [ -f "$MODPATH/modules/snd-aloop.ko" ] && chmod 644 "$MODPATH/modules/snd-aloop.ko"
fi

ui_print "Module installed successfully"
ui_print " "
ui_print "After reboot, UAC2 + ADB will auto-activate"
ui_print "in approximately 75 seconds."
ui_print " "
ui_print "Open KernelSU Manager > Modules > AOWcloud UAC2"
ui_print "to access the WebUI dashboard."
ui_print " "

# IMPORTANT: exit 0 explicitly
exit 0