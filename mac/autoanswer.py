#!/usr/bin/env python3
"""Find WhatsApp's incoming-call UI via the Accessibility API and press Accept.
Needs Accessibility permission for the Python binary that runs it.
  python autoanswer.py --dump      # print WhatsApp + NotificationCenter AX trees (to tune matching)
  python autoanswer.py --once      # try to answer once (exit 0 if a call was active/answered)
  python autoanswer.py             # loop
"""
import re, sys, time, subprocess
import ApplicationServices as AX
from AppKit import NSWorkspace

ACCEPT = re.compile(r"(accept|answer|join|\u043f\u0440\u0438\u043d\u044f\u0442\u044c|\u043e\u0442\u0432\u0435\u0442\u0438\u0442\u044c)", re.I)
INCALL = re.compile(r"(end call|leave|hang ?up|\u0437\u0430\u0432\u0435\u0440\u0448\u0438\u0442\u044c|mute|camera|\u0432\u044b\u043a\u043b\u044e\u0447\u0438\u0442\u044c)", re.I)

def trusted(prompt=False):
    try:
        if prompt:
            return AX.AXIsProcessTrustedWithOptions({AX.kAXTrustedCheckOptionPrompt: True})
        return AX.AXIsProcessTrusted()
    except Exception:
        return AX.AXIsProcessTrusted()

def target_pids():
    out = []
    for app in NSWorkspace.sharedWorkspace().runningApplications():
        n = (app.localizedName() or "").replace("\u200e", "").strip().lower()
        b = (app.bundleIdentifier() or "").lower()
        if any(x in n for x in ("whatsapp",)) or "notificationcenter" in b:
            out.append((app.processIdentifier(), n or b))
    return out

def attr(el, name):
    err, v = AX.AXUIElementCopyAttributeValue(el, name, None)
    return v if err == 0 else None

def actions(el):
    err, v = AX.AXUIElementCopyActionNames(el, None)
    return list(v) if err == 0 and v else []

def label(el):
    parts = [attr(el, a) for a in ("AXTitle", "AXDescription", "AXValue", "AXHelp", "AXIdentifier")]
    return " | ".join(str(p) for p in parts if p not in (None, ""))

def walk(el, depth=0, maxdepth=28):
    yield el, depth
    if depth >= maxdepth:
        return
    for c in (attr(el, "AXChildren") or []):
        yield from walk(c, depth + 1, maxdepth)

def roots():
    for pid, n in target_pids():
        yield n, AX.AXUIElementCreateApplication(pid)

def dump():
    for n, app in roots():
        print("=== %s" % n)
        for el, d in walk(app):
            print("  " * d + "%s [%s] %s" % (attr(el, "AXRole"), label(el), actions(el) or ""))

def scan():
    accept, incall = [], False
    for n, app in roots():
        for el, d in walk(app):
            role = attr(el, "AXRole") or ""
            lab = label(el)
            if role in ("AXButton", "AXCell", "AXImage", "AXStaticText", "AXMenuItem") and ACCEPT.search(lab or ""):
                if "AXPress" in actions(el):
                    accept.append((el, lab))
            if INCALL.search(lab or ""):
                incall = True
    return accept, incall

def press(el):
    return AX.AXUIElementPerformAction(el, "AXPress") == 0

def answer_once():
    accept, incall = scan()
    if incall and not accept:
        return "in_call"
    for el, lab in accept:
        if press(el):
            print("pressed Accept: %s" % lab)
            return "answered"
    return "no_call"

def main():
    if "--dump" in sys.argv:
        if not trusted(prompt=True):
            print("NOT TRUSTED: grant Accessibility to this Python binary, then retry.")
        dump(); return
    if not trusted(prompt=True):
        print("NOT TRUSTED for Accessibility; cannot click. Grant permission and retry.")
        sys.exit(2)
    if "--once" in sys.argv:
        r = answer_once(); print(r)
        sys.exit(0 if r in ("answered", "in_call") else 1)
    while True:
        try:
            r = answer_once()
            if r == "answered":
                print(time.strftime("%H:%M:%S"), "answered a call")
                time.sleep(3)
        except Exception as e:
            print("autoanswer error:", e)
        time.sleep(1)

if __name__ == "__main__":
    main()
