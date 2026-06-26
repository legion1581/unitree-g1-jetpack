# Recovery mode (RCM)

`flash`, `backup`, and `restore` need the NX module in **bootROM recovery (APX)**. Use any
of the three methods below, connect the **USB-A → USB-C** cable from the host to the
**flashing port**, then confirm:

```bash
./go2_custom_jetpack.sh status     # -> APX — bootROM recovery (ready)
```

The PWR/REC buttons and the flashing port are on the NX board inside the G1's chest:

![G1-NX board — power LEDs, PWR/REC buttons, flashing port](g1-nx-board.png)

> ① power indicator lights ② PWR button ③ REC button ④ flashing port

## Method 1 — software (no buttons, easiest)

If the board is already booted and reachable, tell it to reboot straight into recovery —
locally or over SSH:

```bash
sudo reboot --force forced-recovery
```

It drops into APX with no chest access or button timing needed. The USB-C flashing cable
must be connected so the host sees the APX device.

## Method 2 — PWR + REC buttons

1. Power on the G1; wait until **all three power LEDs are steadily lit**.
2. Press and **hold PWR + REC together for ~2 s** — the LEDs go from three steady
   lights to two (or all off).
3. Release **PWR**.
4. Wait ~2 s.
5. Release **REC**.

## Method 3 — REC + power-on

If the LEDs misbehave: power off → hold **REC** → power on while holding REC → release
**REC** after ~2 s.
