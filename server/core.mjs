export const VISION_MODEL="grok-4.20-0309-non-reasoning", CHAT_MODEL="grok-4.20-0309-non-reasoning";
const ORIGINS=["https://raw.githack.com","https://rawcdn.githack.com","https://xoanonxo.github.io"];
const SYS="You are Grok on tiny smart-glasses display. Reply in at most 2 short sentences, plain text, no markdown.";
function cors(o){return{"Access-Control-Allow-Origin":ORIGINS.includes(o)||!o||o==="null"?(o||"*"):ORIGINS[0],"Access-Control-Allow-Methods":"POST,OPTIONS","Access-Control-Allow-Headers":"Content-Type,X-Glasses-Token","Vary":"Origin"}}
async function xai(env,model,messages){const r=await fetch("https://api.x.ai/v1/chat/completions",{method:"POST",headers:{"Content-Type":"application/json",Authorization:"Bearer "+env.XAI_API_KEY},body:JSON.stringify({model,messages,max_tokens:150})});
 const j=await r.json();if(!r.ok)throw new Error("xai "+r.status+": "+(j.error?.message||j.error||JSON.stringify(j)).toString().slice(0,200));return j.choices[0].message.content.trim()}
export async function handle(req,env){const o=req.headers.get("Origin")||"",h={...cors(o),"Content-Type":"application/json"};
 if(req.method==="OPTIONS")return new Response(null,{status:204,headers:h});
 const p=new URL(req.url).pathname;if(p==="/"||p==="/health")return new Response(JSON.stringify({ok:true}),{headers:h});
 if(req.method!=="POST")return new Response('{"error":"method"}',{status:405,headers:h});
 if(env.GLASSES_TOKEN&&req.headers.get("X-Glasses-Token")!==env.GLASSES_TOKEN)return new Response('{"error":"unauthorized"}',{status:401,headers:h});
 try{const b=await req.json();let text;
  if(p==="/analyze"){if(!/^data:image\//.test(b.image||""))throw new Error("image dataURL required");
   text=await xai(env,VISION_MODEL,[{role:"system",content:SYS},{role:"user",content:[{type:"image_url",image_url:{url:b.image,detail:"low"}},{type:"text",text:"Describe what is in this photo for a small display."}]}])}
  else if(p==="/chat"){if(!b.text)throw new Error("text required");const hist=(Array.isArray(b.history)?b.history:[]).slice(-10).filter(m=>["user","assistant"].includes(m.role)).map(m=>({role:m.role,content:String(m.content).slice(0,2000)}));
   text=await xai(env,CHAT_MODEL,[{role:"system",content:SYS},...hist,{role:"user",content:String(b.text).slice(0,4000)}])}
  else return new Response('{"error":"not found"}',{status:404,headers:h});
  return new Response(JSON.stringify({text}),{headers:h})}catch(e){return new Response(JSON.stringify({error:e.message}),{status:500,headers:h})}}
