// PackTimes service worker — REAL FILE on purpose (v335). Do not inline this.
//
// HISTORY: this code used to live inside index.html as a template literal, wrapped in a
// Blob and registered via URL.createObjectURL(). Browsers REJECT blob: URLs for service
// worker scripts (spec-level: script URL must be http/https), the .catch(()=>{}) on
// register() swallowed the rejection, and so from March 2026 to v334 NO service worker
// ever registered — the app had no offline support at all. A service worker must be a
// real same-origin file. Keep it one forever.
//
// VERSIONING: index.html registers this as 'sw.js?v='+APP_VERSION. That query string is
// the ONLY version input here — bump window.APP_VERSION in index.html (STATE section)
// and nothing else. The changed URL makes the browser treat this as a new worker, which
// re-runs install (fresh cache) and the activate cleanup below.
const VERSION=new URL(self.location.href).searchParams.get('v')||'v0';
const CACHE='packtimes-'+VERSION;
const TILE_CACHE='packtimes-tiles-v1';
// This file sits next to index.html, so derive everything from our own URL — unlike the
// old inline version we never depend on how the page happened to be opened.
const BASE=self.location.href.split('?')[0].replace(/[^/]*$/,'');
const PAGE_URL=BASE+'index.html';
// Fonts are real files (v244, no longer base64 in the page), so the SW has to cache them
// itself or the app would fall back to a system font the moment you ride out of coverage.
const FONTS=['dm-sans-latin-400-normal.woff2','dm-sans-latin-500-normal.woff2',
             'dm-sans-latin-600-normal.woff2','dm-sans-latin-700-normal.woff2',
             'dm-mono-latin-400-normal.woff2','dm-mono-latin-500-normal.woff2',
             'archivo-latin-400-normal.woff2','archivo-latin-500-normal.woff2',
             'archivo-latin-600-normal.woff2','archivo-latin-700-normal.woff2',
             'ibm-plex-mono-latin-400-normal.woff2','ibm-plex-mono-latin-500-normal.woff2',
             'ibm-plex-mono-latin-600-normal.woff2','ibm-plex-mono-latin-700-normal.woff2',
             'space-grotesk-latin-400-normal.woff2','space-grotesk-latin-500-normal.woff2',
             'space-grotesk-latin-600-normal.woff2','space-grotesk-latin-700-normal.woff2']
             .map(f=>BASE+'fonts/'+f);

self.addEventListener('install',e=>{
  e.waitUntil((async()=>{
    try{
      const c=await caches.open(CACHE);
      // The page. cache:'reload' bypasses the HTTP cache so we get the freshly pushed
      // version from GitHub, not its 10-minute-stale copy.
      try{
        await c.add(new Request(PAGE_URL,{cache:'reload'}));
      }catch(err){
        // Network died during install (e.g. updating right as reception drops): carry
        // the page over from the previous version's cache. Without this, activate would
        // delete the old cache and leave the NEW one empty — an update could brick
        // offline mode until the next online open. Never let that happen.
        const old=await caches.match(PAGE_URL);
        if(old)await c.put(PAGE_URL,old.clone());
      }
      // Fonts — part of the shell, but a missing font must never fail the install.
      for(const u of FONTS){
        try{
          if(await c.match(u))continue;
          let res=null;
          try{res=await fetch(u);}catch(err){}
          if(res&&res.ok){await c.put(u,res.clone());continue;}
          const old=await caches.match(u);          // carry over from the old cache
          if(old)await c.put(u,old.clone());
        }catch(err){}
      }
    }catch(err){}
    await self.skipWaiting();
  })());
});

self.addEventListener('activate',e=>{
  // Clear old app caches but preserve the tile cache (user-downloaded maps).
  e.waitUntil(
    caches.keys().then(keys=>Promise.all(
      keys.filter(k=>k!==CACHE&&k!==TILE_CACHE).map(k=>caches.delete(k))
    )).then(()=>self.clients.claim())
  );
});

// index.html asks a waiting worker to take over immediately after an update.
// (The old inline worker was sent this message too but never listened for it.)
self.addEventListener('message',e=>{
  if(e.data&&e.data.type==='SKIP_WAITING')self.skipWaiting();
});

self.addEventListener('fetch',e=>{
  const url=new URL(e.request.url);
  // Only handle same-origin navigation and the page itself
  const isNavigate=e.request.mode==='navigate';
  const isPage=url.href===PAGE_URL||url.pathname===new URL(PAGE_URL).pathname;
  if(isNavigate||isPage){
    // Network-first, BUT with a hard 2-second leash (v245, actually live since v335).
    //
    // Why: with no mobile reception the radio does NOT fail fast — it sits there
    // trying for 30-60s before fetch() rejects, and the app can't paint until this
    // respondWith settles. So:
    //   - navigator.onLine false  → skip the network entirely, straight to cache.
    //   - otherwise               → race the network against a 2s timer. If the timer
    //                               wins and we have a cached copy, serve the cache NOW
    //                               and let the fetch keep running in the background to
    //                               refresh the cache for the NEXT open.
    // Trade-off (accepted): on a slow-but-working link a new push can land one open
    // later than before. On a good link the fetch beats the 2s and nothing changes.
    // cache:'no-cache' still forces revalidation with GitHub (beats the 10-min HTTP cache).
    const NET_LEASH_MS=2000;
    const fromCache=()=>caches.match(PAGE_URL).then(cached=>cached||new Response(
      '<h2>Loading PackTimes...</h2><p>Open the app from your home screen while online first to enable offline use.</p>',
      {headers:{'Content-Type':'text/html'}}
    ));
    if(!self.navigator.onLine){e.respondWith(fromCache());return;}
    // Kick the network off once; both the race and the background refresh share it.
    const net=fetch(e.request,{cache:'no-cache'}).then(res=>{
      if(res&&res.ok){
        const clone=res.clone();
        caches.open(CACHE).then(c=>c.put(PAGE_URL,clone));
      }
      return res;
    });
    // Keep the SW alive long enough to finish the background refresh even if we
    // already answered from cache.
    e.waitUntil(net.catch(()=>{}));
    const leash=new Promise(res=>setTimeout(()=>res(null),NET_LEASH_MS));
    e.respondWith(
      Promise.race([net.catch(()=>null),leash])
        .then(res=>res||fromCache())   // network too slow, or it failed → cache
        .catch(()=>fromCache())
    );
    return;
  }
  // Font files — cache-first. Part of the shell: must be there with no signal.
  if(url.origin===self.location.origin&&url.pathname.toLowerCase().endsWith('.woff2')){
    e.respondWith(
      caches.open(CACHE).then(c=>
        c.match(e.request).then(cached=>cached||fetch(e.request).then(res=>{
          if(res&&res.ok)c.put(e.request,res.clone());
          return res;
        }).catch(()=>new Response('',{status:404})))
      )
    );
    return;
  }
  // Tile requests — cache-first for offline map use
  const TILE_HOSTS=['tile.openstreetmap.org','server.arcgisonline.com','tile-cyclosm.openstreetmap.fr','a.tile-cyclosm.openstreetmap.fr','tile.opentopomap.org'];
  if(TILE_HOSTS.some(h=>url.hostname.includes(h))){
    e.respondWith(
      caches.open(TILE_CACHE).then(c=>
        c.match(e.request).then(cached=>{
          if(cached)return cached;
          return fetch(e.request).then(res=>{
            if(res&&res.ok)c.put(e.request,res.clone());
            return res;
          }).catch(()=>new Response('',{status:404}));
        })
      )
    );
    return;
  }
  // All other requests (weather, Overpass, Strava, …) — let them go to network normally.
});
