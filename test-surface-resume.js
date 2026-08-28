#!/usr/bin/env node
// PackTimes — v370 surface-fetch resume tests.
//
// Run:  node test-surface-resume.js          (from the project folder)
// Exit: 0 = all passed, 1 = something failed.
//
// WHY THIS EXISTS. The Tour Divide (4,300 km) is ~86 Overpass chunks, and every
// interesting failure in fetchSurfaceData only shows up at that length: a chunk
// that no mirror will answer, a resume that must skip 4,000 km of stored data, a
// phantom sub-sample gap that makes Refresh claim work outstanding and then issue
// zero requests, an outage that hammers the mirrors 8,000 times. None of those are
// reachable by hand on a real route without a very long afternoon and a lot of
// load on public Overpass servers.
//
// So this lifts the REAL v370 block straight out of index.html (by comment anchor)
// and runs it in a vm against a synthetic 4,300 km route and a fake Overpass that
// refuses whichever stretches the test names. No network, ~2 s, no stubbed copy of
// the logic to drift out of sync with the shipped code.
//
// ⚠ It reads the source between the '── v370 — RESUMABLE SURFACE FETCH' banner and
// the '// v351 — BIKE STANDS.' comment. Rename either and this throws 'anchors' —
// fix the anchor, don't delete the test.
const fs=require('fs'),vm=require('vm'),path=require('path');
const src=fs.readFileSync(process.argv[2]||path.join(__dirname,'index.html'),'utf8');
const si=src.indexOf('// ─── v370 — RESUMABLE SURFACE FETCH');
const ei=src.indexOf('// v351 — BIKE STANDS.');
if(si<0||ei<0)throw new Error('anchors');
const code=src.slice(si,ei);

// ── synthetic route: 4,300 km, a point every 100 m
const N=43000;
const route={id:'td',totalDist:4300,points:[],surfaceSegs:null,surfDone:null,surfGuess:null,cumRiding:null};
for(let i=0;i<N;i++)route.points.push({lat:45+i*0.00001,lon:-110+i*0.00001,ele:2000,dist:i*0.1});

let FAIL_RANGES=[];     // km ranges where every mirror refuses
let saves=0, queries=0, queriedKm=0;
const ctx={
  console,setTimeout,clearTimeout,Math,Date,Map,Set,Uint8Array,Array,JSON,Promise,Number,String,Object,RegExp,Error,
  AbortController,
  cur:()=>route,
  UI:{surfaceStatus:'idle',surfaceMsg:'',routeOverlay:'off',hiddenMapTypes:new Set()},
  renderKeepScroll(){},updateOverlayButtons(){},redrawMap(){},renderDesktopMap(){},rebuildPace(){},
  saveAll:async()=>{saves++;},
  document:{getElementById:()=>null},
  surfaceCategory:()=>'grade2',
  snapToWay:()=>({cat:'grade2',guess:false}),
  // Fake Overpass. Refuses any chunk overlapping a FAIL range; otherwise returns one way.
  fetch:async(url,opt)=>{
    queries++;
    const body=decodeURIComponent(opt.body.slice(5));
    const nums=body.match(/around:250,([-0-9.,]+)/)[1].split(',').map(Number);
    const lat0=nums[0], latN=nums[nums.length-2];
    const km0=(lat0-45)/0.00001*0.1, km1=(latN-45)/0.00001*0.1;
    for(const [a,b] of FAIL_RANGES) if(km1>=a&&km0<=b) throw new Error('simulated mirror failure');
    queriedKm+=(km1-km0);
    return{ok:true,json:async()=>({elements:[{type:'way',tags:{highway:'track'},geometry:[{lat:lat0,lon:-110},{lat:latN,lon:-110}]}]})};
  },
};
ctx.globalThis=ctx;
vm.createContext(ctx);
vm.runInContext(code+'\nthis.__fetchSurfaceData=fetchSurfaceData;this.__gap=surfGapKm;this.__fetched=surfFetchedKm;',ctx);

const gap=()=>ctx.__gap(route), fetchedKm=()=>ctx.__fetched(route);
let failed=0;
const ok=(name,cond,detail)=>{if(!cond)failed++;console.log((cond?'  PASS  ':'  FAIL  ')+name+(detail?'  — '+detail:''));};

(async()=>{
  // ── 1. Clean run, nothing fails.
  await ctx.__fetchSurfaceData();
  ok('clean run covers the whole route', gap()<1, `gap ${gap().toFixed(1)} km, ${route.surfaceSegs.length} segs, ${queries} queries, ${saves} saves`);
  ok('checkpoints fired during the run', saves>=8, saves+' saves');

  // ── 2. Fresh route, three stretches that no mirror will answer.
  Object.assign(route,{surfaceSegs:null,surfDone:null,surfGuess:null});
  FAIL_RANGES=[[900,960],[2100,2160],[3800,3860]];
  saves=0;queries=0;
  await ctx.__fetchSurfaceData();
  const afterPartial=fetchedKm(), gapPartial=gap();
  ok('one bad stretch no longer discards the run', afterPartial>4000, `${afterPartial.toFixed(0)} km stored of 4300`);
  ok('the bad stretches are recorded as gaps', gapPartial>50&&gapPartial<400, `gap ${gapPartial.toFixed(0)} km`);
  ok('status is done, not error', ctx.UI.surfaceStatus==='done', ctx.UI.surfaceMsg);

  // ── 3. Refresh with the mirrors now healthy: must RESUME, not restart.
  FAIL_RANGES=[];
  queries=0;
  const before=fetchedKm();
  await ctx.__fetchSurfaceData(true);
  ok('Refresh resumes instead of wiping', fetchedKm()>=before, `${before.toFixed(0)} -> ${fetchedKm().toFixed(0)} km`);
  ok('Refresh re-queries ONLY the gaps', queries<15, queries+' queries (a full re-run is ~87)');
  ok('route is now complete', gap()<1, `gap ${gap().toFixed(1)} km`);
  ok('segments are contiguous and ordered', route.surfaceSegs.every((s,i,a)=>s.toDist>=s.fromDist&&(i===0||s.fromDist>=a[i-1].fromDist)), route.surfaceSegs.length+' segs');

  // ── 4. Refresh on a COMPLETE route = deliberate full re-fetch.
  queries=0;
  await ctx.__fetchSurfaceData(true);
  ok('Refresh on a complete route re-queries everything', queries>80, queries+' queries');

  // ── 5. A gap nothing will ever answer must not loop forever.
  Object.assign(route,{surfaceSegs:null,surfDone:null,surfGuess:null});
  FAIL_RANGES=[[0,4300]];
  queries=0;
  await ctx.__fetchSurfaceData();
  ok('outage stops early instead of hammering', queries<400, queries+' requests (was 8,034)');
  ok('total failure terminates and reports error', ctx.UI.surfaceStatus==='error', ctx.UI.surfaceMsg+' / '+queries+' queries');

  // ── 6. Range maths.
  Object.assign(route,{surfaceSegs:[{fromDist:0,toDist:10,cat:'grade2'}],surfDone:[[0,10],[10.1,20]],surfGuess:null});
  ok('adjacent ranges merge (no phantom sub-sample gaps)', ctx.__fetched(route)>19.8, ctx.__fetched(route).toFixed(2)+' km');
  Object.assign(route,{surfaceSegs:[{fromDist:0,toDist:10,cat:'grade2'}],surfDone:null});
  ok('pre-v370 plans are treated as complete', ctx.__gap(route)===0);

  console.log(failed?'\nRESULT: '+failed+' FAILED — do not push':'\nRESULT: all checks passed');
  process.exit(failed?1:0);
})();
