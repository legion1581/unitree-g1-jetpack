# 50-enable-typec-host.sh — make the Go2 carrier's recovery Type-C a USB host at boot.
#
# WHAT:  installs a systemd service that (1) drives SoC pin PP.06 high to switch on the
#        recovery Type-C VBUS, and (2) writes role=host to usb2-0's role switch.
# WHY:   the DTB ships usb2-0 as mode="otg" (device-capable) so flash-time recovery RNDIS
#        still works. At runtime the port sources no VBUS until PP.06 is high (Unitree does
#        this from /etc/rc.local, which we don't ship), and stays device/none until the
#        role switch is driven — with VBUS on, role=host hands usb3-0's SuperSpeed to xHCI.
#        Together they make the recovery Type-C a working USB 3.x host (verified on 5.1.6
#        and 6.2.2: RealSense auto-enumerates at SuperSpeed).
# GPIO:  JP5/5.10 has the legacy /sys/class/gpio (value persists after set). JP6/JP7
#        (5.15/6.8) dropped it, so we use libgpiod and must HOLD the line — hence the
#        service is Type=simple and gpioset runs for its lifetime.
# NOTE:  RCM/bootROM recovery is silicon-level and this unit lives in the flashed rootfs
#        (not the recovery initrd), so flashing over usb0 is unaffected. To use the port as
#        a device/gadget instead: `systemctl stop enable-typec-host` (releases VBUS) and
#        `echo device > /sys/class/usb_role/usb2-0-role-switch/role`.
#
# Sourced by apply_patches() with version.env vars + $LFT $SUDO and helpers in scope.

_rfs="$LFT/rootfs"
log "enable-typec-host: install boot service (PP.06 VBUS + usb2-0 role=host on recovery Type-C)"

# the worker script
_sh="$_rfs/usr/sbin/enable-typec-host.sh"
$SUDO mkdir -p "$(dirname "$_sh")"
$SUDO tee "$_sh" >/dev/null <<'SH'
#!/bin/sh
# Make the Go2 recovery Type-C a USB host: PP.06 VBUS + usb2-0 role=host.

# 1) mux PP.06 to GPIO (pinmux reg 0x02430030 = 0x004). Portable devmem: busybox (JP5),
#    else devmem2, else a python3 /dev/mem poke (busybox may be absent on JP6/JP7 Ubuntu).
if   command -v busybox >/dev/null 2>&1; then busybox devmem 0x02430030 w 0x004 2>/dev/null || true
elif command -v devmem2 >/dev/null 2>&1; then devmem2 0x02430030 w 0x004 >/dev/null 2>&1 || true
elif command -v python3 >/dev/null 2>&1; then python3 -c "import mmap,os,struct;fd=os.open('/dev/mem',os.O_RDWR|os.O_SYNC);m=mmap.mmap(fd,4096,offset=0x2430000);m[0x30:0x34]=struct.pack('<I',4);m.close();os.close(fd)" 2>/dev/null || true
fi

# 2) role=host: with VBUS on this hands usb3-0's SuperSpeed to xHCI (persists once set)
R=/sys/class/usb_role/usb2-0-role-switch/role
for i in $(seq 1 50); do [ -e "$R" ] && break; sleep 0.2; done
[ -e "$R" ] && echo host > "$R"

# 3) VBUS: drive PP.06 high
if [ -d /sys/class/gpio ]; then
    # legacy sysfs (JP5/5.10): value persists after set -> oneshot is fine.
    # resolve PP.06's global number by label (base varies by kernel; 446 on 5.10)
    N=$(grep -oE 'gpio-[0-9]+ +\(PP\.06' /sys/kernel/debug/gpio 2>/dev/null | grep -oE '[0-9]+' | head -1)
    [ -n "$N" ] || N=446
    [ -e /sys/class/gpio/PP.06 ] || echo "$N" > /sys/class/gpio/export 2>/dev/null || true
    echo out > /sys/class/gpio/PP.06/direction 2>/dev/null || true
    echo 1   > /sys/class/gpio/PP.06/value     2>/dev/null || true
    exit 0
fi
# libgpiod (JP6/JP7, no /sys/class/gpio): the line reverts when released, so HOLD it via
# exec (this process becomes the service's main PID and keeps VBUS on for its lifetime).
if command -v gpiofind >/dev/null 2>&1; then                       # libgpiod v1 (JP6)
    L=$(gpiofind PP.06 2>/dev/null); [ -n "$L" ] && exec gpioset --mode=signal $L=1
fi
exec gpioset --chip gpiochip0 PP.06=1                               # libgpiod v2 (JP7; holds by default)
SH
$SUDO chmod 755 "$_sh"; $SUDO chown root:root "$_sh"

# the systemd unit (Type=simple: the libgpiod path holds the line for the service lifetime;
# the sysfs path exits 0 and RemainAfterExit keeps the unit active)
_unit="$_rfs/etc/systemd/system/enable-typec-host.service"
$SUDO tee "$_unit" >/dev/null <<'UNIT'
[Unit]
Description=Make Go2 recovery Type-C a USB host (PP.06 VBUS + usb2-0 role=host)
DefaultDependencies=no
After=sysinit.target
Before=multi-user.target

[Service]
Type=simple
RemainAfterExit=yes
ExecStart=/usr/sbin/enable-typec-host.sh
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
UNIT
$SUDO chmod 644 "$_unit"; $SUDO chown root:root "$_unit"

# enable it (offline: drop the wants symlink directly)
_wants="$_rfs/etc/systemd/system/multi-user.target.wants"
$SUDO mkdir -p "$_wants"
$SUDO ln -sf ../enable-typec-host.service "$_wants/enable-typec-host.service"
