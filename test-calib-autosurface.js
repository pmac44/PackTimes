#!/usr/bin/env node
// PackTimes — v438 sample-ride auto-surface tests.
// Run: node test-calib-autosurface.js   Exit 0 = all passed.
//
// Lifts the REAL matcher out of index.html (between the '// Try to read surface mix + climb
// straight off a saved route' comment and 'let _recSaveCtx') and runs it against synthetic
// routes: a ride over part of a LONGER saved route, recorded with a DIFFERENT route loaded,
// with a detour, ridden backwards — the cases that used to fall through to "pick a surface".
const fs=require('fs'),vm=require('vm'),path=require('path');
const src=fs.readFileSync(path.join(__dirname,'index.html'),'utf8');
const si=src.indexOf('// Try to read surface mix + climb straight off a saved route');
const ei=src.indexOf('let _recSaveCtx = null;');
if(si<0||ei<0)throw new Error('anchors');
const pick=(name)=>{const a=src.indexOf('function '+name+'(');let d=0,i=src.indexOf('{',a);for(;;i++){if(src[i]==='{')d++;else if(src[i]==='}'&&--d===0)break;}return src.slice(a,i+1);};
const code=[pick('elevGain'),pick('hav'),pick('_recDist'),src.slice(si,ei)].join('\n');

// 100 km route heading north from (-35,149), point every 100 m, a 300 m hill at km 45–50.
// Surface: road 0–40, gravel 40–60, road 60–100.
function mkRoute(id,lon0,n){const pts=[];for(let i=0;i<n;i++){const km=i*0.1;
  const ele=600+(km>45&&km<50?(km-45)*60:km>=50?300:0);
  pts.push({lat:-35+km/110.57,lon:lon0,ele,dist:km});}
  return{id,name:id,points:pts,totalDist:(n-1)*0.1,loadPreset:'heavy',
    surfaceSegs:[{fromDist:0,toDist:40,cat:'road'},{fromDist:40,toDist:60,cat:'grade2'},{fromDist:60,toDist:100,cat:'road'}]};}
const big=mkRoute('Hunt big',149,1001), other=mkRoute('Other',150,201);
other.surfaceSegs=[{fromDist:0,toDist:20,cat:'single'}];
const ctx={Math,Map,Set,Object,ROUTES:[big,other],_recRouteFor:rec=>[big,other].find(r=>r.id===rec.routeId)||null};
vm.createContext(ctx);vm.runInContext(code,ctx);

// Ride from km a to km b along the big route (points every 20 m), optional detour (km, offset m).
function ride(a,b,opt={}){const pts=[],step=a<b?0.02:-0.02;let t=0;
  for(let km=a;step>0?km<=b:km>=b;km+=step){let lon=149;
    if(opt.detour&&km>opt.detour[0]&&km<opt.detour[0]+opt.detour[1])lon+=opt.detour[2]/1000/91;
    pts.push({lat:-35+km/110.57,lon,t:t+=4000});}
  let d=0;for(let i=1;i<pts.length;i++)d+=ctx._recDist(pts[i-1],pts[i])/1000;
  return{points:pts,totalDist:d,routeId:opt.linked||null};}

let fail=0;const ok=(c,m)=>{console.log((c?'  PASS  ':'  FAIL  ')+m);if(!c)fail++;};
let r=ctx._recCalibAuto(ride(42,58,{linked:'Other'}));
ok(r&&r.surface==='grade2'&&r.routeName==='Hunt big','part of a longer route, other route loaded → gravel from "Hunt big"');
ok(r&&Math.abs(r.elevM-300)<20,'climb read off the route ('+(r&&Math.round(r.elevM))+' m, want ~300)');
r=ctx._recCalibAuto(ride(5,35));
ok(r&&r.surface==='road','no route loaded, sealed stretch → road');
r=ctx._recCalibAuto(ride(42,58,{detour:[50,1.0,800]}));
ok(r&&r.surface==='grade2','1 km detour 800 m off route still matches');
r=ctx._recCalibAuto(ride(58,42));
ok(r&&r.surface==='grade2'&&r.elevM<20,'ridden backwards → descends, ~0 m climb ('+(r&&Math.round(r.elevM))+')');
r=ctx._recCalibAuto(ride(42,58,{detour:[43,10,2000]}));
ok(r===null,'mostly off any route → no match (modal asks)');
console.log(fail?'\nRESULT: '+fail+' failed':'\nRESULT: all passed');process.exit(fail?1:0);
