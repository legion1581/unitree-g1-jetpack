# 40-rootfs-static-ip.sh — static IP via a NetworkManager keyfile.
#
# WHAT:  writes /etc/NetworkManager/system-connections/unitree-static.nmconnection
#        binding $NET_IFACE to $STATIC_IP (manual). gateway/dns only if set.
# WHY:   this image uses NetworkManager (not netplan); the NIC is a point-to-point
#        LAN, so leaving gateway/dns empty avoids a competing default route.
# NOTE:  $NET_IFACE must match the booted name — the image boots net.ifnames=0, so
#        it is 'eth0' (see version.env), NOT the predictable enP8p1s0.
#
# Sourced by apply_patches() with version.env vars + $LFT $SUDO and helpers in scope.

_rfs="$LFT/rootfs"
log "static IP $STATIC_IP on $NET_IFACE (NetworkManager)"
_nm="$_rfs/etc/NetworkManager/system-connections/unitree-static.nmconnection"
$SUDO mkdir -p "$(dirname "$_nm")"
{
    printf '[connection]\nid=unitree-static\ntype=ethernet\ninterface-name=%s\nautoconnect=true\nautoconnect-priority=100\n\n' "$NET_IFACE"
    printf '[ipv4]\nmethod=manual\naddresses=%s\n' "$STATIC_IP"
    [ -n "${GATEWAY:-}" ] && printf 'gateway=%s\n' "$GATEWAY"
    [ -n "${DNS:-}" ]     && printf 'dns=%s\n' "$DNS"
    printf '\n[ipv6]\nmethod=ignore\n'
} | $SUDO tee "$_nm" >/dev/null
$SUDO chmod 600 "$_nm"; $SUDO chown root:root "$_nm"
