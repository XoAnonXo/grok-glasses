import http from "node:http";import {handle} from "./core.mjs";
const PORT=process.env.PORT||8787;let mem=null;const store={get:async()=>mem&&structuredClone(mem),put:async v=>{mem=structuredClone(v)}};
http.createServer(async(q,s)=>{const ch=[];for await(const c of q)ch.push(c);const body=Buffer.concat(ch);
 const req=new Request("http://localhost"+q.url,{method:q.method,headers:q.headers,body:["GET","HEAD","OPTIONS"].includes(q.method)?undefined:body});
 const r=await handle(req,process.env,store);s.writeHead(r.status,Object.fromEntries(r.headers));s.end(Buffer.from(await r.arrayBuffer()))}).listen(PORT,()=>console.log("listening "+PORT));
