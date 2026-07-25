# 74-rootfs-cyclonedds.sh — CycloneDDS runtime lib (libddsc.so.0) for video_hub.
#
# WHAT:  installs libddsc.so.0 (misc/cyclonedds/aarch64) into /usr/lib/aarch64-linux-gnu and
#        refreshes the linker cache (ldconfig -r, no chroot).
# WHY:   video_hub_pc4 links libddsc.so.0 (the Unitree stack uses Eclipse CycloneDDS for its DDS
#        topics). Neither the base install nor the video_hub .upk ships it, and a clean NVIDIA
#        rootfs doesn't have it — so video_hub dies at launch with "libddsc.so.0: cannot open
#        shared object file". On a real robot CycloneDDS is present from the vendor SDK image; our
#        minimal image must provide it, same as nvidia-l4t-gstreamer (72).
# NOTE:  verified live on 7.2 — with libddsc + eth0 (80) + the L4T gstreamer plugins (72), video_hub
#        runs and streams (multicast 230.1.1.1 on eth0). lib is Eclipse CycloneDDS (EPL-2.0/EDL-1.0,
#        redistributable); only deps are libc/libpthread/libdl. Every JetPack needs it (it's not on
#        the stock rootfs); 5.1.6 Phase 3 confirms the 20.04 image doesn't already carry it.
#
# Sourced by apply_patches() with $HERE $LFT $SUDO + log/ok/warn in scope.

_rfs="$LFT/rootfs"
_src="$HERE/misc/cyclonedds/aarch64/libddsc.so.0"

if [ ! -f "$_src" ]; then
    warn "misc/cyclonedds/aarch64/libddsc.so.0 missing — video_hub won't start without it"
else
    log "installing CycloneDDS runtime (libddsc.so.0)"
    $SUDO install -D -m0644 "$_src" "$_rfs/usr/lib/aarch64-linux-gnu/libddsc.so.0"
    $SUDO ldconfig -r "$_rfs"
    ok "CycloneDDS lib installed"
fi
