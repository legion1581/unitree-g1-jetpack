# 60-fix-nvrestore-bugs.sh — two R35 restore bugs that leave a restored board unbootable
# when the disk previously held a DIFFERENT L4T generation (e.g. restoring an R36 backup
# over a 7.2/R39 flash). Both are fixed upstream in R36+; this brings R35 in line, making
# `restore` self-sufficient on any prior on-disk layout (no need to pre-flash the matching
# JetPack first). Patches tools/backup_restore/nvrestore_partitions.sh in the BSP.
#
# BUG 1 — secondary GPT never restored: stock R35 handles the `gpt_2` (backup GPT) entry
#   with `dd of="/dev/${FIELDS[2]}"` -> `/dev/gpt_2`, a nonexistent device (the bytes land
#   in a stray file on the initrd tmpfs). The stale secondary GPT from the previous flash
#   stays on disk. FIX: write it to the real device (/dev/$INTERNAL_STORAGE_DEVICE, e.g.
#   nvme0n1) at its `seek` offset — exactly what R36 does.
#
# BUG 2 — partitions restored with `conv=sparse` and no pre-erase: sparse makes dd SKIP
#   all-zero blocks, leaving the previous flash's bytes underneath. The restored partition
#   is only correct if the disk was already zero (or same-generation-identical) wherever
#   the image has zeros — with a different prior generation, esp/kernel/recovery partitions
#   come out corrupt (verified: sha mismatch on p2/p8/p10 after restoring an R36.4.7 backup
#   over an R39 flash; the corrupt esp/L4TLauncher is what broke boot). R36 only enables
#   conv=sparse after blkdiscard-ing the whole device. FIX: drop conv=sparse (the dd'ed
#   partitions total ~1.5 GB — writing zeros costs seconds and is always correct).
#
# The mmcblk0boot0/1 (eMMC) path is left untouched.
#
# Sourced by patch_bsp() with: $LFT $SUDO and log() in scope.

_f="$LFT/tools/backup_restore/nvrestore_partitions.sh"
if [ ! -f "$_f" ]; then
    log "  nvrestore_partitions.sh not found — skipping nvrestore fixes"
else
    # --- BUG 1: gpt_2 -> real device -------------------------------------------------
    if grep -qF 'gpt_2 ] && _of="${INTERNAL_STORAGE_DEVICE}"' "$_f"; then
        log "  nvrestore secondary-GPT fix already applied"
    else
        $SUDO perl -i -pe '
            BEGIN {
                $old = q{dd if="${FIELDS[1]}" of="/dev/${FIELDS[2]}" bs=512 seek=$((FIELDS[3])) count=$((FIELDS[4]))};
                $new = q{_of="${FIELDS[2]}"; [ "${FIELDS[2]}" = gpt_2 ] && _of="${INTERNAL_STORAGE_DEVICE}"; dd if="${FIELDS[1]}" of="/dev/${_of}" bs=512 seek=$((FIELDS[3])) count=$((FIELDS[4]))};
            }
            s/\Q$old\E/$new/;
        ' "$_f"
        if grep -qF 'gpt_2 ] && _of="${INTERNAL_STORAGE_DEVICE}"' "$_f"; then
            log "  nvrestore gpt_2 -> /dev/\$INTERNAL_STORAGE_DEVICE (secondary GPT now restored)"
        else
            log "  WARNING: nvrestore secondary-GPT anchor not found — fix NOT applied (check upstream script)"
        fi
    fi
    # --- BUG 2: drop conv=sparse (no pre-erase in R35, so sparse leaves stale bytes) --
    if grep -q 'conv=sparse' "$_f"; then
        $SUDO sed -i 's/ conv=sparse bs=512 seek=/ bs=512 seek=/' "$_f"
        if grep -q 'conv=sparse' "$_f"; then
            log "  WARNING: nvrestore conv=sparse still present — fix NOT fully applied (check upstream script)"
        else
            log "  nvrestore conv=sparse dropped (partitions now restored byte-exact)"
        fi
    else
        log "  nvrestore conv=sparse fix already applied"
    fi
fi
