// PackTimes — v372 performance regression test for LONG ROUTES.
//
// This one runs in the BROWSER, not node — it needs a real canvas and real
// event dispatch. Two ways to run it:
//
//   1. node serve.js        → open http://localhost:8777 → paste this whole file
//                             into the DevTools console.
//   2. Open index.html directly and paste it in.
//
// It builds a synthetic 4,300 km Divide-shaped route with 274 stops at two point
// densities and reports the numbers that mattered in v372. Guards three separate
// regressions, all found on Peter's Tour Divide route on 28 Aug 2026:
//
//   • ONE REDRAW PER INPUT EVENT. dragMove, zoomMap and every tile arrival called
//     redrawMap synchronously. A 20-event drag cost 18.1 SECONDS. Now coalesced to
//     one draw per animation frame. If "20-event drag" climbs back into the
//     thousands, the coalescing is gone.
//   • etaAt WAS O(stops) AND CALLED ~23,600 TIMES PER REDRAW. Now a prefix-sum
//     table built once per draw pass, and sampling is capped at two per pixel.
//   • Math.min(...points) THREW above ~124,000 points. The 150k case below is the
//     one that used to die with "Maximum call stack size exceeded" before drawing
//     anything.
//
// Reference numbers, Chrome 148, 28 Aug 2026 (a mid-range desktop — treat the
// RATIOS as the test, not the absolute milliseconds):
//
//                        v371      v372
//   redrawMap  (75k)     774 ms    226 ms
//   elev strip (75k)     624 ms     95 ms
//   20-event drag        18124 ms   126 ms
//   150k points          RangeError 390 ms
(()=>{
  const A=[51.18,-115.57],B=[31.34,-108.53],N=150000,amp=0.1745,R=6371,rad=Math.PI/180;
  const build=(step,label)=>{
    const raw=[];
    for(let i=0;i<=N;i+=step){const f=i/N;
      raw.push([A[0]+(B[0]-A[0])*f+Math.sin(f*300)*amp*0.6, A[1]+(B[1]-A[1])*f+Math.cos(f*300)*amp]);}
    let d=0;const pts=[];
    for(let i=0;i<raw.length;i++){
      if(i>0){const dLa=(raw[i][0]-raw[i-1][0])*rad,dLo=(raw[i][1]-raw[i-1][1])*rad;
        const sq=Math.sin(dLa/2)**2+Math.cos(raw[i][0]*rad)*Math.cos(raw[i-1][0]*rad)*Math.sin(dLo/2)**2;
        d+=2*R*Math.asin(Math.sqrt(sq));}
      const f=i/(raw.length-1);
      pts.push({lat:raw[i][0],lon:raw[i][1],ele:1500+Math.sin(f*260)*700+Math.sin(f*400)*250,dist:d});}
    const r=newRoute(label);r.points=pts;r.totalDist=d;
    r.startDate=new Date(Date.now()+86400000).toISOString().slice(0,10);r.startTime='07:00';
    const T=['town','water','food','camp','fuel','shop','hut'];
    for(let i=0;i<260;i++){const dist=(i+0.5)/260*d,pi=Math.round(dist/d*(pts.length-1));
      r.stops.push({id:'s'+i,dist,type:T[i%T.length],name:'Stop '+i,auto:true,starred:i%3===0,
        lat:pts[pi].lat,lon:pts[pi].lon,meals:i%7===0?[{when:'before',durationMin:30}]:[]});}
    for(let i=0;i<14;i++){const dist=(i+1)*300;if(dist>=d)break;
      r.stops.push({id:'sl'+i,dist,type:'sleep',name:'Night '+(i+1),sleepH:7,starred:true,
        meals:[{when:'after',durationMin:25}]});}
    r.stops.sort((a,b)=>a.dist-b.dist);
    ROUTES.push(r);CUR=ROUTES.length-1;rebuildPace(r);_render();
    return r;
  };
  const run=(step,label)=>{
    const r=build(step,label);
    const out={points:r.points.length,km:Math.round(r.totalDist),stops:r.stops.length};
    const t=(l,fn,n)=>{n=n||1;try{fn();}catch(e){out[l]='THREW: '+e.message;return;}
      const t0=performance.now();for(let i=0;i<n;i++)fn(i);out[l]=+((performance.now()-t0)/n).toFixed(1);};
    t('redrawMap ms',()=>redrawMap('desktop-map'),5);
    t('renderDesktopMap ms',()=>renderDesktopMap(),5);
    t('_render ms',()=>_render(),3);
    const c=document.getElementById('desktop-map'),rect=c.getBoundingClientRect();
    const ev=(ty,x,y)=>c.dispatchEvent(new MouseEvent(ty,{clientX:rect.left+x,clientY:rect.top+y,bubbles:true,buttons:1}));
    const t0=performance.now();
    ev('mousedown',400,180);
    for(let i=0;i<20;i++)ev('mousemove',400-i*4,180+i*2);
    ev('mouseup',320,220);
    out['20-event drag ms']=Math.round(performance.now()-t0);
    return out;
  };
  const res={'75k points':run(2,'PERF 75k'), '150k points':run(1,'PERF 150k')};
  // Correctness guards that ride along with the timings.
  const r=cur();
  const small=r.points.slice(0,50000), eles=small.map(p=>p.ele);
  const [mn,mx]=_minMax(small,p=>p.ele);
  res.checks={
    minMaxMatchesSpread: mn===Math.min(...eles)&&mx===Math.max(...eles),
    nearestPtMatchesReduce: r.stops.every(s=>
      Math.abs(_nearestPt(r.points,s.dist).dist -
        r.points.reduce((b,p)=>Math.abs(p.dist-s.dist)<Math.abs(b.dist-s.dist)?p:b,r.points[0]).dist)<1e-9),
  };
  console.table(res['75k points']); console.table(res['150k points']); console.log(res.checks);
  return res;
})()
