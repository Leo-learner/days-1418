// 界面小工具：转义、格式化、图标

export const esc = s => String(s ?? '')
  .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;').replace(/'/g, '&#39;');

/** 支持 **加粗** 和 *强调* */
export const inline = s => esc(s)
  .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
  .replace(/\*(.+?)\*/g, '<em>$1</em>');

export const joinDot = (parts, sep = ' · ') => parts.filter(Boolean).join(sep);

export function duration(seconds) {
  const m = Math.floor(seconds / 60);
  return m >= 60 ? `${Math.floor(m / 60)} 小时 ${m % 60} 分` : `${m} 分钟`;
}

export const fmtDay = iso => new Date(iso).toLocaleDateString('zh-CN', { year: 'numeric', month: 'short', day: 'numeric' });
export const fmtStamp = iso => new Date(iso).toLocaleString('zh-CN', { dateStyle: 'short', timeStyle: 'short' });

/** 用真正的减号（−），数字对齐也好看些 */
export const signed = d => (d > 0 ? `+${d}` : `−${-d}`);

const svg = (body, { fill = false, size = 16 } = {}) =>
  `<svg class="ico" width="${size}" height="${size}" viewBox="0 0 24 24" aria-hidden="true" ${fill
    ? 'fill="currentColor" stroke="none"'
    : 'fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"'}>${body}</svg>`;

export const icons = {
  rewind: svg('<path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/>'),
  log: svg('<path d="M4 19.5A2.5 2.5 0 0 1 6.5 17H20V2H6.5A2.5 2.5 0 0 0 4 4.5z"/><path d="M4 19.5A2.5 2.5 0 0 0 6.5 22H20v-5"/><path d="M9 7h7"/>'),
  archive: svg('<rect x="2.5" y="3.5" width="19" height="5" rx="1"/><path d="M4.5 8.5v10a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2v-10"/><path d="M10 12.5h4"/>'),
  save: svg('<path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><path d="m7 10 5 5 5-5"/><path d="M12 15V3"/>'),
  folder: svg('<path d="M3 6.5A1.5 1.5 0 0 1 4.5 5h4.2l2 2.2h8.8A1.5 1.5 0 0 1 21 8.7v9.8a1.5 1.5 0 0 1-1.5 1.5h-15A1.5 1.5 0 0 1 3 18.5z"/>'),
  sidebar: svg('<rect x="3" y="4" width="18" height="16" rx="2"/><path d="M15 4v16"/>'),
  house: svg('<path d="m3 10 9-7 9 7v10a1 1 0 0 1-1 1h-5v-6H9v6H4a1 1 0 0 1-1-1z"/>'),
  lock: svg('<path d="M7 11V7.5a5 5 0 0 1 10 0V11h.5A1.5 1.5 0 0 1 19 12.5v7a1.5 1.5 0 0 1-1.5 1.5h-11A1.5 1.5 0 0 1 5 19.5v-7A1.5 1.5 0 0 1 6.5 11zm2 0h6V7.5a3 3 0 0 0-6 0z"/>', { fill: true, size: 12 }),
  seal: svg('<path d="M12 1.8 14.3 4l3.1-.4.8 3 2.8 1.5-1.2 2.9 1.2 2.9-2.8 1.5-.8 3-3.1-.4L12 22.2 9.7 20l-3.1.4-.8-3L3 15.9l1.2-2.9L3 10.1l2.8-1.5.8-3 3.1.4z"/>', { fill: true, size: 11 }),
  sealOutline: svg('<path d="M12 1.8 14.3 4l3.1-.4.8 3 2.8 1.5-1.2 2.9 1.2 2.9-2.8 1.5-.8 3-3.1-.4L12 22.2 9.7 20l-3.1.4-.8-3L3 15.9l1.2-2.9L3 10.1l2.8-1.5.8-3 3.1.4z"/>', { size: 17 }),
  star: svg('<path d="m12 2.5 2.9 6 6.6.9-4.8 4.6 1.2 6.5L12 17.4l-5.9 3.1 1.2-6.5-4.8-4.6 6.6-.9z"/>', { fill: true, size: 10 }),
  chevronLeft: svg('<path d="m15 18-6-6 6-6"/>'),
  docPlus: svg('<path d="M14 2.5H6.5a2 2 0 0 0-2 2v15a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2V8z"/><path d="M14 2.5V8h5.5"/><path d="M12 11.5v6M9 14.5h6"/>'),
  docSearch: svg('<path d="M14 2.5H6.5a2 2 0 0 0-2 2v15a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2V8z"/><path d="M14 2.5V8h5.5"/><circle cx="11.5" cy="14" r="2.6"/><path d="m13.4 15.9 2 2"/>', { size: 18 }),
  close: svg('<path d="M6 6l12 12M18 6 6 18"/>'),
  cloud: svg('<path d="M7 18.5h10a4 4 0 0 0 .6-7.95A5.5 5.5 0 0 0 7 9.5a4.5 4.5 0 0 0 0 9z"/>', { size: 13 }),
};
