Grok Glasses server (xAI only). POST /analyze {image:dataURL} -> {text}; POST /chat {text,history?} -> {text}.
Deploy: npx wrangler login && npx wrangler secret put XAI_API_KEY && (optional) npx wrangler secret put GLASSES_TOKEN && npx wrangler deploy
Node: XAI_API_KEY=... node server.mjs
