#!/system/bin/sh
# AOWcloud UAC2 - install customization

ui_print " "
ui_print "============================================"
ui_print " AOWcloud UAC2"
ui_print " USB Audio Class 2 + ADB composite gadget"
ui_print " by vTomsonek"
ui_print "============================================"
ui_print " "

# Set permissions
chmod 755 "$MODPATH"/*.sh
chmod 755 "$MODPATH/webroot"
chmod 644 "$MODPATH/webroot/index.html"
chmod 755 "$MODPATH/modules"
chmod 644 "$MODPATH/modules/snd-aloop.ko"

ui_print "- Permissions set"
ui_print " "
ui_print "Module installed successfully!"
ui_print " "
ui_print "After reboot, UAC2 + ADB will auto-activate"
ui_print "in approximately 75 seconds."
ui_print " "

exit 0