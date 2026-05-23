(function(){
let ready=false,pending=null,currentAnchors=[],usedAnchors=new Set(),programmatic=false;
const content=document.getElementById("content");
const post=(name,body)=>window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers[name]&&window.webkit.messageHandlers[name].postMessage(body);
const esc=s=>String(s).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c]));
const isRemote=u=>/^https?:\/\//i.test(u||"");
function anchorFor(map){
 if(!map)return"";
 const start=map[0]+1,end=map[1];
 const hit=currentAnchors.find(a=>!usedAnchors.has(a.id)&&a.startLine<=start&&a.endLine>=start)||currentAnchors.find(a=>!usedAnchors.has(a.id)&&a.startLine>=start&&a.startLine<=end);
 if(!hit)return"";
 usedAnchors.add(hit.id);
 return hit.id;
}
function markdown(){
 const md=window.markdownit({html:true,linkify:true,typographer:false,highlight:(s,l)=>`<pre><code class="language-${esc(l||"")}">${esc(s)}</code></pre>`});
 const renderToken=md.renderer.renderToken.bind(md.renderer);
 md.renderer.renderToken=function(tokens,idx,options,env,self){
  const token=tokens[idx],id=token.nesting===1?anchorFor(token.map):"";
  if(id)token.attrSet("data-kaji-anchor-id",id);
  return renderToken(tokens,idx,options,env,self);
 };
 md.renderer.rules.fence=function(tokens,idx){
  const token=tokens[idx],info=(token.info||"").trim().split(/\s+/)[0].toLowerCase(),id=anchorFor(token.map);
  const attr=id?` data-kaji-anchor-id="${esc(id)}"`:"";
  if(info==="mermaid")return `<div class="mermaid"${attr}>${esc(token.content)}</div>`;
  return `<pre${attr}><code class="language-${esc(info)}">${esc(token.content)}</code></pre>`;
 };
 return md;
}
const md=markdown();
function sanitize(html){
 return DOMPurify.sanitize(html,{ADD_TAGS:["video","audio","source"],ADD_ATTR:["controls","poster","playsinline","type","data-kaji-anchor-id"],FORBID_TAGS:["script","style","iframe","object","embed"],RETURN_TRUSTED_TYPE:false});
}
function resolvedURL(value,base){
 try{return new URL(value,base||window.location.href)}catch{return null}
}
function localURL(url){
 return `kaji-preview-file://open?path=${encodeURIComponent(decodeURIComponent(url.pathname))}`;
}
function prepareMedia(root,payload){
 root.querySelectorAll("img,video,audio,source").forEach(el=>{
  const raw=el.getAttribute("src")||el.getAttribute("poster");
  if(!raw)return;
  const attr=el.hasAttribute("src")?"src":"poster";
  const url=resolvedURL(raw,payload.baseURL);
  if(!url)return;
  if(isRemote(url.href)&&!payload.allowRemoteImages){
   const block=document.createElement("div");
   block.className="kaji-remote-blocked";
   block.textContent="Remote media blocked";
   el.replaceWith(block);
   return;
  }
  if(url.protocol==="file:")el.setAttribute(attr,localURL(url));
 });
}
function nextMarker(source,start,kind){
 const regex=/<!--\s*(BEGIN|END)\s+([^>]+?)\s*-->/gi;
 regex.lastIndex=start;
 let match;
 while((match=regex.exec(source))){
  if(match[1].toUpperCase()!==kind)continue;
  const title=match[2].trim();
  if(title)return{start:match.index,end:regex.lastIndex,title};
 }
 return null;
}
function nextEndMarker(source,start,title){
 let search=start,marker;
 while((marker=nextMarker(source,search,"END"))){
  if(marker.title===title)return marker;
  search=marker.end;
 }
 return null;
}
function segments(source){
 const parts=[];
 let search=0,begin;
 while((begin=nextMarker(source,search,"BEGIN"))){
  const before=source.slice(search,begin.start).trim();
  if(before)parts.push({kind:"markdown",content:before});
  const end=nextEndMarker(source,begin.end,begin.title);
  if(!end){
   const rest=source.slice(begin.start).trim();
   if(rest)parts.push({kind:"markdown",content:rest});
   return parts;
  }
  const body=source.slice(begin.end,end.start).trim();
  if(body)parts.push({kind:"managed",title:begin.title,content:body});
  search=end.end;
 }
 const rest=source.slice(search).trim();
 if(rest)parts.push({kind:"markdown",content:rest});
 return parts.length?parts:[{kind:"markdown",content:source}];
}
function renderMarkdown(source){
 return segments(source||"").map(part=>{
  const body=sanitize(md.render(part.content||""));
  if(part.kind!=="managed")return body;
  return `<section class="kaji-managed-block"><header><span>${esc(part.title)}</span><span>Managed block</span></header><div>${body}</div></section>`;
 }).join("");
}
function renderMath(){
 if(!window.renderMathInElement)return;
 renderMathInElement(content,{throwOnError:false,delimiters:[{left:"$$",right:"$$",display:true},{left:"\\[",right:"\\]",display:true},{left:"$",right:"$",display:false},{left:"\\(",right:"\\)",display:false}]});
}
async function renderMermaid(){
 if(!window.mermaid)return;
 mermaid.initialize({startOnLoad:false,securityLevel:"strict",theme:"dark"});
 const nodes=[...content.querySelectorAll(".mermaid")];
 for(let i=0;i<nodes.length;i++){
  const node=nodes[i],source=node.textContent;
  try{const out=await mermaid.render(`kaji-mermaid-${Date.now()}-${i}`,source);node.innerHTML=out.svg}catch(error){node.className="kaji-error";node.textContent=String(error.message||error)}
 }
}
function applyTheme(theme){
 Object.entries(theme||{}).forEach(([key,value])=>document.documentElement.style.setProperty(`--${key}`,value));
}
function reportMetrics(){
 const geometries=[...content.querySelectorAll("[data-kaji-anchor-id]")].map(el=>({anchorID:el.dataset.kajiAnchorId,startLine:null,endLine:null,top:el.offsetTop,height:el.offsetHeight}));
 post("markdownMetrics",{geometries,maxScrollTop:Math.max(0,document.documentElement.scrollHeight-window.innerHeight),viewportHeight:window.innerHeight});
}
async function render(payload){
 pending=null;currentAnchors=payload.anchors||[];usedAnchors=new Set();applyTheme(payload.theme);
 content.className="markdown-body";
 content.innerHTML=renderMarkdown(payload.content);
 prepareMedia(content,payload);
 renderMath();
 await renderMermaid();
 reportMetrics();
 post("markdownReady",{});
}
window.KajiMarkdownPreview={render,scrollTo:y=>{programmatic=true;window.scrollTo({top:y,behavior:"auto"});setTimeout(()=>programmatic=false,80)}};
window.addEventListener("scroll",()=>{if(!programmatic)post("markdownScroll",{scrollTop:window.scrollY})},{passive:true});
window.addEventListener("resize",()=>setTimeout(reportMetrics,30));
ready=true;post("markdownShellReady",{});if(pending)render(pending);
})();
