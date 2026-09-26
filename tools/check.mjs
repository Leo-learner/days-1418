// 剧本检查器（Swift 版 Checker.swift 的移植）
//   node tools/check.mjs [剧本目录=story] [-runs N=3000] [-seed S=42] [-force]
// 1. 静态检查：断链、死路、未登记的结局/档案、疑似拼错的变量、到不了的节点
// 2. 蒙特卡洛：带跨周目进度连续模拟 N 局，统计每个结局被走到几次
import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { loadStory, isRegistry } from '../web/src/story.js';
import { parseExpr, identifier } from '../web/src/expr.js';
import { Engine, SplitMix, newMeta } from '../web/src/engine.js';

export function loadStoryDir(dir) {
  const files = readdirSync(dir).filter(f => f.endsWith('.story'))
    .map(file => ({ file, text: readFileSync(path.join(dir, file), 'utf8') }));
  return loadStory(files);
}

const BUILTINS = new Set(['endings', 'docs', 'runs', 'hardcore', 'true', 'false']);
const FUNCTIONS = new Set(['doc', 'end', 'seen', 'alive', 'rand', 'min', 'max', 'abs', 'if']);

export function check(story, { runs = 3000, seed = 42n, force = false, log = console.log } = {}) {
  const errors = [...story.issues];
  const warnings = [];
  const playable = story.nodeOrder.filter(id => !isRegistry(id));
  const endingIds = new Set(story.endings.map(e => e.id));
  const docIds = new Set(story.docs.map(d => d.id));
  const assigned = new Set(Object.keys(story.initial));
  for (const p of story.persons) for (const s of ['_dead', '_met', '_away']) assigned.add(p.key + s);
  const read = new Map();   // 变量名 → 第一次读到的位置
  const usedEndings = new Set();

  const where = (n, line) => `${n.file}:${line ?? n.line} [${n.id}]`;

  const scanExpr = (e, at, textCondition = false) => {
    if (!e) return;
    switch (e.t) {
      case 'name':
        if (!BUILTINS.has(e.v) && !read.has(e.v)) read.set(e.v, at);
        break;
      case 'un': scanExpr(e.e, at, textCondition); break;
      case 'bin': scanExpr(e.l, at, textCondition); scanExpr(e.r, at, textCondition); break;
      case 'call': {
        if (!FUNCTIONS.has(e.fn)) errors.push(`${at} 未知函数 ${e.fn}()`);
        const id = identifier(e.args[0]) ?? '';
        switch (e.fn) {
          case 'doc': if (!docIds.has(id)) errors.push(`${at} doc(${id}) 没有这份档案`); break;
          case 'end': if (!endingIds.has(id)) errors.push(`${at} end(${id}) 没有这个结局`); break;
          case 'seen': if (!story.nodes.has(id)) errors.push(`${at} seen(${id}) 没有这个节点`); break;
          case 'alive': if (!story.persons.some(p => p.key === id)) errors.push(`${at} alive(${id}) 没有这个人物`); break;
          default:
            if (e.fn === 'rand' && textCondition) warnings.push(`${at} 正文/选项条件里的 rand() 恒为 0`);
            for (const a of e.args) scanExpr(a, at, textCondition);
        }
        break;
      }
    }
  };

  const scanEffects = (effects, at) => {
    for (const e of effects) {
      if (e.t === 'assign') { assigned.add(e.name); scanExpr(e.expr, at); }
      else if (e.t === 'archive') { if (!docIds.has(e.id)) errors.push(`${at} archive ${e.id} 没有这份档案`); }
      else if (e.t === 'kill') assigned.add(e.who + '_dead');
      else if (e.t === 'meet') assigned.add(e.who + '_met');
    }
  };

  const scanText = (text, at) => {
    let rest = text;
    for (;;) {
      const open = rest.indexOf('{');
      if (open < 0) break;
      const close = rest.indexOf('}', open);
      if (close < 0) break;
      const inner = rest.slice(open + 1, close).trim();
      if (inner.startsWith('#')) {
        const key = inner.slice(1);
        if (!story.enums[key]) errors.push(`${at} {#${key}} 没有这个枚举`);
        if (!read.has(key)) read.set(key, at);
      } else {
        try { scanExpr(parseExpr(inner), at, true); } catch (err) { errors.push(`${at} 插值 {${inner}} 写错了：${err.message}`); }
      }
      rest = rest.slice(close + 1);
    }
  };

  const checkTarget = (target, at) => {
    if (!story.nodes.has(target)) errors.push(`${at} 目标不存在：${target}`);
    else if (isRegistry(target)) errors.push(`${at} 不能跳到登记节点：${target}`);
  };

  if (!story.nodes.has(story.start)) errors.push(`@@start 指向的节点不存在：${story.start}`);

  for (const id of playable) {
    const n = story.nodes.get(id);
    scanEffects(n.sets, where(n));
    for (const a of n.archives) if (!docIds.has(a)) errors.push(`${where(n)} @archive ${a} 没有这份档案`);
    for (const r of n.redirects) { scanExpr(r.cond, where(n, r.line)); checkTarget(r.target, where(n, r.line)); }
    for (const p of n.paras) { scanExpr(p.cond, where(n), true); scanText(p.text, where(n)); }
    for (const c of n.choices) {
      scanExpr(c.cond, where(n, c.line), true);
      scanEffects(c.effects, where(n, c.line));
      scanText(c.text, where(n, c.line));
      checkTarget(c.target, where(n, c.line));
    }
    if (n.next !== null) {
      scanEffects(n.nextEffects, where(n));
      checkTarget(n.next, where(n));
      if (n.choices.length) warnings.push(`${where(n)} 同时有选项和 ->，-> 会被忽略`);
    }
    if (n.ending !== null) {
      usedEndings.add(n.ending);
      if (!endingIds.has(n.ending)) errors.push(`${where(n)} @ending ${n.ending} 没有登记`);
    }
    if (n.paras.length && n.redirects.some(r => r.cond)) warnings.push(`${where(n)} 有正文又有条件跳转：跳转生效时正文会被整段跳过`);
    const escapes = n.choices.length || n.next !== null || n.ending !== null || n.redirects.some(r => !r.cond);
    if (!escapes) {
      if (!n.redirects.length) errors.push(`${where(n)} 死路：没有选项、没有 ->、也不是结局`);
      else if (!n.paras.length) errors.push(`${where(n)} 只有条件跳转，全不满足时是空白死路`);
      else warnings.push(`${where(n)} 条件跳转全不满足时会停在这里（没有选项）`);
    }
  }
  for (const e of story.endings) {
    if (!usedEndings.has(e.id)) errors.push(`结局 ${e.id}「${e.title}」没有任何节点用 @ending 指向它`);
    if (e.doc && !docIds.has(e.doc)) errors.push(`结局 ${e.id} 的档案 ${e.doc} 不存在`);
  }
  for (const [name, at] of [...read].sort((a, b) => (a[0] < b[0] ? -1 : 1))) {
    if (!assigned.has(name) && !name.startsWith('m_')) warnings.push(`${at} 读取了从没赋值过的变量 ${name}（拼错了？）`);
  }

  // 不考虑条件的可达性
  const seen = new Set([story.start]);
  const queue = [story.start];
  while (queue.length) {
    const n = story.nodes.get(queue.pop());
    if (!n) continue;
    const targets = [...n.choices.map(c => c.target), ...n.redirects.map(r => r.target), ...(n.next !== null ? [n.next] : [])];
    for (const t of targets) if (!seen.has(t)) { seen.add(t); queue.push(t); }
  }
  for (const id of playable.filter(id => !seen.has(id))) warnings.push(`到不了的节点：${id}（${story.nodes.get(id).file}）`);

  const choiceCount = playable.reduce((s, id) => s + story.nodes.get(id).choices.length, 0);
  log(`剧本：${story.title}`);
  log(`节点 ${playable.length} · 选项 ${choiceCount} · 结局 ${story.endings.length} · 档案 ${story.docs.length} · 正文约 ${story.characterCount} 字`);
  for (const e of errors) log(`✘ ${e}`);
  for (const w of warnings.slice(0, 80)) log(`△ ${w}`);
  if (warnings.length > 80) log(`△ ……另有 ${warnings.length - 80} 条提醒`);

  let sim = null;
  if (runs > 0 && (!errors.length || force)) sim = simulate(story, runs, seed, log);
  log(!errors.length ? `✓ 静态检查通过（${warnings.length} 条提醒）` : `✘ ${errors.length} 个错误`);
  return { errors, warnings, sim };
}

/** 连续模拟：前面几局解锁的档案会让后面几局出现【档案】选项。选择策略偏向"去得少的节点"，照顾冷门分支。 */
export function simulate(story, runs, seed, log = console.log) {
  const rng = new SplitMix(seed);
  const engine = new Engine(story, newMeta());
  const endingHits = {}, firstRun = {}, visits = {}, broken = {}, milestones = {};
  const passed = new Set();
  let loops = 0, totalSteps = 0;

  const targetOf = c => {
    const node = story.nodes.get(engine.state.node);
    return c.index < 0 ? node.next ?? '' : node.choices[c.index].target;
  };
  const leadsToKnownEnding = c => {
    if (!story.nodes.get(engine.state.node)) return false;
    let target = targetOf(c);
    for (let i = 0; i < 6; i++) {
      const n = story.nodes.get(target);
      if (!n) return false;
      if (n.ending !== null) return engine.meta.endings[n.ending] !== undefined;
      if (!n.choices.length && n.next !== null) { target = n.next; continue; }
      const jump = n.redirects.find(r => !r.cond);
      if (jump) { target = jump.target; continue; }
      return false;
    }
    return false;
  };
  const visitsFor = c => (story.nodes.get(engine.state.node) ? visits[targetOf(c)] ?? 0 : 0);

  for (let run = 0; run < runs; run++) {
    engine.newRun(false, rng.next());
    let steps = 0;
    while (steps < 4000) {
      visits[engine.state.node] = (visits[engine.state.node] ?? 0) + 1;
      const e = engine.state.ending;
      if (e) {
        endingHits[e] = (endingHits[e] ?? 0) + 1;
        firstRun[e] ??= run + 1;
        break;
      }
      let options = engine.shownChoices().filter(c => c.enabled);
      // 有别的路可走时，大概率绕开直通"已经见过的结局"的选项，让模拟往深处走
      if (options.length > 1) {
        const fresh = options.filter(c => !leadsToKnownEnding(c));
        if (fresh.length && rng.next() % 100n < 85n) options = fresh;
      }
      if (!options.length) {
        broken[engine.state.node] = (broken[engine.state.node] ?? 0) + 1;
        break;
      }
      let pick;
      if (rng.next() % 100n < 55n) {
        pick = options.reduce((best, c) => (visitsFor(c) < visitsFor(best) ? c : best));
      } else {
        pick = options[Number(rng.next() % BigInt(options.length))];
      }
      engine.choose(pick);
      steps++;
    }
    if (steps >= 4000) loops++;
    totalSteps += steps;
    for (const id of Object.keys(engine.state.visited)) {
      passed.add(id);
      if (id.endsWith('_start') || id.startsWith('frame_i')) milestones[id] = (milestones[id] ?? 0) + 1;
    }
  }

  const playable = story.nodeOrder.filter(id => !isRegistry(id));
  const covered = playable.filter(id => passed.has(id)).length;
  log(`—— 模拟 ${runs} 局 · 平均 ${Math.floor(totalSteps / Math.max(1, runs))} 步 · 节点覆盖 ${covered}/${playable.length}`);
  for (const e of story.endings) {
    const hits = endingHits[e.id] ?? 0;
    const first = firstRun[e.id] ? `（第 ${firstRun[e.id]} 局首次）` : '';
    log(`${hits > 0 ? '●' : '○'} ${e.id} ${e.tier} ${e.title}：${hits} 次${first}`);
  }
  const order = ['a1_start', 'frame_i1', 'a2_start', 'frame_i2', 'a3_start', 'frame_i3', 'a35_start', 'a4_start', 'a4_post_start'];
  log('抵达：' + order.filter(k => milestones[k] !== undefined).map(k => `${k} ${milestones[k]}`).join(' · '));
  log(`档案解密 ${Object.keys(engine.meta.docs).length}/${story.docs.length}`);
  const missing = story.docs.filter(d => engine.meta.docs[d.id] === undefined).map(d => d.id);
  if (missing.length) log(`  没解密到：${missing.join(' ')}`);
  for (const [node, n] of Object.entries(broken).sort((a, b) => b[1] - a[1]).slice(0, 20)) log(`✘ 卡死在 ${node}：${n} 局`);
  if (loops > 0) log(`✘ ${loops} 局超过 4000 步，可能有死循环`);
  const never = playable.filter(id => !passed.has(id));
  if (never.length) log(`  模拟里一次没到过的节点 ${never.length} 个：${never.slice(0, 40).join(' ')}`);
  return { endingHits, broken, loops, covered, missing };
}

const argValue = (args, flag) => {
  const i = args.indexOf(flag);
  return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
};

if (import.meta.url === `file://${process.argv[1]}`) {
  const args = process.argv.slice(2);
  const dir = args[0] && !args[0].startsWith('-') ? args[0] : 'story';
  const runs = Number(argValue(args, '-runs') ?? 3000);
  const seed = BigInt(argValue(args, '-seed') ?? 42);
  const story = loadStoryDir(dir);
  const { errors, sim } = check(story, { runs, seed, force: args.includes('-force') });
  const stuck = sim && (Object.keys(sim.broken).length > 0 || sim.loops > 0);
  process.exit(errors.length || stuck ? 1 : 0);
}
