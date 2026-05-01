#!/system/bin/sh
# AOWcloud UAC2 v3.0.0 - install customization

ui_print " "
ui_print "============================================"
ui_print " AOWcloud UAC2 v3.0.0"
ui_print " UAC2 + ADB + Bridge priv-app"
ui_print " by vTomsonek"
ui_print "============================================"
ui_print " "

# Scripts
chmod 755 "$MODPATH"/*.sh

# WebUI
chmod 755 "$MODPATH/webroot"
chmod 644 "$MODPATH/webroot/index.html"

# Kernel module
chmod 755 "$MODPATH/modules"
chmod 644 "$MODPATH/modules/snd-aloop.ko"

# === v3.0.0: priv-app + permissions whitelist ===
if [ -d "$MODPATH/system/priv-app" ]; then
  chmod 755 "$MODPATH/system"
  chmod 755 "$MODPATH/system/priv-app"
  chmod 755 "$MODPATH/system/priv-app/AOWcloudBridge"
  chmod 644 "$MODPATH/system/priv-app/AOWcloudBridge/AOWcloudBridge.apk"
  ui_print "- priv-app AOWcloudBridge mounted"
fi

if [ -f "$MODPATH/system/etc/permissions/privapp-permissions-pl.aowcloud.bridge.xml" ]; then
  chmod 755 "$MODPATH/system/etc"
  chmod 755 "$MODPATH/system/etc/permissions"
  chmod 644 "$MODPATH/system/etc/permissions/privapp-permissions-pl.aowcloud.bridge.xml"
  ui_print "- privapp-permissions whitelist installed"
fi

# SELinux contexts (best-effort; Magisk/KSU normally fix this on overlay)
[ -x /system/bin/restorecon ] && /system/bin/restorecon -R "$MODPATH/system" 2>/dev/null

ui_print "- Permissions set"
ui_print " "
ui_print "Module installed successfully!"
ui_print " "
ui_print "REBOOT REQUIRED."
ui_print "After reboot:"
ui_print "  1. UAC2 + ADB activate in ~75s"
ui_print "  2. AOWcloud Bridge runs as system priv-app"
ui_print "     verify: dumpsys package pl.aowcloud.bridge | grep priv"
ui_print " "
ui_print "If pl.aowcloud.bridge was previously installed as a"
ui_print "user app, uninstall it first (signature mismatch):"
ui_print "  pm uninstall pl.aowcloud.bridge"
ui_print " "

exit 0
