Grok Glasses server (xAI only, Cloudflare Worker + SQLite Durable Object).
POST /frame {image:dataURL, hash?} (header X-Glasses-Token) -> {text} | 429 rate | {skipped:"duplicate"}
POST /chat {text} -> {text}   (context includes latest scene; both turns stored)
GET /state -> {scene, sceneAt, lastReply, history[last 20]}
POST /analyze {image} -> {text}
Deploy: npx wrangler login && npx wrangler secret put XAI_API_KEY && npx wrangler secret put GLASSES_TOKEN && npx wrangler deploy
Node: XAI_API_KEY=... GLASSES_TOKEN=... node server.mjs
