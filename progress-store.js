import { emitAppEvent } from "./app-events.js";

export const STORE_KEY = "gesturechallenge_lsm_progress_v1";
export const DEFAULT_PROGRESS = Object.freeze({
  done: [], best: 0, points: 0, levels: [], mastery: {}, words: [], phrases: [],
  streak: 0, lastDay: "", history: [], badges: [], sound: true, landmarks: false, v2: 0, v3: 0
});

export function progressPayload(data = {}) {
  return {
    completed_letters: Array.isArray(data.done) ? data.done.filter(x => /^[A-Z]$/.test(x)) : [],
    completed_words: Array.isArray(data.words) ? data.words.filter(x => typeof x === "string") : [],
    completed_phrases: Array.isArray(data.phrases) ? data.phrases.filter(x => typeof x === "string") : [],
    completed_levels: Array.isArray(data.levels) ? data.levels.filter(x => Number.isInteger(x) && x >= 1 && x <= 15) : [],
    mastery: data.mastery && typeof data.mastery === "object" && !Array.isArray(data.mastery) ? data.mastery : {}
  };
}

export function mergeProgress(local, remote) {
  const localPayload = progressPayload(local || {});
  const remotePayload = remote || {};
  const mastery = { ...localPayload.mastery };
  Object.entries(remotePayload.mastery || {}).forEach(([key, value]) => {
    mastery[key] = Math.max(Number(mastery[key]) || 0, Number(value) || 0);
  });
  const unique = values => [...new Set(values)];
  return {
    done: unique([...(localPayload.completed_letters || []), ...(remotePayload.completed_letters || [])]),
    words: unique([...(localPayload.completed_words || []), ...(remotePayload.completed_words || [])]),
    phrases: unique([...(localPayload.completed_phrases || []), ...(remotePayload.completed_phrases || [])]),
    levels: unique([...(localPayload.completed_levels || []), ...(remotePayload.completed_levels || [])]).sort((a, b) => a - b),
    mastery
  };
}

export function loadLocalProgress(levels, all, storage = globalThis.localStorage) {
  let saved;
  try { saved = JSON.parse(storage.getItem(STORE_KEY)); }
  catch (error) { console.warn("No se pudo leer el progreso:", error); }
  const data = { ...DEFAULT_PROGRESS, ...(saved && typeof saved === "object" ? saved : {}) };
  ["done", "levels", "words", "phrases", "history", "badges"].forEach(key => {
    data[key] = Array.isArray(data[key]) ? [...data[key]] : [];
  });
  data.mastery = data.mastery && typeof data.mastery === "object" && !Array.isArray(data.mastery) ? { ...data.mastery } : {};
  if (!data.v2) {
    levels.slice(0, 5).forEach(level => {
      if (level.items.every(item => data.done.includes(item)) && !data.levels.includes(level.n)) data.levels.push(level.n);
    });
    data.v2 = 1;
  }
  if (data.v3 !== 1) {
    data.done = [...new Set(data.done.filter(letter => all.includes(letter)))];
    Object.keys(data.mastery).forEach(key => { if (key.length === 1 && !all.includes(key)) delete data.mastery[key]; });
    data.history = data.history.filter(entry => !(entry && entry.w === "Ñ"));
    data.v3 = 1;
  }
  return data;
}

export function persistProgress(data, queueRemote = () => {}, storage = globalThis.localStorage) {
  storage.setItem(STORE_KEY, JSON.stringify(data));
  queueRemote(data);
}

export function applyRemoteProgress(data, remote, storage = globalThis.localStorage) {
  if (!data || !remote) return false;
  data.done = remote.done; data.words = remote.words; data.phrases = remote.phrases;
  data.levels = remote.levels; data.mastery = remote.mastery;
  storage.setItem(STORE_KEY, JSON.stringify(data));
  emitAppEvent("progress:applied", { ...remote });
  return true;
}
