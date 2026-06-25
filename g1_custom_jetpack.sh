#!/usr/bin/env bash
#
# g1_custom_jetpack.sh — build, back up, restore and flash a JetPack image for the
# Unitree G1 custom carrier board (Jetson Orin NX, p3767 on a p3768-class carrier).
#
#   ./g1_custom_jetpack.sh [-j <ver>] <command> [args]
#
# JetPack version:
#   -j, --jetpack <ver>   which JetPack to act on. Each lives under versions/<ver>/.
#                         Defaults come from ./.env (DEFAULT_JP for init/flash/clean,
#                         BACKUP_JP for backup/restore).  (env: G1_JP=<ver> also works.)
#                         e.g.  -j 5.1.6   |   -j 6.2.2
#
# Commands:
#   init                 download + extract + patch a flash-ready BSP into bsp/<ver>
#   flash [all|qspi]     flash the chosen JetPack (auto-runs init if needed)
#   backup  [name|dir]   back up every partition over the initrd, into a timestamped,
#                        version-tagged folder under backups/ (auto-runs init)
#   restore [name|dir]   restore a backup over the initrd (auto-runs init). With no
#                        arg, picks from backups/ (menu if more than one).
#   status               show recovery state (APX / RNDIS) — version-independent
#   clean [all|bsp|backup]   remove this version's BSP and/or ALL backups (keeps downloads)
#
# Options:
#   --yes           skip the confirmation prompt on destructive operations
#   -h, --help
#
# EVERY change made to the image is a **named file** under versions/<ver>/patches/*.sh
# (BSP and rootfs alike), sourced in sorted order by apply_patches — so opening that
# folder shows the whole patch set at a glance. Patched DTBs are **distributed**
# (versions/<ver>/dtb/), not generated.
#
# Layout:
#   g1_custom_jetpack.sh                   this script (version-aware)
#   .env                                   DEFAULT_JP / BACKUP_JP
#   versions/<ver>/version.env             URLs, board conf, kernel ver, user/IP
#   versions/<ver>/patches/*.sh            every BSP + rootfs change (named, in order)
#   versions/<ver>/{dtb,firmware,modules,overlay}   per-version payload
#   misc/                                  WiFi/BT driver sources (shared)
#   downloads/<ver>/                       cached NVIDIA .tbz2 tarballs  (git-ignored)
#   bsp/<ver>/Linux_for_Tegra              extracted + patched BSP       (git-ignored)
#   backups/<ts>_jp<ver>_l4t<ver>/         partition dumps               (git-ignored)
#
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\033[36m[*]\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
    sed -n '3,/^set -euo pipefail/p' "$0" | sed -e '/^set -euo pipefail/d' -e 's/^# \{0,1\}//'
    exit "${1:-0}"
}

# --- repo config (.env) ----------------------------------------------------------
DEFAULT_JP="6.2.2"      # JetPack when -j is omitted (init/flash/clean)
BACKUP_JP="6.2.2"       # JetPack BSP used by backup/restore
# shellcheck source=/dev/null
[ -f "$HERE/.env" ] && . "$HERE/.env"

# --- arg parsing -----------------------------------------------------------------
JP="${G1_JP:-}"                       # -j/--jetpack overrides; else env G1_JP; else .env default
YES=false; POS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -j|--jetpack)     [ $# -ge 2 ] || die "-j/--jetpack needs a version"; JP="$2"; shift 2;;
        --jetpack=*|-j=*) JP="${1#*=}"; shift;;
        --yes)            YES=true; shift;;
        -h|--help|help)   usage 0;;
        *)                POS+=("$1"); shift;;
    esac
done
set -- "${POS[@]:-}"
[ $# -ge 1 ] || usage 1
CMD="$1"; shift
[ "$CMD" = help ] && usage 0

SUDO=""; [ "$(id -u)" -eq 0 ] || SUDO="sudo"
BACKUPS="$HERE/backups"               # all dumps live here (timestamped + version-tagged)
INIT_MARKER=".g1-init-done"           # written at end of cmd_init; ensure_bsp checks it

# --- resolve + validate the JetPack version (all commands except status) ---------
if [ "$CMD" != status ]; then
    case "$CMD" in
        backup|restore) : "${JP:=$BACKUP_JP}";;   # device-state ops -> the BACKUP_JP BSP
        *)              : "${JP:=$DEFAULT_JP}";;
    esac
    VERSIONS="$HERE/versions"; VDIR="$VERSIONS/$JP"
    if [ ! -f "$VDIR/version.env" ]; then
        avail="$( [ -d "$VERSIONS" ] && (cd "$VERSIONS" && ls -d */ 2>/dev/null | tr -d /) | tr '\n' ' ')"
        die "unknown JetPack '$JP' — no versions/$JP/version.env. Available: ${avail:-<none>}. Use -j <ver>."
    fi
    # shellcheck source=/dev/null
    source "$VDIR/version.env"

    DOWNLOADS="$HERE/downloads/$JP"
    BSP_PARENT="$HERE/bsp/$JP"
    LFT="$BSP_PARENT/Linux_for_Tegra"
    BR="$LFT/tools/backup_restore"

    case "$CMD" in
        backup|restore) log "JetPack $JP BSP for backup/restore — L4T ${L4T_VER}, kernel ${KVER}";;
        *)              log "JetPack $JP — L4T ${L4T_VER}, kernel ${KVER}   [versions/$JP]";;
    esac
fi

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
        warn "BSP already extracted at $LFT (reusing; 'clean bsp' to start fresh)"
    fi
    log "extracting sample rootfs"
    $SUDO tar xpf "$rfs_tb" -C "$LFT/rootfs/"
    command -v qemu-aarch64-static >/dev/null 2>&1 || \
        { log "installing qemu-user-static (needed for apply_binaries on this host)"; $SUDO apt-get install -y qemu-user-static || true; }
    log "running apply_binaries.sh"
    ( cd "$LFT" && $SUDO ./apply_binaries.sh )

    # 3. apply every change (BSP + rootfs) as named steps from versions/<ver>/patches/
    apply_patches

    touch "$LFT/$INIT_MARKER" 2>/dev/null || $SUDO touch "$LFT/$INIT_MARKER"
    ok "BSP ready: $LFT"
    echo "    next:  ./g1_custom_jetpack.sh -j $JP flash all   (board in RCM)"
}

# Run every versions/<ver>/patches/*.sh in sorted order — the COMPLETE set of BSP +
# rootfs changes, one named file each, so opening patches/ shows everything done to
# the image. Sourced, so they share version.env, $LFT, $VDIR, $DTBS, $SUDO, $KVER and
# log()/warn()/die()/rootfs_unmount(). (Runs after the rootfs is extracted + apply_binaries.)
apply_patches() {
    local pdir="$VDIR/patches" p applied=0
    [ -d "$pdir" ] || { warn "no patches/ in versions/$JP — nothing applied"; return 0; }
    log "applying patches from versions/$JP/patches/"
    for p in "$pdir"/*.sh; do
        [ -f "$p" ] || continue                 # glob didn't match -> nothing to do
        log "patch: $(basename "$p")"
        # shellcheck source=/dev/null
        source "$p"
        applied=$((applied+1))
    done
    [ "$applied" -gt 0 ] || warn "versions/$JP/patches/ had no *.sh files"
}

# Build the BSP for $JP if it isn't ready — lets flash/backup/restore self-init.
ensure_bsp() {
    if [ -f "$LFT/$INIT_MARKER" ]; then
        log "using existing BSP: $LFT"
    else
        log "no built BSP for JetPack $JP — running init first"
        cmd_init
    fi
}

# ============================================================ backup/restore =====
# Echo the chosen backup dir on stdout; the menu (if any) goes to stderr.
pick_backup() {
    local list=() d
    while IFS= read -r d; do list+=("$d"); done < <(
        find "$BACKUPS" -mindepth 1 -maxdepth 2 -name nvpartitionmap.txt -printf '%h\n' 2>/dev/null | sort)
    [ "${#list[@]}" -gt 0 ] || { echo "no backups under $BACKUPS (run 'backup' first)" >&2; return 1; }
    if [ "${#list[@]}" -eq 1 ]; then echo "${list[0]}"; return 0; fi
    echo "Multiple backups under $BACKUPS:" >&2
    local i
    for i in "${!list[@]}"; do printf '  [%2d] %s\n' "$((i+1))" "$(basename "${list[$i]}")" >&2; done
    local c
    read -r -p "Choose a backup to restore [1-${#list[@]}]: " c
    [[ "$c" =~ ^[0-9]+$ ]] && [ "$c" -ge 1 ] && [ "$c" -le "${#list[@]}" ] || { echo "invalid choice: $c" >&2; return 1; }
    echo "${list[$((c-1))]}"
}

cmd_backup() {
    local arg="${1:-}"
    ensure_bsp
    [ -x "$BR/l4t_backup_restore.sh" ] || die "no backup_restore tooling in BSP"
    local ts stage final
    ts="$(date +%Y%m%d-%H%M%S)"
    if [ -n "$arg" ]; then                          # explicit name or path -> use as-is
        case "$arg" in /*) stage="$arg";; *) stage="$BACKUPS/$arg";; esac
        final="$stage"
        [ -d "$stage" ] && [ -n "$(ls -A "$stage" 2>/dev/null)" ] && warn "target not empty — images may be overwritten: $stage"
    else                                            # auto: timestamp now, tag jp+l4t on success
        stage="$BACKUPS/$ts"
        final="$BACKUPS/${ts}_jp${JP_VER}_l4t${L4T_VER}"
    fi
    recovery_note
    confirm "Back up the board (RCM) -> $final ?"
    rootfs_unmount
    mkdir -p "$stage"
    ( cd "$LFT" && $SUDO ./tools/backup_restore/l4t_backup_restore.sh \
        --network usb0 -e nvme0n1 -b "$BOARD_CONF" )
    log "collecting images -> $stage"
    $SUDO mv "$BR/images/"* "$stage/" 2>/dev/null || true
    [ "$stage" = "$final" ] || mv "$stage" "$final"
    ok "backup saved to $final"
}

cmd_restore() {
    local arg="${1:-}" dir
    ensure_bsp
    [ -x "$BR/l4t_backup_restore.sh" ] || die "no backup_restore tooling in BSP"
    if [ -n "$arg" ]; then                          # name under backups/ or a full path
        if   [ -d "$arg" ];           then dir="$arg"
        elif [ -d "$BACKUPS/$arg" ];  then dir="$BACKUPS/$arg"
        else die "backup '$arg' not found (looked at the path and under $BACKUPS/)"; fi
    else
        dir="$(pick_backup)" || die "no backup selected"
    fi
    [ -f "$dir/nvpartitionmap.txt" ] || die "not a backup folder (no nvpartitionmap.txt): $dir"
    recovery_note
    confirm "DESTRUCTIVE: restore '$(basename "$dir")' onto the board (erases QSPI + NVMe)?"
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
    case "$what" in all|qspi) ;; *) die "flash takes 'all' or 'qspi'";; esac
    ensure_bsp
    recovery_note
    confirm "DESTRUCTIVE: flash JetPack $JP '$what' to the board from $LFT ?"
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
        printf '  %-9s run  %b./g1_custom_jetpack.sh -j <ver> flash | backup | restore%b\n' "next" "$B" "$R"
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
        if [ -d "$BACKUPS" ] && [ -n "$(ls -A "$BACKUPS" 2>/dev/null)" ]; then
            confirm "Delete ALL backups under $BACKUPS (every version)?"
            log "removing all backups: $BACKUPS"
            $SUDO rm -rf "$BACKUPS"
        else log "no backups to remove"; fi
    fi
    ok "clean ($what) done for JetPack $JP"
    [ "$what" = all ] && echo "    (downloads/$JP cache kept — remove it by hand to force a re-download)"
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
