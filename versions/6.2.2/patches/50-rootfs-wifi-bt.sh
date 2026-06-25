# 50-rootfs-wifi-bt.sh — RTL8852BU WiFi + Bluetooth.
#
# WHAT:  installs versions/<ver>/modules/*.ko into /lib/modules/<KVER>/updates,
#        the rtl8852bu_* firmware into /lib/firmware, the modprobe overlay (8852bu
#        options + `blacklist btusb`), renames the in-box btusb.ko -> btusb_bak when
#        rtk_btusb is shipped, then depmod. Mirrors the Unitree vendor image.
# WHY:   the onboard combo needs the out-of-tree 8852bu (WiFi) + rtk_btusb (BT); the
#        in-box btusb/btrtl can't load the 8852BU patch firmware. Autoload is via
#        udev modalias once depmod regenerates modules.alias — no modules-load.d.
# SKIP:  if modules/ has no .ko yet (driver still to be built on-device, then dropped
#        into versions/<ver>/modules/ + firmware/).
#
# Sourced by apply_patches() with $VDIR $LFT $JP $KVER $SUDO + helpers in scope.

_rfs="$LFT/rootfs"
if [ -n "$(find "$VDIR/modules" -name '*.ko' 2>/dev/null | head -1)" ]; then
    log "installing RTL8852BU WiFi/BT (modules + firmware + overlay)"
    $SUDO mkdir -p "$_rfs/lib/modules/$KVER/updates"
    $SUDO cp -a "$VDIR/modules/." "$_rfs/lib/modules/$KVER/updates/"
    $SUDO mkdir -p "$_rfs/lib/firmware"
    $SUDO cp -f "$VDIR"/firmware/* "$_rfs/lib/firmware/"
    $SUDO cp -a "$VDIR/overlay/." "$_rfs/"
    if find "$VDIR/modules" -name 'rtk_btusb.ko' 2>/dev/null | grep -q .; then
        _btko="$_rfs/lib/modules/$KVER/kernel/drivers/bluetooth/btusb.ko"
        if [ -f "$_btko" ]; then
            $SUDO mv -f "$_btko" "${_btko%.ko}_bak"
            log "  renamed btusb.ko -> btusb_bak"
        fi
    fi
    log "  depmod $KVER"
    $SUDO depmod -b "$_rfs" "$KVER"
else
    warn "no .ko in versions/$JP/modules — skipping WiFi/BT (compile on-device, then add them)"
fi
