# 73-rootfs-ota-uploader.sh — install the on-device OTA uploader web service.
#
# WHAT:  copies ota-uploader/app.py -> /opt/unitree-ota-uploader/, the systemd unit ->
#        /etc/systemd/system/, creates the staging dir, and enables the unit (wants-symlink,
#        no chroot). The service (stdlib python3, already in the rootfs) is a web UI that pushes
#        an uploaded .upk through ota_pipe_cli addpackage/updatemodule.
# WHY:   keeps the vendor upgradePythonServer UX for installing modules on demand, backed by the
#        genuine per-module OTA path instead of "rm -rf /unitree; cp; install.sh". Users download
#        module .upk (incl. video_hub) from external hosting and upload them here.
# NOTE:  binds 0.0.0.0:8888; installing a .upk runs its Install steps as root.
#
# Sourced by apply_patches() with $HERE $LFT $SUDO + log/ok/warn/die in scope.

_rfs="$LFT/rootfs"
_src="$HERE/ota-uploader"

[ -f "$_src/app.py" ] || { warn "ota-uploader/app.py missing — skipping uploader"; return 0 2>/dev/null || true; }

log "installing unitree-ota-uploader service"
$SUDO install -D -m0755 "$_src/app.py" "$_rfs/opt/unitree-ota-uploader/app.py"
$SUDO install -D -m0644 "$_src/unitree-ota-uploader.service" \
      "$_rfs/etc/systemd/system/unitree-ota-uploader.service"
$SUDO mkdir -p "$_rfs/var/lib/unitree-ota-uploader/upk"

# enable at boot (multi-user.target.wants symlink — deterministic, no chroot)
$SUDO mkdir -p "$_rfs/etc/systemd/system/multi-user.target.wants"
$SUDO ln -sf ../unitree-ota-uploader.service \
      "$_rfs/etc/systemd/system/multi-user.target.wants/unitree-ota-uploader.service"
ok "OTA uploader installed + enabled (port 8888)"
