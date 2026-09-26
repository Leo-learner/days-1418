import { ScriptError, parseExpr, parseEffects, toInt } from './expr.js';

// 剧本数据模型 + 解析器。语法见 docs/BIBLE.md 末尾。
// 段落 style：normal 普通叙述 / quote 公文、信件、命令（仿宋）/ rule 场景分隔

export class Story {
  constructor() {
    this.title = '一千四百一十八天';
    this.hero = '伊利亚·谢尔盖耶维奇·格罗莫夫';
    this.start = '';
    this.nodes = new Map();
    this.nodeOrder = [];
    this.stats = [];      // 个人属性
    this.units = [];      // 部队状况
    this.persons = [];
    this.items = [];
    this.enums = {};
    this.initial = {};
    this.bounds = {};     // key → [下限, 上限]
    this.endings = [];
    this.docs = [];
    this.issues = [];
    this.characterCount = 0;
    this.endingIndex = new Map();
    this.docIndex = new Map();
  }

  ending(id) { return this.endingIndex.get(id) ?? null; }
  doc(id) { return this.docIndex.get(id) ?? null; }

  label(key, value) {
    const labels = this.enums[key];
    return labels && value >= 0 && value < labels.length ? labels[value] : String(value);
  }

  buildIndexes() {
    this.endings.sort((a, b) => a.order - b.order);
    this.docs.sort((a, b) => a.order - b.order);
    this.endingIndex = new Map(this.endings.map(e => [e.id, e]));
    this.docIndex = new Map(this.docs.map(d => [d.id, d]));
  }
}

export const isRegistry = id => id.startsWith('ending:') || id.startsWith('doc:');

/** files: [{file, text}]，按文件名排序后依次解析 */
export function loadStory(files) {
  const story = new Story();
  const sorted = [...files].sort((a, b) => (a.file < b.file ? -1 : a.file > b.file ? 1 : 0));
  if (!sorted.length) story.issues.push('没找到任何 .story 剧本');
  for (const { file, text } of sorted) parseStory(text, file, story);
  finalize(story);
  return story;
}

function newNode(id, file, line) {
  return {
    id, file, line,
    chapter: null, date: null, place: null, mood: null, act: null,
    sets: [], redirects: [], ending: null, archives: [],
    paras: [], choices: [], next: null, nextEffects: [], props: {},
  };
}

export function parseStory(text, file, story) {
  let current = null;

  const flush = () => {
    if (!current) return;
    if (story.nodes.has(current.id)) story.issues.push(`${file}:${current.line} 节点重名：${current.id}`);
    else story.nodeOrder.push(current.id);
    story.nodes.set(current.id, current);
    current = null;
  };

  const lines = text.split(/\r\n|\r|\n/);
  for (let index = 0; index < lines.length; index++) {
    const ln = index + 1;
    const line = lines[index].trim();
    if (!line || line.startsWith('//')) continue;
    try {
      if (line.startsWith('@@')) {
        parseDeclaration(line, story);
        continue;
      }
      if (line.startsWith('===')) {
        flush();
        const id = line.slice(3).trim();
        if (!id) throw new ScriptError('=== 后面缺节点名');
        current = newNode(id, file, ln);
        continue;
      }
      if (!current) {
        story.issues.push(`${file}:${ln} 这一行不属于任何节点：${Array.from(line).slice(0, 24).join('')}`);
        continue;
      }
      const node = current;
      if (line.startsWith('@')) {
        parseDirective(line, node, ln);
      } else if (line.startsWith('* ') || line.startsWith('+ ')) {
        node.choices.push(parseChoice(line, ln));
      } else if (line.startsWith('->')) {
        let tail = line.slice(2).trim();
        const bar = tail.indexOf('|');
        if (bar >= 0) {
          node.nextEffects = parseEffects(tail.slice(bar + 1));
          tail = tail.slice(0, bar).trim();
        }
        node.next = tail;
      } else {
        const para = parsePara(line);
        story.characterCount += Array.from(para.text).length;
        node.paras.push(para);
      }
    } catch (err) {
      story.issues.push(`${file}:${ln} ${err instanceof ScriptError ? err.message : err}`);
    }
  }
  flush();
}

function splitHead(s) {
  const m = /[ \t]/.exec(s);
  if (!m) return [s, ''];
  return [s.slice(0, m.index), s.slice(m.index).trim()];
}

function parseDeclaration(line, story) {
  const [keyword, value] = splitHead(line.slice(2));
  const f = value.split('|').map(x => x.trim());
  switch (keyword) {
    case 'title': story.title = value; break;
    case 'start': story.start = value; break;
    case 'hero': story.hero = value; break;
    case 'stat':
    case 'unit': {
      // key | 名称 | 说明 | 初值 | 下限 | 上限 [| 单位]
      const ini = f.length >= 6 ? toInt(f[3]) : null, lo = f.length >= 6 ? toInt(f[4]) : null, hi = f.length >= 6 ? toInt(f[5]) : null;
      if (ini === null || lo === null || hi === null) throw new ScriptError(`@@${keyword} 需要 6 个字段：${value}`);
      const def = { key: f[0], name: f[1], desc: f[2], initial: ini, min: lo, max: hi, unit: f.length > 6 ? f[6] : '' };
      (keyword === 'stat' ? story.stats : story.units).push(def);
      story.initial[f[0]] = ini;
      story.bounds[f[0]] = [lo, hi];
      break;
    }
    case 'person': {
      // key | 名字 | 说明 | 初始信任
      const trust = f.length >= 4 ? toInt(f[3]) : null;
      if (trust === null) throw new ScriptError(`@@person 需要 4 个字段：${value}`);
      story.persons.push({ key: f[0], name: f[1], desc: f[2] });
      story.initial[f[0]] = trust;
      story.bounds[f[0]] = [0, 100];
      break;
    }
    case 'item':
      if (f.length < 2) throw new ScriptError('@@item 至少要有 key 和名称');
      story.items.push({ key: f[0], name: f[1], desc: f.length > 2 ? f[2] : '' });
      break;
    case 'enum':
      if (f.length < 2) throw new ScriptError('@@enum 至少要有一个标签');
      story.enums[f[0]] = f.slice(1);
      break;
    case 'var': {
      const parts = value.split('=').map(x => x.trim());
      const v = parts.length === 2 ? toInt(parts[1]) : null;
      if (v === null) throw new ScriptError('@@var 写法：@@var key = 值');
      story.initial[parts[0]] = v;
      break;
    }
    case 'bound': {
      const lo = f.length === 3 ? toInt(f[1]) : null, hi = f.length === 3 ? toInt(f[2]) : null;
      if (lo === null || hi === null) throw new ScriptError('@@bound 写法：key | 下限 | 上限');
      story.bounds[f[0]] = [lo, hi];
      break;
    }
    default:
      throw new ScriptError(`不认识的声明 @@${keyword}`);
  }
}

function parseDirective(line, node, ln) {
  const [key, value] = splitHead(line.slice(1));
  switch (key) {
    case 'chapter': node.chapter = value; break;
    case 'date': node.date = value; break;
    case 'place': node.place = value; break;
    case 'mood': node.mood = value; break;
    case 'act': node.act = toInt(value); break;
    case 'set': node.sets.push(...parseEffects(value)); break;
    case 'if': {
      const arrow = value.lastIndexOf('->');
      if (arrow < 0) throw new ScriptError('@if 缺少 -> 目标');
      const cond = value.slice(0, arrow).trim();
      const target = value.slice(arrow + 2).trim();
      node.redirects.push({ cond: parseExpr(cond), target, line: ln });
      break;
    }
    case 'goto': node.redirects.push({ cond: null, target: value, line: ln }); break;
    case 'ending': node.ending = value; break;
    case 'archive': node.archives.push(value); break;
    default: node.props[key] = value;
  }
}

function parseChoice(line, ln) {
  const locked = line.startsWith('+');
  let rest = line.slice(1).trim();
  let cond = null;
  if (rest.startsWith('[')) {
    const close = rest.indexOf(']');
    if (close < 0) throw new ScriptError('选项条件的 [ ] 没有闭合');
    cond = parseExpr(rest.slice(1, close));
    rest = rest.slice(close + 1).trim();
  }
  const arrow = rest.lastIndexOf('->');
  if (arrow < 0) throw new ScriptError('选项缺少 -> 目标');
  const text = rest.slice(0, arrow).trim();
  let tail = rest.slice(arrow + 2).trim();
  let effects = [];
  const bar = tail.indexOf('|');
  if (bar >= 0) {
    effects = parseEffects(tail.slice(bar + 1));
    tail = tail.slice(0, bar).trim();
  }
  if (!text || !tail) throw new ScriptError('选项文字或目标为空');
  return { cond, showLocked: locked, text, target: tail, effects, line: ln };
}

function parsePara(line) {
  let rest = line;
  let cond = null;
  if (rest.startsWith('[?')) {
    const close = rest.indexOf(']');
    if (close < 0) throw new ScriptError('条件段落的 [? ] 没有闭合');
    cond = parseExpr(rest.slice(2, close).trim());
    rest = rest.slice(close + 1).trim();
  }
  if (rest === '---') return { cond, style: 'rule', text: '' };
  if (rest.startsWith('>')) return { cond, style: 'quote', text: rest.slice(1).trim() };
  return { cond, style: 'normal', text: rest };
}

/** 把 ending:xx / doc:xx 登记节点整理成结局表和档案表 */
function finalize(story) {
  for (const id of story.nodeOrder) {
    const n = story.nodes.get(id);
    if (!n) continue;
    if (id.startsWith('ending:')) {
      const eid = id.slice('ending:'.length);
      story.endings.push({
        id: eid,
        tier: n.props.tier ?? 'BE',
        title: n.props.title ?? eid,
        act: n.act ?? 0,
        doc: n.props.doc ?? null,
        hint: n.props.hint ?? '',
        order: toInt(n.props.order ?? '') ?? story.endings.length * 10,
      });
    } else if (id.startsWith('doc:')) {
      const did = id.slice('doc:'.length);
      story.docs.push({
        id: did,
        title: n.props.title ?? did,
        source: n.props.source ?? '',
        date: n.date ?? '',
        kind: n.props.kind ?? '档案',
        who: n.props.who ?? null,
        isKey: n.props.key !== undefined ? n.props.key !== '0' : false,
        paras: n.paras,
        order: toInt(n.props.order ?? '') ?? story.docs.length * 10,
      });
    }
  }
  story.buildIndexes();
}
