#!/usr/bin/env python3
"""Grok Glasses bridge supervisor. Runs in the user's GUI session via a LaunchAgent.
Loop: auto-answer WhatsApp calls, start grok_frames capture while a call is active,
stop it when the call ends, and honour the server /control flag (start/stop).
Logs to ~/grok-glasses/bridge.log (stdout, redirected by the LaunchAgent)."""
import json, os, signal, subprocess, sys, time, urllib.request
HERE = os.path.dirname(os.path.abspath(__file__))
PY = sys.executable
SERVER = os.environ.get("GROK_SERVER", "https://grok-glasses-server.conscious-carnation.workers.dev").rstrip("/")
def _load_env():
    f = os.path.join(HERE, ".env")
    if os.path.exists(f):
        for line in open(f):
            line = line.strip()
            if line.startswith("export "): line = line[7:]
            if "=" in line and not line.startswith("#"):
                k, v = line.split("=", 1)
                os.environ[k.strip()] = v.strip().strip(chr(34)).strip(chr(39))
_load_env()
TOKEN = os.environ.get("GLASSES_TOKEN", "")
UA = "Mozilla/5.0 GrokGlasses/1.0"

def _req(path, data=None):
    h = {"User-Agent": UA, "Content-Type": "application/json", "X-Glasses-Token": TOKEN}
    r = urllib.request.Request(SERVER + path, data=json.dumps(data).encode() if data is not None else None, headers=h, method="POST" if data is not None else "GET")
    with urllib.request.urlopen(r, timeout=10) as resp:
        return json.loads(resp.read() or b"{}")

def get_control():
    try: return _req("/control")
    except Exception as e: print("control get err:", e); return {}

def post_bridge(**b):
    try: _req("/control", {"bridge": b})
    except Exception: pass

class Capture:
    def __init__(self): self.p = None
    def running(self): return self.p and self.p.poll() is None
    def start(self):
        if self.running(): return
        env = dict(os.environ)
        log = open(os.path.join(HERE, "run.log"), "a")
        self.p = subprocess.Popen([PY, "-u", "grok_frames.py", "--hud"], cwd=HERE, env=env, stdout=log, stderr=subprocess.STDOUT)
        print("capture started pid", self.p.pid)
    def stop(self):
        if self.running():
            self.p.terminate()
            try: self.p.wait(5)
            except Exception: self.p.kill()
            print("capture stopped")
        self.p = None

def call_active():
    try:
        out = subprocess.run([PY, "autoanswer.py", "--once"], cwd=HERE, capture_output=True, text=True, timeout=20)
        return out.stdout.strip().endswith("answered") or "in_call" in out.stdout
    except Exception as e:
        print("autoanswer err:", e); return False

def main():
    print(time.strftime("%Y-%m-%d %H:%M:%S"), "supervisor up; server", SERVER)
    cap = Capture(); forced = None
    while True:
        ctrl = get_control()
        enabled = ctrl.get("enabled", True)
        cmd = ctrl.get("cmd", "")
        if cmd == "stop": forced = False
        elif cmd in ("start", "answer"): forced = True
        active = call_active() if enabled else False
        want = (forced is True) or (enabled and active and forced is not False)
        if want and not cap.running(): cap.start()
        if (not want) and cap.running(): cap.stop()
        post_bridge(capturing=cap.running(), callActive=active, enabled=enabled, forced=forced)
        time.sleep(2)

if __name__ == "__main__":
    main()
