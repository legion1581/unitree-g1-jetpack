# 30-rootfs-user.sh — create the default login user, bypass oem-config.
#
# WHAT:  runs NVIDIA's l4t_create_default_user.sh (chroots via qemu) to make the
#        $USERNAME / $PASSWORD account, set hostname $HOSTNAME, optional autologin,
#        and accept the EULA — so first boot lands straight at a usable system.
# WHY:   without this the image boots into the interactive oem-config wizard.
# IDEMPOTENT: if the user already exists in the rootfs (re-applied patches), warn and
#        skip instead of failing — but a genuine creation error still aborts (so we
#        never ship an image with no user). To truly recreate, build on a clean BSP.
#
# Sourced by apply_patches() with version.env vars + $LFT $SUDO and helpers in scope.

if $SUDO grep -q "^$USERNAME:" "$LFT/rootfs/etc/passwd" 2>/dev/null; then
    warn "user '$USERNAME' already exists in the rootfs — skipping user creation"
elif [ -x "$LFT/tools/l4t_create_default_user.sh" ]; then
    _uargs=(-u "$USERNAME" -p "$PASSWORD" --accept-license)
    [ -n "${HOSTNAME:-}" ] && _uargs+=(-n "$HOSTNAME")
    case "${AUTOLOGIN:-}" in y|yes|true|1|on) _uargs+=(-a);; esac
    log "creating user '$USERNAME' (host=${HOSTNAME:-tegra-ubuntu}, autologin=${AUTOLOGIN:-no}, oem-config bypassed)"
    $SUDO "$LFT/tools/l4t_create_default_user.sh" "${_uargs[@]}" || die "user creation failed"
    rootfs_unmount   # belt-and-suspenders: never leave /proc bind-mounted under rootfs/
else
    warn "l4t_create_default_user.sh missing — skipping user setup"
fi
