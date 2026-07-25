# versions/_lib/rootfs.sh — shared helpers for the rootfs patches.
#
# Sourced ONCE by apply_patches() before the patch loop, so every versions/<ver>/patches/*.sh
# can use these verbs. Kept here (not in g1_custom_jetpack.sh) so all rootfs machinery lives
# under versions/. Relies on the script's log/ok/warn/die + rootfs_unmount + $LFT $SUDO.
#
# The point of `in_image` is to run a command *as if on the booted device*: the build host is
# x86_64 but the rootfs is aarch64, so we register qemu, bind the kernel pseudo-fs, give it DNS,
# and chroot. Patches then read declaratively — `apt_install nvidia-l4t-gstreamer` — with none of
# that boilerplate. (Same mechanism NVIDIA's l4t_create_default_user.sh already uses.)

# in_image <cmd...> — run <cmd> inside the target rootfs (aarch64 under qemu). Kernel pseudo-fs
# are bind-mounted for the duration and unmounted after (rootfs_unmount), so 'Making system.img'
# never tars a live /proc. Returns the command's exit code.
in_image() {
    local rfs; rfs="$(readlink -f "$LFT/rootfs")"
    [ -d "$rfs" ] || die "in_image: no rootfs at $LFT/rootfs"

    local qemu; qemu="$(command -v qemu-aarch64-static)" \
        || die "in_image: qemu-aarch64-static not found — install qemu-user-static"
    $SUDO install -D -m0755 "$qemu" "$rfs/usr/bin/qemu-aarch64-static"

    # DNS so apt inside the chroot can reach the repos (resolv.conf is often a symlink -> replace it)
    $SUDO rm -f "$rfs/etc/resolv.conf"
    $SUDO cp -L /etc/resolv.conf "$rfs/etc/resolv.conf" 2>/dev/null || \
        printf 'nameserver 8.8.8.8\n' | $SUDO tee "$rfs/etc/resolv.conf" >/dev/null

    local m
    for m in proc sys dev dev/pts; do
        $SUDO mkdir -p "$rfs/$m"
        mountpoint -q "$rfs/$m" || $SUDO mount --bind "/$m" "$rfs/$m"
    done

    local rc=0
    $SUDO chroot "$rfs" /usr/bin/env -i \
        DEBIAN_FRONTEND=noninteractive \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        "$@" || rc=$?

    rootfs_unmount            # drop the binds before anything tars the rootfs
    $SUDO rm -f "$rfs/usr/bin/qemu-aarch64-static"
    return $rc
}

# apt_get <args...>      — run apt-get in the image (e.g. apt_get update)
# apt_install <pkgs...>  — apt-get update + install, inside the image
apt_get()     { in_image apt-get "$@"; }
apt_install() { in_image sh -c "apt-get update && apt-get install -y $*"; }

# fetch_verify <url> <sha256|''> <dest> — resumable download with an optional sha256 gate.
# Reuses a cached, already-verified file. Empty sha256 -> download but only warn (no gate).
fetch_verify() {
    local url="$1" sha="$2" dst="$3"
    need wget
    $SUDO true 2>/dev/null; mkdir -p "$(dirname "$dst")"
    if [ -f "$dst" ] && [ -n "$sha" ] && printf '%s  %s\n' "$sha" "$dst" | sha256sum -c --status 2>/dev/null; then
        log "cached + verified: $(basename "$dst")"; return 0
    fi
    log "downloading $(basename "$dst")"
    wget -c -O "$dst" "$url" || die "download failed: $url"
    if [ -n "$sha" ]; then
        printf '%s  %s\n' "$sha" "$dst" | sha256sum -c --status || die "sha256 mismatch: $(basename "$dst")"
        ok "verified $(basename "$dst")"
    else
        warn "no sha256 pinned for $(basename "$dst") — integrity not checked"
    fi
}
