#!/system/bin/sh
# AOWcloud UAC2 v3.0.5 - post-fs-data
#
# What this does:
#   1. Loads snd-aloop kernel module (UAC2 audio loopback).
#   2. Injects three things into RO /system via tmpfs + mount --bind:
#        a) /system/priv-app/AOWcloudBridge   (signature|privileged app)
#        b) /system/etc/permissions/...xml    (privapp-permissions whitelist)
#        c) /system/xbin/bridge               (ALSA bridge daemon binary)
#   3. Restores SELinux contexts via restorecon after each bind.
#
# Why bind-mount + tmpfs (not OverlayFS):
#   This Xiaomi 12 Pro kernel doesn't expose trusted.* xattr on /data (F2FS)
#   or /dev (tmpfs) and lacks userxattr (kernel <5.11). OverlayFS rejects
#   every fallback (EINVAL / "Operation not supported on transport endpoint").
#   Bind-mount over tmpfs hosting a full copy of the original /system path
#   plus our additions is the working pattern.

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

  # Copy original /system contents first (so SystemUI etc. are not lost on bind)
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

# === 3a. priv-app  (53 MB on this device, give tmpfs 128 MB) ===
PRIV_SRC="$MODDIR/system/priv-app"
if [ -d "$PRIV_SRC/AOWcloudBridge" ]; then
  bind_inject "priv_app" "$PRIV_SRC" "/system/priv-app" "128M"
fi

# === 3b. permissions XML  (120 KB on this device, 8 MB tmpfs) ===
PERM_SRC="$MODDIR/system/etc/permissions"
if [ -f "$PERM_SRC/privapp-permissions-pl.aowcloud.bridge.xml" ]; then
  bind_inject "perm" "$PERM_SRC" "/system/etc/permissions" "8M"
fi

# === 3c. xbin/bridge  (binary daemon, 16 MB tmpfs) ===
XBIN_SRC="$MODDIR/system/xbin"
if [ -f "$XBIN_SRC/bridge" ]; then
  bind_inject "xbin" "$XBIN_SRC" "/system/xbin" "16M"
  # Ensure bridge is executable with proper SELinux context after bind+restorecon
  chmod 755 /system/xbin/bridge 2>>"$LOG"
  chcon u:object_r:system_file:s0 /system/xbin/bridge 2>>"$LOG"
  echo "  bridge ready: $(ls -laZ /system/xbin/bridge 2>&1)" >> "$LOG"
fi

# === 4. Sanity ===
echo "  after priv-app: $(ls -laZ /system/priv-app/AOWcloudBridge/AOWcloudBridge.apk 2>&1)" >> "$LOG"
echo "  after perm:     $(ls -laZ /system/etc/permissions/privapp-permissions-pl.aowcloud.bridge.xml 2>&1)" >> "$LOG"
echo "  after xbin:     $(ls -laZ /system/xbin/bridge 2>&1)" >> "$LOG"

echo "=== post-fs-data.sh DONE $(date) ===" >> "$LOG"
