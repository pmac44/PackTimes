// Run this in your PackTimes folder: node patch_gear.js
var fs = require('fs');
var file = 'index.html';
var html = fs.readFileSync(file, 'utf8');

// Check if already patched
if (html.includes('DEFAULT_GEAR')) {
  console.log('Gear checklist code already present. No changes made.');
  process.exit(0);
}

var changes = 0;

// 1. Add foodSubTab to UI state
var uiEnd = "simPaused:false};";
if (html.includes(uiEnd)) {
  html = html.replace(uiEnd, "simPaused:false,foodSubTab:'food'};");
  changes++;
  console.log('[1] Added foodSubTab to UI state');
}

// 2. Add foodSubTab to saveAll persistence
var saveMatch = "tab:UI.tab}).catch";
if (html.includes(saveMatch)) {
  html = html.replace(saveMatch, "tab:UI.tab,foodSubTab:UI.foodSubTab}).catch");
  changes++;
  console.log('[2] Added foodSubTab to saveAll');
}

// 3. Add foodSubTab to loadAll
var loadMatch = "if(prefs.tab)UI.tab=prefs.tab;";
if (html.includes(loadMatch) && !html.includes('prefs.foodSubTab')) {
  html = html.replace(loadMatch, loadMatch + "\n    if(prefs.foodSubTab)UI.foodSubTab=prefs.foodSubTab;");
  changes++;
  console.log('[3] Added foodSubTab to loadAll');
}

// 4. Rename Food tab to Supplies
if (html.includes("label:'Food'}")) {
  html = html.replace("label:'Food'}", "label:'Supplies'}");
  changes++;
  console.log('[4] Renamed Food tab to Supplies');
} else if (html.includes("label:'Supplies'}")) {
  changes++;
  console.log('[4] Tab already named Supplies');
}

// 5. Insert gear functions before tFood
var tFoodIdx = html.indexOf("function tFood(r){");
if (tFoodIdx === -1) {
  console.log('ERROR: Cannot find tFood function');
  process.exit(1);
}

var gearLines = [];
gearLines.push('');
gearLines.push('// --- Default bikepacking gear checklist ---');
gearLines.push('var DEFAULT_GEAR=[');
gearLines.push("  {cat:'Bike',items:['Bike (checked & tuned)','Frame bag','Seat pack / saddle bag','Handlebar bag / roll','Top tube bag','Stem bag / feed bag','Water bottle cages','Bike computer / GPS']},");
gearLines.push("  {cat:'Tools & Spares',items:['Multi-tool','Tyre levers','Spare inner tubes','Patch kit','Mini pump / CO2 inflator','Chain breaker + quick links','Spare brake pads','Spare derailleur hanger','Spoke wrench','Zip ties & electrical tape','Chain lube']},");
gearLines.push("  {cat:'Navigation & Electronics',items:['Phone + mount','Battery pack / power bank','Charging cables','Front light','Rear light','Spare batteries / backup light','Offline maps downloaded']},");
gearLines.push("  {cat:'Sleep System',items:['Bivvy bag or tent','Sleeping bag / quilt','Sleeping mat','Pillow (inflatable / stuff sack)']},");
gearLines.push("  {cat:'Clothing \\u2013 Riding',items:['Cycling shorts / bibs','Cycling jersey(s)','Base layer','Arm warmers / leg warmers','Cycling gloves','Helmet','Cycling shoes','Socks']},");
gearLines.push("  {cat:'Clothing \\u2013 Weather',items:['Rain jacket','Rain pants / leg covers','Gilet / wind vest','Warm layer (fleece / down)','Buff / neck gaiter','Skull cap / beanie','Overshoes / shoe covers','Waterproof gloves']},");
gearLines.push("  {cat:'Clothing \\u2013 Off-Bike',items:['Casual shorts / pants','T-shirt / top','Thongs / sandals','Warm hat / beanie']},");
gearLines.push("  {cat:'Food & Water',items:['Water bottles','Water filter / purification','Snacks & energy bars','Electrolyte tabs','Stove + fuel (if cooking)','Pot / mug','Spork']},");
gearLines.push("  {cat:'Personal & Safety',items:['Sunscreen','Chamois cream','Lip balm','Toothbrush + toothpaste','ID & cards & cash','First aid kit','Emergency blanket','Whistle','Insect repellent','Sunglasses','Ear plugs']}");
gearLines.push('];');
gearLines.push('');
gearLines.push('function getGearChecklist(r){');
gearLines.push('  if(r.gearChecklist)return r.gearChecklist;');
gearLines.push('  var list=[];');
gearLines.push('  DEFAULT_GEAR.forEach(function(g){');
gearLines.push('    g.items.forEach(function(name){');
gearLines.push('      list.push({id:makeStopId(),cat:g.cat,name:name,bring:false,packed:false,custom:false});');
gearLines.push('    });');
gearLines.push('  });');
gearLines.push('  r.gearChecklist=list;');
gearLines.push('  return list;');
gearLines.push('}');
gearLines.push('');
gearLines.push('function tGear(r){');
gearLines.push('  var gear=getGearChecklist(r);');
gearLines.push('  var cats=[...new Set(gear.map(function(g){return g.cat;}))];');
gearLines.push('  var bringCount=gear.filter(function(g){return g.bring;}).length;');
gearLines.push('  var packedCount=gear.filter(function(g){return g.packed;}).length;');
gearLines.push('');
gearLines.push('  var html=\'<div style="margin-bottom:12px;">\';');
gearLines.push('  html+=\'<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:10px;">\'');
gearLines.push('    +\'<div style="font-size:14px;color:var(--text3);font-family:var(--font);">\'');
gearLines.push('    +\'<span style="color:var(--accent);font-weight:600;">\'+bringCount+\'</span> bringing \\u00b7 <span style="color:#fbbf24;font-weight:600;">\'+packedCount+\'</span> packed\'');
gearLines.push('    +\'</div>\'');
gearLines.push('    +\'<div style="display:flex;gap:6px;">\'');
gearLines.push('    +\'<button class="btn btn-sm" id="gear-reset" style="font-size:12px;">Reset list</button>\'');
gearLines.push('    +\'</div>\'');
gearLines.push('    +\'</div>\';');
gearLines.push('');
gearLines.push('  html+=\'<div style="display:flex;gap:6px;margin-bottom:12px;">\'');
gearLines.push('    +\'<select id="gear-add-cat" class="inp" style="flex:0 0 auto;width:140px;font-size:14px;padding:6px 8px;">\'');
gearLines.push('    +cats.map(function(c){return\'<option value="\'+c+\'">\'+c+\'</option>\';}).join(\'\')');
gearLines.push('    +\'<option value="__new">+ New category</option></select>\'');
gearLines.push('    +\'<input id="gear-add-name" type="text" class="inp" placeholder="Add item..." style="flex:1;font-size:14px;padding:6px 8px;">\'');
gearLines.push('    +\'<button class="btn btn-p btn-sm" id="gear-add-btn" style="flex-shrink:0;">+</button>\'');
gearLines.push('    +\'</div>\';');
gearLines.push('');
gearLines.push('  cats.forEach(function(cat){');
gearLines.push('    var items=gear.filter(function(g){return g.cat===cat;});');
gearLines.push('    var catBring=items.filter(function(g){return g.bring;}).length;');
gearLines.push('    var catPacked=items.filter(function(g){return g.packed;}).length;');
gearLines.push('    html+=\'<div style="margin-bottom:8px;">\'');
gearLines.push('      +\'<div style="display:flex;align-items:center;gap:8px;padding:8px 0 4px;border-bottom:1px solid var(--border);">\'');
gearLines.push('      +\'<span style="font-size:14px;font-weight:600;color:var(--accent);font-family:var(--font);text-transform:uppercase;letter-spacing:.5px;flex:1;">\'+cat+\'</span>\'');
gearLines.push('      +\'<span style="font-size:12px;color:var(--text3);font-family:var(--font);">\'+catBring+\'/\'+items.length+\' \\u00b7 \'+catPacked+\' packed</span>\'');
gearLines.push('      +\'</div><div>\';');
gearLines.push('    items.forEach(function(g){');
gearLines.push('      var bc=g.bring?\'checked\':\'\';');
gearLines.push('      var pc=g.packed?\'checked\':\'\';');
gearLines.push('      var ds=!g.bring?\'opacity:0.45;\':\'\';');
gearLines.push('      html+=\'<div class="gear-row" data-gid="\'+g.id+\'" style="display:flex;align-items:center;gap:8px;padding:6px 4px;border-bottom:1px solid var(--bg3);\'+ds+\'">\'');
gearLines.push('        +\'<label style="display:flex;align-items:center;cursor:pointer;flex-shrink:0;" title="Bring">\'');
gearLines.push('        +\'<input type="checkbox" class="gear-bring" data-gid="\'+g.id+\'" \'+bc+\' style="accent-color:var(--accent);width:18px;height:18px;">\'');
gearLines.push('        +\'</label>\'');
gearLines.push('        +\'<label style="display:flex;align-items:center;cursor:pointer;flex-shrink:0;" title="Packed">\'');
gearLines.push('        +\'<input type="checkbox" class="gear-packed" data-gid="\'+g.id+\'" \'+pc+\' \'+(g.bring?\'\':\'disabled\')+\' style="accent-color:#fbbf24;width:18px;height:18px;">\'');
gearLines.push('        +\'</label>\'');
gearLines.push('        +\'<span style="flex:1;font-size:15px;color:\'+(g.bring?\'var(--text)\':\'var(--text3)\')+\';min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;">\'+g.name+\'</span>\'');
gearLines.push('        +(g.custom?\'<button class="gear-del" data-gid="\'+g.id+\'" style="background:none;border:none;color:var(--text3);cursor:pointer;font-size:16px;padding:2px 6px;" title="Remove">\\u2715</button>\':\'\')+\'</div>\';');
gearLines.push('    });');
gearLines.push('    html+=\'</div></div>\';');
gearLines.push('  });');
gearLines.push('  html+=\'</div>\';');
gearLines.push('  html+=\'<div style="display:flex;gap:16px;padding:8px 4px;font-size:13px;color:var(--text3);">\'');
gearLines.push('    +\'<span><span style="color:var(--accent);">&#9745;</span> = bringing</span>\'');
gearLines.push('    +\'<span><span style="color:#fbbf24;">&#9745;</span> = packed</span>\'');
gearLines.push('    +\'</div>\';');
gearLines.push('  return html;');
gearLines.push('}');
gearLines.push('');

var gearBlock = gearLines.join('\n');
html = html.slice(0, tFoodIdx) + gearBlock + html.slice(tFoodIdx);
changes++;
console.log('[5] Inserted gear functions');

// 6. Add sub-tab bar to tFood
var newTFoodIdx = html.indexOf("function tFood(r){", tFoodIdx + gearBlock.length);
var afterBrace = newTFoodIdx + "function tFood(r){".length;
var nextNL = html.indexOf('\n', afterBrace);

var stb = '\n'
  + "  var subTab=UI.foodSubTab||'food';\n"
  + '  var _html=\'<div style="display:flex;gap:0;margin-bottom:12px;border-bottom:2px solid var(--border);">\';\n'
  + '  _html+=\'<button class="food-sub-tab" data-foodtab="food" style="flex:1;padding:8px 4px;background:none;border:none;border-bottom:2px solid \'+(subTab===\'food\'?\'var(--accent)\':\'transparent\')+\';color:\'+(subTab===\'food\'?\'var(--accent)\':\'var(--text3)\')+\';font-family:var(--sans);font-size:15px;font-weight:600;cursor:pointer;margin-bottom:-2px;display:flex;align-items:center;justify-content:center;gap:6px;"><svg viewBox="0 0 18 18" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" style="flex-shrink:0;"><line x1="5" y1="2" x2="5" y2="7"/><path d="M3 2v4a2 2 0 0 0 4 0V2"/><line x1="5" y1="9" x2="5" y2="16"/><line x1="13" y1="2" x2="13" y2="16"/><path d="M10 2c0 0 3 1.5 3 5"/></svg>Food</button>\';\n'
  + '  _html+=\'<button class="food-sub-tab" data-foodtab="gear" style="flex:1;padding:8px 4px;background:none;border:none;border-bottom:2px solid \'+(subTab===\'gear\'?\'var(--accent)\':\'transparent\')+\';color:\'+(subTab===\'gear\'?\'var(--accent)\':\'var(--text3)\')+\';font-family:var(--sans);font-size:15px;font-weight:600;cursor:pointer;margin-bottom:-2px;display:flex;align-items:center;justify-content:center;gap:6px;"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="flex-shrink:0;"><path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"/><line x1="3" y1="6" x2="21" y2="6"/><path d="M16 10a4 4 0 0 1-8 0"/></svg>Gear</button>\';\n'
  + "  _html+='</div>';\n"
  + "  if(subTab==='gear'){return _html+tGear(r);}\n"
  + "  // Original food content below\n";

html = html.slice(0, afterBrace) + stb + html.slice(nextNL);
changes++;
console.log('[6] Added sub-tab bar to tFood');

// 7. Add gear click handlers after btn-go-food
var goFood = "if(e.target.closest('#btn-go-food')){UI.tab='food';render();return;}";
if (html.includes(goFood)) {
  var replacement = "if(e.target.closest('#btn-go-food')){UI.tab='food';UI.foodSubTab='food';render();return;}\n"
    + "\n"
    + "  // --- Gear checklist click handlers ---\n"
    + "  if(e.target.closest('.food-sub-tab')){\n"
    + "    var _btn=e.target.closest('.food-sub-tab');\n"
    + "    UI.foodSubTab=_btn.dataset.foodtab||'food';\n"
    + "    saveAll();render();return;\n"
    + "  }\n"
    + "  if(e.target.closest('#gear-add-btn')){\n"
    + "    var _r=cur();if(!_r)return;\n"
    + "    var _nameInp=document.getElementById('gear-add-name');\n"
    + "    var _catSel=document.getElementById('gear-add-cat');\n"
    + "    if(!_nameInp||!_catSel)return;\n"
    + "    var _name=_nameInp.value.trim();if(!_name)return;\n"
    + "    var _cat=_catSel.value;\n"
    + "    if(_cat==='__new'){\n"
    + "      _cat=prompt('New category name:');\n"
    + "      if(!_cat||!_cat.trim())return;\n"
    + "      _cat=_cat.trim();\n"
    + "    }\n"
    + "    var _gear=getGearChecklist(_r);\n"
    + "    _gear.push({id:makeStopId(),cat:_cat,name:_name,bring:true,packed:false,custom:true});\n"
    + "    saveAll();render();return;\n"
    + "  }\n"
    + "  if(e.target.closest('.gear-del')){\n"
    + "    var _btn2=e.target.closest('.gear-del');\n"
    + "    var _gid=_btn2.dataset.gid;\n"
    + "    var _r2=cur();if(!_r2)return;\n"
    + "    var _gear2=getGearChecklist(_r2);\n"
    + "    var _idx=_gear2.findIndex(function(g){return g.id===_gid;});\n"
    + "    if(_idx>=0){_gear2.splice(_idx,1);saveAll();render();}\n"
    + "    return;\n"
    + "  }\n"
    + "  if(e.target.closest('#gear-reset')){\n"
    + "    if(!confirm('Reset gear list to defaults? Custom items will be removed.'))return;\n"
    + "    var _r3=cur();if(!_r3)return;\n"
    + "    _r3.gearChecklist=null;\n"
    + "    getGearChecklist(_r3);\n"
    + "    saveAll();render();return;\n"
    + "  }";
  html = html.replace(goFood, replacement);
  changes++;
  console.log('[7] Added gear click handlers');
}

// 8. Add gear change handlers
var changeAnchor = "const r=cur();if(!r)return;\n  if(e.target.id==='inp-date')";
var changeIdx = html.indexOf(changeAnchor);
if (changeIdx !== -1) {
  var insertAt = changeIdx + "const r=cur();if(!r)return;".length;
  var gearChangeCode = "\n\n"
    + "  // --- Gear checklist change handlers ---\n"
    + "  if(e.target.classList.contains('gear-bring')){\n"
    + "    var _gid=e.target.dataset.gid;\n"
    + "    var _gear=getGearChecklist(r);\n"
    + "    var _item=_gear.find(function(g){return g.id===_gid;});\n"
    + "    if(_item){\n"
    + "      _item.bring=e.target.checked;\n"
    + "      if(!_item.bring)_item.packed=false;\n"
    + "      saveAll();render();\n"
    + "    }\n"
    + "    return;\n"
    + "  }\n"
    + "  if(e.target.classList.contains('gear-packed')){\n"
    + "    var _gid2=e.target.dataset.gid;\n"
    + "    var _gear2=getGearChecklist(r);\n"
    + "    var _item2=_gear2.find(function(g){return g.id===_gid2;});\n"
    + "    if(_item2){\n"
    + "      _item2.packed=e.target.checked;\n"
    + "      saveAll();render();\n"
    + "    }\n"
    + "    return;\n"
    + "  }\n";
  html = html.slice(0, insertAt) + gearChangeCode + html.slice(insertAt);
  changes++;
  console.log('[8] Added gear change handlers');
}

// BONUS: Remove hotel emoji
while (html.indexOf('\uD83C\uDFE8 Accommodation Search') !== -1) {
  html = html.replace('\uD83C\uDFE8 Accommodation Search', 'Accommodation Search');
  console.log('[+] Removed hotel emoji');
}

// Write result
fs.writeFileSync(file, html, 'utf8');
var newSize = fs.statSync(file).size;
console.log('\nDone! ' + changes + ' changes applied.');
console.log('New file size: ' + (newSize/1024).toFixed(0) + 'KB');
console.log('Now run push.bat to deploy.');
