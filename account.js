import { SUPABASE_CONFIG } from "./supabase-config.js";
import { progressPayload, mergeProgress } from "./progress-store.js";
import { emitAppEvent } from "./app-events.js";


  const $ = id => document.getElementById(id);
  const config = SUPABASE_CONFIG;
  let client = null;
  let loadingClient = null;
  let currentUser = null;
  let localData = null;
  let saveTimer = null;
  let syncing = false;
  let syncPending = false;
  let authListener = null;
  let mode = "signin";

  const status = message => { $("accountFeedback").textContent = message; };
  const configured = () => Boolean(config.url && config.anonKey);

  async function getClient() {
    if (client) return client;
    if (!configured()) throw new Error("Falta configurar la URL y la clave pública de Supabase en supabase-config.js.");
    if (!loadingClient) {
      loadingClient = import("https://esm.sh/@supabase/supabase-js@2")
        .then(({ createClient }) => client = createClient(config.url, config.anonKey))
        .finally(() => { loadingClient = null; });
    }
    return loadingClient;
  }

  function setMode(next) {
    mode = next;
    $("accountNameFields").hidden = next !== "signup";
    $("accountPasswordFields").hidden = next === "recover" || next === "newpassword";
    $("accountEmailField").hidden = next === "newpassword";
    $("accountEmail").required = next !== "newpassword";
    $("accountPassword").required = next === "signin" || next === "signup";
    $("accountNewPassword").required = next === "newpassword";
    $("accountUsernameField").hidden = next !== "signup";
    $("accountRecoveryFields").hidden = next !== "newpassword";
    $("accountSubmit").hidden = false;
    $("accountSwitchMode").hidden = next === "newpassword";
    $("accountSubmit").textContent = next === "signup" ? "Crear cuenta" : next === "recover" ? "Enviar enlace" : next === "newpassword" ? "Actualizar contraseña" : "Iniciar sesión";
    $("accountModeLabel").textContent = next === "signup" ? "Crea tu cuenta" : next === "recover" ? "Recupera tu contraseña" : next === "newpassword" ? "Define una contraseña nueva" : "Inicia sesión";
    $("accountForgot").hidden = next !== "signin";
    $("accountSwitchMode").textContent = next === "signup" ? "Iniciar sesión" : next === "recover" ? "Volver a iniciar sesión" : "Crear cuenta";
    $("accountForm").reset();
    status(configured() ? "Módulo de cuenta experimental; autenticación y sincronización aún requieren pruebas." : "Configura Supabase para habilitar cuentas. El aprendizaje local sigue disponible.");
  }

  async function showAccount() {
    if (!$("accountDialog").open) $("accountDialog").showModal();
    if (!configured()) {
      status("Completa url y anonKey en supabase-config.js para conectar las cuentas.");
      return;
    }
    try {
      await getClient();
      if (!currentUser) await start();
    } catch (error) {
      status(error.message || "No se pudo conectar con Supabase.");
    }
  }

  async function updateProfileView() {
    $("accountAuthView").hidden = Boolean(currentUser);
    $("accountSignedInView").hidden = !currentUser;
    if (!currentUser) {
      $("accountIdentity").textContent = "";
      return;
    }
    $("accountIdentity").textContent = currentUser.email || "Sesión activa";
    try {
      const db = await getClient();
      const { data: accountData, error } = await db.rpc("get_my_v2_profile");
      if (error) throw error;
      if (accountData?.profile) $("accountIdentity").textContent = `${accountData.profile.display_name} · @${accountData.profile.username}`;
    } catch (error) {
      status(`Sesión iniciada; el perfil requiere migración aplicada. ${error.message || ""}`);
    }
  }

  async function syncProgress() {
    if (!currentUser || !localData) return;
    if (syncing) { syncPending = true; return; }
    syncing = true;
    try {
      const db = await getClient();
      const { data: remote, error } = await db.from("player_progress").select("completed_letters,completed_words,completed_phrases,completed_levels,mastery").eq("user_id", currentUser.id).maybeSingle();
      if (error) throw error;
      const merged = mergeProgress(localData, remote);
      const payload = progressPayload(merged);
      const { error: saveError } = await db.from("player_progress").upsert({ user_id: currentUser.id, ...payload }, { onConflict: "user_id" });
      if (saveError) throw saveError;
      emitAppEvent("progress:remote", merged);
      status("Progreso de aprendizaje sincronizado.");
    } catch (error) {
      status(`No se pudo sincronizar el progreso: ${error.message || "revisa la configuración"}`);
    } finally {
      syncing = false;
      if (syncPending) {
        syncPending = false;
        void syncProgress();
      }
    }
  }

  async function acceptSession(session) {
    currentUser = session?.user || null;
    await updateProfileView();
    emitAppEvent("session", { user: currentUser });
    if (currentUser) await syncProgress();
    else status("Sesión cerrada. El progreso local permanece en este dispositivo.");
  }

  async function start(data) {
    if (data) localData = data;
    if (!configured()) return;
    const db = await getClient();
    const { data: result, error } = await db.auth.getSession();
    if (error) throw error;
    await acceptSession(result.session);
    if (!authListener) {
      authListener = db.auth.onAuthStateChange((event, session) => {
        if (event === "PASSWORD_RECOVERY") setMode("newpassword");
        // Defer Supabase calls until the auth callback has returned.
        queueMicrotask(() => { void acceptSession(session); });
      });
    }
  }

  function queueProgress(data) {
    localData = data;
    if (!currentUser) return;
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => { void syncProgress(); }, 900);
  }

  $("openAccount").addEventListener("click", showAccount);
  $("tabAccount").addEventListener("click", showAccount);
  $("closeAccount").addEventListener("click", () => $("accountDialog").close());
  $("accountSwitchMode").addEventListener("click", () => setMode(mode === "signup" || mode === "recover" ? "signin" : "signup"));
  $("accountForgot").addEventListener("click", () => setMode("recover"));

  $("accountForm").addEventListener("submit", async event => {
    event.preventDefault();
    try {
      const db = await getClient();
      const email = $("accountEmail").value.trim();
      const password = $("accountPassword").value;
      if (mode === "recover") {
        const { error } = await db.auth.resetPasswordForEmail(email, { redirectTo: location.href.split("#")[0] });
        if (error) throw error;
        status("Te enviamos un enlace para recuperar la contraseña.");
        return;
      }
      if (mode === "newpassword") {
        const newPassword = $("accountNewPassword").value;
        if (newPassword.length < 8) throw new Error("La nueva contraseña debe tener al menos 8 caracteres.");
        const { error } = await db.auth.updateUser({ password: newPassword });
        if (error) throw error;
        setMode("signin");
        status("Contraseña actualizada. Ya puedes iniciar sesión.");
        return;
      }
      if (mode === "signup") {
        const username = $("accountUsername").value.trim();
        const displayName = $("accountDisplayName").value.trim();
        if (!/^[a-zA-Z0-9_]{3,20}$/.test(username)) throw new Error("El nombre de jugador debe tener entre 3 y 20 caracteres: letras, números o guion bajo.");
        if (displayName.length < 1 || displayName.length > 40) throw new Error("El nombre visible debe tener entre 1 y 40 caracteres.");
        const { data, error } = await db.auth.signUp({ email, password, options: { data: { username, display_name: displayName } } });
        if (error) throw error;
        if (!data.session) status("Cuenta creada. Confirma tu correo para iniciar sesión.");
        else status("Cuenta creada y sesión iniciada.");
      } else {
        const { error } = await db.auth.signInWithPassword({ email, password });
        if (error) throw error;
        status("Sesión iniciada.");
      }
    } catch (error) {
      status(error.message || "No se pudo completar la solicitud.");
    }
  });
  $("accountSignOut").addEventListener("click", async () => {
    try {
      const db = await getClient();
      const { error } = await db.auth.signOut();
      if (error) throw error;
    } catch (error) { status(error.message || "No se pudo cerrar la sesión."); }
  });

  async function clearRemoteProgress() {
    if (!currentUser) return;
    const db = await getClient();
    const { error } = await db.from("player_progress").delete().eq("user_id", currentUser.id);
    if (error) throw error;
  }

  async function removeLevelProgress(level) {
    if (!currentUser) return;
    const db = await getClient();
    const { data: remote, error } = await db.from("player_progress").select("completed_letters,completed_words,completed_phrases,completed_levels,mastery").eq("user_id", currentUser.id).maybeSingle();
    if (error) throw error;
    if (!remote) return;
    const removed = new Set(level.items);
    const patch = { ...remote, completed_levels: (remote.completed_levels || []).filter(n => n !== level.n) };
    if (level.type === "letters") {
      patch.completed_letters = (remote.completed_letters || []).filter(x => !removed.has(x));
      patch.mastery = { ...(remote.mastery || {}) };
      level.items.forEach(letter => { delete patch.mastery[letter]; });
    } else if (level.type === "words") {
      patch.completed_words = (remote.completed_words || []).filter(x => !removed.has(x));
    } else {
      patch.completed_phrases = (remote.completed_phrases || []).filter(x => !removed.has(x));
    }
    const { error: saveError } = await db.from("player_progress").upsert({ user_id: currentUser.id, ...patch }, { onConflict: "user_id" });
    if (saveError) throw saveError;
  }
  export const GCAccount = Object.freeze({ start, queueProgress, clearRemoteProgress, removeLevelProgress, getClient, getUser: () => currentUser, isConfigured: configured });
