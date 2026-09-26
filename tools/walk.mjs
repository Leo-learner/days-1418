// 按攻略文件走：node tools/walk.mjs tests/true_ending.walk [-story 目录=story] [-expect e30]
// 攻略每行是选项文字里的一段（或 #序号）；@docs d06,d04 预置已解密档案；@endings e01 预置结局；@seed N 固定随机数
import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { loadStoryDir } from './check.mjs';
import { Engine, newMeta } from '../web/src/engine.js';

export function walk(story, text, log = console.log) {
  const meta = newMeta();
  let seed = 1n;
  const steps = [];
  for (const raw of text.split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('//')) continue;
    if (line.startsWith('@docs ')) {
      for (const d of line.slice(6).split(',')) meta.docs[d.trim()] = new Date().toISOString();
    } else if (line.startsWith('@endings ')) {
      for (const e of line.slice(9).split(',')) meta.endings[e.trim()] = new Date().toISOString();
    } else if (line.startsWith('@seed ')) {
      seed = BigInt(line.slice(6).trim() || 1);
    } else {
      steps.push(line);
    }
  }
  const engine = new Engine(story, meta);
  engine.newRun(false, seed);
  const describe = o => `   ${o.enabled ? '·' : '🔒'} ${o.tags.map(t => `【${t}】`).join('')}${o.text}`;
  for (let i = 0; i < steps.length; i++) {
    if (engine.state.ending) break;
    const step = steps[i];
    const options = engine.shownChoices();
    let pick = null;
    const m = /^#(\d+)$/.exec(step);
    if (m) pick = options[Number(m[1]) - 1] ?? null;
    else pick = options.find(o => o.enabled && (o.text.includes(step) || (o.tags.join('') + o.text).includes(step))) ?? null;
    if (!pick) {
      log(`✘ 第 ${i + 1} 步在 [${engine.state.node}] 找不到选项「${step}」。可选：`);
      for (const o of options) log(describe(o));
      return { ok: false, engine };
    }
    log(`[${engine.state.node}] → ${pick.text}`);
    engine.choose(pick);
  }
  const s = engine.state;
  log(`停在：${s.node} ${s.ending ? `· 结局 ${s.ending} ${story.ending(s.ending)?.title ?? ''}` : ''}`);
  const keys = ['men', 'hum', 'trauma', 'susp', 'rank', 'post', 'misha', 'nurlan', 'katya', 'kostya_dead', 'belov_dead', 'f_swap', 'f_love'];
  log(keys.map(k => `${k}=${engine.lookup(k)}`).join(' '));
  if (!s.ending) for (const o of engine.shownChoices()) log(describe(o));
  return { ok: true, engine };
}

// argv[1] 转成 URL 再比：路径里的空格、中文在 import.meta.url 里是百分号编码的；node -e 时 argv[1] 为空
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const args = process.argv.slice(2);
  const flag = f => { const i = args.indexOf(f); return i >= 0 ? args[i + 1] : null; };
  const script = args[0];
  if (!script) { console.error('用法：node tools/walk.mjs <攻略文件> [-story 目录] [-expect 结局id]'); process.exit(2); }
  const story = loadStoryDir(flag('-story') ?? 'story');
  const { ok, engine } = walk(story, readFileSync(script, 'utf8'));
  const expect = flag('-expect');
  if (expect && engine.state.ending !== expect) {
    console.log(`✘ 期望到达结局 ${expect}，实际 ${engine.state.ending ?? '没有结局'}`);
    process.exit(1);
  }
  process.exit(ok ? 0 : 1);
}
