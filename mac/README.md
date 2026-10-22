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
