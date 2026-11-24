import test from "node:test";
import assert from "node:assert/strict";
import { DEFAULT_PROGRESS, STORE_KEY, loadLocalProgress, mergeProgress, persistProgress, progressPayload } from "../progress-store.js";

function memoryStorage(initial = null) {
  let value = initial;
  return {
    getItem(key) { assert.equal(key, STORE_KEY); return value; },
    setItem(key, next) { assert.equal(key, STORE_KEY); value = next; },
    value: () => value
  };
}

const sampleLevels = [
  { n: 1, items: ["A", "B"] },
  { n: 2, items: ["C"] },
  { n: 3, items: ["D"] },
  { n: 4, items: ["E"] },
  { n: 5, items: ["F"] },
  { n: 6, items: ["G"] }
];

test("loads guest defaults and returns fresh mutable collections", () => {
  const storage = memoryStorage();
  const first = loadLocalProgress(sampleLevels, ["A", "B", "C", "D", "E", "F", "G"], storage);
  first.words.push("HOLA");
  const second = loadLocalProgress(sampleLevels, ["A", "B", "C", "D", "E", "F", "G"], storage);
  assert.deepEqual(second.words, []);
  assert.notEqual(DEFAULT_PROGRESS.words, second.words);
});

test("preserves legacy local progress and removes the retired letter", () => {
  const storage = memoryStorage(JSON.stringify({ done: ["A", "Ñ", "B"], levels: [], history: [{w:"Ñ"},{w:"A"}], mastery: { A: 2, Ñ: 1 } }));
  const loaded = loadLocalProgress(sampleLevels, ["A", "B", "C", "D", "E", "F", "G"], storage);
  assert.deepEqual(loaded.done, ["A", "B"]);
  assert.deepEqual(loaded.history, [{w:"A"}]);
  assert.deepEqual(loaded.mastery, {A:2});
});

test("sync merge unions learning progress and keeps maximum mastery", () => {
  const merged = mergeProgress({done:["A"],words:["HOLA"],levels:[2],mastery:{A:1}}, {completed_letters:["A","B"],completed_words:["CASA"],completed_levels:[1,2],mastery:{A:3,B:1}});
  assert.deepEqual(merged, {done:["A","B"],words:["HOLA","CASA"],phrases:[],levels:[1,2],mastery:{A:3,B:1}});
});

test("remote payload contains learning progress only, never wallet or local scores", () => {
  const payload = progressPayload({done:["A"],words:["CASA"],phrases:["HOLA"],levels:[1],mastery:{A:2},coin_balance:999,xp_total:500,points:80,streak:9,history:[{}]});
  assert.deepEqual(Object.keys(payload).sort(), ["completed_letters","completed_levels","completed_phrases","completed_words","mastery"].sort());
  assert.equal(payload.coin_balance, undefined);
});

test("persists guest progress before scheduling optional remote sync", () => {
  const storage = memoryStorage(); let queued = null;
  const progress = {done:["A"],words:[],phrases:[],levels:[],mastery:{}};
  persistProgress(progress, value => { queued = value; }, storage);
  assert.deepEqual(JSON.parse(storage.value()), progress);
  assert.equal(queued, progress);
});
