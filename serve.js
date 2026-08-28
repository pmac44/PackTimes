// Tiny static server for local testing (node serve.js). Not shipped — dev only.
const http=require('http'),fs=require('fs'),path=require('path');
const TYPES={'.html':'text/html','.js':'text/javascript','.json':'application/json','.png':'image/png','.svg':'image/svg+xml','.woff2':'font/woff2','.css':'text/css'};
http.createServer((req,res)=>{
  let f=decodeURIComponent(req.url.split('?')[0]);
  if(f==='/')f='/index.html';
  const p=path.join(__dirname,f);
  fs.readFile(p,(e,d)=>{
    if(e){res.writeHead(404);res.end('not found');return;}
    res.writeHead(200,{'Content-Type':TYPES[path.extname(p)]||'application/octet-stream'});
    res.end(d);
  });
}).listen(8777,()=>console.log('PackTimes dev server on http://localhost:8777'));
