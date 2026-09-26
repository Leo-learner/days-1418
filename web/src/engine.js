import { evaluate, identifier, parseExpr } from './expr.js';

// 一局游戏的全部状态（可以直接 JSON 化存档）。随机数种子也存在里面：
// 同样的选择永远得到同样的结果，读档刷不出好运气。rng 是 64 位无符号整数的十进制字符串。
export function newRunState() {
  return {
    node: '', vars: {}, rng: '0',
    chapter: '', date: '', place: '', mood: '',
    visited: {}, log: [], snapshots: [],
    lastChoice: null, playSeconds: 0, hardcore: false, ending: null,
    savedAt: new Date().toISOString(),
  };
}

/** 跨周目的进度：结局、档案、m_ 变量 */
export function newMeta() {
  return { endings: {}, docs: {}, vars: {}, runsStarted: 0, runsFinished: 0, unseenEndings: [], unseenDocs: [] };
}

const MASK = (1n << 64n) - 1n;

/** SplitMix64：小、快、可复现。和 Swift 版逐位一致 */
export class SplitMix {
  constructor(seed) { this.state = BigInt.asUintN(64, BigInt(seed)); }
  next() {
    this.state = (this.state + 0x9E3779B97F4A7C15n) & MASK;
    let z = this.state;
    z = ((z ^ (z >> 30n)) * 0xBF58476D1CE4E5B9n) & MASK;
    z = ((z ^ (z >> 27n)) * 0x94D049BB133111EBn) & MASK;
    return z ^ (z >> 31n);
  }
}

export function randomSeed() {
  const a = new Uint32Array(2);
  globalThis.crypto.getRandomValues(a);
  const s = (BigInt(a[0]) << 32n) | BigInt(a[1]);
  return (s === 0n ? 1n : s).toString();
}

const clone = v => JSON.parse(JSON.stringify(v));
const now = () => new Date().toISOString();

export class Engine {
  constructor(story, meta) {
    this.story = story;
    this.meta = meta;
    this.state = newRunState();
    this.freshDocs = [];       // 上一步刚解密的档案（给提示条用）
    this.freshEnding = false;
    this.randomAllowed = false;
  }

  // ---- 表达式上下文 ----

  lookup(name) {
    switch (name) {
      case 'endings': return Object.keys(this.meta.endings).length;
      case 'docs': return Object.keys(this.meta.docs).length;
      case 'runs': return this.meta.runsFinished;
      case 'hardcore': return this.state.hardcore ? 1 : 0;
      default:
        if (name.startsWith('m_')) return this.meta.vars[name] ?? 0;
        return this.state.vars[name] ?? this.story.initial[name] ?? 0;
    }
  }

  call(fn, args) {
    const arg = i => (i < args.length ? evaluate(args[i], this) : 0);
    const ident = i => (i < args.length ? identifier(args[i]) ?? '' : '');
    switch (fn) {
      case 'doc': return this.meta.docs[ident(0)] !== undefined ? 1 : 0;
      case 'end': return this.meta.endings[ident(0)] !== undefined ? 1 : 0;
      case 'seen': return (this.state.visited[ident(0)] ?? 0) > 0 ? 1 : 0;
      case 'alive': {
        const k = ident(0);
        return this.lookup(k + '_met') !== 0 && this.lookup(k + '_dead') === 0 ? 1 : 0;
      }
      case 'rand': {
        const n = Math.max(1, arg(0));
        return this.randomAllowed ? Number(this.nextRandom() % BigInt(n)) : 0;
      }
      case 'min': return args.length ? Math.min(...args.map(a => evaluate(a, this))) : 0;
      case 'max': return args.length ? Math.max(...args.map(a => evaluate(a, this))) : 0;
      case 'abs': return Math.abs(arg(0));
      case 'if': return args.length === 3 ? (arg(0) !== 0 ? arg(1) : arg(2)) : 0;
      default: return 0;
    }
  }

  nextRandom() {
    const r = new SplitMix(this.state.rng);
    const v = r.next();
    this.state.rng = r.state.toString();
    return v;
  }

  test(cond) { return cond ? evaluate(cond, this) !== 0 : true; }

  // ---- 状态读写 ----

  set(name, value) {
    let v = value;
    const range = this.story.bounds[name];
    if (range) v = Math.min(Math.max(v, range[0]), range[1]);
    if (name.startsWith('m_')) this.meta.vars[name] = v;
    else this.state.vars[name] = v;
  }

  apply(effects) {
    this.randomAllowed = true;
    try {
      for (const e of effects) {
        switch (e.t) {
          case 'assign': {
            const v = evaluate(e.expr, this);
            if (e.op === '+=') this.set(e.name, this.lookup(e.name) + v);
            else if (e.op === '-=') this.set(e.name, this.lookup(e.name) - v);
            else this.set(e.name, v);
            break;
          }
          case 'archive': this.unlockDoc(e.id); break;
          case 'kill': this.set(e.who + '_dead', 1); break;
          case 'meet': this.set(e.who + '_met', 1); break;
        }
      }
    } finally {
      this.randomAllowed = false;
    }
  }

  unlockDoc(id) {
    if (this.meta.docs[id] !== undefined) return;
    this.meta.docs[id] = now();
    if (!this.meta.unseenDocs.includes(id)) this.meta.unseenDocs.push(id);
    this.freshDocs.push(id);
  }

  // ---- 流程 ----

  newRun(hardcore, seed = null) {
    this.state = newRunState();
    this.state.hardcore = hardcore;
    this.state.vars = { ...this.story.initial };
    this.state.rng = seed !== null ? BigInt.asUintN(64, BigInt(seed)).toString() : randomSeed();
    this.meta.runsStarted += 1;
    this.freshDocs = [];
    this.freshEnding = false;
    this.enter(this.story.start);
    this.appendLog(null);
  }

  restore(saved) {
    this.state = saved;
    this.freshDocs = [];
    this.freshEnding = false;
  }

  /** 进入节点：执行 @set、解密 @archive、按 @if 跳转，最后停在一个要给玩家看的节点上 */
  enter(id) {
    let target = id;
    for (let hop = 0; hop < 64; hop++) {
      const node = this.story.nodes.get(target);
      if (!node) {
        this.state.node = target;
        return;
      }
      this.state.visited[target] = (this.state.visited[target] ?? 0) + 1;
      this.apply(node.sets);
      for (const a of node.archives) this.unlockDoc(a);
      if (node.chapter !== null) this.state.chapter = node.chapter;
      if (node.date !== null) this.state.date = node.date;
      if (node.place !== null) this.state.place = node.place;
      if (node.mood !== null) this.state.mood = node.mood;

      this.randomAllowed = true;
      let jump = null;
      try {
        for (const r of node.redirects) {
          if (this.test(r.cond)) { jump = r; break; }
        }
      } finally {
        this.randomAllowed = false;
      }
      if (jump) {
        target = jump.target;
        continue;
      }
      this.state.node = target;
      if (node.ending !== null) this.reachEnding(node.ending);
      return;
    }
    this.state.node = target;
  }

  reachEnding(id) {
    this.state.ending = id;
    this.meta.runsFinished += 1;
    if (this.meta.endings[id] === undefined) {
      this.meta.endings[id] = now();
      if (!this.meta.unseenEndings.includes(id)) this.meta.unseenEndings.push(id);
      this.freshEnding = true;
    }
    const doc = this.story.ending(id)?.doc;
    if (doc) this.unlockDoc(doc);
  }

  /** 可选的选项（含锁定的）。index 是节点里的第几个选项；-1 表示"继续" */
  shownChoices() {
    const node = this.story.nodes.get(this.state.node);
    if (!node || node.ending !== null) return [];
    const out = [];
    node.choices.forEach((c, i) => {
      const ok = this.test(c.cond);
      if (!ok && !c.showLocked) return;
      const [tags, text] = splitTags(this.interpolate(c.text));
      out.push({ id: out.length, index: i, text, tags, enabled: ok });
    });
    if (!node.choices.length && node.next !== null) {
      out.push({ id: 0, index: -1, text: '继续', tags: [], enabled: true });
    }
    return out;
  }

  passage() {
    const node = this.story.nodes.get(this.state.node);
    let paras = [];
    for (const p of node?.paras ?? []) {
      if (!this.test(p.cond)) continue;
      const text = this.interpolate(p.text);
      // 连续的 > 引文合成一块（纪念章纸条、命令摘录都是多行的）
      const last = paras[paras.length - 1];
      if (p.style === 'quote' && last && last.style === 'quote') last.text += '\n' + text;
      else paras.push({ id: paras.length, style: p.style, text });
    }
    const choices = this.shownChoices();
    const ending = node?.ending ? this.story.ending(node.ending) : null;
    if (!node) paras = [{ id: 0, style: 'quote', text: `（剧本在这里断了：找不到节点「${this.state.node}」）` }];
    return {
      nodeId: this.state.node,
      chapter: this.state.chapter,
      date: this.state.date,
      place: this.state.place,
      mood: this.state.mood,
      paras,
      choices,
      ending,
      lastChoice: this.state.lastChoice,
      broken: !ending && !choices.length,
    };
  }

  choose(shown) {
    const node = this.story.nodes.get(this.state.node);
    if (!node || !shown.enabled) return;
    this.freshDocs = [];
    this.freshEnding = false;
    const s = this.state;
    s.snapshots.push({
      node: s.node, vars: { ...s.vars }, rng: s.rng,
      chapter: s.chapter, date: s.date, place: s.place, mood: s.mood,
      logCount: s.log.length, visited: { ...s.visited }, lastChoice: s.lastChoice,
    });
    if (s.snapshots.length > 300) s.snapshots.splice(0, s.snapshots.length - 300);

    if (shown.index < 0) {
      this.apply(node.nextEffects);
      s.lastChoice = null;
      this.enter(node.next ?? '');
    } else {
      const choice = node.choices[shown.index];
      this.apply(choice.effects);
      s.lastChoice = shown.text;
      this.enter(choice.target);
    }
    this.appendLog(this.state.lastChoice);
  }

  get canRewind() { return this.state.snapshots.length > 0 && !this.state.hardcore; }

  rewind() {
    const s = this.state.snapshots.pop();
    if (!s) return;
    const st = this.state;
    st.node = s.node;
    st.vars = s.vars;
    st.rng = s.rng;
    st.chapter = s.chapter;
    st.date = s.date;
    st.place = s.place;
    st.mood = s.mood;
    st.visited = s.visited;
    st.lastChoice = s.lastChoice;
    st.ending = null;
    if (st.log.length > s.logCount) st.log.splice(s.logCount);
    this.freshDocs = [];
    this.freshEnding = false;
  }

  appendLog(choice) {
    const paras = (this.story.nodes.get(this.state.node)?.paras ?? []).filter(p => this.test(p.cond));
    const text = paras.map(p => (p.style === 'rule' ? '——' : this.interpolate(p.text))).join('\n');
    const header = [this.state.date, this.state.place].filter(Boolean).join(' · ');
    this.state.log.push({ choice, header, text });
    if (this.state.log.length > 800) this.state.log.splice(0, this.state.log.length - 800);
  }

  // ---- 文本 ----

  /** {表达式} 换成数值，{#key} 换成枚举名 */
  interpolate(s) {
    if (!s.includes('{')) return s;
    let out = '';
    let i = 0;
    while (i < s.length) {
      const close = s[i] === '{' ? s.indexOf('}', i) : -1;
      if (close < 0) {
        out += s[i];
        i++;
        continue;
      }
      const inner = s.slice(i + 1, close).trim();
      if (inner.startsWith('#')) {
        const key = inner.slice(1);
        out += this.story.label(key, this.lookup(key));
      } else {
        let e = null;
        try { e = parseExpr(inner); } catch { e = null; }
        out += e ? String(evaluate(e, this)) : `{${inner}}`;
      }
      i = close + 1;
    }
    return out;
  }

  /** 仅供自检：给 ending 前的自动存档做一份深拷贝 */
  cloneState() { return clone(this.state); }
}

/** "【战术 4】【档案】翻过去" → [["战术 4", "档案"], "翻过去"] */
export function splitTags(s) {
  const tags = [];
  let rest = s;
  for (;;) {
    if (!rest.startsWith('【')) break;
    const close = rest.indexOf('】');
    if (close < 0) break;
    tags.push(rest.slice(1, close));
    rest = rest.slice(close + 1).replace(/^ +/, '');
  }
  return [tags, rest];
}
