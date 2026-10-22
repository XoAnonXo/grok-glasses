#!/usr/bin/env python3
"""Capture the WhatsApp video-call window on macOS and send frames to the Grok Glasses server.
Usage: python3 grok_frames.py [--list] [--window ID] [--region x,y,w,h] [--say]
Env: GROK_SERVER (default worker URL), GLASSES_TOKEN (required)."""
import argparse, base64, io, json, os, subprocess, sys, tempfile, time, urllib.request
from PIL import Image

SERVER = os.environ.get("GROK_SERVER", "https://grok-glasses-server.conscious-carnation.workers.dev").rstrip("/")
TOKEN = os.environ.get("GLASSES_TOKEN", "")

def windows():
    import Quartz
    opts = Quartz.kCGWindowListOptionOnScreenOnly | Quartz.kCGWindowListExcludeDesktopElements
    out = []
    for w in Quartz.CGWindowListCopyWindowInfo(opts, Quartz.kCGNullWindowID) or []:
        b = w.get("kCGWindowBounds", {})
        out.append(dict(id=int(w["kCGWindowNumber"]), owner=w.get("kCGWindowOwnerName", ""), name=w.get("kCGWindowName", "") or "",
                        w=int(b.get("Width", 0)), h=int(b.get("Height", 0)), layer=w.get("kCGWindowLayer", 0)))
    return out

def find_whatsapp():
    c = [w for w in windows() if "whatsapp" in w["owner"].lower() and w["layer"] == 0 and w["w"] > 200 and w["h"] > 200]
    # prefer a call window if titled, else the biggest WhatsApp window
    c.sort(key=lambda w: (("call" in w["name"].lower() or "video" in w["name"].lower()), w["w"] * w["h"]), reverse=True)
    return c[0]["id"] if c else None

def capture(win, region, path):
    cmd = ["screencapture", "-x", "-t", "jpg"]
    cmd += (["-o", "-l", str(win)] if win else ["-R", region])
    cmd.append(path)
    subprocess.run(cmd, check=True, capture_output=True)

def dhash(img):
    g = img.convert("L").resize((9, 8))
    p = list(g.getdata()); bits = 0
    for r in range(8):
        for c in range(8):
            bits = (bits << 1) | (p[r * 9 + c] > p[r * 9 + c + 1])
    return f"{bits:016x}"

def post(path, body, token=True):
    h = {"Content-Type": "application/json"}
    if token: h["X-Glasses-Token"] = TOKEN
    req = urllib.request.Request(SERVER + path, data=json.dumps(body).encode(), headers=h, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as r: return r.status, json.loads(r.read())
    except urllib.error.HTTPError as e: return e.code, json.loads(e.read() or b"{}")

def get_state():
    with urllib.request.urlopen(SERVER + "/state", timeout=10) as r: return json.loads(r.read())

HUD = {"scene": "", "reply": ""}

def _font(sz):
    from PIL import ImageFont
    for f in ("/System/Library/Fonts/Supplemental/Arial Bold.ttf", "/System/Library/Fonts/Helvetica.ttc", "/Library/Fonts/Arial.ttf"):
        try: return ImageFont.truetype(f, sz)
        except Exception: pass
    return ImageFont.load_default()

def _wrap(d, text, font, width):
    lines, cur = [], ""
    for w in (text or "").split():
        t = (cur + " " + w).strip()
        if d.textlength(t, font=font) <= width: cur = t
        else: lines.append(cur); cur = w
    if cur: lines.append(cur)
    return lines

def render_hud(W=1280, H=720):
    from PIL import ImageDraw
    img = Image.new("RGB", (W, H), "black"); d = ImageDraw.Draw(img)
    lab, big = _font(34), _font(54); y = 30
    for title, text, col in (("GROK SEES", HUD["scene"] or "waiting...", (140, 200, 255)), ("GROK SAYS", HUD["reply"] or "-", (255, 255, 255))):
        d.text((40, y), title, font=lab, fill=col); y += 46
        for ln in _wrap(d, text, big, W - 80)[:4]:
            d.text((40, y), ln, font=big, fill="white"); y += 64
        y += 30
    return img

def hud_loop():
    import numpy as np, pyvirtualcam, threading
    def run():
        with pyvirtualcam.Camera(width=1280, height=720, fps=10) as cam:
            print("HUD virtual camera:", cam.device, "- pick 'OBS Virtual Camera' as WhatsApp's camera")
            while True:
                cam.send(np.asarray(render_hud())); cam.sleep_until_next_frame()
    threading.Thread(target=run, daemon=True).start()

def main():
    a = argparse.ArgumentParser()
    a.add_argument("--list", action="store_true"); a.add_argument("--window", type=int)
    a.add_argument("--region", help="x,y,w,h in screen points (fallback)"); a.add_argument("--interval", type=float, default=2.0)
    a.add_argument("--size", type=int, default=768); a.add_argument("--say", action="store_true", help="speak new Grok replies with macOS say")
    a.add_argument("--hud", action="store_true", help="render Grok's scene+reply to OBS Virtual Camera (pick it as WhatsApp camera)")
    o = a.parse_args()
    if o.list:
        for w in windows():
            if w["layer"] == 0: print(f'{w["id"]:>7}  {w["owner"][:20]:20} {w["w"]}x{w["h"]}  {w["name"]}')
        return
    if not TOKEN: sys.exit("Set GLASSES_TOKEN first.")
    win, region = o.window, o.region
    if not win and not region:
        try: win = find_whatsapp()
        except ImportError: print("pyobjc-framework-Quartz missing; pip install it or use --region")
        if not win:
            print("WhatsApp call window not found. Drag-select the call video area once (fallback)…")
            print("Tip: run with --list to see window ids, or --region x,y,w,h.")
            region = input("Enter region x,y,w,h: ").strip()
    print("Capturing", f"window {win}" if win else f"region {region}", "->", SERVER)
    path = os.path.join(tempfile.gettempdir(), "grok_frame.jpg"); last_reply = None
    if o.hud: hud_loop()
    if o.say:
        try: last_reply = get_state().get("lastReply")
        except Exception: pass
    while True:
        t0 = time.time()
        try:
            capture(win, region, path)
            img = Image.open(path).convert("RGB"); img.thumbnail((o.size, o.size))
            buf = io.BytesIO(); img.save(buf, "JPEG", quality=70)
            data = "data:image/jpeg;base64," + base64.b64encode(buf.getvalue()).decode()
            code, j = post("/frame", {"image": data, "hash": dhash(img)})
            print(time.strftime("%H:%M:%S"), code, j.get("text") or j.get("skipped") or j.get("error"))
            if o.say or o.hud:
                st = get_state(); r = st.get("lastReply")
                HUD["scene"], HUD["reply"] = st.get("scene") or "", r or ""
                if o.say and r and r != last_reply: last_reply = r; subprocess.Popen(["say", r])
        except subprocess.CalledProcessError:
            print("screencapture failed: grant Screen Recording permission to your Terminal, or the window closed.")
        except Exception as e:
            print("error:", e)
        time.sleep(max(0.2, o.interval - (time.time() - t0)))

if __name__ == "__main__": main()
