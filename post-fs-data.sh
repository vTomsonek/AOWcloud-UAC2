#!/system/bin/sh
# AOWcloud UAC2 v3.1.0 - post-fs-data
#
# What this does:
#   1. Loads snd-aloop kernel module (ALSA loopback for bridge classic mode).
#   2. Injects ALSA bridge daemon binary at /system/xbin/bridge via
#      tmpfs + mount --bind (kernel doesn't support OverlayFS xattr).
#   3. Restores SELinux contexts via restorecon after bind.
#
# v3.1.0 (module-only): aplikacja AOWcloud Bridge jest osobno na
# github.com/vTomsonek/AOWcloud-Bridge (instalujesz przez Android Studio Run
# lub adb install). Module robi auto-grant signature permissions
# w service.sh jesli apka jest zainstalowana.
#
# Why bind-mount + tmpfs (not OverlayFS):
#   This Xiaomi 12 Pro kernel doesn't expose trusted.* xattr on /data (F2FS)
#   or /dev (tmpfs) and lacks userxattr (kernel <5.11). OverlayFS rejects
#   every fallback. Bind-mount over tmpfs is the working pattern.

MODDIR=${0%/*}
LOG=/data/local/tmp/uac2_callcenter.log

echo "=== post-fs-data.sh START $(date) ===" > "$LOG"

# === 1. snd-aloop ===
if ! lsmod | grep -q snd_aloop; then
  insmod "$MODDIR/modules/snd-aloop.ko" 2>>"$LOG"
  echo "  insmod snd-aloop: $?" >> "$LOG"
else
  echo "  snd-aloop already loaded" >> "$LOG"
fi

# === 2. Bind-mount helper ===
# $1 = label, $2 = source dir in module, $3 = system target dir, $4 = tmpfs size
bind_inject() {
  LABEL=$1
  SRC=$2
  TARGET=$3
  SIZE=$4
  TMPFS_DIR=/dev/aow_$LABEL

  if ! mountpoint -q "$TMPFS_DIR" 2>/dev/null; then
    mkdir -p "$TMPFS_DIR"
    mount -t tmpfs -o size="$SIZE",mode=755,context=u:object_r:system_file:s0 \
      tmpfs "$TMPFS_DIR" 2>>"$LOG"
    echo "  tmpfs $TMPFS_DIR: $?" >> "$LOG"
  fi

  # Copy original /system contents first (so other entries are not lost on bind)
  if [ -d "$TARGET" ]; then
    cp -ar "$TARGET/." "$TMPFS_DIR/" 2>>"$LOG"
    echo "  cp $TARGET -> $TMPFS_DIR: $?" >> "$LOG"
  fi

  # Overlay our additions on top
  cp -ar "$SRC/." "$TMPFS_DIR/" 2>>"$LOG"
  echo "  cp $SRC -> $TMPFS_DIR: $?" >> "$LOG"

  # Bind tmpfs over the target
  mkdir -p "$TARGET" 2>/dev/null
  mount --bind "$TMPFS_DIR" "$TARGET" 2>>"$LOG"
  RC=$?
  echo "  bind $TARGET: $RC" >> "$LOG"

  # Restore SELinux contexts using system policy
  if [ $RC -eq 0 ]; then
    restorecon -R "$TARGET" 2>>"$LOG"
    echo "  restorecon $TARGET: $?" >> "$LOG"
  fi

  return $RC
}

# === 3. xbin/bridge  (binary daemon, 16 MB tmpfs) ===
XBIN_SRC="$MODDIR/system/xbin"
if [ -f "$XBIN_SRC/bridge" ]; then
  bind_inject "xbin" "$XBIN_SRC" "/system/xbin" "16M"
  # Ensure bridge is executable with proper SELinux context after bind+restorecon
  chmod 755 /system/xbin/bridge 2>>"$LOG"
  chcon u:object_r:system_file:s0 /system/xbin/bridge 2>>"$LOG"
  echo "  bridge ready: $(ls -laZ /system/xbin/bridge 2>&1)" >> "$LOG"
fi

# === 4. Sanity ===
echo "  bridge in /system/xbin: $(ls -laZ /system/xbin/bridge 2>&1)" >> "$LOG"

echo "=== post-fs-data.sh DONE $(date) ===" >> "$LOG"
