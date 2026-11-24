import { GCAccount } from "./account.js";
import { appEvents } from "./app-events.js";

  const $ = id => document.getElementById(id);
  const status = (id, message) => { const el=$(id); if(el) el.textContent=message||""; };
  let currentView="", wallet=null, catalog=[], inventory=new Set(), equipped={}, currentStage=null, weeklyRank=false, assessmentSession=null, assessmentQuestions=[], assessmentAnswers=new Map();
  const ECONOMY_REWARDS_ENABLED = false; // Activar solo tras validar operaciones económicas en servidor.
  const categoryNames={skin:"Tono",hair:"Cabello",top:"Prenda",bottom:"Pantalón",shoes:"Calzado",accessory:"Accesorio",background:"Fondo"};
  const achievements={first_activity:["Primer paso","Completa tu primera actividad."],letters10:["Explorador del alfabeto","Completa diez letras."],alphabet:["Alfabeto completo","Completa las 26 letras."],word10:["Constructor de palabras","Completa diez palabras."],xp500:["Aprendiz constante","Acumula 500 XP."]};
  const dbClient=async()=>{const c=await GCAccount.getClient(); if(!c) throw new Error("Configura Supabase para usar esta función."); return c;};
  const currentUser=()=>GCAccount.getUser()||null;
  async function rpc(name,args={}){const db=await dbClient();const {data,error}=await db.rpc(name,args);if(error)throw error;return data;}
  function requireUser(){if(!currentUser())throw new Error("Inicia sesión para continuar.");}
  function showMessage(message){const el=$("toast");if(el){el.textContent=message;el.classList.add("show");setTimeout(()=>el.classList.remove("show"),2600);}}
  const node=(tag,cls,text)=>{const e=document.createElement(tag);if(cls)e.className=cls;if(text!==undefined)e.textContent=text;return e;};
  function signedInMessage(target){status(target,currentUser()?"":"Inicia sesión para guardar datos en la comunidad.");}

  async function loadWallet(){
    if(!currentUser()){wallet=null;$("coinBalance").textContent="0";return;}
    wallet=await rpc("get_my_v2_profile");
    $("coinBalance").textContent=String(wallet?.coin_balance||0);
  }
  async function awardCompletion(type,key){
    if(!ECONOMY_REWARDS_ENABLED || !currentUser())return;
    const activity_type={letters:"letter",words:"word",phrases:"phrase"}[type];
    if(!activity_type)return;
    try{const result=await rpc("claim_learning_completion",{p_activity_type:activity_type,p_activity_key:key});await loadWallet();if(result?.awarded)showMessage(`+${result.xp_awarded} XP Â· +${result.coins_awarded} monedas`);}
    catch(error){console.warn("No se pudo registrar la recompensa:",error);showMessage("No se pudo sincronizar la recompensa.");}
  }
  async function onLearningCompletion(type, key, isFirstCompletion) {
    if (!isFirstCompletion || !ECONOMY_REWARDS_ENABLED) return;
    await awardCompletion(type, key);
  }

  async function recordChallengeActivity(type,key){
    if(!currentUser())return;
    const activity_type={letters:"letter",words:"word",phrases:"phrase"}[type];if(!activity_type)return;
    try{await rpc("record_challenge_activity",{p_activity_type:activity_type,p_activity_key:key});}
    catch(error){console.warn("No se pudo registrar actividad de desafío:",error);}
  }

  function renderAvatar(){
    const host=$("avatarPreview");if(!host)return;
    host.replaceChildren();
    const stage=node("div","avatar-stage");
    const person=node("div","avatar-doll");
    const part=(cls,category,fallback)=>{const el=node("span",cls);const item=catalog.find(x=>x.item_key===(equipped[category]||fallback));if(item&&/^#[0-9a-f]{6}$/i.test(item.color_hex))el.style.setProperty("--part-color",item.color_hex);if(item?.icon)el.textContent=item.icon;person.append(el);};
    const bg=catalog.find(x=>x.item_key===(equipped.background||"background_dusk"));if(bg&&/^#[0-9a-f]{6}$/i.test(bg.color_hex))stage.style.setProperty("--avatar-bg",bg.color_hex);
    part("avatar-hair","hair","hair_midnight");part("avatar-head","skin","skin_sand");
    person.append(node("span","avatar-eyes","•  •"));part("avatar-torso","top","top_sky");part("avatar-legs","bottom","bottom_ink");part("avatar-shoes","shoes","shoes_cloud");part("avatar-accessory","accessory","accessory_none");
    stage.append(person);host.append(stage);
  }
  async function loadShop(){
    const host=$("avatarCatalog");if(!host)return;
    if(!currentUser()){host.replaceChildren(node("p","muted","Inicia sesión para ver tu inventario y comprar artículos."));return;}
    const db=await dbClient();
    const [items,owned]=await Promise.all([db.from("avatar_items").select("item_key,category,display_name,color_hex,icon,price,is_starter").eq("active",true).order("category").order("price"),db.from("player_inventory").select("avatar_items(item_key)")]);
    if(items.error)throw items.error;if(owned.error)throw owned.error;
    catalog=items.data||[];inventory=new Set((owned.data||[]).map(x=>x.avatar_items?.item_key).filter(Boolean));
    await loadWallet();equipped=wallet?.equipped||{};renderAvatar();renderCatalog();await loadMission();
  }
  function renderCatalog(){
    const host=$("avatarCatalog");if(!host)return;host.replaceChildren();
    const filter=$("avatarCategory").value;
    catalog.filter(i=>!filter||i.category===filter).forEach(item=>{
      const card=node("article","feature-card item-card");const swatch=node("span","item-swatch");swatch.style.backgroundColor=item.color_hex;
      const title=node("strong","",item.display_name);const meta=node("small","muted",`${categoryNames[item.category]||item.category} Â· ${inventory.has(item.item_key)?"En inventario":`${item.price} monedas`}`);
      const button=node("button",inventory.has(item.item_key)?"secondary-btn":"primary-btn",inventory.has(item.item_key)?(equipped[item.category]===item.item_key?"Equipado":"Equipar"):(ECONOMY_REWARDS_ENABLED?"Comprar · "+item.price+" ◉":"Compras en pausa"));button.type="button";button.disabled=!inventory.has(item.item_key)&&!ECONOMY_REWARDS_ENABLED;
      button.addEventListener("click",async()=>{try{if(inventory.has(item.item_key))equipped=await rpc("equip_avatar_item",{p_item_key:item.item_key});else if(ECONOMY_REWARDS_ENABLED){await rpc("purchase_avatar_item",{p_item_key:item.item_key});showMessage("Artículo desbloqueado.");}else return;await loadShop();}catch(error){showMessage(error.message||"No se pudo completar la acción.");}});
      card.append(swatch,title,meta,button);host.append(card);
    });
  }
  async function loadMission(){
    if(!ECONOMY_REWARDS_ENABLED){status("dailyMission","Recompensas en pausa: validación económica pendiente.");$("claimMission").disabled=true;return;}
    if(!currentUser()){status("dailyMission","Inicia sesión para consultar la misión.");$("claimMission").disabled=true;return;}
    const m=await rpc("get_daily_mission_status");$("dailyMission").textContent=`Completa ${m.completed} de ${m.target} actividades Â· recompensa: ${m.reward} monedas${m.claimed?" Â· Reclamada":""}`;$("claimMission").disabled=Boolean(m.claimed)||m.completed<m.target;
  }

  async function loadLeaderboard(weekly=weeklyRank){
    const body=$("leaderboardRows");body.replaceChildren();
    try{const metric=$("rankMetric").value;$("rankScoreHeader").textContent=metric==="experience"?"XP":metric==="precision"?"Precisión":metric==="consistency"?"Días":"Progreso";const rows=await rpc("get_learning_leaderboard",{p_metric:metric,p_weekly:weekly});if(!rows?.length){body.append(node("tr","","No hay resultados todavía."));return;}
      rows.forEach(row=>{const tr=node("tr");tr.append(node("td","rank-position",String(row.position)),node("td","",`${row.display_name} Â· @${row.username}`),node("td","",`${row.score} ${metric==="experience"?"XP":metric==="consistency"?"días":metric==="weekly_activity"?"actividades":metric==="precision"?"%":"contenidos"}`));body.append(tr);});
    }catch(error){body.append(node("tr","",error.message||"No se pudo cargar la clasificación."));}
  }

  async function startAssessment(){
    try{requireUser();const result=await rpc("start_learning_assessment");assessmentSession=result.session_id;assessmentQuestions=result.questions||[];assessmentAnswers=new Map();const host=$("assessmentQuestions");host.replaceChildren();
      assessmentQuestions.forEach((q,index)=>{const card=node("article","assessment-card");card.append(node("strong","",`Pregunta ${index+1}`));const img=node("img","assessment-reference");img.src=`assets/letras/${q.target}.png`;img.alt=`Referencia manual, pregunta ${index+1}`;img.loading="lazy";card.append(img);const choices=node("div","assessment-choices");q.choices.forEach(letter=>{const b=node("button","quiz-choice",letter);b.type="button";b.onclick=()=>{assessmentAnswers.set(q.id,letter);choices.querySelectorAll("button").forEach(x=>x.classList.toggle("selected",x===b));$("submitAssessment").disabled=assessmentAnswers.size!==assessmentQuestions.length;};choices.append(b);});card.append(choices);host.append(card);});
      $("submitAssessment").disabled=true;status("assessmentResult","Selecciona una respuesta para cada referencia.");
    }catch(error){status("assessmentResult",error.message||"Inicia sesión para evaluar tu aprendizaje.");}
  }
  async function submitAssessment(){
    try{requireUser();if(!assessmentSession||assessmentAnswers.size!==assessmentQuestions.length)throw new Error("Responde todas las preguntas.");const answers=[...assessmentAnswers].map(([id,answer])=>({id,answer}));const result=await rpc("submit_learning_assessment",{p_session_id:assessmentSession,p_answers:answers});status("assessmentResult",`Resultado: ${result.correct}/${result.total} Â· precisión ${result.accuracy_percent}%.`);assessmentSession=null;$("submitAssessment").disabled=true;$("startAssessment").disabled=false;await loadLeaderboard();}
    catch(error){status("assessmentResult",error.message||"No se pudo enviar la evaluación.");}
  }
  async function loadCommunity(){
    const host=$("communityStages");host.replaceChildren();
    try{
      const rows=await rpc("get_public_stage_cards",{p_category:$("stageCategory").value||null,p_difficulty:$("stageDifficulty").value?Number($("stageDifficulty").value):null,p_stage_ids:null,p_sort:$("stageSort").value});
      if(!rows?.length){host.append(node("p","muted","Todavía no hay etapas publicadas."));return;}
      rows.forEach(stage=>{
        const card=node("article","feature-card stage-card"),h=node("h3","",stage.title);
        const author=`${stage.author_display_name||"Jugador"}${stage.author_username?` Â· @${stage.author_username}`:""}`;
        const summary=node("p","muted",stage.description||"Etapa de la comunidad");
        const info=node("small","muted",`${stage.category} Â· dificultad ${stage.difficulty}/5 Â· ${(stage.prompts||[]).length} indicaciones Â· ${stage.play_count} participantes Â· ★ ${Number(stage.average_rating||0).toFixed(1)}`);
        const actions=node("div","card-actions"),play=node("button","primary-btn","Jugar etapa");play.type="button";play.onclick=()=>openStage(stage);
        const authorLink=node("button","account-link",author);authorLink.type="button";authorLink.onclick=()=>openPublicProfile(stage.author_username);
        actions.append(play);card.append(h,authorLink,summary,info,actions);host.append(card);
      });
    }catch(error){host.append(node("p","muted",error.message||"Configura Supabase y aplica las migraciones para explorar."));}
  }
  const average=stage=>Number(stage.average_rating||0);
  function openStage(stage){
    currentStage=stage;$("stagePlayTitle").textContent=stage.title;$("stagePlayDescription").textContent=stage.description||"";
    const list=$("stagePlayPrompts");list.replaceChildren();(stage.prompts||[]).forEach(p=>list.append(node("li","",p)));
    $("stageReviewControls").hidden=true;$("stagePlayStatus").textContent="";$("stagePlayDialog").showModal();
  }
  async function loadFavorites(){
    const host=$("favoriteStages");host.replaceChildren();if(!currentUser()){host.append(node("p","muted","Inicia sesión para guardar y consultar favoritos."));return;}
    try{const rows=await rpc("get_my_favorite_stage_cards");if(!rows?.length){host.append(node("p","muted","Todavía no guardas etapas."));return;}
      rows.forEach(stage=>{const card=node("article","feature-card");card.append(node("strong","",stage.title),node("small","muted",stage.author_display_name||"Jugador"));const b=node("button","secondary-btn","Jugar");b.onclick=()=>openStage(stage);card.append(b);host.append(card);});
    }catch(error){host.append(node("p","muted",error.message||"No se pudieron cargar tus favoritas."));}
  }
  async function openPublicProfile(username){
    if(!username)return;const host=$("publicProfileContent");host.replaceChildren();$("publicProfileName").textContent="Perfil público";$("publicProfileDialog").showModal();
    try{const info=await rpc("get_public_profile",{p_username:username});if(!info){host.append(node("p","muted","Este perfil no está disponible públicamente."));return;}
      $("publicProfileName").textContent=`${info.display_name} Â· @${info.username}`;
      [["Experiencia",info.xp_total===null?"Oculta":`${info.xp_total} XP`], ["Etapas creadas",info.stages_created], ["Etapas publicadas",info.stages_published]].forEach(([label,value])=>{const card=node("article","feature-card");card.append(node("strong","",String(value)),node("small","",label));host.append(card);});
    }catch(error){host.append(node("p","muted",error.message||"No se pudo cargar el perfil."));}
  }
  async function loadMyStages(){
    const host=$("myStages");host.replaceChildren();
    if(!currentUser()){host.append(node("p","muted","Inicia sesión para guardar tus etapas."));return;}
    const data=await rpc("get_my_stages");
    if(!data?.length){host.append(node("p","muted","Aún no has creado etapas."));return;}
    data.forEach(stage=>{
      const row=node("div","history-item");
      row.append(node("span","",stage.title),node("span","",stage.status+(stage.moderation_note?" Â· "+stage.moderation_note:"")));
      if(["draft","rejected"].includes(stage.status)){
        const button=node("button","secondary-btn","Enviar a revisión");
        button.onclick=async()=>{try{await rpc("submit_stage_for_review",{p_stage_id:stage.id});showMessage("Enviada a revisión.");await loadMyStages();}catch(error){showMessage(error.message||"No se pudo enviar.");}};
        row.append(button);
      }
      host.append(row);
    });
  }
  async function loadModeration(){
    const panel=$("moderationPanel"),host=$("moderationQueue");panel.hidden=true;host.replaceChildren();if(!currentUser())return;
    try{
      const rows=await rpc("get_moderation_queue");panel.hidden=false;
      if(!rows?.length){host.append(node("p","muted","La cola está vacía."));return;}
      rows.forEach(stage=>{
        const card=node("article","feature-card");
        card.append(node("strong","",stage.title));
        card.append(node("p","muted",(stage.author_username||"Jugador")+" Â· "+stage.report_count+" reportes"));
        card.append(node("p","",stage.description||""));
        card.append(node("p","",(stage.prompts||[]).join(" Â· ")));
        card.append(node("small","muted",stage.report_summary||""));
        [[true,"Aprobar"],[false,"Rechazar"]].forEach(([approved,label])=>{
          const button=node("button",approved?"primary-btn":"danger-btn",label);
          button.onclick=async()=>{try{const note=approved?"":(prompt("Motivo del rechazo (máximo 500 caracteres):")||"");await rpc("moderate_stage",{p_stage_id:stage.stage_id,p_approved:approved,p_note:note});await loadModeration();}catch(error){showMessage(error.message||"No se pudo moderar.");}};
          card.append(button);
        });
        host.append(card);
      });
    }catch(_){panel.hidden=true;}
  }

  async function loadProfile(){
    if(!currentUser()){$("profileSummary").textContent="Inicia sesión para ver tu perfil.";return;}
    try{
      const data=await rpc("get_my_v2_profile");wallet=data;
      $("profileSummary").textContent=data.profile.display_name+" Â· @"+data.profile.username+" Â· nivel de XP "+(Math.floor((data.xp_total||0)/500)+1)+" Â· "+(data.xp_total||0)+" XP Â· "+(data.coin_balance||0)+" monedas";
      $("settingShowProfile").checked=data.settings?.show_profile!==false;$("settingShowXp").checked=data.settings?.show_xp!==false;$("settingShowActivity").checked=Boolean(data.settings?.show_activity);
      const own=await dbClient();const result=await own.from("player_achievements").select("achievement_key,earned_at");if(result.error)throw result.error;
      const grid=$("achievementList");grid.replaceChildren();
      Object.entries(achievements).forEach(([key,value])=>{const unlocked=(result.data||[]).some(x=>x.achievement_key===key);const card=node("article","feature-card "+(unlocked?"":"locked"));card.append(node("strong","",(unlocked?"🏅":"â—‹")+" "+value[0]),node("small","",value[1]));grid.append(card);});
      const stats=await rpc("get_creator_stats");const cs=$("creatorStats");cs.replaceChildren();[["Etapas creadas",stats.created||0],["Publicadas",stats.published||0],["En revisión",stats.pending||0],["Participaciones",stats.participants||0]].forEach(([label,value])=>{const card=node("article","feature-card");card.append(node("strong","",String(value)),node("small","",label));cs.append(card);});
    }catch(error){status("profileSummary",error.message||"No se pudo cargar el perfil.");}
  }

  async function loadChallenges(){
    const host=$("challengeList");host.replaceChildren();if(!currentUser()){host.append(node("p","muted","Inicia sesión para crear y consultar desafíos."));return;}
    const rows=await rpc("get_my_challenges");if(!rows?.length){host.append(node("p","muted","Todavía no tienes desafíos."));return;}
    rows.forEach(ch=>{
      const card=node("article","feature-card");
      card.append(node("strong","","Código "+ch.join_code),node("small","muted",ch.activity_ids.length+" actividades Â· vence "+new Date(ch.expires_at).toLocaleDateString("es-MX")));
      (ch.participants||[]).forEach(result=>card.append(node("p","",result.username+": "+result.correct_count+"/"+ch.activity_ids.length+" Â· "+(result.elapsed_seconds??"—")+" s")));
      const button=node("button","secondary-btn","Registrar mi resultado");
      button.onclick=async()=>{try{const result=await rpc("complete_player_challenge",{p_challenge_id:ch.id});showMessage(result.correct+"/"+result.total+" actividades Â· "+result.elapsed_seconds+" s");await loadChallenges();}catch(error){showMessage(error.message||"No se pudo registrar el resultado.");}};
      card.append(button);host.append(card);
    });
  }
  async function refreshView(section){
    try{
      if(section==="community"){await loadCommunity();await loadFavorites();}
      if(section==="leaderboard")await loadLeaderboard(false);
      if(section==="lab"){await loadMyStages();await loadModeration();}
      if(section==="shop")await loadShop();
      if(section==="challenges")await loadChallenges();
      if(section==="profile")await loadProfile();
    }catch(error){showMessage(error.message||"No se pudieron cargar los datos.");}
  }
  function bind(){
    $("startAssessment").onclick=startAssessment;$("submitAssessment").onclick=submitAssessment;
    ["stageSort","stageCategory","stageDifficulty"].forEach(id=>$(id).addEventListener("change",loadCommunity));$("refreshStages").onclick=loadCommunity;
    document.querySelectorAll("[data-rank-period]").forEach(b=>b.onclick=()=>{document.querySelectorAll("[data-rank-period]").forEach(x=>x.classList.toggle("active",x===b));weeklyRank=b.dataset.rankPeriod==="true";loadLeaderboard();});$("rankMetric").onchange=()=>loadLeaderboard();$("refreshFavorites").onclick=()=>loadFavorites().catch(e=>showMessage(e.message));$("closePublicProfile").onclick=()=>$("publicProfileDialog").close();
    $("stageForm").addEventListener("submit",async e=>{e.preventDefault();try{requireUser();const prompts=$("stagePrompts").value.split(/\r?\n/).map(x=>x.trim()).filter(Boolean);const id=await rpc("create_draft_stage",{p_title:$("stageTitle").value.trim(),p_description:$("stageDescription").value.trim(),p_category:$("stageCategoryInput").value,p_difficulty:Number($("stageDifficultyInput").value),p_prompts:prompts});e.target.reset();showMessage("Borrador guardado: "+id.slice(0,8));await loadMyStages();}catch(error){showMessage(error.message||"No se pudo guardar el borrador.");}});
    $("refreshMyStages").onclick=()=>{void loadMyStages();void loadModeration();};
    $("avatarCategory").onchange=renderCatalog;$("refreshAvatar").onclick=()=>loadShop().catch(e=>showMessage(e.message));
    $("claimMission").onclick=async()=>{if(!ECONOMY_REWARDS_ENABLED)return;try{await rpc("claim_daily_mission");await loadShop();showMessage("Recompensa reclamada.");}catch(e){showMessage(e.message||"No se pudo reclamar.");}};
    $("challengeForm").addEventListener("submit",async e=>{e.preventDefault();try{requireUser();const keys=$("challengeActivities").value.split(",").map(x=>x.trim()).filter(Boolean);const result=await rpc("create_player_challenge",{p_opponent_username:$("challengeOpponent").value.trim(),p_activity_ids:keys});$("createdChallenge").hidden=false;$("createdChallenge").textContent="Invitación creada. Comparte este código: "+result.join_code;await loadChallenges();}catch(error){showMessage(error.message||"No se pudo crear el desafío.");}});
    $("joinChallengeForm").addEventListener("submit",async e=>{e.preventDefault();try{requireUser();await rpc("join_player_challenge",{p_join_code:$("challengeCode").value.trim()});e.target.reset();showMessage("Te uniste al desafío.");await loadChallenges();}catch(error){showMessage(error.message||"No se pudo aceptar el código.");}});$("refreshChallenges").onclick=loadChallenges;
    $("settingShowProfile").onchange=saveSettings;$("settingShowXp").onchange=saveSettings;$("settingShowActivity").onchange=saveSettings;
    $("closeStagePlay").onclick=()=>$("stagePlayDialog").close();
    $("completeStagePlay").onclick=async()=>{if(!currentStage)return;try{requireUser();await rpc("record_stage_completion",{p_stage_id:currentStage.id});$("stageReviewControls").hidden=false;$("stagePlayStatus").textContent="Etapa completada. Puedes dejar una valoración.";await loadCreatorStatsMaybe();}catch(e){$("stagePlayStatus").textContent=e.message||"Inicia sesión para registrar la participación.";}};
    $("submitStageReview").onclick=async()=>{try{requireUser();await rpc("review_stage",{p_stage_id:currentStage.id,p_rating:Number($("stageRating").value)});showMessage("Gracias por tu valoración.");await loadCommunity();}catch(e){showMessage(e.message||"No se pudo guardar la valoración.");}};
    $("favoriteStage").onclick=async()=>{try{requireUser();await rpc("toggle_stage_favorite",{p_stage_id:currentStage.id,p_favorite:true});showMessage("Etapa guardada en favoritos.");}catch(e){showMessage(e.message||"No se pudo guardar.");}};
    $("reportStage").onclick=()=>{$("reportDialog").showModal();};$("closeReport").onclick=()=>$("reportDialog").close();
    $("reportForm").addEventListener("submit",async e=>{e.preventDefault();try{requireUser();await rpc("report_stage",{p_stage_id:currentStage.id,p_reason:$("reportReason").value,p_details:$("reportDetails").value.trim()});$("reportDialog").close();e.target.reset();status("stagePlayStatus","Reporte enviado para revisión.");}catch(error){status("reportFeedback",error.message||"No se pudo enviar el reporte.");}});
  }
  async function saveSettings(){try{requireUser();const db=await dbClient();const {error}=await db.from("player_settings").update({show_profile:$("settingShowProfile").checked,show_xp:$("settingShowXp").checked,show_activity:$("settingShowActivity").checked}).eq("user_id",currentUser().id);if(error)throw error;showMessage("Privacidad actualizada.");}catch(e){showMessage(e.message||"No se pudo guardar.");}}
  async function loadCreatorStatsMaybe(){if(currentView==="profile")await loadProfile();}
  bind();
  appEvents.addEventListener("session",()=>{if(currentView)void refreshView(currentView);});
  export const GCV2 = Object.freeze({ onView(section) { currentView=section; void refreshView(section); }, onLearningCompletion, refreshView });
