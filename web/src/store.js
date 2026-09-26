// 存档后端。
//  · local  —— 单独打开网页时：浏览器 localStorage（压缩后存）
//  · cloud  —— 在 Game Hub（games.dkz12345.com/play/…）里并且已登录：云存档，每个存档位一个云槽
//  · memory —— 在 Game Hub 里但没登录：按网站的约定，游客进度不落盘，只留在当前页面
//
// 一局完整的存档 JSON 约 700 KB（300 步回溯快照 + 战斗日志），gzip 后约 90 KB，
// 所以统一 gzip + base64 再存；不支持 CompressionStream 的浏览器退回明文 JSON。
//
// 所有写入都在调用那一刻就 JSON.stringify：引擎状态之后还会继续变，排队中的写入不能跟着变。
// 同一个键同时只有一个写入在路上，排队中的只保留最新一份。

export const SLOT_COUNT = 8;         // 手动存档位 1…8；0 号是自动存档
const FORMAT = 'days1418';
const LOCAL_PREFIX = 'days1418:';

// ---- 压缩 ----

const canCompress = typeof CompressionStream === 'function' && typeof DecompressionStream === 'function';

function toBase64(bytes) {
  let s = '';
  for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(s);
}

function fromBase64(b64) {
  const s = atob(b64);
  const out = new Uint8Array(s.length);
  for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i);
  return out;
}

/** json：已经序列化好的字符串 → 存档用的对象 */
export async function pack(json) {
  if (!canCompress) return { format: FORMAT, v: 1, json: JSON.parse(json) };
  const stream = new Blob([json]).stream().pipeThrough(new CompressionStream('gzip'));
  const bytes = new Uint8Array(await new Response(stream).arrayBuffer());
  return { format: FORMAT, v: 1, z: toBase64(bytes) };
}

export async function unpack(data) {
  if (!data || data.format !== FORMAT) return null;
  if (data.json) return data.json;
  if (typeof data.z !== 'string' || !canCompress) return null;
  const stream = new Blob([fromBase64(data.z)]).stream().pipeThrough(new DecompressionStream('gzip'));
  return JSON.parse(await new Response(stream).text());
}

/** 存档位列表里显示的摘要：不用为了列表把整局存档都解压 */
export function summarize(state) {
  return {
    chapter: state.chapter, date: state.date, savedAt: state.savedAt,
    playSeconds: state.playSeconds, hardcore: state.hardcore, ending: state.ending,
  };
}

/** 两份跨周目进度合并（云端被另一台设备改过时用）：结局、档案取并集，计数取大 */
export function mergeMeta(a, b) {
  const earlier = (x, y) => {
    const out = { ...y };
    for (const [k, v] of Object.entries(x)) out[k] = out[k] && out[k] < v ? out[k] : v;
    return out;
  };
  const vars = { ...b.vars };
  for (const [k, v] of Object.entries(a.vars)) vars[k] = Math.max(v, vars[k] ?? v);
  return {
    endings: earlier(a.endings, b.endings),
    docs: earlier(a.docs, b.docs),
    vars,
    runsStarted: Math.max(a.runsStarted, b.runsStarted),
    runsFinished: Math.max(a.runsFinished, b.runsFinished),
    unseenEndings: [...new Set([...a.unseenEndings, ...b.unseenEndings])],
    unseenDocs: [...new Set([...a.unseenDocs, ...b.unseenDocs])],
  };
}

/** 每个键一条写入队列 */
class Writer {
  constructor(put, onError) {
    this.put = put;
    this.onError = onError;
    this.queues = new Map();
  }
  write(key, json) {
    let q = this.queues.get(key);
    if (!q) { q = { pending: null, chain: Promise.resolve() }; this.queues.set(key, q); }
    const idle = q.pending === null;
    q.pending = json;
    if (idle) {
      q.chain = q.chain.then(async () => {
        const next = q.pending;
        q.pending = null;
        try { await this.put(key, next); } catch (err) { this.onError?.(err); }
      });
    }
    return q.chain;
  }
  async flush(key) {
    if (key !== undefined) return this.queues.get(key)?.chain;
    await Promise.all([...this.queues.values()].map(q => q.chain));
  }
}

// 每个后端都有这些方法：
//   loadProgress() / saveProgress({meta, slots})   跨周目进度 + 各存档位摘要
//   loadSlot(n) / saveSlot(n, state) / deleteSlot(n)
//   wipe()  flush()

// ---- memory ----

class MemoryStore {
  constructor() { this.kind = 'memory'; this.data = new Map(); }
  async read(key) { const s = this.data.get(key); return s ? JSON.parse(s) : null; }
  loadProgress() { return this.read('progress'); }
  async saveProgress(p) { this.data.set('progress', JSON.stringify(p)); }
  loadSlot(n) { return this.read('slot' + n); }
  async saveSlot(n, state) { this.data.set('slot' + n, JSON.stringify(state)); }
  async deleteSlot(n) { this.data.delete('slot' + n); }
  async wipe() { this.data.clear(); }
  async flush() {}
}

export const memoryStore = () => new MemoryStore();

// ---- local ----

class LocalStore {
  constructor(storage, onError) {
    this.kind = 'local';
    this.ls = storage;
    this.writer = new Writer(async (key, json) => {
      this.ls.setItem(LOCAL_PREFIX + key, JSON.stringify(await pack(json)));
    }, onError);
  }
  async read(key) {
    await this.writer.flush(key);
    const raw = this.ls.getItem(LOCAL_PREFIX + key);
    if (!raw) return null;
    try { return await unpack(JSON.parse(raw)); } catch { return null; }
  }
  loadProgress() { return this.read('progress'); }
  saveProgress(p) { return this.writer.write('progress', JSON.stringify(p)); }
  loadSlot(n) { return this.read('slot' + n); }
  saveSlot(n, state) { return this.writer.write('slot' + n, JSON.stringify(state)); }
  async deleteSlot(n) {
    await this.writer.flush('slot' + n);
    this.ls.removeItem(LOCAL_PREFIX + 'slot' + n);
  }
  async wipe() {
    await this.writer.flush();
    for (let n = 0; n <= SLOT_COUNT; n++) this.ls.removeItem(LOCAL_PREFIX + 'slot' + n);
    this.ls.removeItem(LOCAL_PREFIX + 'progress');
  }
  flush() { return this.writer.flush(); }
}

function localStorageOrNull() {
  try {
    const ls = globalThis.localStorage;
    const probe = LOCAL_PREFIX + 'probe';
    ls.setItem(probe, '1');
    ls.removeItem(probe);
    return ls;
  } catch {
    return null;
  }
}

// ---- cloud (Game Hub) ----

/** 版本冲突（另一台设备写过）时：进度槽合并后重写，存档位直接以本机为准覆盖 */
class CloudStore {
  constructor(client, slug, user, onError) {
    this.kind = 'cloud';
    this.client = client;
    this.slug = slug;
    this.user = user;
    this.revisions = new Map();
    this.writer = new Writer((slot, json) => this.put(slot, json), onError);
  }

  async init() {
    const { items } = await this.client.saves.list(this.slug);
    for (const it of items) this.revisions.set(it.slot, it.revision);
  }

  async read(slot, { flush = true } = {}) {
    if (flush) await this.writer.flush(slot);
    const saved = await this.client.saves.load(this.slug, slot);
    if (!saved) { this.revisions.set(slot, 0); return null; }
    this.revisions.set(slot, saved.revision);
    return unpack(saved.data);
  }

  async put(slot, json) {
    for (let attempt = 0; ; attempt++) {
      const data = await pack(json);
      try {
        const meta = await this.client.saves.save(this.slug, slot, {
          data, schemaVersion: 1, expectedRevision: this.revisions.get(slot) ?? 0,
        });
        this.revisions.set(slot, meta.revision);
        return;
      } catch (err) {
        if (err?.code !== 'SAVE_CONFLICT' || attempt >= 2) throw err;
        if (slot === 'progress') {
          const remote = await this.read(slot, { flush: false });
          if (remote) {
            const mine = JSON.parse(json);
            json = JSON.stringify({ meta: mergeMeta(mine.meta, remote.meta), slots: { ...remote.slots, ...mine.slots } });
          }
        } else {
          this.revisions.set(slot, Number(err.details?.currentRevision ?? 0));
        }
      }
    }
  }

  async remove(slot) {
    await this.writer.flush(slot);
    const rev = this.revisions.get(slot) ?? 0;
    if (!rev) return;
    try {
      await this.client.saves.remove(this.slug, slot, rev);
    } catch (err) {
      if (err?.code !== 'SAVE_NOT_FOUND') throw err;
    }
    this.revisions.set(slot, 0);
  }

  loadProgress() { return this.read('progress'); }
  saveProgress(p) { return this.writer.write('progress', JSON.stringify(p)); }
  loadSlot(n) { return this.read('slot' + n); }
  saveSlot(n, state) { return this.writer.write('slot' + n, JSON.stringify(state)); }
  deleteSlot(n) { return this.remove('slot' + n); }
  async wipe() {
    for (let n = 0; n <= SLOT_COUNT; n++) await this.remove('slot' + n);
    await this.remove('progress');
  }
  flush() { return this.writer.flush(); }
}

/**
 * 选后端。在 Game Hub 的 /play/<slug>/<版本>/ 下运行时用网站的 SDK；
 * 其余情况（本地打开、别的静态托管）用 localStorage，localStorage 不可用就只留在内存里。
 * 返回 {store, hub:{client, slug, user}|null}
 */
export async function openStore({ onError } = {}) {
  const m = /^\/play\/([^/]+)\//.exec(location.pathname);
  if (m) {
    let hub = null;
    try {
      const { createClient } = await import('/sdk/game-hub.js');
      const client = createClient();
      hub = { client, slug: decodeURIComponent(m[1]), user: await client.auth.me() };
    } catch (err) {
      console.warn('Game Hub SDK 不可用，改用浏览器存档', err);
    }
    if (hub && !hub.user) return { store: new MemoryStore(), hub };
    if (hub) {
      const store = new CloudStore(hub.client, hub.slug, hub.user, onError);
      try {
        await store.init();
        return { store, hub };
      } catch (err) {
        // 登录了但云存档读不到：不偷偷改用本地存档，这一局只留在内存里并告诉玩家
        return { store: new MemoryStore(), hub, error: err };
      }
    }
  }
  const ls = localStorageOrNull();
  return { store: ls ? new LocalStore(ls, onError) : new MemoryStore(), hub: null };
}
