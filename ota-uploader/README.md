# unitree-ota-uploader

A tiny **stdlib-only** web front-end for on-device Unitree OTA. Keeps the vendor
`upgradePythonServer` UX (upload a package → install → log → roll back) but backs it with the
genuine per-module OTA path — it shells out to `ota_pipe_cli addpackage` + `updatemodule` instead
of the vendor's `rm -rf /unitree; cp; install.sh`.

Version-independent (no pip deps), so the same code drops into every JetPack image. Installed into
the rootfs by `versions/<ver>/patches/73-rootfs-ota-uploader.sh`:

- `app.py`            → `/opt/unitree-ota-uploader/app.py`
- `*.service`         → `/etc/systemd/system/unitree-ota-uploader.service` (enabled)
- staging dir created at `/var/lib/unitree-ota-uploader/upk`

## Use

Browse to `http://<board>:8888/` (port 8888). Upload a module `.upk` (e.g. `video_hub_pc4_1.0.1.1.upk`),
click **Install**. Module/version are read from the .upk header (rename-proof) and the
OTA token is the file's md5 — both derived automatically. **Refresh modules** shows
`listmoduleversion`. `.upk` files are hosted off-image; users download the one they want and upload it.

## HTTP API

| method | path | does |
|--|--|--|
| GET  | `/`            | the one-page UI |
| GET  | `/list`        | staged `.upk` (JSON, with parsed module/version) |
| GET  | `/modules`     | `ota_pipe_cli listmoduleversion` |
| GET  | `/services`    | JSON service list — `mscli listservice` merged with per-module versions from `listmoduleversion` (`[{name,status,running,enable,starttime,version}]`) |
| PUT  | `/upk/<name>`  | store an uploaded `.upk` (raw body) |
| POST | `/install?file=<name>[&module=&version=]` | `addpackage` + `updatemodule` |
| POST | `/service?action=start\|stop\|restart&name=<svc>` | `mscli {start,stop,restart}service` |
| POST | `/rollback?module=&version=` | `fallbackmodule` |
| POST | `/delete?file=<name>` | remove a staged `.upk` |

The **Services** panel (top of the UI) shows each master_service-managed service with its version and
run state, and gives Start / Stop / Restart buttons (via `mscli`). Handy for restarting `video_hub_pc4`
if the camera stream isn't up after boot.

## Config (env, set in the unit)

`PORT` (8888) · `BIND` (0.0.0.0) · `OTA_CLI` (`/unitree/sbin/ota_pipe_cli`) ·
`MSCLI` (`/unitree/sbin/mscli`) · `OTA_ALIAS` (`default`) · `STAGE_DIR` ·
`OTA_TOKEN` (empty = no auth; set to require `?token=`/`X-Token`).

## Security

Installing a `.upk` runs its `module.json` Install steps **as root**, so this is effectively a
remote-root endpoint. Default bind is `0.0.0.0:8888`. Set `OTA_TOKEN` and/or
restrict the bind if you deploy somewhere untrusted.
