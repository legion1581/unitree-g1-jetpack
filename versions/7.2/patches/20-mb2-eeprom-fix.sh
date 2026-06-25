# 20-mb2-eeprom-fix.sh — MB2 carrier-EEPROM boot fix.
#
# WHAT:  sets  cvb_eeprom_read_size = <0x0>  in the MB2 BCT misc DTS
#        (tegra234-mb2-bct-misc-p3767-0000.dts) — a FLASHING BCT, not a kernel DTS.
# WHY:   the custom carrier has no module-EEPROM; MB2 stalls if it tries to read one.
#        (R36 ships 0x100 and needs this; R35 already ships 0x0, so it's a no-op there.)
#
# Sourced by patch_bsp() with: $LFT $SUDO and log() in scope.

_n=0
while IFS= read -r _f; do
    if grep -q 'cvb_eeprom_read_size = <0x0>;' "$_f"; then continue; fi
    $SUDO sed -i 's/cvb_eeprom_read_size = <0x[0-9a-fA-F]*>;/cvb_eeprom_read_size = <0x0>;/' "$_f"
    _n=$((_n+1))
done < <(find "$LFT/bootloader" -maxdepth 3 -name 'tegra234-mb2-bct-misc-p3767-0000.dts' 2>/dev/null)
log "  MB2 cvb_eeprom_read_size -> 0x0 ($_n file(s) changed)"
