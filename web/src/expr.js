// 剧本里的条件和数值表达式：整数、变量、四则运算、比较、&& || !、函数调用。
// 所有值都是整数，布尔值用 0/1 表示——剧本作者只需要记住"非零即真"。
// 语法树是普通对象：{t:'num',v} {t:'name',v} {t:'un',op,e} {t:'bin',op,l,r} {t:'call',fn,args}

export class ScriptError extends Error {}

const PRECEDENCE = {
  '||': 1, '&&': 2,
  '==': 3, '!=': 3,
  '<': 4, '<=': 4, '>': 4, '>=': 4,
  '+': 5, '-': 5,
  '*': 6, '/': 6, '%': 6,
};
const TWO_CHAR = new Set(['==', '!=', '<=', '>=', '&&', '||']);
const ONE_CHAR = '+-*/%<>!(),';
const isDigit = c => c >= '0' && c <= '9';
const isLetter = c => (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z');

/** 严格的整数解析，对应 Swift 的 Int(String)：失败返回 null */
export function toInt(s) {
  return /^[+-]?\d+$/.test(s) ? Number.parseInt(s, 10) : null;
}

export function tokenize(source) {
  const out = [];
  const cs = Array.from(source);
  let i = 0;
  while (i < cs.length) {
    const c = cs[i];
    if (c === ' ' || c === '\t') { i++; continue; }
    if (isDigit(c)) {
      let j = i;
      while (j < cs.length && isDigit(cs[j])) j++;
      out.push({ k: 'num', v: toInt(cs.slice(i, j).join('')) ?? 0 });
      i = j;
      continue;
    }
    if (isLetter(c) || c === '_') {
      let j = i;
      while (j < cs.length && (isLetter(cs[j]) || isDigit(cs[j]) || cs[j] === '_')) j++;
      out.push({ k: 'id', v: cs.slice(i, j).join('') });
      i = j;
      continue;
    }
    if (i + 1 < cs.length && TWO_CHAR.has(c + cs[i + 1])) {
      out.push({ k: 'op', v: c + cs[i + 1] });
      i += 2;
      continue;
    }
    if (ONE_CHAR.includes(c)) {
      out.push({ k: 'op', v: c });
      i++;
      continue;
    }
    throw new ScriptError(`表达式里有认不出的字符「${c}」：${source}`);
  }
  out.push({ k: 'end' });
  return out;
}

class Parser {
  constructor(tokens) { this.tokens = tokens; this.pos = 0; }
  get peek() { return this.tokens[this.pos]; }
  next() {
    const t = this.tokens[this.pos];
    if (this.pos < this.tokens.length - 1) this.pos++;
    return t;
  }
  isOp(v) { const t = this.peek; return t.k === 'op' && t.v === v; }

  // 优先级爬升；同级左结合
  parse(minPrecedence) {
    let lhs = this.parseUnary();
    for (;;) {
      const t = this.peek;
      const p = t.k === 'op' ? PRECEDENCE[t.v] : undefined;
      if (p === undefined || p < minPrecedence) break;
      this.next();
      const rhs = this.parse(p + 1);
      lhs = { t: 'bin', op: t.v, l: lhs, r: rhs };
    }
    return lhs;
  }

  parseUnary() {
    const t = this.peek;
    if (t.k === 'op' && (t.v === '!' || t.v === '-')) {
      this.next();
      return { t: 'un', op: t.v, e: this.parseUnary() };
    }
    return this.parsePrimary();
  }

  parsePrimary() {
    const t = this.next();
    if (t.k === 'num') return { t: 'num', v: t.v };
    if (t.k === 'id') {
      if (t.v === 'true') return { t: 'num', v: 1 };
      if (t.v === 'false') return { t: 'num', v: 0 };
      if (!this.isOp('(')) return { t: 'name', v: t.v };
      this.next();
      const args = [];
      if (this.isOp(')')) {
        this.next();
        return { t: 'call', fn: t.v, args };
      }
      for (;;) {
        args.push(this.parse(1));
        const n = this.next();
        if (n.k === 'op' && n.v === ')') break;
        if (!(n.k === 'op' && n.v === ',')) throw new ScriptError(`函数 ${t.v}(…) 的参数写法不对`);
      }
      return { t: 'call', fn: t.v, args };
    }
    if (t.k === 'op' && t.v === '(') {
      const e = this.parse(1);
      const n = this.next();
      if (!(n.k === 'op' && n.v === ')')) throw new ScriptError('括号没有闭合');
      return e;
    }
    throw new ScriptError('表达式不完整');
  }
}

export function parseExpr(source) {
  const p = new Parser(tokenize(source));
  const e = p.parse(1);
  if (p.peek.k !== 'end') throw new ScriptError(`表达式后面多了东西：${source}`);
  return e;
}

/** doc(d06)、seen(a1_start) 这类函数的参数是裸标识符，不当变量求值 */
export const identifier = e => (e && e.t === 'name' ? e.v : null);

const bool = b => (b ? 1 : 0);

/** ctx 需要 lookup(name) 和 call(fn, args) */
export function evaluate(e, ctx) {
  switch (e.t) {
    case 'num': return e.v;
    case 'name': return ctx.lookup(e.v);
    case 'un': {
      const v = evaluate(e.e, ctx);
      return e.op === '!' ? (v === 0 ? 1 : 0) : -v;
    }
    case 'bin': {
      if (e.op === '&&') return evaluate(e.l, ctx) !== 0 && evaluate(e.r, ctx) !== 0 ? 1 : 0;
      if (e.op === '||') return evaluate(e.l, ctx) !== 0 || evaluate(e.r, ctx) !== 0 ? 1 : 0;
      const a = evaluate(e.l, ctx), b = evaluate(e.r, ctx);
      switch (e.op) {
        case '+': return a + b;
        case '-': return a - b;
        case '*': return a * b;
        case '/': return b === 0 ? 0 : Math.trunc(a / b);
        case '%': return b === 0 ? 0 : a % b;
        case '==': return bool(a === b);
        case '!=': return bool(a !== b);
        case '<': return bool(a < b);
        case '<=': return bool(a <= b);
        case '>': return bool(a > b);
        case '>=': return bool(a >= b);
        default: return 0;
      }
    }
    case 'call': return ctx.call(e.fn, e.args);
    default: return 0;
  }
}

// 进入节点或做出选择时执行的效果：
// {t:'assign', name, op:'='|'+='|'-=', expr} {t:'archive', id} {t:'kill', who} {t:'meet', who}

export function parseEffects(source) {
  const out = [];
  for (const raw of source.split(';')) {
    const s = raw.trim();
    if (s) out.push(parseEffect(s));
  }
  return out;
}

function parseEffect(s) {
  for (const keyword of ['archive', 'kill', 'meet']) {
    if (!s.startsWith(keyword + ' ')) continue;
    const arg = s.slice(keyword.length + 1).trim();
    if (!arg) throw new ScriptError(`${keyword} 后面缺少名字`);
    if (keyword === 'archive') return { t: 'archive', id: arg };
    if (keyword === 'kill') return { t: 'kill', who: arg };
    return { t: 'meet', who: arg };
  }
  const chars = Array.from(s);
  for (let i = 0; i < chars.length; i++) {
    if (chars[i] !== '=') continue;
    const prev = i > 0 ? chars[i - 1] : null;
    const next = i + 1 < chars.length ? chars[i + 1] : null;
    if (next === '=' || prev === '=' || prev === '!' || prev === '<' || prev === '>') continue;
    let op = '=';
    let lhsEnd = i;
    if (prev === '+' || prev === '-') {
      op = prev + '=';
      lhsEnd = i - 1;
    }
    const name = chars.slice(0, lhsEnd).join('').trim();
    const rhs = chars.slice(i + 1).join('').trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(name)) throw new ScriptError(`赋值左边不是变量名：${s}`);
    return { t: 'assign', name, op, expr: parseExpr(rhs) };
  }
  throw new ScriptError(`看不懂的效果：${s}`);
}
