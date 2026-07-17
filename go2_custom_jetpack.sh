#!/usr/bin/env bash
#
# go2_custom_jetpack.sh — build, back up, restore and flash a JetPack image for the
# Unitree G1 custom carrier board (Jetson Orin NX, p3767 on a p3768-class carrier).
#
#   ./go2_custom_jetpack.sh [-j <ver>] <command> [args]
#
# JetPack version:
#   -j, --jetpack <ver>   the JetPack to act on; each lives under versions/<ver>/.
#                         REQUIRED for init/flash. Optional for clean (scopes to one
#                         version, else all). Ignored by backup/restore/status — those
#                         are device ops; backup/restore auto-pick a built BSP's initrd.
#                         e.g.  -j 5.1.6   |   -j 6.2.2   (env: GO2_JP=<ver>)
#
# Commands:
#   init                 download + extract + patch a flash-ready BSP into bsp/<ver>
#   flash [all|qspi]     flash the chosen JetPack (auto-runs init; rebuilds if stale)
#   backup  [name|dir]   back up every partition over the initrd, into a timestamped,
#                        version-tagged folder under backups/ (auto-runs init)
#   restore [name|dir]   restore a backup over the initrd (auto-runs init). With no
#                        arg, picks from backups/ (menu if more than one).
#   status               show recovery state (APX / RNDIS) — version-independent
#   clean [all|bsp|backup]   remove a version's BSP (-j) or all BSPs, and/or ALL backups
#
# Options:
#   --yes           skip the confirmation prompt on destructive operations
#   --super         (flash/init) use NVIDIA's "Super" board config — MAXN_SUPER + a
#                   40W power mode. Only versions that define BOARD_CONF_SUPER (7.2).
#                   Orin NX pulls much more power; confirm the carrier rail + cooling.
#   -h, --help
#
# EVERY change made to the image is a **named file** under versions/<ver>/patches/*.sh
# (BSP and rootfs alike), sourced in sorted order by apply_patches — so opening that
# folder shows the whole patch set at a glance. Patched DTBs are **distributed**
# (versions/<ver>/dtb/), not generated.
#
# Layout:
#   go2_custom_jetpack.sh                   this script (version-aware)
#   versions/<ver>/version.env             URLs, board conf, kernel ver, user/IP
#   versions/<ver>/patches/*.sh            every BSP + rootfs change (named, in order)
#   versions/<ver>/dtb/                    per-version payload (carrier-patched DTB)
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

# --- arg parsing -----------------------------------------------------------------
VERSIONS="$HERE/versions"
JP="${GO2_JP:-}"                       # from -j/--jetpack or env GO2_JP — no silent default
YES=false; SUPER=false; POS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -j|--jetpack)     [ $# -ge 2 ] || die "-j/--jetpack needs a version"; JP="$2"; shift 2;;
        --jetpack=*|-j=*) JP="${1#*=}"; shift;;
        --yes)            YES=true; shift;;
        --super)          SUPER=true; shift;;
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

list_versions() { (cd "$VERSIONS" 2>/dev/null && ls -d */ 2>/dev/null | tr -d /) | sort -V | tr '\n' ' '; }

# Load a version: validate, source its version.env, set per-version build paths.
load_version() {
    JP="$1"; VDIR="$VERSIONS/$JP"
    [ -f "$VDIR/version.env" ] || die "unknown JetPack '$JP' — available: $(list_versions). Use -j <ver>."
    # shellcheck source=/dev/null
    source "$VDIR/version.env"
    DOWNLOADS="$HERE/downloads/$JP"
    BSP_PARENT="$HERE/bsp/$JP"
    LFT="$BSP_PARENT/Linux_for_Tegra"
    BR="$LFT/tools/backup_restore"
}

# backup/restore are version-agnostic device ops; they only borrow a recovery initrd.
# Pick a version to borrow it from: any already-built BSP (highest version), else the
# highest version dir (ensure_bsp will then build it).
recovery_jp() {
    local built="" v
    for v in $(list_versions); do
        [ -f "$HERE/bsp/$v/Linux_for_Tegra/$INIT_MARKER" ] && built="$built $v"
    done
    if [ -n "$built" ]; then printf '%s\n' $built        | sort -V | tail -1
    else                     printf '%s\n' $(list_versions) | sort -V | tail -1; fi
}

# --- resolve the JetPack version for this command --------------------------------
case "$CMD" in
    init|flash)
        [ -n "$JP" ] || die "'$CMD' needs a JetPack version: -j <ver>   (available: $(list_versions))"
        load_version "$JP"
        log "JetPack $JP — L4T ${L4T_VER}, kernel ${KVER}   [versions/$JP]"
        if $SUPER; then
            [ -n "${BOARD_CONF_SUPER:-}" ] || die "--super is not available for JetPack $JP (no BOARD_CONF_SUPER in version.env)"
            BOARD_CONF="$BOARD_CONF_SUPER"
            warn "SUPER mode: board config '$BOARD_CONF' (MAXN_SUPER + 40W) — confirm the carrier rail + cooling can supply it"
        fi
        ;;
    backup|restore)
        JP_GIVEN=0; [ -n "$JP" ] && JP_GIVEN=1   # did the user force -j? (restore auto-matches if not)
        [ -n "$JP" ] || JP="$(recovery_jp)"
        [ -n "$JP" ] || die "no versions/ found"
        load_version "$JP"
        log "backup/restore via the JetPack $JP recovery initrd (L4T ${L4T_VER})"
        ;;
    clean)
        if [ -n "$JP" ]; then
            [ -d "$VERSIONS/$JP" ] || die "unknown JetPack '$JP' — available: $(list_versions)"
            BSP_PARENT="$HERE/bsp/$JP"; LFT="$BSP_PARENT/Linux_for_Tegra"
        else
            BSP_PARENT="$HERE/bsp"        # no -j -> all built BSPs
        fi
        ;;
    status) : ;;
    *)      die "unknown command: $CMD (try --help)" ;;
esac

if $SUPER && [ "$CMD" != flash ] && [ "$CMD" != init ]; then
    warn "--super only affects 'flash' / 'init' — ignored for '$CMD'"
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
    [ -n "${LFT:-}" ] || return 0
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
    echo "    next:  ./go2_custom_jetpack.sh -j $JP flash all   (board in RCM)"
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
# With "fresh" (flash only): if any versions/<ver> file is newer than the build
# marker, rebuild so an edited patch/asset can't be silently flashed from a stale BSP.
ensure_bsp() {
    if [ ! -f "$LFT/$INIT_MARKER" ]; then
        log "no built BSP for JetPack $JP — running init first"
        cmd_init; return
    fi
    if [ "${1:-}" = fresh ] && [ -n "$(find "$VDIR" -newer "$LFT/$INIT_MARKER" -print -quit 2>/dev/null)" ]; then
        warn "versions/$JP changed since this BSP was built — rebuilding to pick up the changes"
        rootfs_unmount
        $SUDO rm -rf "$BSP_PARENT"
        cmd_init; return
    fi
    log "using existing BSP: $LFT"
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

# Map an L4T release (e.g. 36.4.7) to its JetPack version. Exact for the common Orin
# releases this repo handles; otherwise the JetPack series by L4T major.
l4t_to_jp() {
    case "$1" in
        35.6.4) echo 5.1.6 ;; 35.6.1|35.6.0) echo 5.1.5 ;; 35.5.0) echo 5.1.4 ;;
        35.4.1) echo 5.1.2 ;; 35.3.1) echo 5.1.1 ;; 35.2.1) echo 5.1 ;;
        36.4.0) echo 6.1 ;; 36.4.3) echo 6.2 ;; 36.4.4|36.4.7) echo 6.2.1 ;; 36.5.0) echo 6.2.2 ;;
        39.2.0) echo 7.2 ;;
        35.*) echo 5.x ;; 36.*) echo 6.x ;; 39.*) echo 7.x ;; *) echo unknown ;;
    esac
}

# Read the on-board JetPack + L4T from a backup's rootfs tarball (/etc/nv_tegra_release).
# Sets REAL_JP and REAL_L4T; returns non-zero if it can't be determined.
read_board_version() {
    local tarf="$1" rel maj rev
    [ -f "$tarf" ] || return 1
    rel="$(tar xzf "$tarf" --occurrence=1 -O ./etc/nv_tegra_release 2>/dev/null)"
    [ -n "$rel" ] || rel="$(tar xzf "$tarf" --occurrence=1 -O etc/nv_tegra_release 2>/dev/null)"
    [ -n "$rel" ] || return 1
    maj="$(printf '%s' "$rel" | grep -oiE 'R[0-9]+' | head -1 | tr -dc '0-9')"
    rev="$(printf '%s' "$rel" | sed -n 's/.*REVISION: *\([0-9.]\+\).*/\1/p' | head -1)"
    [ -n "$maj" ] && [ -n "$rev" ] || return 1
    REAL_L4T="${maj}.${rev}"
    REAL_JP="$(l4t_to_jp "$REAL_L4T")"
    return 0
}

# Echo the JetPack version whose RESTORE tooling matches a backup, by inspecting the
# dump's partition-map *schema* (not its folder name — that's tagged by board version).
# R35's l4t_backup_restore.sh writes `gpt_1`/`gpt_2` entries; R36+ (nvrestore_partitions.sh)
# uses a different schema and rejects an R35 map ("GPT does not exist"). Prefers a built
# BSP of the matching L4T family, else the highest matching version dir (to build). "" = none.
restore_jp_for() {
    local map="$1/nvpartitionmap.txt" want v maj built="" any=""
    [ -f "$map" ] || return 0
    if grep -qE ',gpt_[12],' "$map"; then want=35; else want=36; fi   # 36 = "R36 or newer"
    for v in $(list_versions); do
        maj="$(grep -E '^L4T_VER=' "$VERSIONS/$v/version.env" 2>/dev/null | cut -d'"' -f2)"; maj="${maj%%.*}"
        [ -n "$maj" ] || continue
        { [ "$want" = 35 ] && [ "$maj" = 35 ]; } || { [ "$want" = 36 ] && [ "$maj" -ge 36 ]; } || continue
        any="$any $v"
        [ -f "$HERE/bsp/$v/Linux_for_Tegra/$INIT_MARKER" ] && built="$built $v"
    done
    if   [ -n "$built" ]; then printf '%s\n' $built | sort -V | tail -1
    elif [ -n "$any" ];   then printf '%s\n' $any   | sort -V | tail -1
    fi
}

cmd_backup() {
    local arg="${1:-}"
    ensure_bsp
    [ -x "$BR/l4t_backup_restore.sh" ] || die "no backup_restore tooling in BSP"
    # R35 tooling writes the legacy gpt_1/gpt_2 (gzip) dump schema; R36+ writes the
    # modern one. Both restore fine (restore auto-matches, and the R35 restore path is
    # fixed by 60-fix-nvrestore-bugs.sh) — just let the user know which they're minting.
    [ "${L4T_VER%%.*}" -lt 36 ] && \
        warn "backing up with the R35 ($JP) tooling — the dump will use the legacy R35 schema; build 6.2.2/7.2 first if you prefer the modern R36+ format (both restore fine)"
    local ts stage final
    ts="$(date +%Y%m%d-%H%M%S)"
    if [ -n "$arg" ]; then                          # explicit name or path -> use as-is
        case "$arg" in /*) stage="$arg";; *) stage="$BACKUPS/$arg";; esac
        final="$stage"
        [ -d "$stage" ] && [ -n "$(ls -A "$stage" 2>/dev/null)" ] && warn "target not empty — images may be overwritten: $stage"
    else                                            # auto: timestamp now; the jp+l4t tag is
        stage="$BACKUPS/$ts"                        # read from the dumped rootfs after backup
        final="$stage"
    fi
    recovery_note
    confirm "Back up the board (RCM) -> $stage ?"
    rootfs_unmount
    mkdir -p "$stage"
    # R35's l4t_backup_restore.sh brings up usb0/NFS itself and rejects --network;
    # R36+ requires it to be passed explicitly.
    local -a netargs=(); [ "${L4T_VER%%.*}" -ge 36 ] && netargs=(--network usb0)
    ( cd "$LFT" && $SUDO ./tools/backup_restore/l4t_backup_restore.sh \
        "${netargs[@]}" -e nvme0n1 -b "$BOARD_CONF" ) || die "backup_restore tool failed"
    log "collecting images -> $stage"
    $SUDO mv "$BR/images/"* "$stage/" 2>/dev/null || true
    [ -n "$(ls -A "$stage" 2>/dev/null)" ] || die "no images produced — backup did not run (check RCM/RNDIS link)"
    if [ -z "$arg" ]; then                          # auto: tag with the BOARD's real version
        log "reading on-board version from the dump…"   # (the initrd's may differ)
        if read_board_version "$stage/nvme0n1p1.tar.gz"; then
            [ "$REAL_JP/$REAL_L4T" = "$JP_VER/$L4T_VER" ] || \
                log "on-board: JetPack $REAL_JP (L4T $REAL_L4T) — dumped via the $JP_VER initrd"
            final="$BACKUPS/${ts}_jp${REAL_JP}_l4t${REAL_L4T}"
        else
            warn "couldn't read on-board version from the dump — tagging with the initrd's $JP_VER/$L4T_VER"
            final="$BACKUPS/${ts}_jp${JP_VER}_l4t${L4T_VER}"
        fi
    fi
    [ "$stage" = "$final" ] || mv "$stage" "$final"
    ok "backup saved to $final"
}

cmd_restore() {
    local arg="${1:-}" dir
    # Resolve the dump BEFORE choosing a BSP: the restore tooling must match the dump's
    # L4T generation (R35's l4t_backup_restore vs R36+'s nvrestore — incompatible
    # partition-map schemas). We read that from the dump, not the (board-tagged) folder name.
    if [ -n "$arg" ]; then                          # name under backups/ or a full path
        if   [ -d "$arg" ];           then dir="$arg"
        elif [ -d "$BACKUPS/$arg" ];  then dir="$BACKUPS/$arg"
        else die "backup '$arg' not found (looked at the path and under $BACKUPS/)"; fi
    else
        dir="$(pick_backup)" || die "no backup selected"
    fi
    [ -f "$dir/nvpartitionmap.txt" ] || die "not a backup folder (no nvpartitionmap.txt): $dir"
    if [ "${JP_GIVEN:-0}" != 1 ]; then              # auto-match the BSP to the dump (unless -j forced)
        local want; want="$(restore_jp_for "$dir")"
        if [ -n "$want" ] && [ "$want" != "$JP" ]; then
            log "dump matches JetPack $want restore tooling — switching from $JP (override with -j)"
            load_version "$want"
        elif [ -z "$want" ]; then
            warn "no BSP matches this dump's L4T generation — using $JP; pass -j <ver> if restore fails"
        fi
    fi
    ensure_bsp
    [ -x "$BR/l4t_backup_restore.sh" ] || die "no backup_restore tooling in BSP"
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
    local -a netargs=(); [ "${L4T_VER%%.*}" -ge 36 ] && netargs=(--network usb0)
    ( cd "$LFT" && $SUDO ./tools/backup_restore/l4t_backup_restore.sh \
        "${netargs[@]}" -e nvme0n1 -r "$BOARD_CONF" ) || die "backup_restore tool failed"
    $SUDO rm -rf "$BR/images"              # free the staging copy on success
    ok "restore complete"
}

# ================================================================= flash =========
cmd_flash() {
    local what="${1:-all}"
    case "$what" in all|qspi) ;; *) die "flash takes 'all' or 'qspi'";; esac
    ensure_bsp fresh
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
    pid="${vidpid##*:}"          # the 0955:XXXX product id — classify by it, not the
                                 # description (booted gadget 7020 and recovery initrd
                                 # 7035 both say "L4T (Linux for Tegra)…").

    if grep -qi 'APX' <<<"$dev" || [ "$pid" = 7023 ] || [ "$pid" = 7323 ]; then
        printf '  %-9s %b● APX — bootROM recovery (ready)%b\n' "state" "$G" "$R"
        printf '  %-9s %s  %s  %b(bus %s / dev %s)%b\n' "device" "$vidpid" "$desc" "$DIM" "$bus" "$dnum" "$R"
        printf '  %-9s run  %b./go2_custom_jetpack.sh -j <ver> flash | backup | restore%b\n' "next" "$B" "$R"
    elif [ "$pid" = 7035 ]; then
        printf '  %-9s %b● RNDIS — recovery initrd running%b\n' "state" "$G" "$R"
        printf '  %-9s %s  %s  %b(bus %s / dev %s)%b\n' "device" "$vidpid" "$desc" "$DIM" "$bus" "$dnum" "$R"
        printf '  %-9s a backup / restore / flash is in progress\n' "meaning"
        printf '  %-9s wait for it to finish — or  %bssh root@192.168.55.1%b\n' "next" "$B" "$R"
    elif [ "$pid" = 7020 ]; then
        printf '  %-9s %b● booted — L4T running, NOT in recovery%b\n' "state" "$Y" "$R"
        printf '  %-9s %s  %s  %b(bus %s / dev %s)%b\n' "device" "$vidpid" "$desc" "$DIM" "$bus" "$dnum" "$R"
        printf '  %-9s this is the running OS USB gadget (ssh root@192.168.55.1)\n' "meaning"
        printf '  %-9s put the board in %bRCM (recovery)%b to flash/backup/restore\n' "next" "$B" "$R"
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
    local scope; [ -n "$JP" ] && scope="JetPack $JP" || scope="all versions"
    ok "clean ($what) done for $scope"
    [ "$what" = all ] && echo "    (downloads/${JP:-*} cache kept — remove it by hand to force a re-download)"
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
