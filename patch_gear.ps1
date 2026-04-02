# Run this in PowerShell from your PackTimes folder:
#   powershell -ExecutionPolicy Bypass -File patch_gear.ps1

$file = "index.html"
$html = [System.IO.File]::ReadAllText((Resolve-Path $file).Path)

if ($html.Contains("DEFAULT_GEAR")) {
    Write-Host "Gear checklist code already present. No changes made."
    exit
}

$changes = 0

# 1. Add foodSubTab to UI state
$old1 = "simPaused:false};"
$new1 = "simPaused:false,foodSubTab:'food'};"
if ($html.Contains($old1)) {
    $html = $html.Replace($old1, $new1)
    $changes++
    Write-Host "[1] Added foodSubTab to UI state"
}

# 2. Add foodSubTab to saveAll
$old2 = "tab:UI.tab}).catch"
$new2 = "tab:UI.tab,foodSubTab:UI.foodSubTab}).catch"
if ($html.Contains($old2)) {
    $html = $html.Replace($old2, $new2)
    $changes++
    Write-Host "[2] Added foodSubTab to saveAll"
}

# 3. Add foodSubTab to loadAll
$old3 = "if(prefs.tab)UI.tab=prefs.tab;"
if ($html.Contains($old3) -and -not $html.Contains("prefs.foodSubTab")) {
    $html = $html.Replace($old3, "$old3`n    if(prefs.foodSubTab)UI.foodSubTab=prefs.foodSubTab;")
    $changes++
    Write-Host "[3] Added foodSubTab to loadAll"
}

# 4. Rename Food tab to Supplies
if ($html.Contains("label:'Food'}")) {
    $html = $html.Replace("label:'Food'}", "label:'Supplies'}")
    $changes++
    Write-Host "[4] Renamed Food tab to Supplies"
} elseif ($html.Contains("label:'Supplies'}")) {
    $changes++
    Write-Host "[4] Tab already named Supplies"
}

# 5. Insert gear functions before tFood
$marker = "function tFood(r){"
$idx = $html.IndexOf($marker)
if ($idx -eq -1) {
    Write-Host "ERROR: Cannot find tFood function"
    exit
}

$gearBlock = @'

// --- Default bikepacking gear checklist ---
var DEFAULT_GEAR=[
  {cat:'Bike',items:['Bike (checked & tuned)','Frame bag','Seat pack / saddle bag','Handlebar bag / roll','Top tube bag','Stem bag / feed bag','Water bottle cages','Bike computer / GPS']},
  {cat:'Tools & Spares',items:['Multi-tool','Tyre levers','Spare inner tubes','Patch kit','Mini pump / CO2 inflator','Chain breaker + quick links','Spare brake pads','Spare derailleur hanger','Spoke wrench','Zip ties & electrical tape','Chain lube']},
  {cat:'Navigation & Electronics',items:['Phone + mount','Battery pack / power bank','Charging cables','Front light','Rear light','Spare batteries / backup light','Offline maps downloaded']},
  {cat:'Sleep System',items:['Bivvy bag or tent','Sleeping bag / quilt','Sleeping mat','Pillow (inflatable / stuff sack)']},
  {cat:'Clothing \u2013 Riding',items:['Cycling shorts / bibs','Cycling jersey(s)','Base layer','Arm warmers / leg warmers','Cycling gloves','Helmet','Cycling shoes','Socks']},
  {cat:'Clothing \u2013 Weather',items:['Rain jacket','Rain pants / leg covers','Gilet / wind vest','Warm layer (fleece / down)','Buff / neck gaiter','Skull cap / beanie','Overshoes / shoe covers','Waterproof gloves']},
  {cat:'Clothing \u2013 Off-Bike',items:['Casual shorts / pants','T-shirt / top','Thongs / sandals','Warm hat / beanie']},
  {cat:'Food & Water',items:['Water bottles','Water filter / purification','Snacks & energy bars','Electrolyte tabs','Stove + fuel (if cooking)','Pot / mug','Spork']},
  {cat:'Personal & Safety',items:['Sunscreen','Chamois cream','Lip balm','Toothbrush + toothpaste','ID & cards & cash','First aid kit','Emergency blanket','Whistle','Insect repellent','Sunglasses','Ear plugs']}
];

function getGearChecklist(r){
  if(r.gearChecklist)return r.gearChecklist;
  var list=[];
  DEFAULT_GEAR.forEach(function(g){
    g.items.forEach(function(name){
      list.push({id:makeStopId(),cat:g.cat,name:name,bring:false,packed:false,custom:false});
    });
  });
  r.gearChecklist=list;
  return list;
}

function tGear(r){
  var gear=getGearChecklist(r);
  var cats=[...new Set(gear.map(function(g){return g.cat;}))];
  var bringCount=gear.filter(function(g){return g.bring;}).length;
  var packedCount=gear.filter(function(g){return g.packed;}).length;

  var html='<div style="margin-bottom:12px;">';
  html+='<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:10px;">'
    +'<div style="font-size:14px;color:var(--text3);font-family:var(--font);">'
    +'<span style="color:var(--accent);font-weight:600;">'+bringCount+'</span> bringing \u00b7 <span style="color:#fbbf24;font-weight:600;">'+packedCount+'</span> packed'
    +'</div>'
    +'<div style="display:flex;gap:6px;">'
    +'<button class="btn btn-sm" id="gear-reset" style="font-size:12px;">Reset list</button>'
    +'</div>'
    +'</div>';

  html+='<div style="display:flex;gap:6px;margin-bottom:12px;">'
    +'<select id="gear-add-cat" class="inp" style="flex:0 0 auto;width:140px;font-size:14px;padding:6px 8px;">'
    +cats.map(function(c){return'<option value="'+c+'">'+c+'</option>';}).join('')
    +'<option value="__new">+ New category</option></select>'
    +'<input id="gear-add-name" type="text" class="inp" placeholder="Add item..." style="flex:1;font-size:14px;padding:6px 8px;">'
    +'<button class="btn btn-p btn-sm" id="gear-add-btn" style="flex-shrink:0;">+</button>'
    +'</div>';

  cats.forEach(function(cat){
    var items=gear.filter(function(g){return g.cat===cat;});
    var catBring=items.filter(function(g){return g.bring;}).length;
    var catPacked=items.filter(function(g){return g.packed;}).length;
    html+='<div style="margin-bottom:8px;">'
      +'<div style="display:flex;align-items:center;gap:8px;padding:8px 0 4px;border-bottom:1px solid var(--border);">'
      +'<span style="font-size:14px;font-weight:600;color:var(--accent);font-family:var(--font);text-transform:uppercase;letter-spacing:.5px;flex:1;">'+cat+'</span>'
      +'<span style="font-size:12px;color:var(--text3);font-family:var(--font);">'+catBring+'/'+items.length+' \u00b7 '+catPacked+' packed</span>'
      +'</div><div>';
    items.forEach(function(g){
      var bc=g.bring?'checked':'';
      var pc=g.packed?'checked':'';
      var ds=!g.bring?'opacity:0.45;':'';
      html+='<div class="gear-row" data-gid="'+g.id+'" style="display:flex;align-items:center;gap:8px;padding:6px 4px;border-bottom:1px solid var(--bg3);'+ds+'">'
        +'<label style="display:flex;align-items:center;cursor:pointer;flex-shrink:0;" title="Bring">'
        +'<input type="checkbox" class="gear-bring" data-gid="'+g.id+'" '+bc+' style="accent-color:var(--accent);width:18px;height:18px;">'
        +'</label>'
        +'<label style="display:flex;align-items:center;cursor:pointer;flex-shrink:0;" title="Packed">'
        +'<input type="checkbox" class="gear-packed" data-gid="'+g.id+'" '+pc+' '+(g.bring?'':'disabled')+' style="accent-color:#fbbf24;width:18px;height:18px;">'
        +'</label>'
        +'<span style="flex:1;font-size:15px;color:'+(g.bring?'var(--text)':'var(--text3)')+';min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">'+g.name+'</span>'
        +(g.custom?'<button class="gear-del" data-gid="'+g.id+'" style="background:none;border:none;color:var(--text3);cursor:pointer;font-size:16px;padding:2px 6px;" title="Remove">\u2715</button>':'')+'</div>';
    });
    html+='</div></div>';
  });
  html+='</div>';
  html+='<div style="display:flex;gap:16px;padding:8px 4px;font-size:13px;color:var(--text3);">'
    +'<span><span style="color:var(--accent);">&#9745;</span> = bringing</span>'
    +'<span><span style="color:#fbbf24;">&#9745;</span> = packed</span>'
    +'</div>';
  return html;
}

'@

$html = $html.Insert($idx, $gearBlock)
$changes++
Write-Host "[5] Inserted gear functions"

# 6. Add sub-tab bar to tFood
$newIdx = $html.IndexOf("function tFood(r){", $idx + $gearBlock.Length)
$afterBrace = $newIdx + "function tFood(r){".Length
$nextNL = $html.IndexOf("`n", $afterBrace)

$stb = @"
`n  var subTab=UI.foodSubTab||'food';
  var _html='<div style="display:flex;gap:0;margin-bottom:12px;border-bottom:2px solid var(--border);">';
  _html+='<button class="food-sub-tab" data-foodtab="food" style="flex:1;padding:8px 4px;background:none;border:none;border-bottom:2px solid '+(subTab==='food'?'var(--accent)':'transparent')+';color:'+(subTab==='food'?'var(--accent)':'var(--text3)')+';font-family:var(--sans);font-size:15px;font-weight:600;cursor:pointer;margin-bottom:-2px;display:flex;align-items:center;justify-content:center;gap:6px;"><svg viewBox="0 0 18 18" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" style="flex-shrink:0;"><line x1="5" y1="2" x2="5" y2="7"/><path d="M3 2v4a2 2 0 0 0 4 0V2"/><line x1="5" y1="9" x2="5" y2="16"/><line x1="13" y1="2" x2="13" y2="16"/><path d="M10 2c0 0 3 1.5 3 5"/></svg>Food</button>';
  _html+='<button class="food-sub-tab" data-foodtab="gear" style="flex:1;padding:8px 4px;background:none;border:none;border-bottom:2px solid '+(subTab==='gear'?'var(--accent)':'transparent')+';color:'+(subTab==='gear'?'var(--accent)':'var(--text3)')+';font-family:var(--sans);font-size:15px;font-weight:600;cursor:pointer;margin-bottom:-2px;display:flex;align-items:center;justify-content:center;gap:6px;"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink:0;"><path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"/><line x1="3" y1="6" x2="21" y2="6"/><path d="M16 10a4 4 0 0 1-8 0"/></svg>Gear</button>';
  _html+='</div>';
  if(subTab==='gear'){return _html+tGear(r);}
  // Original food content below
"@

$html = $html.Remove($afterBrace, $nextNL - $afterBrace).Insert($afterBrace, $stb)
$changes++
Write-Host "[6] Added sub-tab bar to tFood"

# 7. Add gear click handlers
$goFood = "if(e.target.closest('#btn-go-food')){UI.tab='food';render();return;}"
if ($html.Contains($goFood)) {
    $clickHandlers = @"
if(e.target.closest('#btn-go-food')){UI.tab='food';UI.foodSubTab='food';render();return;}

  // --- Gear checklist click handlers ---
  if(e.target.closest('.food-sub-tab')){
    var _btn=e.target.closest('.food-sub-tab');
    UI.foodSubTab=_btn.dataset.foodtab||'food';
    saveAll();render();return;
  }
  if(e.target.closest('#gear-add-btn')){
    var _r=cur();if(!_r)return;
    var _nameInp=document.getElementById('gear-add-name');
    var _catSel=document.getElementById('gear-add-cat');
    if(!_nameInp||!_catSel)return;
    var _name=_nameInp.value.trim();if(!_name)return;
    var _cat=_catSel.value;
    if(_cat==='__new'){
      _cat=prompt('New category name:');
      if(!_cat||!_cat.trim())return;
      _cat=_cat.trim();
    }
    var _gear=getGearChecklist(_r);
    _gear.push({id:makeStopId(),cat:_cat,name:_name,bring:true,packed:false,custom:true});
    saveAll();render();return;
  }
  if(e.target.closest('.gear-del')){
    var _btn2=e.target.closest('.gear-del');
    var _gid=_btn2.dataset.gid;
    var _r2=cur();if(!_r2)return;
    var _gear2=getGearChecklist(_r2);
    var _idx=_gear2.findIndex(function(g){return g.id===_gid;});
    if(_idx>=0){_gear2.splice(_idx,1);saveAll();render();}
    return;
  }
  if(e.target.closest('#gear-reset')){
    if(!confirm('Reset gear list to defaults? Custom items will be removed.'))return;
    var _r3=cur();if(!_r3)return;
    _r3.gearChecklist=null;
    getGearChecklist(_r3);
    saveAll();render();return;
  }
"@
    $html = $html.Replace($goFood, $clickHandlers)
    $changes++
    Write-Host "[7] Added gear click handlers"
}

# 8. Add gear change handlers
$changeAnchor = "const r=cur();if(!r)return;" + "`n" + "  if(e.target.id==='inp-date')"
$changeIdx = $html.IndexOf($changeAnchor)
if ($changeIdx -ne -1) {
    $insertAt = $changeIdx + "const r=cur();if(!r)return;".Length
    $gearChange = @"


  // --- Gear checklist change handlers ---
  if(e.target.classList.contains('gear-bring')){
    var _gid=e.target.dataset.gid;
    var _gear=getGearChecklist(r);
    var _item=_gear.find(function(g){return g.id===_gid;});
    if(_item){
      _item.bring=e.target.checked;
      if(!_item.bring)_item.packed=false;
      saveAll();render();
    }
    return;
  }
  if(e.target.classList.contains('gear-packed')){
    var _gid2=e.target.dataset.gid;
    var _gear2=getGearChecklist(r);
    var _item2=_gear2.find(function(g){return g.id===_gid2;});
    if(_item2){
      _item2.packed=e.target.checked;
      saveAll();render();
    }
    return;
  }

"@
    $html = $html.Insert($insertAt, $gearChange)
    $changes++
    Write-Host "[8] Added gear change handlers"
}

# BONUS: Remove hotel emoji
$html = $html.Replace([char]0xD83C + [char]0xDFE8 + " Accommodation Search", "Accommodation Search")

# Write result
[System.IO.File]::WriteAllText((Resolve-Path $file).Path, $html)
$newSize = (Get-Item $file).Length
Write-Host "`nDone! $changes changes applied."
Write-Host "New file size: $([math]::Round($newSize/1024))KB"
Write-Host "Now run push.bat to deploy."
