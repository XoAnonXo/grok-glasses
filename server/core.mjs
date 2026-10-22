export const VISION_MODEL="grok-4.20-0309-non-reasoning", CHAT_MODEL="grok-4.20-0309-non-reasoning";
const ORIGINS=["https://raw.githack.com","https://rawcdn.githack.com","https://xoanonxo.github.io"];
const SYS="You are Grok on a tiny smart-glasses display. Reply in at most 2 short sentences, plain text, no markdown.";
const VSYS="You are Grok, seeing through the user's smart glasses (frame from a video call). Describe the scene in 1-2 short sentences, plain text, focusing on what matters: people, objects, text, screens.";
const MIN_FRAME_MS=1800, KEEP=100;
function cors(o){return{"Access-Control-Allow-Origin":ORIGINS.includes(o)||!o||o==="null"?(o||"*"):ORIGINS[0],"Access-Control-Allow-Methods":"GET,POST,OPTIONS","Access-Control-Allow-Headers":"Content-Type,X-Glasses-Token","Vary":"Origin"}}
async function xai(env,model,messages){const r=await fetch("https://api.x.ai/v1/chat/completions",{method:"POST",headers:{"Content-Type":"application/json",Authorization:"Bearer "+env.XAI_API_KEY},body:JSON.stringify({model,messages,max_tokens:150})});
 const j=await r.json();if(!r.ok)throw new Error("xai "+r.status+": "+(j.error?.message||j.error||JSON.stringify(j)).toString().slice(0,200));return j.choices[0].message.content.trim()}
const ham=(a,b)=>{try{let x=BigInt("0x"+a)^BigInt("0x"+b),n=0;while(x){n+=Number(x&1n);x>>=1n}return n}catch{return 99}};
async function sha(s){const d=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(s));return [...new Uint8Array(d)].slice(0,8).map(b=>b.toString(16).padStart(2,"0")).join("")}
const blank=()=>({control:{enabled:true,cmd:"",cmdAt:0,by:""},bridge:{},pendingAsk:null,botReply:null,scene:"",sceneAt:0,lastReply:"",history:[],lastFrameAt:0,lastHash:"",lastSha:""});
// store: {get():Promise<state|null>, put(state):Promise}
export async function handle(req,env,store){const o=req.headers.get("Origin")||"",h={...cors(o),"Content-Type":"application/json"};
 const J=(b,s=200)=>new Response(JSON.stringify(b),{status:s,headers:h});
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:h});
 const p=new URL(req.url).pathname;if(p==="/"||p==="/health")return J({ok:true,v:8,hasXai:!!env.XAI_API_KEY,hasToken:!!env.GLASSES_TOKEN,hasRelay:!!(env.RELAY_URL&&env.RELAY_AUTH)});
 const st=Object.assign(blank(),(await store.get())||{});
 if(p==="/control"){
  if(!env.GLASSES_TOKEN)return J({error:"GLASSES_TOKEN not configured"},503);
  if(req.headers.get("X-Glasses-Token")!==env.GLASSES_TOKEN)return J({error:"unauthorized"},401);
  if(req.method==="GET")return J({...st.control,bridge:st.bridge,now:Date.now()});
  if(req.method!=="POST")return J({error:"method"},405);
  const b=await req.json().catch(()=>({}));
  if(typeof b.enabled==="boolean")st.control.enabled=b.enabled;
  if(typeof b.cmd==="string"){st.control.cmd=b.cmd.slice(0,40);st.control.cmdAt=Date.now()}
  if(b.bridge&&typeof b.bridge==="object")st.bridge={...b.bridge,at:Date.now()};
  await store.put(st);return J({...st.control,bridge:st.bridge})}
 if(p==="/ask"||p==="/reply"){
  if(!env.GLASSES_TOKEN)return J({error:"GLASSES_TOKEN not configured"},503);
  if(req.headers.get("X-Glasses-Token")!==env.GLASSES_TOKEN)return J({error:"unauthorized"},401);
  if(req.method!=="POST")return J({error:"method"},405);
  const b=await req.json().catch(()=>({}));const now=Date.now();
  if(p==="/ask"){const text=String(b.text||"").trim();if(!text)return J({error:"text required"},400);
   const bot=String(b.bot||"Grok Bot").slice(0,60);const id=crypto.randomUUID();
   const ask={id,text:text.slice(0,4000),bot,at:now,status:"pending"};
   st.pendingAsk=ask;st.history.push({role:"ask",text:ask.text,bot,at:now});st.history=st.history.slice(-KEEP);
   const RURL=(env.RELAY_URL||"").trim(),RAUTH=(env.RELAY_AUTH||"").trim();
   if(!RURL||!RAUTH){st.pendingAsk.status="relay_not_configured";await store.put(st);
    return J({id,status:"relay_not_configured",error:"relay not configured"},200)}
   await store.put(st);
   try{const r=await fetch(RURL,{method:"POST",headers:{Authorization:RAUTH,"Content-Type":"application/json"},
     body:JSON.stringify({id,text:ask.text,bot,scene:st.scene})});
    const ok=r.ok;const body=await r.text().catch(()=>"");
    const fresh=Object.assign(blank(),(await store.get())||{});
    if(fresh.pendingAsk&&fresh.pendingAsk.id===id)fresh.pendingAsk.status=ok?"sent":"relay_error";
    await store.put(fresh);
    return J({id,status:ok?"sent":"relay_error",relayStatus:r.status,relayBody:body.slice(0,200)},ok?200:502)}
   catch(e){const fresh=Object.assign(blank(),(await store.get())||{});
    if(fresh.pendingAsk&&fresh.pendingAsk.id===id)fresh.pendingAsk.status="relay_error";await store.put(fresh);
    const detail=String(e.message||e).split(RURL).join("<relay_url>");
    const diag={absoluteHttps:/^https:\/\//i.test(RURL),urlLen:RURL.length,authLen:RAUTH.length,host:(()=>{try{return new URL(RURL).host}catch{return "INVALID_URL"}})()};
    return J({id,status:"relay_error",error:detail,diag},502)}}
  // /reply
  const text=String(b.text||"").trim();if(!text)return J({error:"text required"},400);
  const bot=String(b.bot||(st.pendingAsk&&st.pendingAsk.bot)||"Grok Bot").slice(0,60);
  st.botReply={id:b.id||null,bot,text:text.slice(0,4000),at:now};
  if(st.pendingAsk&&(!b.id||st.pendingAsk.id===b.id))st.pendingAsk.status="answered";
  st.history.push({role:"bot",text:st.botReply.text,bot,at:now});st.history=st.history.slice(-KEEP);
  await store.put(st);return J({ok:true,botReply:st.botReply})}
 if(p==="/state"&&req.method==="GET")return J({scene:st.scene,sceneAt:st.sceneAt,lastReply:st.lastReply,pendingAsk:st.pendingAsk,botReply:st.botReply,history:st.history.slice(-20)});
 if(req.method!=="POST")return J({error:"method"},405);
 try{const b=await req.json();const now=Date.now();
  if(p==="/frame"){
   if(!env.GLASSES_TOKEN)return J({error:"GLASSES_TOKEN not configured"},503);
   if(req.headers.get("X-Glasses-Token")!==env.GLASSES_TOKEN)return J({error:"unauthorized"},401);
   if(!/^data:image\//.test(b.image||""))throw new Error("image dataURL required");
   if(now-st.lastFrameAt<MIN_FRAME_MS)return J({skipped:"rate",retryMs:MIN_FRAME_MS-(now-st.lastFrameAt)},429);
   const s=await sha(b.image),fresh=now-st.sceneAt>30000;
   if(!fresh&&(s===st.lastSha||(b.hash&&st.lastHash&&ham(b.hash,st.lastHash)<=4))){st.lastFrameAt=now;await store.put(st);return J({skipped:"duplicate",scene:st.scene})}
   st.lastFrameAt=now;await store.put(st);
   const text=await xai(env,VISION_MODEL,[{role:"system",content:VSYS},{role:"user",content:[{type:"image_url",image_url:{url:b.image,detail:"low"}},{type:"text",text:"What do I see right now?"}]}]);
   Object.assign(st,{scene:text,sceneAt:now,lastSha:s,lastHash:b.hash||""});
   const last=st.history[st.history.length-1];if(!(last&&last.role==="scene"&&last.text===text))st.history.push({role:"scene",text,at:now});
   st.history=st.history.slice(-KEEP);await store.put(st);return J({text,sceneAt:now})}
  if(p==="/chat"){if(!b.text)throw new Error("text required");const t=String(b.text).slice(0,4000);
   const turns=st.history.filter(m=>m.role!=="scene").slice(-10).map(m=>({role:m.role,content:m.text.slice(0,2000)}));
   const ctx=st.scene?[{role:"system",content:`Latest view from the user's glasses (${Math.round((now-st.sceneAt)/1000)}s ago): ${st.scene}`}]:[];
   const text=await xai(env,CHAT_MODEL,[{role:"system",content:SYS},...ctx,...turns,{role:"user",content:t}]);
   const fresh=Object.assign(blank(),(await store.get())||{});// re-read: frames may have landed meanwhile
   fresh.history.push({role:"user",text:t,at:now},{role:"assistant",text,at:Date.now()});fresh.history=fresh.history.slice(-KEEP);fresh.lastReply=text;await store.put(fresh);
   return J({text})}
  if(p==="/analyze"){if(!/^data:image\//.test(b.image||""))throw new Error("image dataURL required");
   return J({text:await xai(env,VISION_MODEL,[{role:"system",content:SYS},{role:"user",content:[{type:"image_url",image_url:{url:b.image,detail:"low"}},{type:"text",text:"Describe what is in this photo for a small display."}]}])})}
  return J({error:"not found"},404)}catch(e){return J({error:e.message},500)}}
