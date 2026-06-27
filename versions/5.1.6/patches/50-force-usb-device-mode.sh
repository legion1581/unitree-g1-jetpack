# 50-force-usb-device-mode.sh — force the usb2-0 OTG port to USB *device* mode on boot.
#
# WHAT:  installs a tiny systemd oneshot that writes "device" to the usb2-0 role
#        switch after the L4T device-mode gadget service is up.
# WHY:   the carrier has no FUSB301/CC chip, so the usb2-0 OTG role never auto-
#        resolves — it defaults to "none" and the L4T gadget (RNDIS @ 192.168.55.1)
#        never binds. The DTB sets mode="peripheral" (hardware = device), but unlike
#        host mode (which needs no userspace), device mode needs the role driven to
#        "device" so nv-l4t-usb-device-mode binds the gadget. This unit does that.
# NOTE:  pairs with the dtb/ change (mode=peripheral, fusb301 dropped, usb3-0 off).
#
# Sourced by apply_patches() with version.env vars + $LFT $SUDO and helpers in scope.

_rfs="$LFT/rootfs"
log "force-usb-device-mode: install boot unit (no CC chip -> drive role=device)"

# the worker script
_sh="$_rfs/usr/sbin/force-usb-device-mode.sh"
$SUDO mkdir -p "$(dirname "$_sh")"
$SUDO tee "$_sh" >/dev/null <<'SH'
#!/bin/sh
# Carrier has no FUSB301/CC chip, so usb2-0's OTG role never auto-resolves.
# Force it to "device" so the L4T USB device-mode gadget (RNDIS @ 192.168.55.1) binds.
R=/sys/class/usb_role/usb2-0-role-switch/role
for i in $(seq 1 50); do [ -e "$R" ] && break; sleep 0.2; done
[ -e "$R" ] && echo device > "$R"
SH
$SUDO chmod 755 "$_sh"; $SUDO chown root:root "$_sh"

# the systemd unit
_unit="$_rfs/etc/systemd/system/force-usb-device-mode.service"
$SUDO tee "$_unit" >/dev/null <<'UNIT'
[Unit]
Description=Force usb2-0 OTG to USB device mode (no CC chip on carrier)
After=nv-l4t-usb-device-mode.service
Wants=nv-l4t-usb-device-mode.service

[Service]
Type=oneshot
ExecStart=/usr/sbin/force-usb-device-mode.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
UNIT
$SUDO chmod 644 "$_unit"; $SUDO chown root:root "$_unit"

# enable it (offline: drop the wants symlink directly)
_wants="$_rfs/etc/systemd/system/multi-user.target.wants"
$SUDO mkdir -p "$_wants"
$SUDO ln -sf ../force-usb-device-mode.service "$_wants/force-usb-device-mode.service"
