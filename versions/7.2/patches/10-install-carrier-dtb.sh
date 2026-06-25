# 10-install-carrier-dtb.sh — install the carrier-patched kernel DTB(s).
#
# WHAT:  copies versions/<ver>/dtb/<dtb> over the stock kernel/dtb/<dtb> (and the
#        bootloader/ copy that flash.sh signs from). DTB names come from $DTBS
#        (version.env).
# WHY:   the patched DTB corrects the G1 carrier's USB3 lane wiring (so recovery
#        RNDIS + the USB host ports work) and stamps a board-version string.
#
# Sourced by patch_bsp() with: $VDIR $JP $LFT $DTBS $SUDO and log()/die() in scope.

for _d in $DTBS; do
    [ -f "$VDIR/dtb/$_d" ] || die "missing DTB: versions/$JP/dtb/$_d"
    $SUDO cp -f "$VDIR/dtb/$_d" "$LFT/kernel/dtb/$_d"
    [ -f "$LFT/bootloader/$_d" ] && $SUDO cp -f "$VDIR/dtb/$_d" "$LFT/bootloader/$_d"
    log "  DTB <- $_d"
done
