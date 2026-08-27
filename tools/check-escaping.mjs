// Finds player-typed values interpolated into innerHTML without escaping.
//
// Counting how many times esc() appears tells you nothing on its own — a file
// with 100 esc() calls and 20 misses is still a file with 20 misses. This looks
// for the specific shape that matters: a field whose value came from a person,
// dropped into a template literal raw.
//
// It reports; it does not rewrite. A miss inside an event attribute needs
// delegation, not escaping, and only a human can tell those apart.
//
//   node tools/check-escaping.mjs [dir]
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';

// Fields that hold something a person typed. Ids, timestamps and enum values
// are left out deliberately — wrapping those is noise, not safety.
const FREE_TEXT = [
  'name', 'notes', 'label', 'title', 'location', 'narrative', 'description',
  'reason', 'message', 'comment', 'content', 'summary', 'address', 'plate',
  'firstname', 'lastname', 'username', 'author', 'text', 'body', 'query',
  'officer_name', 'created_by_name', 'admin_name', 'banned_by', 'player_name',
  'item', 'itemName', 'vehicle', 'model', 'job', 'gang',
].join('|');

// Checked by hand and genuinely safe.
//
// It lives here rather than as a comment on the line, because every one of
// these sits inside a template literal — a `//` there would render as text in
// the panel rather than being a comment.
//
// A checker that always reports the same known-safe lines is one people learn
// to ignore, and then it stops catching the real ones too. Each entry says why.
const ALLOW = [
  { match: '${PCR_PRIORITY[p].label}', why: 'PCR_PRIORITY is a const defined in that file' },
  { match: '${s.label}',               why: 'reads INCIDENT_STATUS_LABELS, a const in that file' },
  { match: "${data.vehicle.fuel ? Math.round(data.vehicle.fuel) + '%' : '—'}", why: 'a number' },
];

const root = process.argv[2] || 'html/js';

const files = [];
(function walk(dir) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) walk(p);
    else if (entry.name.endsWith('.js')) files.push(p);
  }
})(root);

// ${ ... field ... } where the expression does not mention an escaper.
const RE = new RegExp(
  '\\$\\{(?![^}]*\\b(?:esc|escAttr|escNum|escapeHtml)\\s*\\()[^}]*\\.(?:' + FREE_TEXT + ')\\b[^}]*\\}',
  'g',
);
const EVENT_ATTR = /on\w+\s*=\s*"[^"]*"/g;

let inText = 0;
let inAttr = 0;
const rows = [];

for (const file of files) {
  const lines = readFileSync(file, 'utf8').split('\n');

  lines.forEach((line, i) => {
    // Only lines that are building markup.
    if (!line.includes('${')) return;

    const attrRanges = [];
    for (const m of line.matchAll(EVENT_ATTR)) attrRanges.push([m.index, m.index + m[0].length]);

    for (const m of line.matchAll(RE)) {
      if (ALLOW.some((a) => a.match === m[0])) continue;

      const body = m[0].slice(2, -1);   // inside the ${ }

      // .length and friends are numbers; escaping a number is noise.
      if (/\.(?:length|size|count)\s*$/.test(body)) continue;

      // A comparison yields a literal class name, not the field's value.
      if (/[=!]==|\s<\s|\s>\s/.test(body)) continue;

      // `${helper(x.name)}` — the helper owns what it returns. Escaping here
      // would double-escape whatever it built.
      if (/^\s*[\w.$]+\s*\(/.test(body)) continue;

      // Already inside an enclosing esc(...) that opened earlier on this line.
      const before = line.slice(0, m.index);
      const opens = (before.match(/\b(?:esc|escAttr|escapeHtml)\s*\(/g) || []).length;
      const balance = (before.match(/\(/g) || []).length - (before.match(/\)/g) || []).length;
      if (opens > 0 && balance > 0) continue;

      const inEvent = attrRanges.some(([a, b]) => m.index >= a && m.index < b);
      if (inEvent) inAttr++; else inText++;
      rows.push({ file, line: i + 1, snippet: m[0].slice(0, 70), inEvent });
    }
  });
}

console.log(`  files scanned         : ${files.length}`);
console.log(`  unescaped in markup   : ${inText}   <- escape these`);
console.log(`  unescaped in handlers : ${inAttr}   <- these need delegation, not escaping`);

if (rows.length) {
  console.log('');
  for (const r of rows.filter((r) => !r.inEvent).slice(0, 40)) {
    console.log(`    ${r.file}:${r.line}  ${r.snippet}`);
  }
}

process.exit(inText > 0 ? 1 : 0);
