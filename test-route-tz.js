#!/usr/bin/env node
// PackTimes — v374 regression test for the ROUTE-LOCAL CLOCK.
//
// Run:  TZ='Australia/Sydney' node test-route-tz.js    (no network)
//
// Guards the v374 bug family: plan wall-clock strings ("2026-06-12", "07:00",
// departTime "06:00") were parsed AND displayed in the BROWSER's timezone, while
// they mean ROUTE-local time. Planning the Tour Divide from Sydney (16 h from
// Mountain Daylight Time) skewed every ETA instant by 16 h, so sunAt — correct
// since v371 for any true instant — painted daylight onto the plan's night hours.
// The test runs its assertions in whatever TZ it is given; the Sydney run is the
// one that reproduces the original report.
const fs=require('fs'),vm=require('vm');
const src=fs.readFileSync('index.html','utf8');
const grab=(a,b)=>{const i=src.indexOf(a);const j=src.indexOf(b,i);if(i<0||j<0)throw new Error('anchor '+a);return src.slice(i,j);};
const code=[
  grab('function routeTzOffsetMin(r){','\nfunction startDT'),
  grab('function sleepHoursFor(s,arrivalEta,r){','\nconst SLEEP_NEAR_KM'),
  grab('const _sunMemo=new Map();','\n// ═══'),
].join('\n');
const sb={Math,Date,Map,console,Number,String,Object,Array,Infinity};
vm.createContext(sb);vm.runInContext(code,sb);

let pass=0,fail=0;
const ok=(cond,name,detail)=>{
  if(cond){pass++;console.log('  ✓ '+name);}
  else{fail++;console.log('  ✗ '+name+(detail?'  — '+detail:''));}
};

const devOffMin=-new Date().getTimezoneOffset();   // minutes east of UTC, this environment
console.log(`Environment offset: UTC${devOffMin>=0?'+':''}${devOffMin/60}h\n`);

// The Divide with the API-derived offset (MDT, −360 min), as it is once any
// weather fetch has run _adoptRouteTz.
const divide={points:[{lat:51.18,lon:-115.57,dist:0}],startDate:'2026-06-12',startTime:'07:00',tzOffsetMin:-360};

// 1 ── offset resolution
ok(sb.routeTzOffsetMin(divide)===-360,'API-derived offset wins');
const divideNoApi={points:[{lat:51.18,lon:-115.57,dist:0}]};
if(Math.abs(-480-devOffMin)>=180)
  ok(sb.routeTzOffsetMin(divideNoApi)===-480,'solar estimate (−8 h) when the device is a continent away');
else
  ok(sb.routeTzOffsetMin(divideNoApi)===devOffMin,'device clock trusted for a rider near the route (DST-safe 3 h window)');
const sydneyRoute={points:[{lat:-33.87,lon:151.21,dist:0}]};
if(Math.abs(600-devOffMin)<180)
  ok(sb.routeTzOffsetMin(sydneyRoute)===devOffMin,'device clock trusted when it matches the route (±3 h)');
else console.log('  – device-trust case skipped (environment not near UTC+10)');

// 2 ── parsing: 07:00 12 Jun MDT is 13:00 UTC, wherever the browser is
const inst=sb.routeWallToInstant('2026-06-12','07:00',divide);
ok(inst.getTime()===Date.UTC(2026,5,12,13,0),'routeWallToInstant: 07:00 MDT → 13:00 UTC',inst.toISOString());

// 3 ── display round-trip: the instant shows back as 07:00 in ANY environment tz
const rc=sb.toRouteClock(inst,divide);
ok(rc.getHours()===7&&rc.getMinutes()===0,'toRouteClock round-trips to the entered wall clock');

// 4 ── the headline: 22:00 route-local at Banff in June is NIGHT
const tenPm=sb.routeWallToInstant('2026-06-12','22:00',divide);
const sun=sb.sunAt(51.18,-115.57,tenPm);
ok(tenPm>sun.sunset,'22:00 route-local at Banff reads as night (after sunset)');
// …and the OLD parse would have called it daylight from Sydney
if(Math.abs(devOffMin-(-360))>=180){
  const oldInst=new Date('2026-06-12T22:00:00');      // browser-local — the pre-v374 behaviour
  const oldSun=sb.sunAt(51.18,-115.57,oldInst);
  ok(oldInst>=oldSun.sunrise&&oldInst<oldSun.sunset,'(proof) the old browser-local parse called that same 22:00 daylight');
}

// 5 ── fixed-departure sleep: arrive 21:00, wake 06:00 route-local = 9 h, any browser tz
const arr=sb.routeWallToInstant('2026-06-12','21:00',divide);
const hrs=sb.sleepHoursFor({departTime:'06:00'},arr,divide);
ok(Math.abs(hrs-9)<0.01,'sleepHoursFor: 21:00 → 06:00 route-local = 9 h',hrs+'h');

// 6 ── nights & day numbering on route-local midnights
const fin=sb.routeWallToInstant('2026-06-14','10:00',divide);
ok(sb.routeNightsBetween(inst,fin,divide)===2,'routeNightsBetween counts route-local midnights');
ok(sb.routeDayNum(inst,fin,divide)===3,'routeDayNum: finish lands on route-local day 3');

// 7 ── weatherAtEta pairing formula: a 14:00 local forecast hour matches a 14:00
// route-local ETA exactly once both become true instants
const hTime='2026-06-12T14:00',utcOffsetSec=-21600;
const hMs=Date.UTC(+hTime.slice(0,4),+hTime.slice(5,7)-1,+hTime.slice(8,10),+hTime.slice(11,13),+hTime.slice(14,16)||0)-utcOffsetSec*1000;
const eta=sb.routeWallToInstant('2026-06-12','14:00',divide);
ok(hMs===eta.getTime(),'forecast-hour string and route-local ETA meet at the same instant');

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail?1:0);
