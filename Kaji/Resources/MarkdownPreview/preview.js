(function(){
let currentAnchors=[],usedAnchors=new Set(),anchorByID=new Map(),programmatic=false,programmaticTarget=null,programmaticTimer=null,renderGeneration=0,currentPayload=null;
const loadedScripts=new Map();
const content=document.getElementById("content");
const post=(name,body)=>window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers[name]&&window.webkit.messageHandlers[name].postMessage(body);
const esc=s=>String(s).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;","\"":"&quot;","'":"&#39;"}[c]));
const isRemote=u=>/^https?:\/\//i.test(u||"");
const raf=()=>new Promise(resolve=>requestAnimationFrame(resolve));
function anchorFor(map){
 if(!map)return"";
 const start=map[0]+1,end=map[1];
 const hit=currentAnchors.find(a=>!usedAnchors.has(a.id)&&a.startLine<=start&&a.endLine>=start)||currentAnchors.find(a=>!usedAnchors.has(a.id)&&a.startLine>=start&&a.startLine<=end);
 if(!hit)return"";
 usedAnchors.add(hit.id);
 return hit.id;
}
function markdownEngine(){
 const md=window.markdownit({html:true,linkify:true,typographer:false,highlight:(source,language)=>`<pre><code class="language-${esc(language||"")}">${esc(source)}</code></pre>`});
 const renderToken=md.renderer.renderToken.bind(md.renderer);
 md.renderer.renderToken=function(tokens,index,options,env,self){
  const token=tokens[index],id=token.nesting===1?anchorFor(token.map):"";
  if(id)token.attrSet("data-kaji-anchor-id",id);
  return renderToken(tokens,index,options,env,self);
 };
 md.renderer.rules.fence=function(tokens,index){
  const token=tokens[index],info=(token.info||"").trim().split(/\s+/)[0].toLowerCase(),id=anchorFor(token.map);
  const attr=id?` data-kaji-anchor-id="${esc(id)}"`:"";
  if(info==="mermaid")return `<div class="mermaid"${attr}>${esc(token.content)}</div>`;
  return `<pre${attr}><code class="language-${esc(info)}">${esc(token.content)}</code></pre>`;
 };
 return md;
}
const markdown=markdownEngine();
function sanitize(html){
 return DOMPurify.sanitize(html,{ADD_TAGS:["video","audio","source"],ADD_ATTR:["controls","poster","playsinline","type","data-kaji-anchor-id"],FORBID_TAGS:["script","style","iframe","object","embed"],RETURN_TRUSTED_TYPE:false});
}
function resolvedURL(value,base){
 try{return new URL(value,base||window.location.href)}catch{return null}
}
function localURL(url){
 return `kaji-markdown-file://open?path=${encodeURIComponent(decodeURIComponent(url.pathname))}`;
}
function prepareMedia(root,payload){
 root.querySelectorAll("img,video,audio,source").forEach(el=>{
  for(const attr of ["src","poster"]){
   const raw=el.getAttribute(attr);
   if(!raw)continue;
   const url=resolvedURL(raw,payload.baseURL);
   if(!url)continue;
   if(isRemote(url.href)&&!payload.allowRemoteImages){
    const block=document.createElement("div");
    block.className="kaji-remote-blocked";
    block.textContent="Remote media blocked";
    el.replaceWith(block);
    return;
   }
   if(url.protocol==="file:")el.setAttribute(attr,localURL(url));
  }
 });
}
function handleLinkClick(event){
 const link=event.target.closest&&event.target.closest("a[href]");
 if(!link||!content.contains(link))return;
 const href=link.getAttribute("href")||"";
 if(href.startsWith("#"))return;
 event.preventDefault();
 const url=resolvedURL(href,currentPayload&&currentPayload.baseURL);
 post("markdownLinkClicked",{href,resolvedURL:url?url.href:null});
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
 return parts.length?parts:[{kind:"markdown",content:source||""}];
}
function renderMarkdown(source){
 return segments(source).map(part=>{
  const body=sanitize(markdown.render(part.content||""));
  if(part.kind!=="managed")return body;
  return `<section class="kaji-managed-block"><header><span>${esc(part.title)}</span><span>Managed block</span></header><div>${body}</div></section>`;
 }).join("");
}
function renderMath(){
 if(!window.renderMathInElement)return;
 renderMathInElement(content,{throwOnError:false,delimiters:[{left:"$$",right:"$$",display:true},{left:"\\[",right:"\\]",display:true},{left:"$",right:"$",display:false},{left:"\\(",right:"\\)",display:false}]});
}
function loadScript(name){
 if(loadedScripts.has(name))return loadedScripts.get(name);
 const promise=new Promise((resolve,reject)=>{
  const script=document.createElement("script");
  script.src=`kaji-markdown://asset/vendor/${name}`;
  script.onload=resolve;
  script.onerror=()=>reject(new Error(`Failed to load ${name}`));
  document.head.appendChild(script);
 });
 loadedScripts.set(name,promise);
 return promise;
}
async function renderMermaid(generation){
 const nodes=[...content.querySelectorAll(".mermaid")];
 if(!nodes.length)return;
 try{
  if(!window.mermaid)await loadScript("mermaid.min.js");
  if(generation!==renderGeneration)return;
  mermaid.initialize({startOnLoad:false,securityLevel:"strict",theme:"dark"});
  for(let i=0;i<nodes.length;i++){
   if(generation!==renderGeneration)return;
   const node=nodes[i],source=node.textContent;
   const out=await mermaid.render(`kaji-mermaid-${generation}-${i}`,source);
   node.innerHTML=out.svg;
  }
 }catch(error){
  if(generation!==renderGeneration)return;
  nodes.forEach(node=>{node.className="kaji-error";node.textContent=String(error.message||error)});
 }
}
function applyTheme(payload){
 Object.entries(payload.theme||{}).forEach(([key,value])=>document.documentElement.style.setProperty(`--${key}`,value));
 const typography=payload.typography||{};
 const family=String(typography.fontFamily||"SF Mono").replace(/["\\;\n\r{}]/g,"");
 document.documentElement.style.setProperty("--font-family",`"${family}",-apple-system,BlinkMacSystemFont,"Helvetica Neue",Arial,sans-serif`);
 document.documentElement.style.setProperty("--font-size",`${Number(typography.fontSize||15)}px`);
 document.documentElement.style.setProperty("--line-height",String(Number(typography.lineHeight||1.58)));
}
function reportMetrics(){
 const geometries=[...content.querySelectorAll("[data-kaji-anchor-id]")].map(el=>{
  const anchor=anchorByID.get(el.dataset.kajiAnchorId)||{};
  return{anchorID:el.dataset.kajiAnchorId,startLine:anchor.startLine||null,endLine:anchor.endLine||null,top:el.offsetTop,height:el.offsetHeight};
 });
 post("markdownMetrics",{geometries,maxScrollTop:Math.max(0,document.documentElement.scrollHeight-window.innerHeight),viewportHeight:window.innerHeight});
}
function endProgrammaticScroll(){
 programmatic=false;programmaticTarget=null;
 if(programmaticTimer)clearTimeout(programmaticTimer);programmaticTimer=null;
}
function settleProgrammaticScroll(deadline){
 if(!programmatic)return;
 if(programmaticTarget!==null&&Math.abs(window.scrollY-programmaticTarget)<=1){
  requestAnimationFrame(()=>endProgrammaticScroll());
  return;
 }
 if(performance.now()>=deadline)return endProgrammaticScroll();
 return requestAnimationFrame(()=>settleProgrammaticScroll(deadline));
}
function scrollToTarget(y){
 const max=Math.max(0,document.documentElement.scrollHeight-window.innerHeight);
 programmaticTarget=Math.max(0,Math.min(Number(y)||0,max));programmatic=true;
 if(programmaticTimer)clearTimeout(programmaticTimer);
 window.scrollTo({top:programmaticTarget,behavior:"auto"});
 programmaticTimer=setTimeout(endProgrammaticScroll,700);
 requestAnimationFrame(()=>settleProgrammaticScroll(performance.now()+650));
}
async function render(payload){
 const generation=++renderGeneration;
 currentPayload=payload;
 currentAnchors=payload.anchors||[];
 anchorByID=new Map(currentAnchors.map(anchor=>[anchor.id,anchor]));
 usedAnchors=new Set();
 applyTheme(payload);
 const visible=content.classList.contains("kaji-visible");
 content.className=visible?"markdown-body kaji-visible":"markdown-body";
 content.innerHTML=renderMarkdown(payload.content||"");
 prepareMedia(content,payload);
 renderMath();
 reportMetrics();
 await raf();
 await raf();
 if(generation!==renderGeneration)return;
 content.classList.add("kaji-visible");
 post("markdownReady",{});
 renderMermaid(generation).then(()=>{if(generation===renderGeneration)reportMetrics()});
}
window.KajiMarkdownPreview={render,scrollTo:scrollToTarget};
content.addEventListener("click",handleLinkClick);
window.addEventListener("scroll",()=>{if(!programmatic)post("markdownScroll",{scrollTop:window.scrollY})},{passive:true});
window.addEventListener("resize",()=>setTimeout(reportMetrics,30));
post("markdownShellReady",{});
})();
