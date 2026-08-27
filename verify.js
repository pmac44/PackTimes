#!/usr/bin/env node
// PackTimes — the standing pre-push verification, as a script.
//
// Run:  node verify.js            (from the project folder)
// Exit: 0 = everything passed, 1 = something failed. Safe to wire into push.bat.
//
// This encodes the rule CLAUDE.md has repeated by hand since ~v176: assert the file still ends
// </html> FIRST, then node --check every inline script block, then the CSS braces. It exists
// because on 27 Aug 2026 the machine turned out to have no node and no python at all, the rule
// could not be run for three consecutive versions, and the checks were re-derived from scratch
// each time. Install node with:  winget install OpenJS.NodeJS.LTS
//
// ⚠ The </html> assert runs FIRST and deliberately. A truncated write is the failure mode that
// makes every other check meaningless — a half-written file can still have balanced braces in
// the part that survived.
//
// ⚠ Do NOT add a naive /* vs */ counter for the JS. It was tried and it FALSELY FAILS: a regex
// literal ending in a quantifier, e.g. /[-_ ]*/, closes with the two characters `*/`. There is
// one in the date-prefix stripper (~line 21069 of the big block) and it made the count read
// 9/10. `node --check` already catches an unterminated block comment definitively, so the JS
// side needs nothing more. The CSS side does need it — nothing else parses CSS here.

const fs = require('fs');
const cp = require('child_process');
const path = require('path');
const os = require('os');

const FILE = process.argv[2] || path.join(__dirname, 'index.html');
let fail = 0;
const pass = (name, ok, detail) => {
  console.log((ok ? '  PASS  ' : '  FAIL  ') + name + (detail ? '  — ' + detail : ''));
  if (!ok) fail++;
};

if (!fs.existsSync(FILE)) { console.error('no such file: ' + FILE); process.exit(1); }
const src = fs.readFileSync(FILE, 'utf8');

console.log('PackTimes verify — ' + path.basename(FILE));

// 1 ── ends </html>. FIRST, always.
pass('ends </html> (asserted FIRST)', /<\/html>\s*$/.test(src),
     'tail ' + JSON.stringify(src.slice(-22)));

const lines = src.split('\n').length;
const ver = (src.match(/window\.APP_VERSION\s*=\s*'([^']+)'/) || [])[1] || '(none)';
console.log('  ' + lines.toLocaleString() + ' lines, ' +
            (src.length / 1048576).toFixed(2) + ' MB, APP_VERSION ' + ver);

// 2 ── node --check every inline script block.
// Skips <script src=...> (nothing inline to check). Blocks are written to temp files because
// --check needs a path.
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'ptverify-'));
const blockRe = /<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g;
let m, n = 0, broken = [];
while ((m = blockRe.exec(src))) {
  n++;
  const p = path.join(tmp, 'block' + n + '.js');
  fs.writeFileSync(p, m[1]);
  try {
    cp.execFileSync(process.execPath, ['--check', p], { stdio: 'pipe' });
  } catch (e) {
    const msg = String(e.stderr || e.message).split('\n').slice(0, 4).join(' ').trim();
    broken.push('block ' + n + ' → ' + msg);
  }
}
pass(n + ' inline script block(s) node --check clean', broken.length === 0, broken.join(' | '));

// 3 ── CSS braces, counted only inside <style>. node can't help here.
let css = '', sm, styleRe = /<style[^>]*>([\s\S]*?)<\/style>/g;
while ((sm = styleRe.exec(src))) css += sm[1];
const open = (css.match(/\{/g) || []).length, close = (css.match(/\}/g) || []).length;
pass('CSS braces balanced', open === close, open + '/' + close);

// 4 ── CSS block comments. Same reasoning — nothing else parses CSS, and CSS has no regex
// literals, so the naive count is actually sound here.
const co = (css.match(/\/\*/g) || []).length, cc = (css.match(/\*\//g) || []).length;
pass('CSS comment pairs closed', co === cc, co + '/' + cc);

try { fs.rmSync(tmp, { recursive: true, force: true }); } catch (e) { /* temp dir, never fatal */ }

console.log(fail ? '\nRESULT: ' + fail + ' FAILED — do not push' : '\nRESULT: all checks passed');
process.exit(fail ? 1 : 0);
