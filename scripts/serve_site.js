// A project-subpath server: exercise the same URLs as GitHub Pages.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '../site');
const mime = {'.html':'text/html', '.js':'text/javascript', '.css':'text/css', '.png':'image/png'};
http.createServer((req,res) => {
  const url = new URL(req.url, 'http://localhost');
  if (!url.pathname.startsWith('/crisperplayer/')) { res.writeHead(404).end(); return; }
  const relative = decodeURIComponent(url.pathname.slice('/crisperplayer/'.length)) || 'index.html';
  const file = path.resolve(root, relative);
  if (!file.startsWith(root + path.sep)) { res.writeHead(403).end(); return; }
  fs.readFile(file, (error, data) => {
    if (error) { res.writeHead(404).end(); return; }
    res.writeHead(200, {'Content-Type': mime[path.extname(file)] || 'application/octet-stream'}).end(data);
  });
}).listen(8765, '127.0.0.1');
