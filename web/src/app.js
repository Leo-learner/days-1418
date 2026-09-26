import { loadStory, isRegistry } from './story.js';
import { Engine, newMeta } from './engine.js';
import { openStore, memoryStore, summarize, SLOT_COUNT } from './store.js';
import { Atmosphere } from './atmosphere.js';
import { esc, inline, joinDot, duration, fmtDay, fmtStamp, signed, icons } from './ui.js';

// ============================================================
//  设置（只是本机的阅读偏好，不是游戏进度）
// ============================================================

const PREF_KEY = 'days1418:prefs';
const prefs = {
  textMode: 0,        // 0 逐段浮现  1 打字机  2 立即显示
  fontSize: 18,
  theme: 0,           // 0 夜  1 纸
  motion: !matchMedia('(prefers-reduced-motion: reduce)').matches,
  hints: true,
  sidebar: true,
};
try { Object.assign(prefs, JSON.parse(localStorage.getItem(PREF_KEY) || '{}')); } catch { /* 无痕模式等 */ }
function savePrefs() {
  try { localStorage.setItem(PREF_KEY, JSON.stringify(prefs)); } catch { /* 忽略 */ }
}

// ============================================================
//  状态
// ============================================================

const $ = (sel, root = document) => root.querySelector(sel);
const screenEl = $('#screen');
const modalEl = $('#modal');
const toastEl = $('#toasts');
const bannerEl = $('#banner');
let atmo = null;

const app = {
  story: null,
  engine: null,
  store: null,
  hub: null,
  storeError: null,
  screen: 'loading',       // title | game | ending | archive
  passage: null,
  passageVersion: 0,
  deltas: {},
  changes: [],
  archiveTab: 0,
  archiveDoc: null,
  archiveBack: 'title',
  slots: {},               // 存档位 → 摘要
  modal: null,
  lastTick: Date.now(),
  showDoc: false,
  drawer: false,
};
let deltaTimer = 0;

const meta = () => app.engine.meta;
const endingCount = () => Object.keys(meta().endings).length;
const docCount = () => Object.keys(meta().docs).length;
const unseenCount = () => meta().unseenDocs.length + meta().unseenEndings.length;
const isHardcore = () => app.engine.state.hardcore;
const canRewind = () => app.engine.canRewind && (app.screen === 'game' || app.screen === 'ending');
const wideLayout = matchMedia('(min-width: 900px)');
const sidebarInline = () => wideLayout.matches && prefs.sidebar;

// ============================================================
//  存档
// ============================================================

function saveProgress() {
  app.store.saveProgress({ meta: meta(), slots: app.slots });
}

function writeSlot(n, state) {
  const copy = { ...state, savedAt: new Date().toISOString() };
  app.store.saveSlot(n, copy);
  app.slots[n] = summarize(copy);
}

function writeAutosave() {
  writeSlot(0, app.engine.state);
  saveProgress();
}

let lastCloudError = 0;
function reportStoreError(err) {
  console.error(err);
  if (err?.code === 'ACCOUNT_CHANGED' || err?.code === 'AUTH_REQUIRED') return authChanged();
  if (Date.now() - lastCloudError < 10000) return;
  lastCloudError = Date.now();
  toast(app.store?.kind === 'cloud' ? '云存档没有保存成功' : '存档没有保存成功', err?.message || String(err), true);
}

function storageNote() {
  const s = app.store;
  if (app.storeError) return { text: '云存档暂时连不上 · 这一次的进度只保留在当前页面', warn: true };
  if (s.kind === 'cloud') return { text: `云存档 · ${app.hub.user.displayName}`, cloud: true };
  if (s.kind === 'local') return { text: '进度保存在这个浏览器里' };
  if (app.hub) return { text: '游客模式 · 进度只保留在当前页面，登录 Game Hub 后自动启用云存档', warn: true };
  return { text: '浏览器不允许本地存储 · 进度只保留在当前页面', warn: true };
}

let authNoticeShown = false;
function authChanged() {
  if (authNoticeShown) return;
  authNoticeShown = true;
  // 账号变了：之后的进度不能再写到原来那个账号里
  if (app.store.kind === 'cloud') app.store = memoryStore();
  bannerEl.innerHTML = `<span>登录状态变了。重新载入游戏，才能用现在的账号读写云存档。</span>
    <button class="btn small" data-act="reload">重新载入</button>`;
  bannerEl.hidden = false;
}

// ============================================================
//  流程（对应 Mac 版 GameModel）
// ============================================================

// 调试用：?seed=11 让新的卷宗用固定的随机数种子（和 tests/*.walk 里的 @seed 对应）
const seedParam = new URLSearchParams(location.search).get('seed');
const debugSeed = /^\d+$/.test(seedParam ?? '') ? seedParam : null;

function newGame(hardcore) {
  app.engine.newRun(hardcore, debugSeed);
  app.changes = [];
  app.lastTick = Date.now();
  refresh();
  app.screen = app.engine.state.ending ? 'ending' : 'game';
  writeAutosave();
  render();
}

async function continueGame() {
  const saved = await app.store.loadSlot(0);
  if (!saved) {
    delete app.slots[0];
    toast('没有找到自动存档', '可能已经在别处被删除了。', true);
    return render();
  }
  enterSaved(saved);
}

function enterSaved(saved) {
  app.engine.restore(saved);
  app.changes = [];
  app.lastTick = Date.now();
  refresh();
  app.screen = saved.ending ? 'ending' : 'game';
  app.showDoc = false;
  render();
}

function choose(choice) {
  if (!choice?.enabled) return;
  const before = { ...app.engine.state.vars };
  tick();
  app.engine.choose(choice);
  showDeltas(before);
  refresh();
  if (app.engine.state.ending) {
    reachedEnding();
  } else {
    writeAutosave();
  }
  render();
}

function rewind() {
  if (!app.engine.canRewind) return;
  app.engine.rewind();
  app.changes = [];
  refresh();
  app.screen = 'game';
  writeAutosave();
  render();
}

function saveTo(slot) {
  if (isHardcore()) return;
  tick();
  writeSlot(slot, app.engine.state);
  saveProgress();
  toast('已存档', `存档位 ${slot} · ${app.engine.state.date}`);
}

async function loadFrom(slot) {
  const saved = await app.store.loadSlot(slot);
  closeModal();
  if (!saved) {
    delete app.slots[slot];
    saveProgress();
    toast('这个存档位是空的', '可能已经在别处被删除了。', true);
    return render();
  }
  enterSaved(saved);
}

function backToTitle() {
  if (app.screen === 'game') {
    tick();
    writeAutosave();
  }
  app.screen = 'title';
  app.drawer = false;
  render();
}

function openArchive(tab = 0, doc = null) {
  if (app.screen !== 'archive') app.archiveBack = app.screen;
  app.archiveTab = tab;
  app.archiveDoc = doc;
  app.screen = 'archive';
  app.drawer = false;
  render();
}

function closeArchive() {
  app.screen = app.archiveBack === 'archive' ? 'title' : app.archiveBack;
  render();
}

function markSeenEnding(id) {
  const list = meta().unseenEndings;
  if (!list.includes(id)) return false;
  meta().unseenEndings = list.filter(x => x !== id);
  saveProgress();
  return true;
}

function markSeenDoc(id) {
  const list = meta().unseenDocs;
  if (!list.includes(id)) return false;
  meta().unseenDocs = list.filter(x => x !== id);
  saveProgress();
  return true;
}

async function resetEverything() {
  closeModal();
  await app.store.wipe();
  app.engine.meta = newMeta();
  app.slots = {};
  app.passage = null;
  app.screen = 'title';
  render();
  toast('已清空', '所有存档、结局和档案都清空了。');
}

function reachedEnding() {
  // 铁人模式一局一命：结局后删掉自动存档。标准模式把自动存档留在最后一个抉择之前。
  const e = app.engine;
  if (e.state.hardcore) {
    app.store.deleteSlot(0);
    delete app.slots[0];
  } else {
    const ended = e.cloneState();
    e.rewind();
    writeSlot(0, e.state);
    e.restore(ended);
  }
  saveProgress();
  app.screen = 'ending';
  app.showDoc = false;
}

function refresh() {
  const e = app.engine;
  const fresh = e.freshDocs;
  const endingDoc = e.state.ending ? app.story.ending(e.state.ending)?.doc : null;
  app.passage = e.passage();
  app.passageVersion++;
  for (const id of fresh) {
    if (id === endingDoc) continue;
    const doc = app.story.doc(id);
    if (doc) toast('档案已解密', `《${doc.title}》`);
  }
}

function tick() {
  const now = Date.now();
  app.engine.state.playSeconds += Math.min(600, (now - app.lastTick) / 1000);
  app.lastTick = now;
}

// ---- 数值变化：军人证上的 +/-，以及正文开头的一排小标签 ----

const RISING_IS_BAD = new Set(['trauma', 'susp', 'wounded']);

function showDeltas(before) {
  const s = app.story, e = app.engine;
  const keys = [...s.stats, ...s.units, ...s.persons, ...s.items].map(x => x.key).concat(['rank', 'post']);
  const old = k => before[k] ?? s.initial[k] ?? 0;
  const changed = {};
  for (const k of keys) {
    const d = e.lookup(k) - old(k);
    if (d !== 0) changed[k] = d;
  }
  app.deltas = changed;
  clearTimeout(deltaTimer);
  deltaTimer = setTimeout(() => { app.deltas = {}; updateSidebar(); }, 6000);

  // 标签：军衔 → 部队 → 人物 → 个人 → 物品，和军人证的顺序一致
  const chips = [];
  const tone = (k, d) => ((d > 0) !== RISING_IS_BAD.has(k) ? 'good' : 'bad');
  for (const k of ['rank', 'post']) {
    const d = changed[k];
    if (!d) continue;
    const now = s.label(k, e.lookup(k));
    chips.push({ tone: k === 'rank' ? (d > 0 ? 'good' : 'bad') : 'neutral', label: k === 'post' ? `职务 ${now}` : d > 0 ? `晋升 ${now}` : `降为 ${now}` });
  }
  for (const u of s.units) {
    const d = changed[u.key];
    if (!d) continue;
    const amount = u.unit === '%' ? `${signed(d)}%` : u.unit ? `${signed(d)} ${u.unit}` : signed(d);
    chips.push({ tone: tone(u.key, d), label: `${u.name} ${amount}` });
  }
  for (const p of s.persons) {
    const died = !old(p.key + '_dead') && e.lookup(p.key + '_dead');
    const met = !old(p.key + '_met') && e.lookup(p.key + '_met');
    if (died) chips.push({ tone: 'bad', label: `${p.name} †` });
    else if (met) chips.push({ tone: 'neutral', label: `结识 ${p.name}` });
    const d = changed[p.key];
    if (d && !died) chips.push({ tone: tone(p.key, d), label: `${p.name} 信任 ${signed(d)}` });
  }
  for (const st of s.stats) {
    const d = changed[st.key];
    if (d) chips.push({ tone: tone(st.key, d), label: `${st.name} ${signed(d)}` });
  }
  for (const it of s.items) {
    const d = changed[it.key];
    if (d) chips.push({ tone: 'neutral', label: d > 0 ? `获得 ${it.name}` : `失去 ${it.name}` });
  }
  app.changes = chips;
}

// ============================================================
//  提示条
// ============================================================

function toast(title, detail, warn = false) {
  const el = document.createElement('div');
  el.className = 'toast paper' + (warn ? ' warn' : '');
  el.innerHTML = `<span class="toast-ico">${icons.docSearch}</span>
    <div><div class="toast-title">${esc(title)}</div><div class="toast-detail">${esc(detail)}</div></div>`;
  toastEl.append(el);
  setTimeout(() => {
    el.classList.add('out');
    setTimeout(() => el.remove(), 400);
  }, 4500);
}

// ============================================================
//  渲染
// ============================================================

function applyPrefs() {
  const root = document.documentElement;
  root.dataset.theme = prefs.theme === 1 ? 'paper' : 'night';
  root.style.setProperty('--fs', `${prefs.fontSize}px`);
  document.querySelector('meta[name="theme-color"]')?.setAttribute('content', prefs.theme === 1 ? '#E8DFCA' : '#121110');
}

function setAtmosphere() {
  const p = app.passage;
  const mood = { title: 'snow', archive: 'archive', game: p?.mood, ending: p?.mood }[app.screen] ?? '';
  const dark = prefs.theme !== 1;
  atmo.set({ mood: mood ?? '', dark, motion: prefs.motion, dim: app.screen === 'ending' && dark ? 0.55 : 1 });
}

let renderedScreen = '';
function render() {
  if (app.screen !== 'game') cancelReveal();
  setAtmosphere();
  const fresh = renderedScreen !== app.screen;
  renderedScreen = app.screen;
  screenEl.className = 'screen screen-' + app.screen + (fresh ? ' fade-in' : '');
  switch (app.screen) {
    case 'title': screenEl.innerHTML = titleHTML(); break;
    case 'game': renderGame(); break;
    case 'ending': screenEl.innerHTML = endingHTML(); afterEnding(); break;
    case 'archive': screenEl.innerHTML = archiveHTML(); afterArchive(); break;
    default: break;
  }
  if (app.modal) renderModal();
}

// ---- 标题 ----

function titleHTML() {
  const auto = app.slots[0];
  const runs = meta().runsStarted;
  const note = storageNote();
  const s = app.story;
  const item = (act, title, detail, badge = false) => `
    <button class="title-item" data-act="${act}">
      <span class="title-item-name">${esc(title)}</span>
      ${badge ? '<i class="badge-dot"></i>' : ''}
      ${detail ? `<span class="title-item-detail">${esc(detail)}</span>` : ''}
    </button>`;
  return `
  <div class="title-bg-num" aria-hidden="true">1418</div>
  <div class="title-inner">
    <div class="title-kicker">ВОСТОЧНЫЙ ФРОНТ · 22.06.1941 — 09.05.1945</div>
    <h1 class="title-name">一千四百一十八天</h1>
    <div class="title-sub"><span class="title-bar"></span><span>东 线 档 案</span></div>
    <p class="title-blurb">从布格河到施普雷河，一个红军排长的战争，<br>和一枚写错了名字的纪念章。</p>
    <nav class="title-menu">
      ${auto ? item('continue', '继续', joinDot([auto.chapter, auto.date])) : ''}
      ${item('newGameSheet', '新的卷宗', runs === 0 ? '1941年6月21日，星期六' : `第 ${runs + 1} 次复原`)}
      ${item('loadSheet', '读取存档', null)}
      ${item('archive', '档案馆', `结局 ${endingCount()}/${s.endings.length} · 档案 ${docCount()}/${s.docs.length}`, unseenCount() > 0)}
      ${item('settings', '设置', null)}
    </nav>
    <div class="title-store${note.warn ? ' warn' : ''}">${note.cloud ? icons.cloud : ''}<span>${esc(note.text)}</span></div>
  </div>
  <footer class="title-foot">
    <span>本作部队番号、人物与村庄均为虚构；历史背景、制度与时间线参照真实事件。</span>
    <span class="spacer"></span>
    ${s.issues.length ? `<span class="accent">剧本有 ${s.issues.length} 处问题</span>` : ''}
    <span class="tw">v1.0 · web</span>
  </footer>`;
}

// ---- 游戏 ----

const rv = { timer: 0, revealed: 0, typing: null, done: false, version: -1 };

function cancelReveal() {
  clearTimeout(rv.timer);
  rv.typing = null;
}

function renderGame() {
  const p = app.passage;
  if (!p) return;
  const keepScroll = rv.version === app.passageVersion && $('.story-scroll');
  const scrollTop = keepScroll ? $('.story-scroll').scrollTop : 0;
  screenEl.innerHTML = `
  <div class="game ${sidebarInline() ? 'sb-inline' : ''} ${app.drawer ? 'drawer-open' : ''}">
    <div class="game-main">
      ${topBarHTML(p)}
      <div class="story-scroll" data-act="revealAll">
        <article class="story">
          ${p.lastChoice ? `<div class="last-choice"><span class="accent">▸</span><em>${esc(p.lastChoice)}</em></div>` : ''}
          ${app.changes.length ? `<div class="chips">${app.changes.map(c => `<span class="chip ${c.tone}">${esc(c.label)}</span>`).join('')}</div>` : ''}
          <div class="paras"></div>
          <div class="choices"></div>
          <div class="story-end"></div>
        </article>
      </div>
    </div>
    <div class="drawer-scrim" data-act="closeDrawer"></div>
    <aside class="sidebar" aria-label="军人证">${sidebarHTML()}</aside>
  </div>`;
  if (rv.version === app.passageVersion) {
    // 同一屏重画（切换侧栏等）：直接全部显示，不重放动画
    showAllParas(false);
    $('.story-scroll').scrollTop = scrollTop;
  } else {
    rv.version = app.passageVersion;
    startReveal();
  }
}

function topBarHTML(p) {
  const btn = (act, icon, tip, { enabled = true, badge = false, label = '' } = {}) =>
    `<button class="bar-btn" data-act="${act}" title="${esc(tip)}" aria-label="${esc(tip)}" ${enabled ? '' : 'disabled'}>${icon}${badge ? '<i class="badge-dot small"></i>' : ''}${label}</button>`;
  return `
  <header class="topbar">
    <div class="topbar-where">
      <div class="topbar-chapter">${esc(p.chapter)}</div>
      <div class="topbar-date">${esc(joinDot([p.date, p.place], '  ·  '))}</div>
    </div>
    <div class="topbar-btns">
      ${isHardcore() ? '<span class="hardcore-tag">铁人</span>' : ''}
      ${btn('rewind', icons.rewind, '回溯到上一个抉择（Z）', { enabled: canRewind() })}
      ${btn('log', icons.log, '战斗日志（L）')}
      ${btn('archive', icons.archive, '档案馆（A）', { badge: unseenCount() > 0 })}
      ${btn('saveSheet', icons.save, '存档（S）', { enabled: !isHardcore() })}
      ${btn('loadSheet', icons.folder, '读档（O）')}
      ${btn('toggleSidebar', icons.sidebar, '军人证（M）')}
      ${btn('title', icons.house, '返回标题')}
    </div>
  </header>`;
}

function paraHTML(para, typed = null) {
  if (para.style === 'rule') return `<div class="para rule"><span></span><i>✦</i><span></span></div>`;
  const text = typed !== null ? esc(typed) : para.style === 'quote' ? esc(para.text) : inline(para.text);
  return `<div class="para ${para.style}">${text}</div>`;
}

function appendPara(para, animate, typed = null) {
  const box = $('.paras');
  box.insertAdjacentHTML('beforeend', paraHTML(para, typed));
  const el = box.lastElementChild;
  if (animate) el.classList.add('enter');
  return el;
}

function startReveal() {
  cancelReveal();
  rv.revealed = 0;
  rv.done = false;
  const p = app.passage;
  $('.story-scroll').scrollTop = 0;
  if (prefs.textMode === 2 || !p.paras.length) return showAllParas(false);
  nextPara();
}

function nextPara() {
  const p = app.passage;
  if (rv.revealed >= p.paras.length) return finishReveal(true);
  const para = p.paras[rv.revealed++];
  if (prefs.textMode === 1) {
    const plain = para.style === 'rule' ? [] : Array.from(para.text.replace(/\*/g, ''));
    const el = appendPara(para, true, para.style === 'rule' ? null : '');
    rv.typing = { el, para, chars: plain, n: 0, ticks: 0 };
    scrollToLatest(el);
    typeTick();
  } else {
    const el = appendPara(para, true);
    scrollToLatest(el);
    const delay = Math.min(1.25, 0.3 + Array.from(para.text).length / 160) * 1000;
    rv.timer = setTimeout(nextPara, delay);
  }
}

function typeTick() {
  const t = rv.typing;
  if (!t) return;
  if (t.n >= t.chars.length) {
    finishTyping();
    rv.timer = setTimeout(nextPara, 160);
    return;
  }
  t.el.textContent = t.chars.slice(0, t.n).join('');
  if (++t.ticks % 12 === 0) scrollToLatest(t.el);
  t.n += 2;
  rv.timer = setTimeout(typeTick, 24);
}

function finishTyping() {
  const t = rv.typing;
  if (!t) return;
  rv.typing = null;
  t.el.outerHTML = paraHTML(t.para);
}

function showAllParas(animate) {
  cancelReveal();
  finishTyping();
  const p = app.passage;
  const box = $('.paras');
  if (!rv.revealed || !animate) {
    box.innerHTML = p.paras.map(x => paraHTML(x)).join('');
  } else {
    for (const para of p.paras.slice(rv.revealed)) appendPara(para, true);
  }
  rv.revealed = p.paras.length;
  finishReveal(false);
}

function finishReveal(scroll) {
  cancelReveal();
  rv.done = true;
  const p = app.passage;
  const box = $('.choices');
  if (!box || box.childElementCount) return;
  box.innerHTML = p.choices.map((c, i) => choiceHTML(c, i + 1)).join('') + (p.broken ? `
    <p class="broken">（这里的剧本还没写完——你可以回溯，或回到标题。）</p>
    <button class="btn" data-act="title">回到标题</button>` : '');
  box.classList.add('enter');
  if (scroll && box.firstElementChild) scrollToLatest(box.firstElementChild);
}

function scrollToLatest(el) {
  const sc = $('.story-scroll');
  if (!sc || rv.revealed <= 1) return;
  const bottom = el.offsetTop + el.offsetHeight + 40;
  const target = bottom - sc.clientHeight;
  if (target > sc.scrollTop) sc.scrollTo({ top: target, behavior: 'smooth' });
}

function choiceHTML(c, number) {
  const archive = c.tags.includes('档案');
  const tags = c.tags.length ? `<span class="choice-tags">${c.tags.map(t => `<span class="tag ${t === '档案' ? 'archive' : ''}">${t === '档案' ? icons.seal : ''}${esc(t)}</span>`).join('')}</span>` : '';
  return `
  <button class="choice ${archive ? 'is-archive' : ''}" data-act="choose" data-arg="${c.id}" ${c.enabled ? '' : 'disabled'}>
    <span class="choice-no">${number}</span>
    <span class="choice-body">${tags}<span class="choice-text">${esc(c.text)}</span></span>
    ${c.enabled ? '' : `<span class="choice-lock">${icons.lock}</span>`}
  </button>`;
}

// ---- 军人证 ----

function sidebarHTML() {
  const e = app.engine, s = app.story, d = app.deltas;
  const delta = k => {
    const v = d[k];
    return v ? `<span class="delta ${v > 0 ? 'up' : 'down'}">${v > 0 ? '+' : ''}${v}</span>` : '';
  };
  const meter = (name, key, value, max, text, tint, help) => `
    <div class="row meter" title="${esc(help)}">
      <div class="row-line"><span class="row-name">${esc(name)}</span><span class="spacer"></span>${delta(key)}<span class="row-val">${esc(text)}</span></div>
      <div class="bar"><i class="${tint}" style="width:${(Math.max(0, Math.min(value, max)) / Math.max(1, max)) * 100}%"></i></div>
    </div>`;
  const section = (title, body) => `<section class="sb-sec"><h3><span>${title}</span><i></i></h3>${body}</section>`;

  const units = s.units.map(u => {
    const v = e.lookup(u.key);
    if (u.max === 100) return meter(u.name, u.key, v, 100, `${v}${u.unit}`, v < 30 ? 'accent' : 'khaki', u.desc);
    return `<div class="row value" title="${esc(u.desc)}"><span class="row-name">${esc(u.name)}</span><span class="spacer"></span>${delta(u.key)}<span class="row-val ${u.key === 'men' ? 'big' : ''}">${v} ${esc(u.unit)}</span></div>`;
  }).join('');

  const stats = s.stats.map(st => {
    const v = e.lookup(st.key);
    if (st.max <= 10) {
      const pips = Array.from({ length: st.max }, (_, i) => `<i class="${i < v ? 'on' : ''}"></i>`).join('');
      return `<div class="row pips" title="${esc(st.desc)}"><span class="row-name">${esc(st.name)}</span><span class="spacer"></span>${delta(st.key)}<span class="pip-row">${pips}</span><span class="pip-val">${v}</span></div>`;
    }
    const bad = st.key === 'trauma' || st.key === 'susp';
    return meter(st.name, st.key, v, st.max, String(v), bad ? 'accent' : 'khaki', st.desc);
  }).join('');

  const trustWord = t => (t < 20 ? '敌视' : t < 40 ? '疏远' : t < 60 ? '一般' : t < 80 ? '信任' : '生死之交');
  const people = s.persons.filter(p => e.lookup(p.key + '_met') !== 0).map(p => {
    const trust = e.lookup(p.key), dead = e.lookup(p.key + '_dead') !== 0, away = e.lookup(p.key + '_away') !== 0;
    return `<div class="row person ${dead ? 'dead' : ''}" title="${esc(p.desc)}">
      <div class="row-line"><span class="person-name">${esc(p.name)}</span>${dead ? '<span class="dagger">†</span>' : away ? '<span class="away">不在身边</span>' : ''}
        <span class="spacer"></span>${dead ? '' : `${delta(p.key)}<span class="trust">${trustWord(trust)}</span>`}</div>
      ${dead ? '' : `<div class="bar thin"><i class="dim" style="width:${trust}%"></i></div>`}
    </div>`;
  }).join('');

  const items = s.items.filter(it => e.lookup(it.key) > 0).map(it => {
    const n = e.lookup(it.key);
    return `<div class="row item" title="${esc(it.desc)}"><span class="khaki">·</span><span>${esc(it.name)}${n > 1 ? ` ×${n}` : ''}</span>${d[it.key] ? '<span class="new">新</span>' : ''}</div>`;
  }).join('');

  const parts = s.hero.split('·');
  const surname = parts[parts.length - 1] || s.hero;
  const given = parts.slice(0, -1).join('·');
  return `
  <div class="sb-head"><span>军人证</span><button class="bar-btn" data-act="closeDrawer" aria-label="收起">${icons.close}</button></div>
  <div class="id-card paper">
    <div class="id-top"><span class="tw">КРАСНОАРМЕЙСКАЯ КНИЖКА</span><span class="spacer"></span><span class="tw stamp-ink">№ 1418</span></div>
    <div class="id-surname">${esc(surname)}</div>
    <div class="id-given">${esc(given)}</div>
    <div class="id-rank"><b>${esc(s.label('rank', e.lookup('rank')))}</b><span class="faint">·</span><span>${esc(s.label('post', e.lookup('post')))}</span>${d.rank || d.post ? '<span class="new stamp-ink">变动</span>' : ''}</div>
  </div>
  ${section('部队', units)}
  ${section('个人', stats)}
  ${people ? section('人物', people) : ''}
  ${items ? section('随身物品', items) : ''}`;
}

function updateSidebar() {
  const sb = $('.sidebar');
  if (sb) sb.innerHTML = sidebarHTML();
}

// ---- 结局 ----

function docCardHTML(doc) {
  const paras = doc.paras.map(p => (p.style === 'rule'
    ? '<hr class="doc-rule">'
    : `<p class="doc-para ${p.style === 'quote' ? 'quote' : ''}">${esc(p.text)}</p>`)).join('');
  return `
  <article class="doc-card paper">
    <div class="doc-head">
      <span class="doc-kind">${esc(doc.kind)}</span>
      ${doc.isKey ? '<span class="key-tag">关键档案</span>' : ''}
      <span class="spacer"></span>
      <span class="tw doc-no">№ ${esc(doc.id.toUpperCase())}</span>
    </div>
    <h2 class="doc-title">${esc(doc.title)}</h2>
    ${doc.who ? `<div class="doc-who">${esc(doc.who)}</div>` : ''}
    ${doc.source ? `<div class="doc-source">${esc(doc.source)}</div>` : ''}
    <hr class="doc-sep">
    ${paras}
    ${doc.date ? `<div class="doc-date">${esc(doc.date)}</div>` : ''}
    <div class="stamp declass">РАССЕКРЕЧЕНО</div>
  </article>`;
}

const TIER_NAMES = { TE: '真结局', GE: '好结局', NE: '普通结局', SE: '特殊结局', BE: '坏结局' };
const tierName = t => TIER_NAMES[t] ?? '坏结局';
const tierClass = t => 'tier-' + (TIER_NAMES[t] ? t : 'BE');

function endingHTML() {
  const p = app.passage, ending = p?.ending;
  if (!ending) return '';
  const doc = ending.doc ? app.story.doc(ending.doc) : null;
  const s = app.story;
  return `
  <div class="ending-scroll">
    <div class="ending ${tierClass(ending.tier)}">
      <header class="ending-head">
        <div class="ending-tier tw">${esc(ending.tier)} · ${tierName(ending.tier)}</div>
        <h1 class="ending-title">${esc(ending.title)}</h1>
        <div class="ending-bar"></div>
        <div class="ending-date">${esc(joinDot([p.date, p.place], '  ·  '))}</div>
      </header>
      <div class="ending-body">${p.paras.map(x => paraHTML(x)).join('')}</div>
      ${doc ? `<div class="ending-doc">${app.showDoc
        ? `<p class="ending-doc-intro">这不是一个人的结局。档案里写着它真正属于谁。</p>${docCardHTML(doc)}`
        : `<button class="decrypt" data-act="showDoc">${icons.sealOutline}<span>解密档案 № ${esc(doc.id.toUpperCase())}</span></button>`}</div>` : ''}
      <footer class="ending-foot">
        <div class="faint small">结局 ${endingCount()} / ${s.endings.length}  ·  档案 ${docCount()} / ${s.docs.length}</div>
        <div class="ending-btns">
          ${canRewind() ? `<button class="btn" data-act="rewind">${icons.rewind}<span>回到上一个抉择</span></button>` : ''}
          <button class="btn" data-act="archive">${icons.archive}<span>档案馆</span></button>
          <button class="btn" data-act="newGameSheet">${icons.docPlus}<span>新的卷宗</span></button>
          <button class="btn" data-act="title">${icons.house}<span>返回标题</span></button>
        </div>
      </footer>
    </div>
  </div>`;
}

function afterEnding() {
  const ending = app.passage?.ending;
  if (!ending) return;
  markSeenEnding(ending.id);
  if (app.showDoc && ending.doc) markSeenDoc(ending.doc);
}

// ---- 档案馆 ----

const ACTS = [
  [1, '第一卷 · 包围圈 · 1941'],
  [2, '第二卷 · 伏尔加 · 1942—1943'],
  [3, '第三卷 · 大河 · 1943—1944'],
  [4, '第四卷 · 柏林 · 1945'],
  [5, '尾声 · 1946 年以后'],
  [0, '卷宗之外'],
];

function archiveHTML() {
  const s = app.story, m = meta();
  const keyDocs = s.docs.filter(d => d.isKey);
  const keyFound = keyDocs.filter(d => m.docs[d.id] !== undefined).length;
  const percent = s.docs.length ? Math.floor(docCount() * 100 / s.docs.length) : 0;
  return `
  <div class="archive">
    <header class="archive-head">
      <button class="back" data-act="closeArchive">${icons.chevronLeft}<span>返回</span></button>
      <h1>档案馆</h1>
      <div class="seg" role="tablist">
        <button role="tab" class="${app.archiveTab === 0 ? 'on' : ''}" data-act="archiveTab" data-arg="0">结局图鉴 ${endingCount()}/${s.endings.length}</button>
        <button role="tab" class="${app.archiveTab === 1 ? 'on' : ''}" data-act="archiveTab" data-arg="1">解密档案 ${docCount()}/${s.docs.length}</button>
      </div>
      <span class="spacer"></span>
      <div class="archive-progress">
        <div>真相复原 ${percent}%</div>
        <div class="${keyFound === keyDocs.length ? 'gold' : 'faint'}">关键档案 ${keyFound}/${keyDocs.length}</div>
      </div>
    </header>
    <div class="archive-body">${app.archiveTab === 0 ? galleryHTML() : docBrowserHTML()}</div>
  </div>`;
}

function galleryHTML() {
  const s = app.story, m = meta();
  const showHint = prefs.hints || m.runsFinished > 0;
  return `<div class="gallery">${ACTS.map(([act, title]) => {
    const list = s.endings.filter(e => e.act === act);
    if (!list.length) return '';
    return `<section class="gallery-sec"><h2><span>${title}</span><i></i></h2><div class="gallery-grid">${list.map(e => {
      const date = m.endings[e.id], unlocked = date !== undefined, isNew = m.unseenEndings.includes(e.id);
      return `<button class="ending-card ${tierClass(e.tier)} ${unlocked ? 'unlocked' : ''}" data-act="endingCard" data-arg="${esc(e.id)}" ${unlocked ? '' : 'aria-disabled="true"'}>
        <div class="ec-top"><span class="ec-tier tw">${esc(e.tier)}</span><span class="faint">${tierName(e.tier)}</span><span class="spacer"></span>${isNew ? '<span class="new">新</span>' : ''}<span class="tw faint">${esc(e.id.toUpperCase())}</span></div>
        <div class="ec-title">${unlocked ? esc(e.title) : '？？？'}</div>
        ${unlocked ? `<div class="ec-date">首次抵达 ${esc(fmtDay(date))}</div>` : showHint ? `<div class="ec-hint">${esc(e.hint)}</div>` : ''}
      </button>`;
    }).join('')}</div></section>`;
  }).join('')}</div>`;
}

function docBrowserHTML() {
  const s = app.story, m = meta();
  const sel = app.archiveDoc ? s.doc(app.archiveDoc) : null;
  const rows = s.docs.map(d => {
    const unlocked = m.docs[d.id] !== undefined, isNew = m.unseenDocs.includes(d.id);
    const bars = '█'.repeat(Math.max(4, Math.min(12, Array.from(d.title).length)));
    return `<button class="doc-row ${app.archiveDoc === d.id ? 'on' : ''}" data-act="pickDoc" data-arg="${esc(d.id)}">
      <span class="tw doc-row-id">${esc(d.id.toUpperCase())}</span>
      ${unlocked ? `<span class="doc-row-title">${esc(d.title)}</span>` : `<span class="doc-row-bars">${bars}</span>`}
      <span class="spacer"></span>
      ${d.isKey ? `<span class="${unlocked ? 'gold' : 'faint'}">${icons.star}</span>` : ''}
      ${isNew ? '<i class="badge-dot small"></i>' : ''}
    </button>`;
  }).join('');
  let detail;
  if (sel) {
    if (m.docs[sel.id] !== undefined) {
      detail = docCardHTML(sel);
    } else {
      const source = s.endings.find(e => e.doc === sel.id);
      const widths = [380, 440, 300, 420, 360, 250, 400];
      detail = `<article class="doc-card paper locked">
        <div class="tw doc-no">№ ${esc(sel.id.toUpperCase())}</div>
        ${widths.map(w => `<div class="redact" style="width:min(${w}px, 100%)"></div>`).join('')}
        <p class="locked-note">${source
          ? `某一次复原走到结局「${esc(m.endings[source.id] !== undefined ? source.title : '？？？')}」时，这份档案会解密。`
          : '这份档案藏在某一次复原的路上。'}</p>
        <div class="stamp secret">СЕКРЕТНО</div>
      </article>`;
    }
    detail = `<button class="back doc-back" data-act="pickDoc" data-arg="">${icons.chevronLeft}<span>档案列表</span></button>${detail}`;
  } else {
    detail = `<div class="doc-empty">${icons.archive}<p>从左边选一份档案</p><p class="small">每一个结局，都是某个人真实的结局。</p></div>`;
  }
  return `<div class="doc-browser ${sel ? 'has-sel' : ''}">
    <div class="doc-list">${rows}</div>
    <div class="doc-detail">${detail}</div>
  </div>`;
}

function afterArchive() {
  if (app.archiveTab === 1 && app.archiveDoc && meta().docs[app.archiveDoc] !== undefined) markSeenDoc(app.archiveDoc);
}

// ============================================================
//  对话框
// ============================================================

function openModal(kind, extra = {}) {
  app.modal = { kind, ...extra };
  app.drawer = false;
  $('.game')?.classList.remove('drawer-open');
  renderModal();
}

function closeModal() {
  app.modal = null;
  modalEl.innerHTML = '';
  modalEl.hidden = true;
}

function renderModal() {
  const m = app.modal;
  if (!m) return closeModal();
  const body = {
    newGame: newGameHTML, save: () => slotsHTML(true), load: () => slotsHTML(false),
    log: logHTML, settings: settingsHTML,
  }[m.kind]?.() ?? '';
  const confirm = m.confirm ? `
    <div class="confirm-scrim">
      <div class="confirm" role="alertdialog" aria-label="${esc(m.confirm.message)}">
        <p>${esc(m.confirm.message)}</p>
        <div class="sheet-actions"><span class="spacer"></span>
          <button class="btn" data-act="confirmNo">取消</button>
          <button class="btn danger" data-act="confirmYes">${esc(m.confirm.label)}</button>
        </div>
      </div>
    </div>` : '';
  modalEl.hidden = false;
  modalEl.innerHTML = `<div class="modal-scrim" data-act="closeModal"></div>
    <div class="sheet sheet-${m.kind}" role="dialog" aria-modal="true">${body}${confirm}</div>`;
  const focus = modalEl.querySelector(m.confirm ? '.confirm .danger' : '[data-autofocus]') ?? modalEl.querySelector('button');
  focus?.focus({ preventScroll: true });
  if (m.kind === 'log' && !m.scrolled) {
    m.scrolled = true;
    const list = modalEl.querySelector('.log-list');
    if (list) list.scrollTop = list.scrollHeight;
  }
}

function sheetHead(title, extra = '', closeLabel = '关闭') {
  return `<div class="sheet-head"><h2>${title}</h2>${extra}<span class="spacer"></span><button class="btn" data-act="closeModal">${closeLabel}</button></div>`;
}

function newGameHTML() {
  const hard = !!app.modal.hardcore;
  const card = (title, lines, on, arg) => `
    <button class="mode-card ${on ? 'on' : ''}" data-act="pickMode" data-arg="${arg}" aria-pressed="${on}">
      <span class="mode-top"><b>${title}</b><span class="spacer"></span><i class="radio"></i></span>
      ${lines.map(l => `<span class="mode-line">· ${l}</span>`).join('')}
    </button>`;
  return `
    <h2 class="sheet-title">新的卷宗</h2>
    <p class="dim">一千四百一十八天，从 1941 年 6 月 21 日的傍晚开始。</p>
    <div class="mode-cards">
      ${card('标准', ['随时存档、读档', '可以回溯到上一个抉择', '适合第一次复原'], !hard, 0)}
      ${card('铁人', ['只有自动存档', '不能回溯，一局一命', '和他们当年一样'], hard, 1)}
    </div>
    <p class="note">随机数跟着存档走：同样的选择永远得到同样的结果，读档刷不出运气。</p>
    ${app.slots[0] ? '<p class="note accent">开始新的卷宗会覆盖当前的自动存档（手动存档不受影响）。</p>' : ''}
    <div class="sheet-actions"><span class="spacer"></span>
      <button class="btn" data-act="closeModal">取消</button>
      <button class="btn primary" data-act="startGame" data-autofocus>开始</button>
    </div>`;
}

function slotsHTML(saving) {
  const cards = [];
  for (let n = 0; n <= SLOT_COUNT; n++) {
    const st = app.slots[n];
    const usable = saving ? n !== 0 : !!st;
    cards.push(`<button class="slot" data-act="${saving ? 'saveSlot' : 'loadSlot'}" data-arg="${n}" ${usable ? '' : 'disabled'}>
      <span class="slot-top"><span>${n === 0 ? '自动存档' : `存档位 ${n}`}</span><span class="spacer"></span>${st?.hardcore ? '<span class="accent">铁人</span>' : ''}</span>
      ${st ? `<span class="slot-chapter">${esc(st.chapter || '序章')}</span>
        <span class="slot-date">${esc(st.date)}</span>
        <span class="spacer-v"></span>
        <span class="slot-foot"><span>${st.savedAt ? esc(fmtStamp(st.savedAt)) : ''}</span><span class="spacer"></span><span>${duration(st.playSeconds ?? 0)}</span></span>`
      : `<span class="spacer-v"></span><span class="slot-empty">${saving && n !== 0 ? '空位 · 点击存档' : '空'}</span><span class="spacer-v"></span>`}
    </button>`);
  }
  const note = storageNote();
  return `${sheetHead(saving ? '存档' : '读档')}
    <div class="slots">${cards.join('')}</div>
    <p class="note ${note.warn ? 'accent' : ''}">${esc(note.text)}</p>`;
}

function logHTML() {
  const st = app.engine.state;
  const entries = st.log.map(e => `
    <div class="log-entry">
      ${e.choice ? `<div class="log-choice">▸ ${esc(e.choice)}</div>` : ''}
      ${e.header ? `<div class="log-header">${esc(e.header)}</div>` : ''}
      <div class="log-text">${esc(e.text.replace(/\*/g, ''))}</div>
    </div>`).join('');
  return `${sheetHead('战斗日志', `<span class="faint small">本局 ${st.log.length} 段 · ${duration(st.playSeconds)}</span>`)}
    <div class="log-list">${entries}</div>`;
}

function settingsHTML() {
  const s = app.story;
  const seg = (key, options) => `<div class="seg">${options.map(([v, label]) =>
    `<button class="${prefs[key] === v ? 'on' : ''}" data-act="pref" data-arg="${key}:${v}">${label}</button>`).join('')}</div>`;
  const toggle = (key, label) => `<label class="toggle"><span>${label}</span><input type="checkbox" data-pref="${key}" ${prefs[key] ? 'checked' : ''}><i></i></label>`;
  return `${sheetHead('设置', '', '完成')}
    <div class="form">
      <div class="form-row"><span>文字出现方式</span>${seg('textMode', [[0, '逐段浮现'], [1, '打字机'], [2, '立即显示']])}</div>
      <div class="form-row"><span>正文字号</span><span class="range"><input type="range" min="15" max="24" step="1" value="${prefs.fontSize}" data-pref="fontSize"><b class="fs-val">${prefs.fontSize}</b></span></div>
      <div class="form-row"><span>配色</span>${seg('theme', [[0, '夜'], [1, '纸']])}</div>
      <div class="form-row">${toggle('motion', '雪、灰烬、雨等动态效果')}</div>
      <div class="form-row">${toggle('hints', '结局图鉴里显示未解锁结局的提示')}</div>
    </div>
    <p class="sample">示例：炮声停了。你数了数，还剩 {men} 个人。</p>
    <div class="settings-foot">
      <div>
        <div class="dim small">进度：结局 ${endingCount()}/${s.endings.length}，档案 ${docCount()}/${s.docs.length}</div>
        <div class="faint small">剧本 ${s.nodeOrder.filter(id => !isRegistry(id)).length} 节 · 约 ${Math.floor(s.characterCount / 1000)} 千字 · ${esc(storageNote().text)}</div>
      </div>
      <span class="spacer"></span>
      <button class="btn danger" data-act="askReset">重置全部进度…</button>
    </div>
    <div class="settings-keys faint small">快捷键：空格/回车 继续 · 1–9 选择 · Z 回溯 · L 日志 · A 档案馆 · S 存档 · O 读档 · M 军人证 · Esc 返回</div>`;
}

function askConfirm(message, label, action) {
  app.modal.confirm = { message, label, action };
  renderModal();
}

// ============================================================
//  事件
// ============================================================

const actions = {
  continue: () => continueGame(),
  newGameSheet: () => openModal('newGame', { hardcore: false }),
  pickMode: arg => { app.modal.hardcore = arg === '1'; renderModal(); },
  startGame: () => { const hard = !!app.modal.hardcore; closeModal(); newGame(hard); },
  loadSheet: () => openModal('load'),
  saveSheet: () => { if (!isHardcore() && app.screen === 'game') openModal('save'); },
  saveSlot: arg => {
    const n = Number(arg);
    if (n === 0) return;
    if (app.slots[n]) askConfirm('覆盖这个存档位？', '覆盖', () => { saveTo(n); renderModal(); });
    else { saveTo(n); renderModal(); }
  },
  loadSlot: arg => loadFrom(Number(arg)),
  archive: () => openArchive(),
  closeArchive: () => closeArchive(),
  archiveTab: arg => { app.archiveTab = Number(arg); render(); },
  pickDoc: arg => { app.archiveDoc = arg || null; render(); $('.doc-detail')?.scrollTo(0, 0); },
  endingCard: arg => {
    const e = app.story.ending(arg);
    if (!e || meta().endings[e.id] === undefined) return;
    markSeenEnding(e.id);
    if (e.doc) openArchive(1, e.doc);
    else render();
  },
  settings: () => openModal('settings'),
  log: () => { if (app.passage) openModal('log'); },
  closeModal: () => closeModal(),
  confirmNo: () => { app.modal.confirm = null; renderModal(); },
  confirmYes: () => { const a = app.modal.confirm.action; app.modal.confirm = null; a(); },
  askReset: () => askConfirm('清空所有存档、结局和档案？此操作无法撤销。', '全部清空', () => resetEverything()),
  pref: arg => {
    const [key, v] = arg.split(':');
    prefs[key] = Number(v);
    savePrefs();
    applyPrefs();
    renderModal();
    if (key === 'theme') render();
  },
  choose: arg => {
    if (!rv.done) return;
    const c = app.passage?.choices.find(x => String(x.id) === arg);
    choose(c);
  },
  revealAll: () => { if (!rv.done) showAllParas(true); },
  rewind: () => rewind(),
  title: () => backToTitle(),
  toggleSidebar: () => {
    if (wideLayout.matches) {
      prefs.sidebar = !prefs.sidebar;
      savePrefs();
      $('.game')?.classList.toggle('sb-inline', sidebarInline());
    } else {
      app.drawer = !app.drawer;
      $('.game')?.classList.toggle('drawer-open', app.drawer);
    }
  },
  closeDrawer: () => { app.drawer = false; $('.game')?.classList.remove('drawer-open'); },
  showDoc: () => {
    app.showDoc = true;
    const scroll = $('.ending-scroll')?.scrollTop ?? 0;
    render();
    const sc = $('.ending-scroll');
    if (sc) {
      sc.scrollTop = scroll;
      const card = $('.ending-doc');
      setTimeout(() => sc.scrollTo({ top: card.offsetTop - 40, behavior: 'smooth' }), 250);
    }
  },
  reload: () => location.reload(),
};

document.addEventListener('click', ev => {
  const el = ev.target.closest('[data-act]');
  if (!el || el.disabled || !app.engine) return;
  // 正文区的"点一下显示全部"不能吞掉按钮点击
  if (el.dataset.act === 'revealAll' && ev.target.closest('button')) return;
  const fn = actions[el.dataset.act];
  if (fn) fn(el.dataset.arg ?? '');
});

document.addEventListener('input', ev => {
  const key = ev.target.dataset?.pref;
  if (!key) return;
  if (ev.target.type === 'checkbox') prefs[key] = ev.target.checked;
  else prefs[key] = Number(ev.target.value);
  savePrefs();
  applyPrefs();
  if (key === 'fontSize') { const v = modalEl.querySelector('.fs-val'); if (v) v.textContent = prefs.fontSize; }
  if (key === 'motion') setAtmosphere();
});

document.addEventListener('keydown', ev => {
  if (!app.engine || ev.metaKey || ev.ctrlKey || ev.altKey) return;
  if (ev.key === 'Escape') {
    if (app.modal?.confirm) { app.modal.confirm = null; renderModal(); }
    else if (app.modal) closeModal();
    else if (app.drawer) actions.closeDrawer();
    else if (app.screen === 'archive') closeArchive();
    return;
  }
  if (app.modal) return;
  const onButton = document.activeElement?.tagName === 'BUTTON';
  const k = ev.key.toLowerCase();
  if (app.screen === 'game') {
    const p = app.passage;
    if ((ev.key === ' ' || ev.key === 'Enter') && !onButton) {
      ev.preventDefault();
      if (!rv.done) showAllParas(true);
      else if (p.choices.length === 1 && p.choices[0].enabled) choose(p.choices[0]);
      return;
    }
    if (/^[1-9]$/.test(ev.key) && Number(ev.key) <= p.choices.length) {
      ev.preventDefault();
      if (!rv.done) return showAllParas(true);
      const c = p.choices[Number(ev.key) - 1];
      if (c.enabled) choose(c);
      return;
    }
    if (k === 's') return actions.saveSheet();
    if (k === 'm') return actions.toggleSidebar();
  }
  if (k === 'z' && canRewind()) return rewind();
  if (k === 'l' && (app.screen === 'game' || app.screen === 'ending')) return actions.log();
  if (k === 'a' && app.screen !== 'archive') return openArchive();
  if (k === 'o') return openModal('load');
});

wideLayout.addEventListener('change', () => {
  app.drawer = false;
  const g = $('.game');
  if (g) { g.classList.toggle('sb-inline', sidebarInline()); g.classList.remove('drawer-open'); }
});

// 关页面、切到后台时把游戏时长和进度补存一次
function persistOnLeave() {
  if (!app.engine) return;
  if (app.screen === 'game') {
    tick();
    writeAutosave();
  }
  app.store.flush?.();
}
window.addEventListener('pagehide', persistOnLeave);
document.addEventListener('visibilitychange', () => { if (document.hidden) persistOnLeave(); });

// ============================================================
//  启动
// ============================================================

async function loadStoryBundle() {
  const res = await fetch('story.json', { cache: 'no-cache' });
  if (!res.ok) throw new Error(`剧本读取失败（HTTP ${res.status}）`);
  return loadStory(await res.json());
}

async function boot() {
  applyPrefs();
  atmo = new Atmosphere($('#atmo'));
  atmo.set({ mood: 'snow', dark: prefs.theme !== 1, motion: prefs.motion });
  try {
    const [story, opened] = await Promise.all([loadStoryBundle(), openStore({ onError: reportStoreError })]);
    app.story = story;
    app.store = opened.store;
    app.hub = opened.hub;
    app.storeError = opened.error ?? null;
    for (const issue of story.issues.slice(0, 20)) console.warn('剧本问题：', issue);
    let progress = null;
    try { progress = await app.store.loadProgress(); } catch (err) { reportStoreError(err); }
    app.slots = progress?.slots ?? {};
    app.engine = new Engine(story, progress?.meta ? { ...newMeta(), ...progress.meta } : newMeta());
    if (app.hub) {
      const initial = app.hub.user?.id ?? null;
      app.hub.client.onAuthChange(user => { if ((user?.id ?? null) !== initial) authChanged(); });
    }
    if (app.storeError) toast('云存档暂时连不上', '这一次的进度只保留在当前页面。', true);
    app.screen = 'title';
    render();
  } catch (err) {
    console.error(err);
    screenEl.className = 'screen screen-error';
    screenEl.innerHTML = `<div class="boot-error"><h1>卷宗打不开</h1><p>${esc(err.message || String(err))}</p><button class="btn" onclick="location.reload()">重新载入</button></div>`;
  }
}

boot();
