import {handle} from "./core.mjs";
export class GlassesState{constructor(ctx,env){this.ctx=ctx;this.env=env}
 fetch(req){const s=this.ctx.storage;return handle(req,this.env,{get:()=>s.get("state"),put:v=>s.put("state",v)})}}
export default {fetch:(req,env)=>env.STATE.get(env.STATE.idFromName("main")).fetch(req)};
