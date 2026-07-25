# 71-rootfs-openssl-1.1.sh — provide OpenSSL 1.1 runtime libs (22.04/24.04 only).
#
# WHAT:  copies libcrypto.so.1.1 + libssl.so.1.1 (misc/openssl-1.1/aarch64) into the rootfs
#        /usr/lib/aarch64-linux-gnu and refreshes the linker cache (ldconfig -r, no chroot).
# WHY:   the Unitree binaries are built against OpenSSL 1.1 (JetPack 5.1 / 20.04). JetPack 6.2.2
#        (22.04) and 7.2 (24.04) ship only OpenSSL 3.0, so master_service dies at launch with
#        "libcrypto.so.1.1: cannot open shared object file". Additive — coexists with libcrypto.so.3.
# SKIP:  20.04 ships libssl1.1 by default, so 5.1.6 doesn't include this patch.
#
# Sourced by apply_patches() with $HERE $LFT $SUDO + log/ok/warn/die in scope.

_rfs="$LFT/rootfs"
_src="$HERE/misc/openssl-1.1/aarch64"
_dst="$_rfs/usr/lib/aarch64-linux-gnu"

if [ ! -f "$_src/libcrypto.so.1.1" ]; then
    warn "misc/openssl-1.1/aarch64/libcrypto.so.1.1 missing — skipping OpenSSL 1.1 shim"
else
    log "installing OpenSSL 1.1 libs (libcrypto/libssl.so.1.1)"
    $SUDO install -D -m0644 "$_src/libcrypto.so.1.1" "$_dst/libcrypto.so.1.1"
    $SUDO install -D -m0644 "$_src/libssl.so.1.1"    "$_dst/libssl.so.1.1"
    $SUDO ldconfig -r "$_rfs"
    ok "OpenSSL 1.1 shim installed"
fi
