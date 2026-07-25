# 72-rootfs-gstreamer.sh — L4T hardware GStreamer plugins, baked from a pinned .deb.
#
# WHAT:  fetch_verify the nvidia-l4t-gstreamer .deb ($NVIDIA_GST_DEB_URL, pinned + SHA in
#        version.env) and dpkg -i it in the image. Provides nvvidconv / nvv4l2h264enc / nvjpegenc
#        (libgstnvvidconv.so, libgstnvvideo4linux2.so, libgstnvjpeg.so).
# WHY:   video_hub_pc4's pipeline hard-codes those elements; a minimal image doesn't ship them.
#        We bake the EXACT .deb (not `apt install`) so the build is reproducible and needs no
#        build-time apt run / reachable in-image nvidia apt source — same posture as the BSP and
#        Unitree-base downloads. nvidia-l4t-gstreamer's only deps are base Ubuntu libs already in
#        the rootfs (libdrm2, libegl1, libgles2, libglib2.0-0t64, …), so dpkg -i needs no apt
#        dependency resolution.
# SKIP:  JetPack 5.1 / 20.04 ships these with the L4T BSP, so 5.1.6 doesn't include this patch.
#
# Sourced by apply_patches() with version.env ($NVIDIA_GST_DEB_URL/_SHA256, $DOWNLOADS) + $LFT
# $SUDO $JP + log/ok/warn/die + the _lib verbs (fetch_verify, in_image) in scope.

_rfs="$LFT/rootfs"
_deb="$DOWNLOADS/nvidia-l4t-gstreamer-$JP.deb"

if in_image sh -c 'command -v gst-inspect-1.0 >/dev/null && gst-inspect-1.0 nvv4l2h264enc >/dev/null 2>&1'; then
    warn "nvv4l2h264enc already present — skipping nvidia-l4t-gstreamer"
else
    [ -n "${NVIDIA_GST_DEB_URL:-}" ] || die "NVIDIA_GST_DEB_URL not set in versions/$JP/version.env"
    fetch_verify "$NVIDIA_GST_DEB_URL" "${NVIDIA_GST_DEB_SHA256:-}" "$_deb"
    log "installing nvidia-l4t-gstreamer from pinned .deb (nvvidconv/nvv4l2h264enc/nvjpegenc)"
    $SUDO install -D -m0644 "$_deb" "$_rfs/tmp/nvidia-l4t-gstreamer.deb"
    in_image dpkg -i /tmp/nvidia-l4t-gstreamer.deb || die "dpkg -i nvidia-l4t-gstreamer failed (deps missing?)"
    $SUDO rm -f "$_rfs/tmp/nvidia-l4t-gstreamer.deb"
    ok "L4T GStreamer plugins installed (pinned .deb)"
fi
