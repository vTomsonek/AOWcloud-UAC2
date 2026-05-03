#!/system/bin/sh
# AOWcloud UAC2 v4.0.4 - post-fs-data
#
# What this does:
#   1. Loads snd-aloop kernel module (ALSA loopback for bridge classic mode).
#   2. Injects ALSA bridge daemon binary at /system/xbin/bridge.
#   3. Injects modified audio_policy_configuration.xml at
#      /vendor/etc/audio/sku_taro_qssi/ (voice_rx mixPort with maxOpenCount=2
#      maxActiveCount=2 - allows Bridge AND soundrecorder to capture voice
#      DOWNLINK simultaneously without race condition).
#   4. Restores SELinux contexts via restorecon after each bind.
#
# v4.0.4 (audio policy override - call-center mode trade-off): Bridge i system soundrecorder dziala
# rownolegle. Voice DOWNLINK leci do dwoch konsumentow przez voice_rx mixPort
# z maxActiveCount=2.

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
# $5 = SELinux context (default: system_file:s0; for /vendor use vendor_configs_file:s0)
bind_inject() {
  LABEL=$1
  SRC=$2
  TARGET=$3
  SIZE=$4
  CONTEXT=${5:-u:object_r:system_file:s0}
  TMPFS_DIR=/dev/aow_$LABEL

  if ! mountpoint -q "$TMPFS_DIR" 2>/dev/null; then
    mkdir -p "$TMPFS_DIR"
    mount -t tmpfs -o size="$SIZE",mode=755,context="$CONTEXT" \
      tmpfs "$TMPFS_DIR" 2>>"$LOG"
    echo "  tmpfs $TMPFS_DIR (ctx=$CONTEXT): $?" >> "$LOG"
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

# === 4. v4.0.3: SINGLE-FILE bind-mount dla audio_policy_configuration.xml ===
# Zamiast cp -ar 12 plikow + restorecon -R (cap'owanego przez init timeout)
# uzywamy bind --bind na pojedynczym pliku - milisekunda zamiast sekundy.
# Pattern: chcon source -> mount --bind source target

audio_policy_bind() {
  SKU=$1
  SRC="$MODDIR/vendor/etc/audio/$SKU/audio_policy_configuration.xml"
  TARGET="/vendor/etc/audio/$SKU/audio_policy_configuration.xml"

  if [ ! -f "$SRC" ]; then
    echo "  audio_policy_bind $SKU: source missing - $SRC" >> "$LOG"
    return 1
  fi

  # Set proper SELinux context na source (musi byc vendor_configs_file:s0)
  chcon u:object_r:vendor_configs_file:s0 "$SRC" 2>>"$LOG"

  # Single-file bind --bind (sec dla 1 pliku zamiast restorecon na 12)
  mount --bind "$SRC" "$TARGET" 2>>"$LOG"
  RC=$?
  echo "  audio_policy_bind $SKU: bind=$RC