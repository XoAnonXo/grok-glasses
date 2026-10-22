# Grok Glasses — Mac camera bridge
The glasses video-call your Mac on WhatsApp; this script grabs frames from the call window every 2s and sends them to Grok.

## Setup (once)
1. Install WhatsApp for Mac, sign in. On the glasses: "Hey Meta, video call <your Mac's WhatsApp contact>" (or start a WhatsApp video call from the phone and switch to the glasses camera). Answer on the Mac.
2. `python3 -m pip install pillow pyobjc-framework-Quartz`
3. System Settings → Privacy & Security → Screen & System Audio Recording → enable your Terminal (or iTerm). Restart Terminal.
4. `export GLASSES_TOKEN=<token from Grok Bot>`

## Run
```
python3 grok_frames.py --list      # show window ids (find WhatsApp)
python3 grok_frames.py             # auto-find the WhatsApp call window
python3 grok_frames.py --window 1234
python3 grok_frames.py --region 100,100,800,600   # fallback: screen region
python3 grok_frames.py --say       # also speak Grok's replies (Mac audio goes into the call)
```
Keep the call window visible-sized (it can be behind other windows with --window). The glasses page shows "Grok sees", "Grok says" and history.

## Optional: HUD on the glasses Display (--hud)
On a WhatsApp video call the glasses Display shows the Mac's outgoing video. `--hud` renders a black frame with big white text (Grok sees / Grok says) into a virtual camera.
1. Install OBS Studio (obsproject.com), open it once, click **Start Virtual Camera**, then **Stop** and quit OBS (this installs the camera extension; approve it in System Settings → General → Login Items & Extensions → Camera Extensions if asked).
2. `python3 -m pip install pyvirtualcam numpy`
3. `python3 grok_frames.py --hud --say`
4. In WhatsApp for Mac (during the call or in Settings → Video) choose **OBS Virtual Camera** as the camera.
`--say` speaks each new Grok reply with macOS `say`; WhatsApp sends Mac audio to the glasses' speakers if the Mac mic picks it up (use speakers, not headphones).

## Voice into the call via BlackHole (--say --say-device)
1. `brew install blackhole-2ch` (or download from existential.audio/blackhole), then reboot or restart Core Audio.
2. Audio MIDI Setup → "+" → Create Multi-Output Device with your speakers + BlackHole 2ch (so you hear it too), optional.
3. In WhatsApp for Mac → Settings → Calls / Video & Audio → Microphone: **BlackHole 2ch**.
4. `python3 grok_frames.py --hud --say --say-device "BlackHole 2ch"` — each new Grok reply is spoken straight into the call and heard in the glasses speakers. (`say -a ?` lists device names.)
Without BlackHole, plain `--say` plays on Mac speakers and the Mac mic picks it up.

## Auto-answer + always-on bridge (LaunchAgent)
`autoanswer.py` uses the Accessibility API to find WhatsApp's incoming-call Accept button and press it. `supervisor.py` loops: auto-answer, run `grok_frames.py --hud` while a call is active, stop it when it ends, and obey the server `/control` flag. Install:
1. `~/grok-glasses/.venv/bin/pip install pyobjc-framework-ApplicationServices pyobjc-framework-Cocoa`
2. Grant permissions ONCE to the real Python binary
   `/opt/homebrew/Cellar/python@3.14/3.14.7/Frameworks/Python.framework/Versions/3.14/bin/python3.14`
   (and `/usr/bin/osascript`) in System Settings → Privacy & Security:
   - **Accessibility** (to click Accept)
   - **Screen & System Audio Recording** (grok_frames.py capture)
   Easiest: run `~/grok-glasses/.venv/bin/python autoanswer.py --dump` once; macOS prompts for Accessibility — approve it, then drag the binary into the Screen Recording list too.
3. Load the agent: `launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.grokglasses.bridge.plist`
   Reload after edits: `launchctl bootout gui/$(id -u)/com.grokglasses.bridge; launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.grokglasses.bridge.plist`
4. Logs: `tail -f ~/grok-glasses/bridge.log`

### Remote control (no SSH)
`POST /control` with header `X-Glasses-Token` (body `{"cmd":"start"|"stop"|"answer"}` or `{"enabled":false}`) tells the running supervisor to force capture on/off. `GET /control` shows the latest `bridge` status it reported.
