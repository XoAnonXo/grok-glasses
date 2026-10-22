# Grok Glasses — iOS (Meta Wearables Device Access Toolkit)

Native iOS app for **Meta Ray-Ban Display** glasses. It streams the glasses camera
to our xAI-backed Cloudflare Worker, shows "Grok sees" / "Grok says" on the glasses
Display, and lets you ask Grok by voice or text. **All AI goes through our server; no
xAI key is ever in the app.**

- SDK: `meta-wearables-dat-ios` **1.0.1** via Swift Package Manager (modules
  `MWDATCore`, `MWDATCamera`, `MWDATDisplay`, `MWDATMockDevice`, `MWDATSpeech`).
- Deployment target iOS 17.2, Swift 6.0. Project is generated with **XcodeGen**
  (`project.yml`); run `xcodegen generate` to produce `GrokGlasses.xcodeproj`.
- The glasses token is entered in the app and stored in the **Keychain**; it is
  never committed.
- Verified: compiles for the iOS Simulator and generic iOS device without signing
  (Xcode 26.1.1, iOS 26.1 SDK).

## Build
```
brew install xcodegen          # if needed
cd ios
xcodegen generate
open GrokGlasses.xcodeproj
```

## Run on glasses
1. In Xcode, select the **GrokGlasses** target → Signing & Capabilities → set your **Team**.
2. Plug in the iPhone, pick it as the run destination, Run.
3. In the **Meta AI** app, enable **Developer Mode** (Settings → your glasses → Developer Mode).
4. In Grok Glasses, tap **Register with Meta AI** and approve in Meta AI.
5. Paste the **glasses token** into the token field and tap **Save token**.
6. Tap **Start camera + display**, grant the camera permission in Meta AI.
   "Grok sees" / "Grok says" render on the Display and update ~every 2 s.
7. **Ask by voice (experimental)** adds Speech; or type a question and tap **Send**.
   Replies are spoken with `AVSpeechSynthesizer`.

## How it maps to the server (`server/core.mjs`)
- `POST /frame` body `{image: "data:image/jpeg;base64,…", hash}` with header
  `X-Glasses-Token`. Frames are throttled to ~1 / 2 s, downscaled to ~768 px, and
  near-duplicates are skipped with a 64-bit dHash (Hamming ≤ 4).
- `POST /chat {text}` for questions; `GET /state` is polled every 2 s for the
  latest scene, reply, and history. A browser-like **User-Agent** is sent because
  Cloudflare returns 1010 for odd UAs.

## Known limits
- **UAE is not a supported Meta developer country.** The toolkit downloads and the
  app builds, but registration and the Developer Center may be unavailable there.
- **Speech**, **in-stream audio**, and **standalone camera capture** are
  **experimental** in DAT and cannot be published to production release channels yet.
- Publishing to a store is not open; share via sideload/TestFlight with Developer Mode.
- `AVSpeechSynthesizer` plays to the current audio route; it reaches the glasses only
  when they are the active audio output.
- Without Developer Mode, `MetaAppID`/`ClientToken` from the Wearables Developer Center
  and your Apple Team ID in `MWDAT.TeamID` are required.
