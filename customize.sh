#!/system/bin/sh
# AOWcloud UAC2 - install customization (debug version)

ui_print " "
ui_print "============================================"
ui_print " AOWcloud UAC2"
ui_print " USB Audio Class 2 + ADB composite gadget"
ui_print " by vTomsonek"
ui_print "============================================"
ui_print " "

# Debug - sprawdz zmienne
ui_print "DEBUG: MODPATH=$MODPATH"
ui_print "DEBUG: MODDIR=$MODDIR"
ui_print "DEBUG: TMPDIR=$TMPDIR"
ui_print "DEBUG: PATH=$PATH"

# Sprawdz co jest w MODPATH
if [ -n "$MODPATH" ] && [ -d "$MODPATH" ]; then
  ui_print "DEBUG: MODPATH content:"
  ls "$MODPATH" 2>&1 | while read line; do
    ui_print "  $line"
  done
fi

ui_print " "
ui_print "Module installed - manual permissions check needed"
ui_print " "

exit 0