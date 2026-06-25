# 30-rootfs-user.sh — create the default login user, bypass oem-config.
#
# WHAT:  runs NVIDIA's l4t_create_default_user.sh (chroots via qemu) to make the
#        $USERNAME / $PASSWORD account, set hostname $HOSTNAME, optional autologin,
#        and accept the EULA — so first boot lands straight at a usable system.
# WHY:   without this the image boots into the interactive oem-config wizard.
#
# Sourced by apply_patches() with version.env vars + $LFT $SUDO and helpers in scope.

if [ -x "$LFT/tools/l4t_create_default_user.sh" ]; then
    _uargs=(-u "$USERNAME" -p "$PASSWORD" --accept-license)
    [ -n "${HOSTNAME:-}" ] && _uargs+=(-n "$HOSTNAME")
    case "${AUTOLOGIN:-}" in y|yes|true|1|on) _uargs+=(-a);; esac
    log "creating user '$USERNAME' (host=${HOSTNAME:-tegra-ubuntu}, autologin=${AUTOLOGIN:-no}, oem-config bypassed)"
    $SUDO "$LFT/tools/l4t_create_default_user.sh" "${_uargs[@]}" || die "user creation failed"
    rootfs_unmount   # belt-and-suspenders: never leave /proc bind-mounted under rootfs/
else
    warn "l4t_create_default_user.sh missing — skipping user setup"
fi
