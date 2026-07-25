# 70-rootfs-unitree-base.sh — install the Unitree PC4 base stack into the rootfs.
#
# WHAT:  fetch_verify the vendor bootstrap zip ($UNITREE_INSTALL_URL) from Unitree's CDN, then
#        install its payload into the rootfs the way the vendor `install` script would — copy
#        /unitree + /etc/init.d/{master_service,ota_pipe}, chown root, chmod +x the binaries, and
#        enable both SysV services (update-rc.d, run in the image). This bakes master_service +
#        ota_pipe + unitree_patch 1.0.0.2 so the board comes up supervised, with the OTA pipe
#        listening — ready for the uploader to push modules (video_hub, etc.).
# WHY:   an out-of-the-box Unitree stack with no post-flash bootstrap. Fetched (not vendored) so no
#        proprietary bytes live in the repo — same posture as the NVIDIA BSP download.
# NOTE:  we do NOT run the vendor `install` verbatim: its `service master_service restart` + `mscli
#        ls` wait are runtime ops that can't work in a build chroot. We reproduce only the
#        persistent bits; the services start normally on first boot. libcrypto.so.1.1 (needed by
#        master_service on 22.04/24.04) is handled by 71-rootfs-openssl-1.1.sh.
#
# Sourced by apply_patches() with: version.env ($UNITREE_INSTALL_URL/_SHA256, $DOWNLOADS) + $LFT
# $SUDO $JP and log/ok/warn/die + the _lib verbs (fetch_verify, in_image) in scope.

_rfs="$LFT/rootfs"
_zip="$DOWNLOADS/g1plus_pc4_unitree_install.zip"
_stage="$DOWNLOADS/unitree-base"

[ -n "${UNITREE_INSTALL_URL:-}" ] || die "UNITREE_INSTALL_URL not set in versions/$JP/version.env"
need unzip

if $SUDO test -x "$_rfs/unitree/module/master_service/master_service"; then
    warn "Unitree base already present in rootfs — skipping (clean bsp to reinstall)"
else
    fetch_verify "$UNITREE_INSTALL_URL" "${UNITREE_INSTALL_SHA256:-}" "$_zip"

    rm -rf "$_stage"; mkdir -p "$_stage"
    unzip -q "$_zip" -d "$_stage"
    _src="$(dirname "$(find "$_stage" -name install -maxdepth 3 -type f | head -1)")"
    [ -d "$_src/unitree" ] && [ -d "$_src/etc/init.d" ] || die "unexpected bootstrap layout under $_stage"

    log "installing Unitree base into rootfs (/unitree + init.d)"
    $SUDO cp -a "$_src/unitree" "$_rfs/unitree"
    $SUDO cp -a "$_src/etc/init.d/." "$_rfs/etc/init.d/"
    $SUDO chown -R root:root "$_rfs/unitree" "$_rfs/etc/init.d/master_service" "$_rfs/etc/init.d/ota_pipe"

    # executables the vendor install relies on (cp -a preserves modes, but be explicit)
    $SUDO chmod 0755 "$_rfs/etc/init.d/master_service" "$_rfs/etc/init.d/ota_pipe" \
                     "$_rfs/unitree/module/master_service/master_service" \
                     "$_rfs/unitree/sbin/mscli" "$_rfs/unitree/sbin/ota_pipe_cli" \
                     "$_rfs/unitree/sbin/start-stop-daemon" "$_rfs/unitree/bin/json_checker" 2>/dev/null || true
    [ -f "$_rfs/unitree/ota/pipe/ota_pipe_service" ] && \
        $SUDO chmod 0755 "$_rfs/unitree/ota/pipe/ota_pipe_service"

    # enable the SysV services (creates /etc/rc?.d symlinks from the LSB headers, in the image)
    log "  enabling master_service + ota_pipe (update-rc.d)"
    in_image update-rc.d master_service defaults >/dev/null || warn "update-rc.d master_service failed"
    in_image update-rc.d ota_pipe       defaults >/dev/null || warn "update-rc.d ota_pipe failed"

    _ver="$_rfs/unitree/robot/pkg/version/version.json"
    [ -f "$_ver" ] && log "  installed modules: $(tr -d ' \n' < "$_ver" | sed 's/.*Module"://;s/,"Package.*//')"
    ok "Unitree base stack installed"
fi
