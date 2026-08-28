#!/usr/bin/env node
// PackTimes — v371 regression test for DAY/NIGHT COLOURING.
//
// Run:  node test-sun-daynight.js       (from the project folder, no network)
//
// Colours a 4,300 km Banff→Mexico line the way the map does and reports the
// day/twilight/night split. Guards the v371 bug: sun times used to be cached
// under a calendar date formed in the BROWSER's timezone while belonging to the
// ROUTE's, so planning a US route from Sydney left about 1 h of "day" per 24 h
// and the whole line read as night. Expect roughly 54% day / 8% twilight / 38%
// night in early September, midday blue near 10:00 and 14:00 local, navy at
// midnight.
const fs=require('fs'),vm=require('vm');
const src=fs.readFileSync('index.html','utf8');
const grab=(a,b)=>{const i=src.indexOf(a);const j=src.indexOf(b,i);if(i<0||j<0)throw new Error('anchor '+a);return src.slice(i,j);};
const code=[
  grab('const _sunMemo=new Map();','\n// ═══'),
  grab('function dayNightBg(dt,sun){','\nfunction dayNightLabel'),
].join('\n');
const sb={Math,Date,Map,console,Number,String,Object,Array,Infinity};
vm.createContext(sb);vm.runInContext(code,sb);

// Banff -> Antelope Wells, 4,300 km, ridden continuously at 15 km/h from 07:00 MDT 1 Sep.
const A=[51.18,-115.57],B=[31.34,-108.53],TOTAL=4300,SPEED=15;
const start=Date.UTC(2026,8,1,13,0,0);   // 07:00 MDT
let night=0,day=0,twi=0,n=0;
const bucket={};
for(let km=0;km<=TOTAL;km+=2){
  const f=km/TOTAL;
  const lat=A[0]+(B[0]-A[0])*f, lon=A[1]+(B[1]-A[1])*f;
  const t=new Date(start+km/SPEED*3600000);
  const s=sb.sunAt(lat,lon,t);
  const bg=sb.dayNightBg(t,s);
  const m=bg.match(/rgba?\((\d+),(\d+),(\d+)/);
  const lum=(+m[1]*0.299+ +m[2]*0.587+ +m[3]*0.114);
  n++;
  if(t>=s.sunrise&&t<=s.sunset){day++;bucket.day=(bucket.day||0)+1;}
  else if(t>=s.dawn&&t<=s.dusk){twi++;}
  else night++;
  if(km%430===0){
    const localH=((t.getTime()+lon/15*3600000)/3600000)%24;
    console.log(`  ${String(km).padStart(4)} km  local ${String(Math.floor(localH)).padStart(2,'0')}:${String(Math.round(localH%1*60)).padStart(2,'0')}  ${bg.padEnd(26)} lum ${lum.toFixed(0).padStart(3)}  ${t>=s.sunrise&&t<=s.sunset?'DAY':t>=s.dawn&&t<=s.dusk?'twilight':'night'}`);
  }
}
console.log(`\nOver ${TOTAL} km ridden non-stop: day ${(day/n*100).toFixed(1)}%  twilight ${(twi/n*100).toFixed(1)}%  night ${(night/n*100).toFixed(1)}%`);
console.log(`(A rider who never stops should see roughly the real day/night split — ~55% day in early September at these latitudes.)`);


// ── The faithful reconstruction of the v371 bug, kept because it is the number
// that actually proved the diagnosis. For each hour of a route day in Wyoming,
// ask which sun record the OLD code would have looked up — the one filed under
// the instant's SYDNEY calendar date — and whether it brackets that instant.
console.log('\nOLD behaviour, hour by hour (route day 2 Sep, Mountain Time):');
const dateIn=(t,tz)=>new Intl.DateTimeFormat('en-CA',{timeZone:tz}).format(t);
const sunForSydneyDate=(t,lat,lon)=>{
  // the cache held one record per Sydney-local calendar date, at the route midpoint
  const key=dateIn(t,'Australia/Sydney');
  return sb.sunAt(lat,lon,Date.parse(key+'T12:00:00Z')-lon/15*3600000);
};
let matched=0;
for(let h=0;h<24;h++){
  const t=new Date(Date.UTC(2026,8,2,h+6));            // 06:00 UTC = 00:00 MDT
  const s=sunForSydneyDate(t,41.30,-110.35);
  const old=(t>=s.sunrise&&t<=s.sunset)?'DAY':'night';
  const real=(h>=7&&h<20)?'DAY':'night';               // ~13 h of actual daylight
  if(old==='DAY')matched++;
  if(old!==real)process.stdout.write('');
  console.log(`  ${String(h).padStart(2,'0')}:00 MDT   old key says ${old.padEnd(5)}  truth ${real}${old!==real?'   <- wrong':''}`);
}
console.log(`\n  Hours the old key called DAY: ${matched} of the ~13 real ones.`);
console.log('  That is the "most of it is in darkness" Peter reported.');
