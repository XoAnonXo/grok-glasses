import {handle} from "./core.mjs";

// The Durable Object captures env at construction time, so a warm instance
// created before a secret was added never sees it. The stateless top-level
// worker always has fresh env, so it injects a fresh snapshot on every request
// (internal subrequest only; never leaves Cloudflare).
export class GlassesState{
  constructor(ctx,env){this.ctx=ctx;this.env=env}
  fetch(req){
    let env=this.env;
    const ovr=req.headers.get("X-Env-Override");
    if(ovr){try{env={...this.env,...JSON.parse(decodeURIComponent(escape(atob(ovr))))}}catch{}}
    const s=this.ctx.storage;
    return handle(req,env,{get:()=>s.get("state"),put:v=>s.put("state",v)});
  }
}

export default {
  fetch:(req,env)=>{
    const stub=env.STATE.get(env.STATE.idFromName("main"));
    const r=new Request(req);
    const snap={XAI_API_KEY:env.XAI_API_KEY||"",GLASSES_TOKEN:env.GLASSES_TOKEN||"",RELAY_URL:env.RELAY_URL||"",RELAY_AUTH:env.RELAY_AUTH||""};
    r.headers.set("X-Env-Override", btoa(unescape(encodeURIComponent(JSON.stringify(snap)))));
    return stub.fetch(r);
  }
};
