// 打包网页版：node tools/build.mjs
//   build/web/                  可以直接丢到任何静态托管上的目录（index.html 在根上）
//   build/days-1418-web.zip     Game Hub 上传用的包（根上是 index.html + game.json + cover.svg）
// 打包前先把剧本解析一遍，有语法问题直接失败。
import { cpSync, mkdirSync, readdirSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { deflateRawSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { loadStory } from '../web/src/story.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const out = path.join(root, 'build', 'web');
const zipPath = path.join(root, 'build', 'days-1418-web.zip');

export function storyBundle(dir = path.join(root, 'story')) {
  return readdirSync(dir).filter(f => f.endsWith('.story')).sort()
    .map(file => ({ file, text: readFileSync(path.join(dir, file), 'utf8') }));
}

function listFiles(dir, base = dir) {
  return readdirSync(dir).flatMap(name => {
    const full = path.join(dir, name);
    return statSync(full).isDirectory() ? listFiles(full, base) : [path.relative(base, full).split(path.sep).join('/')];
  }).sort();
}

// ---- 最小 ZIP 写入器（deflate，无第三方依赖） ----

const CRC_TABLE = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
function crc32(buf) {
  let c = 0xFFFFFFFF;
  for (const b of buf) c = CRC_TABLE[(c ^ b) & 0xFF] ^ (c >>> 8);
  return (c ^ 0xFFFFFFFF) >>> 0;
}

export function zip(entries) {
  const locals = [], centrals = [];
  let offset = 0;
  const dosTime = 0, dosDate = (2026 - 1980) << 9 | 1 << 5 | 1;   // 固定时间戳：同样的输入得到同样的包
  for (const { name, data } of entries) {
    const nameBuf = Buffer.from(name, 'utf8');
    const deflated = deflateRawSync(data, { level: 9 });
    const useDeflate = deflated.length < data.length;
    const body = useDeflate ? deflated : data;
    const crc = crc32(data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x0800, 6);                 // UTF-8 文件名
    local.writeUInt16LE(useDeflate ? 8 : 0, 8);
    local.writeUInt16LE(dosTime, 10);
    local.writeUInt16LE(dosDate, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(body.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(nameBuf.length, 26);
    local.writeUInt16LE(0, 28);
    locals.push(local, nameBuf, body);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(20, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(useDeflate ? 8 : 0, 10);
    central.writeUInt16LE(dosTime, 12);
    central.writeUInt16LE(dosDate, 14);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(body.length, 20);
    central.writeUInt32LE(data.length, 24);
    central.writeUInt16LE(nameBuf.length, 28);
    central.writeUInt32LE(0o100644 << 16 >>> 0, 38);
    central.writeUInt32LE(offset, 42);
    centrals.push(central, nameBuf);
    offset += 30 + nameBuf.length + body.length;
  }
  const centralSize = centrals.reduce((s, b) => s + b.length, 0);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(centralSize, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, ...centrals, end]);
}

export function build() {
  const files = storyBundle();
  const story = loadStory(files);
  if (story.issues.length) {
    for (const i of story.issues) console.error('✘ ' + i);
    throw new Error(`剧本有 ${story.issues.length} 处问题，停止打包`);
  }

  rmSync(out, { recursive: true, force: true });
  mkdirSync(out, { recursive: true });
  for (const f of ['index.html', 'style.css', 'icon.svg', 'cover.svg', 'game.json']) cpSync(path.join(root, 'web', f), path.join(out, f));
  cpSync(path.join(root, 'web', 'src'), path.join(out, 'src'), { recursive: true });
  writeFileSync(path.join(out, 'story.json'), JSON.stringify(files));

  const names = listFiles(out);
  writeFileSync(zipPath, zip(names.map(name => ({ name, data: readFileSync(path.join(out, name)) }))));
  const size = statSync(zipPath).size;
  console.log(`✓ ${story.nodeOrder.length} 个节点 · ${story.endings.length} 个结局 · ${story.docs.length} 份档案`);
  console.log(`✓ ${path.relative(root, out)}/（${names.length} 个文件）`);
  console.log(`✓ ${path.relative(root, zipPath)}（${(size / 1024).toFixed(0)} KB）`);
  return { out, zipPath };
}

if (import.meta.url === `file://${process.argv[1]}`) build();
