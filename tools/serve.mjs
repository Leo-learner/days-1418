// 本地试玩：node tools/serve.mjs [端口=8418]
// 直接用 web/ 里的源码，story.json 每次请求时从 story/ 现拼，改完剧本刷新页面就能看到。
import { createServer } from 'node:http';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { storyBundle } from './build.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const webDir = path.join(root, 'web');
const port = Number(process.argv[2] ?? process.env.PORT ?? 8418);
const TYPES = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.css': 'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png',
};

createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  let file = decodeURIComponent(url.pathname);
  if (file.endsWith('/')) file += 'index.html';
  try {
    let body;
    if (file === '/story.json') body = JSON.stringify(storyBundle());
    else {
      const full = path.join(webDir, path.normalize(file));
      if (!full.startsWith(webDir + path.sep)) throw new Error('outside');
      body = await readFile(full);
    }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] ?? 'application/octet-stream', 'Cache-Control': 'no-cache' });
    res.end(body);
  } catch {
    res.writeHead(404, { 'Content-Type': 'text/plain; charset=utf-8' });
    res.end('404');
  }
}).listen(port, () => console.log(`▸ http://localhost:${port}/`));
