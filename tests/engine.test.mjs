// node --test tests/engine.test.mjs   剧本引擎的回归测试：按攻略走到真结局 / 好结局，静态检查 + 小规模模拟不卡死
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { loadStoryDir, check } from '../tools/check.mjs';
import { walk } from '../tools/walk.mjs';
import { parseExpr, evaluate } from '../web/src/expr.js';
import { SplitMix } from '../web/src/engine.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const story = loadStoryDir(path.join(root, 'story'));
const quiet = () => {};

test('剧本解析没有问题', () => {
  assert.deepEqual(story.issues, []);
  assert.equal(story.endings.length, 32);
  assert.equal(story.docs.length, 41);
});

test('表达式：比较、逻辑、整除', () => {
  const ctx = { lookup: n => ({ a: 7, b: 2 })[n] ?? 0, call: () => 0 };
  const v = s => evaluate(parseExpr(s), ctx);
  assert.equal(v('a == 7 && b != 3'), 1);
  assert.equal(v('a < b || !(b >= 2)'), 0);
  assert.equal(v('-a / b'), -3);
  assert.equal(v('a % b + 2 * 3'), 7);
  assert.equal(v('a / 0'), 0);
});

test('SplitMix64 符合标准测试向量（Swift 版是同一个算法）', () => {
  const r = new SplitMix(0n);
  assert.equal(r.next(), 0xE220A8397B1DCDAFn);
  assert.equal(r.next(), 0x6E789E6AA1B965F4n);
});

for (const [file, ending] of [['true_ending.walk', 'e30'], ['good_ending.walk', 'e26']]) {
  test(`攻略 ${file} 走到 ${ending}`, () => {
    const { ok, engine } = walk(story, readFileSync(path.join(root, 'tests', file), 'utf8'), quiet);
    assert.ok(ok);
    assert.equal(engine.state.ending, ending);
  });
}

test('静态检查 + 300 局模拟：没有错误、没有卡死', () => {
  const { errors, sim } = check(story, { runs: 300, seed: 42n, log: quiet });
  assert.deepEqual(errors, []);
  assert.deepEqual(sim.broken, {});
  assert.equal(sim.loops, 0);
});
