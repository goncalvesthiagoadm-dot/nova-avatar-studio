"use strict";
const $=id=>document.getElementById(id);
const state={id:null,projects:[],engines:[],engine:"audio-replace",videoUrl:null,apiKey:sessionStorage.getItem("nova_studio_key")||"",timer:null};
const toast=msg=>{const n=$("toast");n.textContent=msg;n.classList.add("visible");setTimeout(()=>n.classList.remove("visible"),3600)};
async function api(url,options={}){
  const headers={...(options.headers||{})};
  if(state.apiKey)headers["x-api-key"]=state.apiKey;
  const r=await fetch(url,{...options,headers});
  const obj=r.headers.get("content-type")?.includes("json")?await r.json():null;
  if(!r.ok)throw new Error(obj?.detail||`Erro HTTP ${r.status}`);
  return obj;
}
function setConnected(connected){$("healthDot").classList.toggle("on",connected);$("serverStatus").textContent=connected?"Motor conectado":"Motor indisponível"}
function selectProject(p){
  state.id=p.id;$("projectName").value=p.name;$("script").value=p.script;
  $("charCount").textContent=p.script.length+" / 4000";
  $("projectBadge").textContent="Projeto ativo";$("currentCrumb").textContent=p.name;
  $("dropVideo").classList.toggle("loaded",!!p.video);$("dropAudio").classList.toggle("loaded",!!p.audio);
  $("dropVideo").querySelector(".pick-label").textContent=p.video?"✓ Vídeo enviado":"Selecionar vídeo ↗";
  $("dropAudio").querySelector(".pick-label").textContent=p.audio?"✓ Áudio enviado":"Selecionar áudio ↗";
  renderProjects();
}
function renderProjects(){
  const el=$("projects");el.replaceChildren();
  if(!state.projects.length){const p=document.createElement("p");p.className="muted small";p.textContent="Nenhum projeto salvo";el.append(p);return}
  state.projects.forEach(p=>{
    const b=document.createElement("button");b.className="navitem"+(p.id===state.id?" active":"");
    b.textContent="▣  "+p.name;b.title=p.name;b.onclick=()=>selectProject(p);el.append(b);
  });
}
async function loadProjects(){
  state.projects=await api("/api/v1/projects");
  if(state.projects.length)selectProject(state.projects.find(p=>p.id===state.id)||state.projects[0]);
  else{state.id=null;renderProjects();}
}
function renderEngines(){
  const parent=$("engineOptions");parent.replaceChildren();
  state.engines.forEach(e=>{
    const l=document.createElement("label");l.className="engine"+(state.engine===e.id?" selected":"")+(e.available?"":" unavailable");
    const check=document.createElement("input");check.type="radio";check.name="engine";check.value=e.id;check.checked=state.engine===e.id;check.disabled=!e.available;
    const body=document.createElement("div");body.className="engine-info";
    const strong=document.createElement("strong");strong.textContent=e.name;
    const p=document.createElement("p");p.textContent=e.id==="audio-replace"?"Fluxo real de arquivos, mas sem animação labial":"Exige GPU e modelos oficiais instalados";
    body.append(strong,p);const tag=document.createElement("span");tag.className="engine-type";tag.textContent=e.available?"DISPONÍVEL":"NÃO INSTALADO";
    l.append(check,body,tag);
    l.onchange=()=>{if(!e.available)return;state.engine=e.id;renderEngines();updateEngineMessage()};parent.append(l);
  });updateEngineMessage();
}
function updateEngineMessage(){
  const selected=state.engines.find(e=>e.id===state.engine);
  $("selectedEngineName").textContent=selected?.name||"Não selecionado";
  $("engineNote").textContent=state.engine==="audio-replace"?"Teste técnico: junta seu vídeo-base com outro áudio. NÃO movimenta os lábios, nem usa IA. Para sincronia real selecione MuseTalk quando instalado.":"MuseTalk 1.5: gera sincronização labial com IA. A qualidade depende dos modelos, do vídeo-base e da GPU. Não promete equivalência ao HeyGen.";
}
async function boot(){
  try{const h=await api("/api/v1/health");setConnected(true);state.engines=h.engines;renderEngines();await loadProjects()}
  catch(e){
    setConnected(false);
    $("engineOptions").textContent=e.message.includes("Chave")
      ? "Acesso protegido. Toque em Entrar / Chave para informar sua chave privada."
      : "Não foi possível acessar a API.";
    toast("Conexão: "+e.message)
  }
}
async function save(){
  const name=$("projectName").value.trim(),script=$("script").value;
  if(!name){toast("Informe um nome de projeto.");$("projectName").focus();return}
  try{
    if(!state.id){const p=await api("/api/v1/projects",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({name,script})});state.id=p.id}
    else{
      const current=state.projects.find(x=>x.id===state.id);
      // Nome criado na primeira gravação; texto pode ser revisado sem afetar renderizações anteriores.
      if(current?.name!==name)toast("O nome atual é fixo após a criação; o roteiro foi salvo.");
      await api(`/api/v1/projects/${state.id}`,{method:"PATCH",headers:{"Content-Type":"application/json"},body:JSON.stringify({script})});
    }
    await loadProjects();toast("Projeto salvo com sucesso.");
  }catch(e){toast("Falha ao salvar: "+e.message)}
}
async function newProject(){
  state.id=null;$("projectName").value="";$("script").value="";$("charCount").textContent="0 / 4000";
  $("projectBadge").textContent="Novo projeto";$("currentCrumb").textContent="Novo projeto";
  for(const kind of ["video","audio"]){const zone=$(kind==="video"?"dropVideo":"dropAudio");zone.classList.remove("loaded");zone.querySelector(".pick-label").textContent="Selecionar "+kind+" ↗"}
  if(state.videoUrl)URL.revokeObjectURL(state.videoUrl);state.videoUrl=null;$("videoPreview").hidden=true;
  $("stageInner").hidden=false;renderProjects();$("projectName").focus();toast("Novo projeto preparado.");
}
async function upload(kind,file){
  if(!file)return;
  if(!state.id){toast("Salve o projeto antes de enviar arquivos.");return}
  const form=new FormData();form.append("file",file);
  try{
    $("uploadInfo").textContent="Enviando e validando "+file.name+"…";
    const info=await api(`/api/v1/projects/${state.id}/assets/${kind}`,{method:"POST",body:form});
    $("uploadInfo").textContent=kind==="video"?`Vídeo validado: ${info.duration}s.`:`Áudio validado: ${info.duration}s.`;
    await loadProjects();
    if(kind==="video"){
      if(state.videoUrl)URL.revokeObjectURL(state.videoUrl);
      state.videoUrl=URL.createObjectURL(file);$("videoPreview").src=state.videoUrl;$("videoPreview").hidden=false;$("stageInner").hidden=true;
      setStage("Vídeo-base carregado","Prévia local. Nenhum movimento de IA foi produzido.","READY",true);
    }
    toast("Arquivo enviado e validado.");
  }catch(e){$("uploadInfo").textContent="Erro: "+e.message;toast(e.message)}
}
function setStage(heading,description,status,good=false){$("resultHeading").textContent=heading;$("resultDescription").textContent=description;$("renderState").textContent=status;$("stageDot").classList.toggle("on",good)}
async function exportVideo(id){
  const u=`/api/v1/jobs/${id}/download`;const headers={};if(state.apiKey)headers["x-api-key"]=state.apiKey;
  const resp=await fetch(u,{headers});if(!resp.ok)throw new Error("Falha ao baixar vídeo");
  const blob=await resp.blob();const url=URL.createObjectURL(blob);
  const a=document.createElement("a");a.href=url;a.download="nova-studio-"+id.slice(0,8)+".mp4";a.click();setTimeout(()=>URL.revokeObjectURL(url),5000);
}
async function checkJob(jid){
  const j=await api(`/api/v1/jobs/${jid}`);
  $("lastJob").textContent="Render: "+j.status;
  if(["queued","running"].includes(j.status)){
    setStage(j.status==="queued"?"Na fila":"Processando vídeo…","O processamento ocorre no servidor; o navegador pode permanecer aberto.",j.status.toUpperCase());
    state.timer=setTimeout(()=>checkJob(jid).catch(e=>toast(e.message)),2000);return;
  }
  $("renderBtn").disabled=false;
  if(j.status==="done"){
    setStage("Vídeo processado","Arquivo MP4 pronto. A sincronização labial depende do motor escolhido.","DONE",true);
    $("download").hidden=false;$("download").dataset.job=jid;
    toast("Vídeo pronto para exportação.");
  }else{setStage("Renderização não concluída",j.error||"Tente novamente.","ERROR");toast(j.error||"Falha no processamento")}
}
async function render(){
  if(!state.id){toast("Crie e salve um projeto antes de processar.");return}
  $("download").hidden=true;
  try{
    const result=await api(`/api/v1/projects/${state.id}/render`,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({engine:state.engine})});
    $("renderBtn").disabled=true;await checkJob(result.job_id);
  }catch(e){toast(e.message);setStage("Arquivos ou motor incompletos",e.message,"ATTENTION");$("renderBtn").disabled=false}
}
$("saveProject").onclick=save;
for(const x of ["newProjectSide","newProjectTop"])$(x).onclick=newProject;
$("navStudio").onclick=()=>{document.querySelector(".content").scrollIntoView({behavior:"smooth"})};
$("navProjects").onclick=()=>{$("projects").scrollIntoView({behavior:"smooth"})};
function openKeyDialog(){
  const dialog=$("keyDialog");
  $("apiKeyInput").value="";
  $("keyStatus").hidden=true;
  $("keyStatus").classList.remove("success");
  dialog.showModal();
  $("apiKeyInput").focus();
}
$("changeKey").onclick=openKeyDialog;
$("cancelKey").onclick=()=>$("keyDialog").close();
$("toggleKeyVisibility").onclick=()=>{
  const input=$("apiKeyInput"), visible=input.type==="text";
  input.type=visible?"password":"text";
  $("toggleKeyVisibility").textContent=visible?"Mostrar":"Ocultar";
  $("toggleKeyVisibility").setAttribute("aria-label",visible?"Mostrar chave":"Ocultar chave");
};
$("keyForm").onsubmit=async e=>{
  e.preventDefault();
  const candidate=$("apiKeyInput").value.trim(), button=$("saveKey"), status=$("keyStatus");
  if(!candidate){status.textContent="Cole a chave privada para continuar.";status.hidden=false;return}
  button.disabled=true;button.textContent="Validando…";
  status.hidden=true;status.classList.remove("success");
  try{
    const response=await fetch("/api/v1/health",{headers:{"x-api-key":candidate},cache:"no-store"});
    const result=response.headers.get("content-type")?.includes("json")?await response.json():null;
    if(!response.ok)throw new Error(response.status===401?"A chave foi rejeitada. Confira se copiou somente o valor depois de STUDIO_API_TOKEN=, sem aspas.":(result?.detail||`Erro HTTP ${response.status}`));
    state.apiKey=candidate;
    sessionStorage.setItem("nova_studio_key",candidate);
    $("keyDialog").close();
    toast("Chave validada e salva nesta sessão.");
    await boot();
  }catch(err){
    state.apiKey="";
    sessionStorage.removeItem("nova_studio_key");
    setConnected(false);
    status.textContent=err.message||"Não foi possível validar a chave.";
    status.hidden=false;
    $("apiKeyInput").focus();
  }finally{
    button.disabled=false;button.textContent="Validar e conectar";
  }
};
$("script").oninput=e=>{$("charCount").textContent=e.target.value.length+" / 4000"};
$("videoUpload").onchange=e=>upload("video",e.target.files?.[0]);
$("audioUpload").onchange=e=>upload("audio",e.target.files?.[0]);
$("renderBtn").onclick=render;
$("download").onclick=e=>{e.preventDefault();const jid=e.currentTarget.dataset.job;if(jid)exportVideo(jid).catch(err=>toast(err.message))};
$("hearScript").onclick=()=>{
  if(!("speechSynthesis" in window)){toast("Voz do navegador não disponível.");return}
  const text=$("script").value.trim();if(!text){toast("Escreva o roteiro antes de ouvir.");return}
  speechSynthesis.cancel();const u=new SpeechSynthesisUtterance(text);u.lang="pt-BR";u.rate=.98;speechSynthesis.speak(u);
  toast("Prévia com a voz do navegador (não gera arquivo de áudio).")
};
boot();
