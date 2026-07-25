#!/usr/bin/env python3
# unitree-ota-uploader — a tiny stdlib-only web front-end for on-device OTA.
#
# Keeps the vendor upgradePythonServer *UX* (upload a package, click install, see log, roll back)
# but swaps its crude "rm -rf /unitree; cp; install.sh" backend for the genuine per-module OTA:
# it shells out to `ota_pipe_cli addpackage` + `updatemodule` (which verifies the signature, runs
# each module's module.json Install steps, updates version.json, and supports fallbackmodule).
#
# Stdlib only (http.server/subprocess/hashlib) so it drops into any JetPack rootfs with no pip.
# Upload is a raw-body PUT (no multipart parsing). Module/version are parsed from the .upk name
# (<module>_<a.b.c.d>.upk) and the OTA token is the file md5, both overridable per request.
#
# Config via env (see the systemd unit): PORT, BIND, OTA_CLI, OTA_ALIAS, STAGE_DIR, OTA_TOKEN.
# NOTE: installing a .upk runs its Install steps as root — this endpoint is effectively remote
# root. Bind/expose accordingly (default 0.0.0.0, matching the vendor). Set OTA_TOKEN to require
# a shared secret (?token=… or X-Token header) if you ever want that.

import hashlib
import html
import json
import os
import re
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

PORT      = int(os.environ.get("PORT", "8888"))
BIND      = os.environ.get("BIND", "0.0.0.0")
OTA_CLI   = os.environ.get("OTA_CLI", "/unitree/sbin/ota_pipe_cli")
MSCLI     = os.environ.get("MSCLI", "/unitree/sbin/mscli")   # master_service control
OTA_ALIAS = os.environ.get("OTA_ALIAS", "default")
STAGE_DIR = os.environ.get("STAGE_DIR", "/var/lib/unitree-ota-uploader/upk")
OTA_TOKEN = os.environ.get("OTA_TOKEN", "")          # empty -> no auth

VER_RE = re.compile(r"^(?P<module>.+)_(?P<version>\d+\.\d+\.\d+\.\d+)$")

os.makedirs(STAGE_DIR, exist_ok=True)


def run(args, timeout=300):
    """Run a command, return (rc, combined_output)."""
    try:
        p = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           timeout=timeout)
        return p.returncode, p.stdout.decode("utf-8", "replace")
    except Exception as ex:  # noqa: BLE001
        return 255, "exec error: %s\n" % ex


def cli(*ota_args, timeout=300):
    return run([OTA_CLI, "-a", OTA_ALIAS, *ota_args], timeout=timeout)


def ms(*args, timeout=60):
    """Run mscli (master_service control). The uploader runs as root, so no sudo."""
    return run([MSCLI, *args], timeout=timeout)


# mscli listservice line:  #1 name:video_hub_pc4, starttime:1784922491, status:0, enable:1
_SVC_RE = re.compile(r"name:(?P<name>\S+?),\s*starttime:(?P<starttime>\d+),"
                     r"\s*status:(?P<status>-?\d+),\s*enable:(?P<enable>\d+)")
# ota_pipe_cli listmoduleversion line:  #0 name:video_hub_pc4, version:1.0.1.1
_MODVER_RE = re.compile(r"name:(?P<name>\S+?),\s*version:(?P<version>\S+)")


def module_versions():
    """module name -> installed version, from ota_pipe_cli listmoduleversion."""
    _, out = cli("-c", "listmoduleversion", timeout=30)
    return {m.group("name"): m.group("version") for m in _MODVER_RE.finditer(out)}


def service_list():
    """[{name, status, enable, starttime, running, version}] merging mscli + module versions."""
    _, out = ms("listservice")
    vers = module_versions()
    svcs = []
    for m in _SVC_RE.finditer(out):
        name = m.group("name")
        status = int(m.group("status"))
        svcs.append({
            "name": name,
            "status": status,
            "running": status == 0,
            "enable": int(m.group("enable")),
            "starttime": int(m.group("starttime")),
            "version": vers.get(name),   # None if this service isn't a versioned module
        })
    return svcs


def ota_code(output):
    """Extract the OTA result code from 'run command <x>, code:N' (last match)."""
    m = re.findall(r"run command \w+, code:(-?\d+)", output)
    return int(m[-1]) if m else None


def md5_of(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def _split_modver(stem):
    m = VER_RE.match(stem)
    return (m.group("module"), m.group("version")) if m else (None, None)


def upk_pkgname(path):
    """Read the module_version from the .upk's internal UTPK header (bytes 48..),
    so a renamed file still installs under the right module/version."""
    try:
        with open(path, "rb") as f:
            head = f.read(112)
        if head[:4] != b"UTPK":
            return None
        return head[48:112].split(b"\x00", 1)[0].decode("utf-8", "ignore") or None
    except Exception:
        return None


def derive_modver(path, filename):
    """Prefer the .upk header PackageName (rename-proof); fall back to the filename."""
    pkg = upk_pkgname(path)
    if pkg:
        mv = _split_modver(pkg)
        if mv[0]:
            return mv
    return _split_modver(filename[:-4] if filename.endswith(".upk") else filename)


def staged_files():
    return sorted(f for f in os.listdir(STAGE_DIR) if f.endswith(".upk"))


PAGE = """<!doctype html><meta charset=utf-8><title>Unitree OTA</title>
<style>body{font:14px/1.5 system-ui,sans-serif;max-width:820px;margin:2rem auto;padding:0 1rem}
h1{font-size:1.3rem}h3{margin-top:1.6rem}button{cursor:pointer}pre{background:#111;color:#0f0;
padding:1rem;overflow:auto;white-space:pre-wrap;border-radius:6px;min-height:2rem}
table{border-collapse:collapse;width:100%}td,th{border-bottom:1px solid #ddd;padding:.4rem;
text-align:left}.row{display:flex;gap:.5rem;align-items:center;margin:.5rem 0}
.on{color:#128a12;font-weight:600}.off{color:#c00;font-weight:600}
.btns button{margin-right:.3rem}</style>
<h1>Unitree OTA uploader</h1>

<h3>Services <button onclick=services() style=font-size:.8rem>↻</button></h3>
<div id=services>…</div>

<h3>Install module</h3>
<div class=row><input type=file id=f accept=".upk"><button onclick=up()>Upload .upk</button></div>
<div id=staged></div>
<div class=row><button onclick=refresh()>Refresh module versions</button></div>
<pre id=modules>…</pre>
<h3>Log</h3><pre id=log></pre>
<script>
const tok=new URLSearchParams(location.search).get('token');
const q=k=>tok?`${k.includes('?')?'&':'?'}token=${encodeURIComponent(tok)}`:'';
async function up(){const fi=document.getElementById('f');if(!fi.files[0])return;
 const fn=fi.files[0].name;log('uploading '+fn+' …');
 await fetch('/upk/'+encodeURIComponent(fn)+q('/upk'),{method:'PUT',body:fi.files[0]});
 log('uploaded '+fn);list();}
function renderServices(j){
 let h='<table><tr><th>service</th><th>version</th><th>status</th><th>boot</th><th>actions</th></tr>';
 for(const s of j){
  const st=s.running?'<span class=on>● running</span>':`<span class=off>○ stopped (${s.status})</span>`;
  h+=`<tr><td>${s.name}</td><td>${s.version||'—'}</td><td>${st}</td>
  <td>${s.enable?'enabled':'disabled'}</td>
  <td class=btns><button onclick="svc('start','${s.name}')">Start</button>
  <button onclick="svc('stop','${s.name}')">Stop</button>
  <button onclick="svc('restart','${s.name}')">Restart</button></td></tr>`;}
 h+='</table>';document.getElementById('services').innerHTML=h;}
async function services(){const r=await fetch('/services'+q('/services'));
 try{renderServices(await r.json())}catch(e){document.getElementById('services').textContent='(error)';}}
async function svc(action,name){log('⏳ '+action+' '+name+' …');
 const r=await fetch('/service?action='+action+'&name='+encodeURIComponent(name)+q('/service?'),{method:'POST'});
 const j=await r.json();renderServices(j.services);
 log((j.rc==0?'✅':'⚠️')+' '+action+' '+name+' (rc='+j.rc+')\\n\\n'+(j.output||''));}
async function list(){const r=await fetch('/list'+q('/list'));const j=await r.json();
 let h='<table><tr><th>staged .upk</th><th>module</th><th>version</th><th></th></tr>';
 for(const it of j){h+=`<tr><td>${it.file}</td><td>${it.module||'?'}</td><td>${it.version||'?'}</td>
 <td><button onclick="inst('${it.file}')">Install</button>
 <button onclick="del('${it.file}')">Delete</button></td></tr>`;}
 h+='</table>';document.getElementById('staged').innerHTML=h;}
async function inst(f){log('⏳ installing '+f+' … (runs the module Install as root; may take ~30s)');
 const r=await fetch('/install?file='+encodeURIComponent(f)+q('/install?'),{method:'POST'});
 let j; try{j=await r.json()}catch(e){log('❌ error: '+await r.text());return}
 const icon=j.status=='ok'?'✅':(j.status=='warn'?'⚠️':'❌');
 let head;
 if(j.status=='ok') head=icon+' INSTALLED '+j.module+' '+(j.installed||j.version);
 else if(j.status=='warn') head=icon+' INSTALLED '+j.module+' '+(j.installed||j.version)+' — service did NOT start (code 32: check camera / runtime deps)';
 else head=icon+' FAILED '+j.module+' '+j.version+'  (updatemodule code='+j.code_updatemodule+', addpackage code='+j.code_addpackage+')';
 log(head+'\\n\\n'+(j.log||''));refresh();}
async function del(f){await fetch('/delete?file='+encodeURIComponent(f)+q('/delete?'),{method:'POST'});list();}
async function refresh(){const r=await fetch('/modules'+q('/modules'));
 document.getElementById('modules').textContent=await r.text();}
function log(t){document.getElementById('log').textContent=t;}
services();list();refresh();setInterval(services,5000);
</script>"""


class H(BaseHTTPRequestHandler):
    server_version = "unitree-ota-uploader/1.0"

    # --- helpers ---------------------------------------------------------------
    def _auth_ok(self, q):
        if not OTA_TOKEN:
            return True
        return q.get("token", [""])[0] == OTA_TOKEN or self.headers.get("X-Token") == OTA_TOKEN

    def _send(self, code, body, ctype="text/plain; charset=utf-8"):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")   # always serve fresh UI/JSON
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, *a):  # quieter default logging
        pass

    # --- routes ----------------------------------------------------------------
    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if not self._auth_ok(q):
            return self._send(403, "forbidden (bad token)\n")
        if u.path == "/":
            return self._send(200, PAGE, "text/html; charset=utf-8")
        if u.path == "/list":
            items = [dict(zip(("module", "version"),
                              derive_modver(os.path.join(STAGE_DIR, f), f)), file=f)
                     for f in staged_files()]
            return self._send(200, json.dumps(items), "application/json")
        if u.path == "/modules":
            rc, out = cli("-c", "listmoduleversion", timeout=30)
            return self._send(200, out or "(no output)\n")
        if u.path == "/services":
            return self._send(200, json.dumps(service_list()), "application/json")
        return self._send(404, "not found\n")

    def do_PUT(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if not self._auth_ok(q):
            return self._send(403, "forbidden (bad token)\n")
        if not u.path.startswith("/upk/"):
            return self._send(404, "not found\n")
        name = os.path.basename(u.path[len("/upk/"):])
        if not name.endswith(".upk"):
            return self._send(400, "filename must end in .upk\n")
        n = int(self.headers.get("Content-Length", "0"))
        dst = os.path.join(STAGE_DIR, name)
        with open(dst, "wb") as f:
            left = n
            while left > 0:
                chunk = self.rfile.read(min(1 << 20, left))
                if not chunk:
                    break
                f.write(chunk)
                left -= len(chunk)
        return self._send(200, "stored %s (%d bytes)\n" % (name, os.path.getsize(dst)))

    def do_POST(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        if not self._auth_ok(q):
            return self._send(403, "forbidden (bad token)\n")

        if u.path == "/delete":
            name = os.path.basename(q.get("file", [""])[0])
            p = os.path.join(STAGE_DIR, name)
            if name and os.path.isfile(p):
                os.remove(p)
                return self._send(200, "deleted %s\n" % name)
            return self._send(404, "no such staged file\n")

        if u.path == "/install":
            name = os.path.basename(q.get("file", [""])[0])
            path = os.path.join(STAGE_DIR, name)
            if not (name and os.path.isfile(path)):
                return self._send(404, "no such staged file\n")
            _dm, _dv = derive_modver(path, name)
            module = q.get("module", [""])[0] or _dm
            version = q.get("version", [""])[0] or _dv
            if not (module and version):
                return self._send(400, "cannot derive module/version from %r; "
                                        "pass ?module=&version=\n" % name)
            token = md5_of(path)
            log_ = "== addpackage %s %s ==\n" % (module, version)
            _, o_a = cli("-c", "addpackage", "-m", module, "-v", version,
                         "-f", path, "-p", name, "-t", token)
            log_ += o_a
            code_a = ota_code(o_a)
            log_ += "\n== updatemodule %s %s ==\n" % (module, version)
            _, o_u = cli("-c", "updatemodule", "-m", module, "-v", version,
                         "-p", name, "-t", token, "-s", "1")  # -s 1: allow same-version overwrite
            log_ += o_u
            code_u = ota_code(o_u)
            # what version is actually installed now?
            _, mods = cli("-c", "listmoduleversion", timeout=30)
            mm = re.search(r"name:%s, version:(\S+)" % re.escape(module), mods)
            installed = mm.group(1) if mm else None
            # verdict: 0 = installed+started; 32 = installed but service didn't start; else = failed
            status = "ok" if code_u == 0 else ("warn" if code_u == 32 else "fail")
            return self._send(200, json.dumps({
                "status": status, "module": module, "version": version,
                "installed": installed, "code_addpackage": code_a,
                "code_updatemodule": code_u, "log": log_,
            }), "application/json")

        if u.path == "/service":
            action = q.get("action", [""])[0]
            name = q.get("name", [""])[0]
            verb = {"start": "startservice", "stop": "stopservice",
                    "restart": "restartservice"}.get(action)
            if not (verb and name):
                return self._send(400, "need ?action=start|stop|restart&name=<service>\n")
            rc, out = ms(verb, name)
            return self._send(200, json.dumps({
                "action": action, "name": name, "rc": rc,
                "output": out, "services": service_list(),
            }), "application/json")

        if u.path == "/rollback":
            module = q.get("module", [""])[0]
            version = q.get("version", [""])[0]
            if not (module and version):
                return self._send(400, "need ?module=&version=\n")
            rc, out = cli("-c", "fallbackmodule", "-m", module, "-v", version)
            return self._send(200, out or ("fallbackmodule rc=%d\n" % rc))

        return self._send(404, "not found\n")


def main():
    srv = ThreadingHTTPServer((BIND, PORT), H)
    print("unitree-ota-uploader on http://%s:%d  (cli=%s alias=%s stage=%s auth=%s)"
          % (BIND, PORT, OTA_CLI, OTA_ALIAS, STAGE_DIR, "token" if OTA_TOKEN else "none"),
          flush=True)
    srv.serve_forever()


if __name__ == "__main__":
    main()
