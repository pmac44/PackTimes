#!/usr/bin/env node
// PackTimes — v371 regression test for the CHUNKED OSM POI SEARCH.
//
// Run:  node test-osm-chunked.js        (from the project folder, needs network)
//
// Pulls the REAL fetchOverpass / snapTo / _snapRefine straight out of index.html
// (never a hand-copy — see CLAUDE.md), stubs the app around them, and runs the
// search against the live Overpass API over a 771 km route laid through twelve
// known Rockies towns. A pass finds all twelve, inside the search radius, with no
// duplicates at the chunk seams.
//
// Guards the v371 bug: the old whole-route bounding box timed out on Overpass and
// came back HTTP 200 + empty + "remark", which the code reported as "✓ Found 0
// points along route". If this ever prints 0/12 alongside status 'done', that
// failure mode is back.
const fs=require('fs');
const src=fs.readFileSync('index.html','utf8');

function grab(startMark,endMark){
  const a=src.indexOf(startMark);
  if(a<0)throw new Error('missing '+startMark);
  const b=src.indexOf(endMark,a);
  if(b<0)throw new Error('missing end '+endMark);
  return src.slice(a,b);
}

const code=[
  grab('function _snapRefine(r,lat,lon,best){','\n// liveFix — true ONLY'),
  grab('function snapTo(r,lat,lon,lastIdx,liveFix){','\nfunction toggleGPS()'),
  grab("const MIRRORS=['https://overpass-api.de","\n// ─── v371 — CHUNKED POI SEARCH"),
  grab('async function fetchOverpass(){','\n// ─── Town search: geocode name'),
].join('\n');

// ── Synthetic 900 km route down the Colorado Rockies (3 chunks at CHUNK_KM=300) ──
const R=6371;
const hav=(a,b)=>{const dLat=(b.lat-a.lat)*Math.PI/180,dLon=(b.lon-a.lon)*Math.PI/180;
  const s=Math.sin(dLat/2)**2+Math.cos(a.lat*Math.PI/180)*Math.cos(b.lat*Math.PI/180)*Math.sin(dLon/2)**2;
  return 2*R*Math.asin(Math.sqrt(s));};
// Waypoints straight through real Rockies towns, so we know exactly what a
// working search must return. Interpolated to ~100 m spacing.
const WPT=[
  ['Salida',38.5347,-105.9989],['Buena Vista',38.8422,-106.1311],['Leadville',39.2508,-106.2925],
  ['Frisco',39.5744,-106.0975],['Silverthorne',39.6297,-106.0719],['Kremmling',40.0586,-106.3892],
  ['Walden',40.7311,-106.2822],['Saratoga',41.4553,-106.8059],['Rawlins',41.7911,-107.2387],
  ['Lander',42.8330,-108.7307],['Dubois',43.5394,-109.6335],['Jackson',43.4799,-110.7624],
];
const EXPECT=WPT.map(w=>w[0]);
const points=[];
for(let k=0;k<WPT.length-1;k++){
  const [,la0,lo0]=WPT[k],[,la1,lo1]=WPT[k+1];
  const legKm=hav({lat:la0,lon:lo0},{lat:la1,lon:lo1});
  const n=Math.max(2,Math.round(legKm*10));           // ~100 m spacing
  for(let i=0;i<n;i++)points.push({lat:la0+(la1-la0)*i/n,lon:lo0+(lo1-lo0)*i/n,dist:0,ele:2000});
}
points.push({lat:WPT[WPT.length-1][1],lon:WPT[WPT.length-1][2],dist:0,ele:2000});
for(let i=1;i<points.length;i++)points[i].dist=points[i-1].dist+hav(points[i-1],points[i]);
const totalDist=points[points.length-1].dist;

const route={points,totalDist,stops:[]};
const added=[];

// ── Stubs for everything fetchOverpass touches ──
const sandbox={
  cur:()=>route,
  UI:{osmOpts:{towns:true},searchRadiusKm:1.2,opStatus:'idle',opMsg:''},
  renderKeepScroll:()=>{},
  saveAll:async()=>{},
  parseOH:()=>null,
  _bikeStandTag:()=>false,
  _bikeStandName:()=>'',
  addStop:(r,dist,type,name,o)=>{const st={dist,type,name,auto:true,...o};r.stops.push(st);added.push(st);},
  document:{getElementById:()=>({set textContent(v){process.stdout.write('   · '+v+'\n');}})},
  hav,
  SNAP_NEAR_KM:0.2,SNAP_FWD_DEG:60,SNAP_ENDS_MEET_KM:0.15,SNAP_STARTAWAY_KM:0.5,
  SNAP_SWITCH_KM:2,SNAP_SWITCH_HOLD:3,SNAP_WARMUP_KM:0.3,SNAP_TIE_M:15,
  _snapDir:0,_snapDirAccum:0,_snapRiderLat:null,_snapRiderLon:null,_snapOdoKm:0,
  _snapLeftStart:false,_snapPendKm:null,_snapPendCnt:0,_snapMaxKm:0,
  fetch:(u,o)=>fetch(u,{...o,headers:{...o.headers,'User-Agent':'PackTimes/v371 (route planner)'}}),
  AbortController,setTimeout,clearTimeout,console,Math,Date,JSON,String,Number,Object,Array,Infinity,encodeURIComponent,
};
const vm=require('vm');
vm.createContext(sandbox);
vm.runInContext(code,sandbox);

(async()=>{
  console.log(`Synthetic route: ${totalDist.toFixed(0)} km, ${points.length} points`);
  console.log(`Chunks expected: ${Math.ceil(totalDist/300)}  (CHUNK_KM=300)\n`);
  const t0=Date.now();
  await sandbox.fetchOverpass();
  const secs=((Date.now()-t0)/1000).toFixed(1);
  console.log(`\nstatus : ${sandbox.UI.opStatus}`);
  console.log(`message: ${sandbox.UI.opMsg}`);
  console.log(`elapsed: ${secs}s`);
  console.log(`\n${added.length} stops added. First 12 by route km:`);
  added.sort((a,b)=>a.dist-b.dist).slice(0,12)
    .forEach(s=>console.log(`  ${s.dist.toFixed(1).padStart(7)} km  ${s.type.padEnd(6)} ${s.name}${s.offRouteM?'  ('+s.offRouteM+'m off)':''}`));
  // Sanity: nothing should be outside the search radius, and coverage should span the route
  const maxOff=Math.max(0,...added.map(s=>s.offRouteM||0))/1000;
  const spans=[added[0]?.dist??-1,added[added.length-1]?.dist??-1];
  console.log(`\nmax off-route: ${maxOff.toFixed(2)} km (limit ${(1.2*2).toFixed(1)} km for towns)`);
  console.log(`coverage: ${spans[0].toFixed(0)}–${spans[1].toFixed(0)} km of ${totalDist.toFixed(0)} km`);
  const names=new Set(added.map(s=>s.name));
  const missing=EXPECT.filter(n=>!names.has(n));
  console.log(`\nwaypoint towns found: ${EXPECT.length-missing.length}/${EXPECT.length}` + (missing.length?`  MISSING: ${missing.join(', ')}`:'  ✓ all'));
  const dupes=added.map(s=>s.name).filter((n,i,a)=>a.indexOf(n)!==i);
  console.log(`duplicate names across chunk boundaries: ${dupes.length?[...new Set(dupes)].join(', '):'none'}`);
})();
