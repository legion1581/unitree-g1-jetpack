#!/usr/bin/env bash
#
# g1_custom_jetpack.sh — build, back up, restore and flash a JetPack image for the
# Unitree G1 custom carrier board (Jetson Orin NX, p3767 on a p3768-class carrier).
#
#   ./g1_custom_jetpack.sh <command> [options]
#
# Commands:
#   init                 download + extract + patch a flash-ready BSP into ./bsp
#   flash [all|qspi]     flash via the recovery initrd (default: all = QSPI+NVMe)
#   backup  [dir]        back up every partition over the initrd (default: ./backups)
#   restore [dir]        restore a backup over the initrd        (default: ./backups)
#   status               show recovery state (APX / RNDIS)
#   clean [all|bsp|backup]   remove the extracted BSP and/or backups (keeps downloads)
#
# Options:
#   --yes           skip the confirmation prompt on destructive operations
#   -h, --help
#
# This repo is single-version: the JetPack version is whatever this branch ships
# (see version.env). Each JetPack lives on its own branch (6.2.2, 5.1.6, 7.2 ...).
# Patched **DTBs are distributed** (dtb/), not generated — no device-tree compiler
# or kernel-DTS surgery here.
#
# Layout (all under this repo root):
#   version.env                    URLs, board conf, kernel ver, user/IP
#   dtb/ firmware/ modules/ overlay/   the patch set applied to the BSP/rootfs
#   downloads/                     cached NVIDIA .tbz2 tarballs   (git-ignored)
#   bsp/Linux_for_Tegra            extracted + patched BSP        (git-ignored)
#
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\033[36m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[x]\033[0m %s\n' "$*" >&2; exit 1; }
c_grn(){ printf '\033[32m%s\033[0m' "$*"; }

usage() {
    sed -n '3,29p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# --- arg parsing -----------------------------------------------------------------
[ $# -ge 1 ] || usage 1
CMD="$1"; shift
YES=false; POS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --yes)     YES=true; shift;;
        -h|--help) usage 0;;
        *)         POS+=("$1"); shift;;
    esac
done
set -- "${POS[@]:-}"

case "$CMD" in -h|--help|help) usage 0;; esac

[ -f "$HERE/version.env" ] || die "missing version.env (are you on a version branch?)"
# shellcheck source=/dev/null
source "$HERE/version.env"

DOWNLOADS="$HERE/downloads"
BSP_PARENT="$HERE/bsp"
LFT="$BSP_PARENT/Linux_for_Tegra"
BACKUP_DIR="$HERE/backups"          # default backup/restore location (git-ignored)

SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"

need() { command -v "$1" >/dev/null || die "missing tool: $1"; }
confirm() {
    $YES && return 0
    printf '\033[33m%s\033[0m\n' "$1"
    read -r -p "Type 'yes' to continue: " a; [ "$a" = yes ] || die "aborted"
}

# unmount any pseudo-fs a chroot left under rootfs/ (symlink-safe). Without this,
# 'Making system.img' tars the live host /proc — incl. /proc/kcore — and overflows
# the image. (Learned the hard way.)
rootfs_unmount() {
    local rfs; rfs="$(readlink -f "$LFT/rootfs" 2>/dev/null || echo "$LFT/rootfs")"
    [ -d "$rfs" ] || return 0
    local m
    while read -r m; do
        [ -n "$m" ] || continue
        warn "unmounting stale mount under rootfs: $m"
        $SUDO umount -lf "$m" 2>/dev/null || true
    done < <(awk -v r="$rfs/" 'index($2, r)==1 {print $2}' /proc/mounts | sort -r)
    local still; still="$(awk -v r="$rfs/" 'index($2, r)==1 {print $2}' /proc/mounts)"
    [ -z "$still" ] || die "still mounted under rootfs: $still — unmount before continuing"
}

# ================================================================= init ==========
dl_verify() {  # $1 url  $2 dest — resumable download + 'is it really a tbz2?' check
    local url="$1" dst="$2"
    log "downloading $(basename "$dst")"
    wget -c -O "$dst" "$url" || die "download failed: $url"
    [ "$(head -c3 "$dst")" = "BZh" ] || die "not a valid .tbz2 (error page?): $dst"
}

cmd_init() {
    need wget; need tar; need rsync
    mkdir -p "$DOWNLOADS" "$BSP_PARENT"
    local bsp_tb="$DOWNLOADS/jetson_linux_r${L4T_VER}_aarch64.tbz2"
    local rfs_tb="$DOWNLOADS/sample_rootfs_r${L4T_VER}_aarch64.tbz2"

    # 1. download
    dl_verify "$BSP_URL" "$bsp_tb"
    dl_verify "$RFS_URL" "$rfs_tb"

    # 2. extract BSP + sample rootfs + apply_binaries
    if [ ! -d "$LFT" ]; then
        log "extracting BSP -> $LFT"
        tar xf "$bsp_tb" -C "$BSP_PARENT"
    else
        warn "BSP already extracted at $LFT (reusing; delete it to start clean)"
    fi
    log "extracting sample rootfs"
    $SUDO tar xpf "$rfs_tb" -C "$LFT/rootfs/"
    command -v qemu-aarch64-static >/dev/null 2>&1 || \
        { log "installing qemu-user-static (needed for apply_binaries on this host)"; $SUDO apt-get install -y qemu-user-static || true; }
    log "running apply_binaries.sh"
    ( cd "$LFT" && $SUDO ./apply_binaries.sh )

    # 3. BSP patches: drop in the patched DTBs + the MB2 boot fix
    patch_bsp

    # 4. rootfs: user, static IP, wifi/bt
    rootfs_customize

    ok "BSP ready: $LFT"
    echo "    next:  ./g1_custom_jetpack.sh flash all   (board in RCM)"
}

patch_bsp() {
    log "patching BSP (DTBs + MB2)"
    # 3a. distribute the patched kernel DTBs over the stock ones (kernel/dtb + the
    #     bootloader copy flash.sh signs from).
    local d
    for d in $DTBS; do
        [ -f "$HERE/dtb/$d" ] || die "missing shipped DTB: dtb/$d"
        $SUDO cp -f "$HERE/dtb/$d" "$LFT/kernel/dtb/$d"
        [ -f "$LFT/bootloader/$d" ] && $SUDO cp -f "$HERE/dtb/$d" "$LFT/bootloader/$d"
        log "  DTB <- $d"
    done
    # 3b. MB2 EEPROM boot fix: tell MB2 to read 0 bytes of carrier EEPROM (the
    #     custom carrier has none). This is a flashing BCT (.dts), not a kernel DTS.
    local f n=0
    while IFS= read -r f; do
        if grep -q 'cvb_eeprom_read_size = <0x0>;' "$f"; then continue; fi
        $SUDO sed -i 's/cvb_eeprom_read_size = <0x[0-9a-fA-F]*>;/cvb_eeprom_read_size = <0x0>;/' "$f"
        n=$((n+1))
    done < <(find "$LFT/bootloader" -maxdepth 3 -name 'tegra234-mb2-bct-misc-p3767-0000.dts' 2>/dev/null)
    log "  MB2 cvb_eeprom_read_size -> 0x0 ($n file(s))"
}

rootfs_customize() {
    local rfs="$LFT/rootfs"
    [ -d "$rfs" ] || die "no rootfs at $rfs"

    # 4a. default user + bypass oem-config (NVIDIA's tool; it chroots via qemu)
    if [ -x "$LFT/tools/l4t_create_default_user.sh" ]; then
        local uargs=(-u "$USERNAME" -p "$PASSWORD" --accept-license)
        [ -n "${HOSTNAME:-}" ] && uargs+=(-n "$HOSTNAME")
        case "${AUTOLOGIN:-}" in y|yes|true|1|on) uargs+=(-a);; esac
        log "creating user '$USERNAME' (host=${HOSTNAME:-tegra-ubuntu}, autologin=${AUTOLOGIN:-no}, oem-config bypassed)"
        $SUDO "$LFT/tools/l4t_create_default_user.sh" "${uargs[@]}" || die "user creation failed"
        rootfs_unmount   # belt-and-suspenders: never leave /proc bind-mounted
    else
        warn "l4t_create_default_user.sh missing — skipping user setup"
    fi

    # 4b. static IP via a NetworkManager keyfile (this image uses NM, not netplan).
    #     gateway/dns are optional — this NIC is usually a point-to-point LAN, so
    #     leaving them empty avoids a competing default route (internet via WiFi).
    log "static IP $STATIC_IP on $NET_IFACE (NetworkManager)"
    local nm="$rfs/etc/NetworkManager/system-connections/unitree-static.nmconnection"
    $SUDO mkdir -p "$(dirname "$nm")"
    {
        printf '[connection]\nid=unitree-static\ntype=ethernet\ninterface-name=%s\nautoconnect=true\nautoconnect-priority=100\n\n' "$NET_IFACE"
        printf '[ipv4]\nmethod=manual\naddresses=%s\n' "$STATIC_IP"
        [ -n "${GATEWAY:-}" ] && printf 'gateway=%s\n' "$GATEWAY"
        [ -n "${DNS:-}" ]     && printf 'dns=%s\n' "$DNS"
        printf '\n[ipv6]\nmethod=ignore\n'
    } | $SUDO tee "$nm" >/dev/null
    $SUDO chmod 600 "$nm"; $SUDO chown root:root "$nm"

    # 4c. WiFi + BT: prebuilt modules + firmware + autoload/blacklist overlay
    log "installing RTL8852BU WiFi/BT (modules + firmware + overlay)"
    $SUDO mkdir -p "$rfs/lib/modules/$KVER/updates"
    $SUDO cp -a "$HERE/modules/." "$rfs/lib/modules/$KVER/updates/"
    $SUDO mkdir -p "$rfs/lib/firmware"
    $SUDO cp -f "$HERE"/firmware/* "$rfs/lib/firmware/"
    $SUDO cp -a "$HERE/overlay/." "$rfs/"
    log "  depmod $KVER"
    $SUDO depmod -b "$rfs" "$KVER"

    # 4d. user-home overlay: home/ maps onto /home/$USERNAME (username from version.env,
    #     not hardcoded). The copy is root-owned, so hand the home back to the login
    #     user afterwards (first user = uid/gid 1000). e.g. home/Desktop/RoboLegion/*.deb
    if [ -d "$HERE/home" ] && [ -n "$(ls -A "$HERE/home" 2>/dev/null)" ]; then
        log "deploying home/ overlay to ${USERNAME}'s home"
        $SUDO mkdir -p "$rfs/home/$USERNAME"
        $SUDO cp -a "$HERE/home/." "$rfs/home/$USERNAME/"
        $SUDO chown -R 1000:1000 "$rfs/home/$USERNAME"
    fi
}

# ============================================================ backup/restore =====
BR="$LFT/tools/backup_restore"
cmd_backup() {
    local dir="${1:-$BACKUP_DIR}"
    [ -d "$LFT" ] || die "no BSP — run 'init' first"
    [ -x "$BR/l4t_backup_restore.sh" ] || die "no backup_restore tooling in BSP"
    [ -d "$dir" ] && [ -n "$(ls -A "$dir" 2>/dev/null)" ] && warn "backup dir not empty — existing images may be overwritten: $dir"
    recovery_note
    confirm "Back up the board (RCM) into $dir ?"
    rootfs_unmount
    mkdir -p "$dir"
    ( cd "$LFT" && $SUDO ./tools/backup_restore/l4t_backup_restore.sh \
        --network usb0 -e nvme0n1 -b "$BOARD_CONF" )
    log "moving images -> $dir"
    $SUDO mv "$BR/images/"* "$dir/" 2>/dev/null || true
    ok "backup saved to $dir"
}
cmd_restore() {
    local dir="${1:-$BACKUP_DIR}"
    [ -d "$dir" ] || die "backup dir not found: $dir (run 'backup' first, or pass a dir)"
    [ -f "$dir/nvpartitionmap.txt" ] || die "not a backup folder (no nvpartitionmap.txt): $dir"
    [ -x "$BR/l4t_backup_restore.sh" ] || die "no backup_restore tooling — run 'init' first"
    recovery_note
    confirm "DESTRUCTIVE: restore '$dir' onto the board (erases QSPI + NVMe)?"
    rootfs_unmount
    # The initrd reads the images over NFS from the BSP's images/ dir, so they must
    # be REAL files there — symlinks to another filesystem won't resolve in the
    # initrd. Stage a copy in (freed afterwards).
    log "staging backup into the BSP images/ (~9 GB copy)…"
    $SUDO rm -rf "$BR/images"; $SUDO mkdir -p "$BR/images"
    $SUDO cp -a "$dir/." "$BR/images/"
    $SUDO rm -rf "$BR/images/tmp"          # backup tool leftover, not a partition image
    ( cd "$LFT" && $SUDO ./tools/backup_restore/l4t_backup_restore.sh \
        --network usb0 -e nvme0n1 -r "$BOARD_CONF" )
    $SUDO rm -rf "$BR/images"              # free the staging copy on success
    ok "restore complete"
}

# ================================================================= flash =========
cmd_flash() {
    local what="${1:-all}"
    [ -d "$LFT" ] || die "no BSP — run 'init' first"
    case "$what" in all|qspi) ;; *) die "flash takes 'all' or 'qspi'";; esac
    recovery_note
    confirm "DESTRUCTIVE: flash '$what' to the board from $LFT ?"
    rootfs_unmount
    if [ "$what" = all ]; then
        log "full flash (QSPI + NVMe rootfs) via initrd"
        ( cd "$LFT" && $SUDO ./tools/kernel_flash/l4t_initrd_flash.sh \
            --external-device "$ROOT_DEV" \
            -c "$NVME_XML" \
            -p "-c $QSPI_CFG --no-systemimg" \
            --showlogs --network usb0 "$BOARD_CONF" internal )
    else
        log "QSPI-only flash (bootloader/firmware; rootfs untouched)"
        ( cd "$LFT" && $SUDO ./tools/kernel_flash/l4t_initrd_flash.sh \
            -c "$QSPI_CFG" \
            --showlogs --network usb0 "$BOARD_CONF" internal )
    fi
    ok "flash '$what' complete"
}

# ================================================================ status =========
recovery_note() {
    warn "Board must be in RECOVERY (RCM) mode with the USB-C flashing cable connected."
}
cmd_status() {
    # Detect recovery state purely from the USB device list:
    #   0955:7023 / 0955:7323  "APX"             -> bootROM recovery (ready to flash)
    #   0955:7035              "Linux for Tegra" -> recovery initrd up (RNDIS device-mode)
    local dev bus dnum vidpid desc
    dev="$(lsusb 2>/dev/null | grep -iE 'ID 0955:[0-9a-f]{4}' | head -1 || true)"

    local B='\033[1m' G='\033[32m' Y='\033[33m' DIM='\033[2m' R='\033[0m'
    local bar="  ────────────────────────────────────────────────────────"
    printf '\n  %bJetson recovery status%b\n%s\n' "$B" "$R" "$bar"

    if [ -z "$dev" ]; then
        printf '  %-9s %bnot in recovery%b — no 0955:* device on the bus\n' "state" "$Y" "$R"
        printf '  %-9s hold FORCE_RECOVERY, (re)apply power, connect the USB-C\n' "next"
        printf '  %-9s flashing cable, then re-run: %bstatus%b\n%s\n\n' "" "$B" "$R" "$bar"
        return
    fi

    bus="$(awk '{print $2}' <<<"$dev")"
    dnum="$(awk '{print $4}' <<<"$dev" | tr -d ':')"
    vidpid="$(awk '{print $6}' <<<"$dev")"
    desc="$(sed -E 's/^.*ID [0-9a-fA-F:]+ //' <<<"$dev")"

    if grep -qiE 'Linux for Tegra|0955:7035' <<<"$dev"; then
        printf '  %-9s %b● RNDIS — recovery initrd running%b\n' "state" "$G" "$R"
        printf '  %-9s %s  %s  %b(bus %s / dev %s)%b\n' "device" "$vidpid" "$desc" "$DIM" "$bus" "$dnum" "$R"
        printf '  %-9s a backup / restore / flash is in progress\n' "meaning"
        printf '  %-9s wait for it to finish — or  %bssh root@192.168.55.1%b\n' "next" "$B" "$R"
    elif grep -qi 'APX' <<<"$dev"; then
        printf '  %-9s %b● APX — bootROM recovery (ready)%b\n' "state" "$G" "$R"
        printf '  %-9s %s  %s  %b(bus %s / dev %s)%b\n' "device" "$vidpid" "$desc" "$DIM" "$bus" "$dnum" "$R"
        printf '  %-9s run  %b./g1_custom_jetpack.sh  flash | backup | restore%b\n' "next" "$B" "$R"
    else
        printf '  %-9s %b● NVIDIA recovery device%b (unrecognized PID)\n' "state" "$Y" "$R"
        printf '  %-9s %s  %s  %b(bus %s / dev %s)%b\n' "device" "$vidpid" "$desc" "$DIM" "$bus" "$dnum" "$R"
        printf '  %-9s treat as bootROM recovery; flash/backup/restore should work\n' "next"
    fi
    printf '%s\n\n' "$bar"
}

# ================================================================= clean =========
cmd_clean() {
    local what="${1:-}"
    case "$what" in all|bsp|backup) ;; *) die "clean takes 'all', 'bsp' or 'backup'";; esac
    if [ "$what" = bsp ] || [ "$what" = all ]; then
        rootfs_unmount                       # drop any leftover bind-mounts before rm
        if [ -d "$BSP_PARENT" ]; then
            log "removing BSP tree: $BSP_PARENT"
            $SUDO rm -rf "$BSP_PARENT"
        else log "no BSP tree to remove"; fi
    fi
    if [ "$what" = backup ] || [ "$what" = all ]; then
        if [ -d "$BACKUP_DIR" ] && [ -n "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
            log "removing backups: $BACKUP_DIR"
            $SUDO rm -rf "$BACKUP_DIR"
        else log "no backups to remove"; fi
    fi
    ok "clean ($what) done"
    [ "$what" = all ] && echo "    (downloads/ cache kept — remove it by hand to force a re-download)"
}

# --- dispatch --------------------------------------------------------------------
case "$CMD" in
    init)     cmd_init ;;
    flash)    cmd_flash "${1:-all}" ;;
    backup)   cmd_backup "${1:-}" ;;
    restore)  cmd_restore "${1:-}" ;;
    status)   cmd_status ;;
    clean)    cmd_clean "${1:-}" ;;
    *)        die "unknown command: $CMD (try --help)" ;;
esac
