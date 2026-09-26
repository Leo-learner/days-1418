// 场景氛围：底色 + 粒子（雪、灰、火星、雨、花瓣……）+ 胶片颗粒 + 暗角
// 粒子是无状态的：每颗粒子的位置只由编号和时间决定。

const MOODS = {
  dusk:    { top: '#2A1F16', bottom: '#121110', glow: '#6B3A1A', particle: 'dust', count: 40 },
  fire:    { top: '#1A100D', bottom: '#100C0A', glow: '#8A2A12', particle: 'ember', count: 70 },
  smoke:   { top: '#1E1C19', bottom: '#121110', glow: null, particle: 'ash', count: 50 },
  forest:  { top: '#121812', bottom: '#0E110E', glow: null, particle: 'dust', count: 36 },
  night:   { top: '#0C0F15', bottom: '#090A0D', glow: null, particle: 'dust', count: 14 },
  river:   { top: '#121A20', bottom: '#0D1114', glow: '#24323A', particle: 'dust', count: 26 },
  snow:    { top: '#16191C', bottom: '#0F1113', glow: null, particle: 'snow', count: 110 },
  ash:     { top: '#1C1816', bottom: '#100E0D', glow: '#3A1E14', particle: 'ash', count: 90 },
  rain:    { top: '#111518', bottom: '#0B0D0F', glow: null, particle: 'rain', count: 90 },
  summer:  { top: '#1C1A12', bottom: '#121110', glow: '#3A3216', particle: 'dust', count: 34 },
  autumn:  { top: '#1C1610', bottom: '#110F0C', glow: null, particle: 'leaf', count: 22 },
  spring:  { top: '#19161B', bottom: '#110F12', glow: null, particle: 'petal', count: 28 },
  archive: { top: '#151A1D', bottom: '#0E1113', glow: null, particle: 'dust', count: 18 },
  dawn:    { top: '#1A1C24', bottom: '#111114', glow: '#2C2A3A', particle: 'none', count: 0 },
};
const DEFAULT_MOOD = { top: '#151412', bottom: '#121110', glow: null, particle: 'none', count: 0 };

export const moodStyle = mood => MOODS[mood] ?? DEFAULT_MOOD;

function hexToRgba(hex, a) {
  const n = Number.parseInt(hex.slice(1), 16);
  return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
}

// mulberry32：给每颗粒子一组固定的随机参数
function rng(seed) {
  let t = seed >>> 0;
  return () => {
    t = (t + 0x6D2B79F5) >>> 0;
    let r = Math.imul(t ^ (t >>> 15), 1 | t);
    r = (r + Math.imul(r ^ (r >>> 7), 61 | r)) ^ r;
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

const wrap = (v, m) => ((v % m) + m) % m;

export class Atmosphere {
  constructor(root) {
    this.root = root;
    this.canvas = root.querySelector('canvas');
    this.ctx = this.canvas.getContext('2d');
    this.mood = '';
    this.dark = true;
    this.motion = true;
    this.dim = 1;
    this.particles = [];
    this.kind = 'none';
    this.raf = 0;
    this.last = 0;
    this.w = 0;
    this.h = 0;
    this.resize = this.resize.bind(this);
    this.frame = this.frame.bind(this);
    new ResizeObserver(this.resize).observe(root);
    document.addEventListener('visibilitychange', () => this.schedule());
    document.documentElement.style.setProperty('--grain', `url(${grainURL()})`);
    this.resize();
  }

  set({ mood, dark, motion, dim = 1 }) {
    const changed = mood !== this.mood || dark !== this.dark;
    this.mood = mood;
    this.dark = dark;
    this.motion = motion;
    this.dim = dim;
    const s = moodStyle(mood);
    const r = this.root.style;
    if (dark) {
      r.setProperty('--atmo-top', s.top);
      r.setProperty('--atmo-bottom', s.bottom);
      r.setProperty('--atmo-glow', s.glow ? hexToRgba(s.glow, 0.55) : 'transparent');
    } else {
      r.setProperty('--atmo-top', hexToRgba(s.top, 0.10));
      r.setProperty('--atmo-bottom', 'transparent');
      r.setProperty('--atmo-glow', 'transparent');
    }
    this.root.style.opacity = String(dim);
    if (changed) {
      this.kind = s.particle;
      const n = s.particle === 'none' ? 0 : s.count;
      this.particles = Array.from({ length: n }, (_, i) => {
        const u = rng((i + 1) * 0x9E3779B9);
        return { x0: u(), y0: u(), speed: 0.5 + u(), phase: u() * 6.283, scale: 0.6 + u() * 1.6 };
      });
    }
    this.schedule();
  }

  resize() {
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const { width, height } = this.root.getBoundingClientRect();
    this.w = width;
    this.h = height;
    this.canvas.width = Math.round(width * dpr);
    this.canvas.height = Math.round(height * dpr);
    this.ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.draw(performance.now() / 1000);
  }

  schedule() {
    const running = this.motion && this.kind !== 'none' && this.particles.length && !document.hidden;
    if (running && !this.raf) this.raf = requestAnimationFrame(this.frame);
    if (!running) {
      if (this.raf) cancelAnimationFrame(this.raf);
      this.raf = 0;
      this.ctx.clearRect(0, 0, this.w, this.h);
    }
  }

  frame(ms) {
    this.raf = 0;
    if (ms - this.last >= 1000 / 30) {
      this.last = ms;
      this.draw(ms / 1000);
    }
    this.schedule();
  }

  draw(t) {
    const { ctx, w: width, h: height } = this;
    ctx.clearRect(0, 0, width, height);
    if (!this.motion || this.kind === 'none') return;
    const w = width + 40, h = height + 40, dark = this.dark;
    for (const p of this.particles) {
      const x0 = p.x0 * width, y0 = p.y0 * height, { speed, phase, scale } = p;
      switch (this.kind) {
        case 'snow': {
          const x = wrap(x0 + Math.sin(t * 0.5 + phase) * 24 + t * 6 * speed, w) - 20;
          const y = wrap(y0 + t * 22 * speed, h) - 20;
          const r = 1.1 * scale;
          ctx.fillStyle = dark ? `rgba(255,255,255,${0.35 + 0.35 * speed / 1.5})` : 'rgba(111,105,92,0.25)';
          ctx.beginPath(); ctx.arc(x + r, y + r, r, 0, 6.283); ctx.fill();
          break;
        }
        case 'ash': {
          const x = wrap(x0 + Math.sin(t * 0.35 + phase) * 34 + t * 4 * speed, w) - 20;
          const y = wrap(y0 + t * 11 * speed, h) - 20;
          const r = 0.9 * scale;
          ctx.fillStyle = dark ? 'rgba(185,177,162,0.28)' : 'rgba(94,85,70,0.18)';
          ctx.fillRect(x, y, r * 1.6, r);
          break;
        }
        case 'ember': {
          const x = wrap(x0 + Math.sin(t * 1.2 + phase) * 16, w) - 20;
          const y = wrap(y0 - t * 28 * speed, h) - 20;
          const flicker = 0.25 + 0.75 * Math.abs(Math.sin(t * 3 + phase));
          const r = 0.9 * scale;
          ctx.fillStyle = `rgba(255,138,61,${(dark ? 0.75 : 0.45) * flicker})`;
          ctx.beginPath(); ctx.arc(x + r, y + r, r, 0, 6.283); ctx.fill();
          break;
        }
        case 'dust': {
          const x = wrap(x0 + t * 4 * speed + Math.sin(t * 0.3 + phase) * 10, w) - 20;
          const y = wrap(y0 - t * 2.5 * speed + Math.cos(t * 0.25 + phase) * 8, h) - 20;
          const r = 0.7 * scale;
          const a = (0.10 + 0.20 * Math.abs(Math.sin(t * 0.5 + phase))) * (dark ? 1 : 0.6);
          ctx.fillStyle = dark ? `rgba(230,223,207,${a})` : `rgba(94,85,70,${a})`;
          ctx.beginPath(); ctx.arc(x + r, y + r, r, 0, 6.283); ctx.fill();
          break;
        }
        case 'rain': {
          const x = wrap(x0 - t * 90 * speed, w) - 20;
          const y = wrap(y0 + t * 620 * speed, h) - 20;
          ctx.strokeStyle = dark ? 'rgba(169,182,192,0.22)' : 'rgba(94,106,115,0.22)';
          ctx.lineWidth = 1;
          ctx.beginPath(); ctx.moveTo(x, y); ctx.lineTo(x - 3, y + 14 * scale); ctx.stroke();
          break;
        }
        case 'petal':
        case 'leaf': {
          const x = wrap(x0 + Math.sin(t * 0.6 + phase) * 44 + t * 10 * speed, w) - 20;
          const y = wrap(y0 + t * 18 * speed, h) - 20;
          const petal = this.kind === 'petal';
          ctx.fillStyle = petal ? `rgba(232,185,194,${dark ? 0.45 : 0.55})` : `rgba(154,106,50,${dark ? 0.5 : 0.45})`;
          const rw = (petal ? 3.2 : 4.2) * scale;
          ctx.save();
          ctx.translate(x, y);
          ctx.rotate(t * 0.8 * speed + phase);
          ctx.beginPath(); ctx.ellipse(0, 0, rw, rw * 0.45, 0, 0, 6.283); ctx.fill();
          ctx.restore();
          break;
        }
      }
    }
  }
}

let grain = null;
/** 胶片颗粒：生成一张 160×160 的噪点图，CSS 里平铺叠加 */
export function grainURL() {
  if (grain) return grain;
  const side = 160;
  const c = document.createElement('canvas');
  c.width = side;
  c.height = side;
  const g = c.getContext('2d');
  const img = g.createImageData(side, side);
  const u = rng(1418);
  for (let i = 0; i < side * side; i++) {
    const v = Math.floor(u() * 256);
    img.data[i * 4] = v;
    img.data[i * 4 + 1] = v;
    img.data[i * 4 + 2] = v;
    img.data[i * 4 + 3] = 255;
  }
  g.putImageData(img, 0, 0);
  grain = c.toDataURL('image/png');
  return grain;
}
