#!/system/bin/sh
# AOWcloud UAC2 v5.3.0 - post-fs-data
#
# What this does:
#   1. Loads snd-aloop kernel module (ALSA loopback for bridge classic mode).
#   2. Injects ALSA bridge daemon binary at /system/xbin/bridge.
#   3. Injects modified audio_policy_configuration.xml at
#      /vendor/etc/audio/sku_taro{,_qssi}/ (voice_rx mixPort with maxOpenCount=2
#      maxActiveCount=2 - opens audio policy gate dla 2 voice DL clients).
#   4. v5.3.0 SURGICAL PATCH: Injects binary-patched libaudioflingerimpl.so at
#      /system_ext/lib64/. 4 funkcje isSilenced patched zeby ZAWSZE zwracaly 0:
#         - RecordTrack::isSilenced @ 0x0020a0e0  (ldrb -> mov w0, #0)
#         - virtual thunk RecordTrack::isSilenced @ 0x0020ff74
#         - MmapTrack::isSilenced_l @ 0x00210910
#         - non-virtual thunk MmapTrack::isSilenced_l @ 0x00210944
#      W RecordThread::threadLoop: jezeli isSilenced=true, memset(buffer, 0).
#      Po patchu isSilenced ZAWSZE zwraca 0 -> memset NIE wykonuje sie ->
#      drugi klient voice DL dostaje real samples (zamiast zer).
#      Audio policy state NIE jest zmienione (vs. odrzucone v5.0.0/v5.2.0
#      ktore patchowaly setRecordSilenced/allowConcurrentApp).
#   5. Restores SELinux contexts via restorecon after each bind.
#
# v5.3.0: Bridge AND HyperOS soundrecorder dziala rownolegle w kazdej rozmowie.
# Patch jest precyzyjny - zmienia tylko field READ (mSilenced), nie state setting.

MODDIR=${0%/*}
LOG=/data/local/tmp/uac2_callcenter.log

echo "=== post-fs-data.sh v5.3.0 START $(date) ===" > "$LOG"

# === 1. snd-aloop ===
if ! lsmod | grep -q snd_aloop; then
  insmod "$MODDIR/modules/snd-aloop.ko" 2>>"$LOG"
  echo "  insmod snd-aloop: $?" >> "$LOG"
else
  echo "  snd-aloop already loaded" >> "$LOG"
fi

# === 2. Bind-mount helper for /system overlay (tmpfs + cp -ar) ===
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

  if [ -d "$TARGET" ]; then
    cp -ar "$TARGET/." "$TMPFS_DIR/" 2>>"$LOG"
    echo "  cp $TARGET -> $TMPFS_DIR: $?" >> "$LOG"
  fi

  cp -ar "$SRC/." "$TMPFS_DIR/" 2>>"$LOG"
  echo "  cp $SRC -> $TMPFS_DIR: $?" >> "$LOG"

  mkdir -p "$TARGET" 2>/dev/null
  mount --bind "$TMPFS_DIR" "$TARGET" 2>>"$LOG"
  RC=$?
  echo "  bind $TARGET: $RC" >> "$LOG"

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
  chmod 755 /system/xbin/bridge 2>>"$LOG"
  chcon u:object_r:system_file:s0 /system/xbin/bridge 2>>"$LOG"
  echo "  bridge ready: $(ls -laZ /system/xbin/bridge 2>&1)" >> "$LOG"
fi

# === 4a. SINGLE-FILE bind-mount audio_policy_configuration.xml (oba SKU) ===
audio_policy_bind() {
  SKU=$1
  SRC="$MODDIR/vendor/etc/audio/$SKU/audio_policy_configuration.xml"
  TARGET="/vendor/etc/audio/$SKU/audio_policy_configuration.xml"

  if [ ! -f "$SRC" ]; then
    echo "  audio_policy_bind $SKU: source missing - $SRC" >> "$LOG"
    return 1
  fi

  chcon u:object_r:vendor_configs_file:s0 "$SRC" 2>>"$LOG"
  mount --bind "$SRC" "$TARGET" 2>>"$LOG"
  RC=$?
  echo "  audio_policy_bind $SKU: bind=$RC, file=$(ls -laZ $TARGET 2>&1)" >> "$LOG"
  return $RC
}

audio_policy_bind sku_taro
audio_policy_bind sku_taro_qssi

# === 4b. v5.3.0: bind-mount patched libaudioflingerimpl.so ===
# 4 funkcje isSilenced zpatchowane na "mov w0, #0" (always return false).
# RecordThread::threadLoop nie wykonuje memset(0) -> drugi klient dostaje samples.
# Source patched MD5: 443AE80F4709BA9759F5B6867DC6545E
# Original MD5:       42E1FC0CA05999EC9964ACCE68D15BE8

audio_libaf_bind() {
  SRC="$MODDIR/system_ext/lib64/libaudioflingerimpl.so"
  TARGET="/system_ext/lib64/libaudioflingerimpl.so"

  if [ ! -f "$SRC" ]; then
    echo "  audio_libaf_bind: source missing - $SRC" >> "$LOG"
    return 1
  fi

  # SELinux context: system_lib_file:s0 (zgodnie z oryginalem)
  chcon u:object_r:system_lib_file:s0 "$SRC" 2>>"$LOG"

  mount --bind "$SRC" "$TARGET" 2>>"$LOG"
  RC=$?
  echo "  audio_libaf_bind: bind=$RC, file=$(ls -laZ $TARGET 2>&1)" >> "$LOG"
  return $RC
}

audio_libaf_bind

# Restart audioserver zeby zaladowal patched libaudioflingerimpl
echo "  killing audioserver to reload patched libaf..." >> "$LOG"
killall -9 audioserver 2>>"$LOG"
echo "  audioserver killed (init will respawn): $?" >> "$LOG"

# === 5. Sanity ===
echo "  bridge in /system/xbin: $(ls -laZ /system/xbin/bridge 2>&1)" >> "$LOG"
echo "  audio_policy taro: $(ls -la /vendor/etc/audio/sku_taro/audio_policy_configuration.xml 2>&1)" >> "$LOG"
echo "  audio_policy qssi: $(ls -la /vendor/etc/audio/sku_taro_qssi/audio_policy_configuration.xml 2>&1)" >> "$LOG"
echo "  libaf patched:     $(ls -laZ /system_ext/lib64/libaudioflingerimpl.so 2>&1)" >> "$LOG"

echo "=== post-fs-data.sh v5.3.0 DONE $(date) ===" >> "$LOG"
