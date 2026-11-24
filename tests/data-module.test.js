import test from "node:test";
import assert from "node:assert/strict";
import { ALL, STAGES, STAGE_LV, LEVELS, SHAPES, EQUIV } from "../data.js";

test("ES module exports preserve the original learning curriculum", () => {
  assert.equal(ALL.length, 26);
  assert.equal(LEVELS.length, 15);
  assert.equal(STAGES.length, 3);
  assert.equal(STAGE_LV.flat().length, 15);
  assert.ok(LEVELS.every(level => Array.isArray(level.items) && level.items.length > 0));
  assert.ok(SHAPES.A && EQUIV.length > 0);
});
