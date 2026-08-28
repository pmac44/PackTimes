// v376 verification — cidx binary search vs the old linear scan, + the _kmLen cache maths.
// Extracts the REAL cidx from index.html (no hand-port to drift).
const fs=require('fs');
const src=fs.readFileSync('F:/Dropbox/Claude/Work Areas/Apps/PackTimes-project/index.html','utf8');

// Extract the new cidx by anchor
const m=src.match(/function cidx\(r,d\)\{[\s\S]*?\n\}/);
if(!m){console.error('FAIL: could not extract cidx');process.exit(1);}
const cidxNew=new Function('return '+m[0])();

// The OLD implementation, verbatim (the oracle)
function cidxOld(r,d){let b=0,bd=Infinity;r.points.forEach((p,i)=>{const v=Math.abs(p.dist-d);if(v<bd){bd=v;b=i;}});return b;}

let pass=0,fail=0;
function chk(name,cond){if(cond){pass++;}else{fail++;console.error('FAIL: '+name);}}

// Route shapes
function mkRoute(dists){return{points:dists.map(d=>({dist:d}))};}
const uniform=mkRoute(Array.from({length:1001},(_,i)=>i*0.3));           // 300 km, 300 m spacing
const irregular=mkRoute([0,0.05,0.31,0.32,1.7,1.71,5,9.99,10,10.01,42.5]);
const dupes=mkRoute([0,1,2,2,2,3,4,4,5]);                                 // zero-length segments
const single=mkRoute([0]);
const twoPt=mkRoute([0,10]);

// 1. Exhaustive sweep on the uniform route: every 10 m from -1 to 301 km,
//    asserting the returned point is at the SAME distance from d as the oracle's
//    (index may differ only on an exact tie, where both are equally near).
for(let d=-1;d<=301;d+=0.01){
  const a=cidxOld(uniform,d),b=cidxNew(uniform,d);
  if(a!==b){
    const da=Math.abs(uniform.points[a].dist-d),db=Math.abs(uniform.points[b].dist-d);
    if(Math.abs(da-db)>1e-12){fail++;console.error(`FAIL uniform d=${d}: old ${a}(${da}) new ${b}(${db})`);}
    else pass++;
  } else pass++;
}

// 2. Irregular + dupes + tiny routes: exact index match required (incl. exact ties → old behaviour)
for(const[route,name]of[[irregular,'irregular'],[dupes,'dupes'],[single,'single'],[twoPt,'twoPt']]){
  const ds=[-5,0,0.04,0.055,1.705,2,2.5,3.5,4,4.5,5,9.995,10,10.005,26.25,42.5,99];
  for(const d of ds){
    const a=cidxOld(route,d),b=cidxNew(route,d);
    chk(`${name} d=${d} (old ${a} vs new ${b})`,a===b);
  }
}

// 3. Empty points → 0, no throw
chk('empty points returns 0',cidxNew({points:[]},5)===0);
chk('missing points returns 0',cidxNew({points:null},5)===0);

// 4. _kmLen maths: cached u*scale must equal the old per-segment px/py sum.
//    Synthetic wiggly route; px/py exactly as drawMap defines them.
const N=5000;const pts=[];let lat=-34,lon=148,dist=0;
for(let i=0;i<N;i++){lat+=0.0003*Math.sin(i*0.1);lon+=0.0004+0.0002*Math.cos(i*0.07);
  if(i>0){const p=pts[i-1];dist+=Math.sqrt(((lon-p.lon)*111.32*Math.cos(-34*Math.PI/180))**2+((lat-p.lat)*110.57)**2);}
  pts.push({lat,lon,dist});}
const midLat=(pts.reduce((a,p)=>Math.max(a,p.lat),-Infinity)+pts.reduce((a,p)=>Math.min(a,p.lat),Infinity))/2;
const kx=111.32*Math.cos(midLat*Math.PI/180),ky=110.57;
for(const scale of[0.7,3.3,42]){
  const cLon=lon-0.5,cLat=lat+0.2,cpx=400,cpy=300;
  const px=l=>cpx+(l-cLon)*kx*scale, py=l=>cpy-(l-cLat)*ky*scale;
  let old=0;for(let i=1;i<pts.length;i++){const dx=px(pts[i].lon)-px(pts[i-1].lon),dy=py(pts[i].lat)-py(pts[i-1].lat);old+=Math.sqrt(dx*dx+dy*dy);}
  let u=0;for(let i=1;i<pts.length;i++){const dx=(pts[i].lon-pts[i-1].lon)*kx,dy=(pts[i].lat-pts[i-1].lat)*ky;u+=Math.sqrt(dx*dx+dy*dy);}
  const neu=u*scale;
  chk(`kmLen scale=${scale}: ${old.toFixed(6)} vs ${neu.toFixed(6)}`,Math.abs(old-neu)/old<1e-9);
}

// 5. Benchmark: the reproduced bug (4,300 marker candidates on a 150k-point route)
const big=mkRoute(Array.from({length:150001},(_,i)=>i*4300/150000));
let t0=Date.now();for(let km=1;km<4300;km+=1)cidxOld(big,km);const oldMs=Date.now()-t0;
t0=Date.now();for(let km=1;km<4300;km+=1)cidxNew(big,km);const newMs=Date.now()-t0;
console.log(`benchmark: 4,300 lookups on 150k points — old ${oldMs} ms, new ${newMs} ms`);
chk('new is dramatically faster',newMs<oldMs/10||oldMs<10);

console.log(`${pass} pass, ${fail} fail`);
process.exit(fail?1:0);
