// Balances Lua block keywords across the resource.
//
// There is no Lua interpreter in this dev environment, so a typo in a .lua file
// is not found until FiveM refuses to start the resource. This will not catch
// every syntax error — it is not a parser — but it reliably catches the one
// that actually happens when editing at scale: a block left unclosed, or an
// `end` too many after a bad patch.
//
//   node tools/check-lua-blocks.mjs
import { readFileSync, globSync } from 'node:fs';

// Order matters: long brackets are stripped before line comments, or a `--`
// inside a [[ ]] string would truncate it.
function strip(src) {
  let s = src;
  s = s.replace(/--\[(=*)\[[\s\S]*?\]\1\]/g, ' ');   // long comments
  s = s.replace(/\[(=*)\[[\s\S]*?\]\1\]/g, ' "" ');  // long strings
  s = s.replace(/--[^\n]*/g, ' ');                   // line comments
  s = s.replace(/\\./g, ' ');                        // escapes, before quotes
  s = s.replace(/"[^"\n]*"/g, ' "" ');
  s = s.replace(/'[^'\n]*'/g, " '' ");
  return s;
}

const count = (s, word) => (s.match(new RegExp('\\b' + word + '\\b', 'g')) || []).length;

let bad = 0;
const files = globSync('{server,client}/*.lua', { cwd: process.cwd() });

for (const file of files.sort()) {
  const s = strip(readFileSync(file, 'utf8'));

  // `for` and `while` are not counted: each is followed by its own `do`, which
  // is the keyword that actually opens the block.
  const opens = count(s, 'function') + count(s, 'if') + count(s, 'do') + count(s, 'repeat');
  const closes = count(s, 'end') + count(s, 'until');

  // No elseif adjustment is needed, despite looking like it should be: \bif\b
  // does not match inside "elseif", because the preceding "e" is a word
  // character. Subtracting them removes blocks that were never counted, and
  // reports every healthy file with an elseif in it as broken.
  const expected = opens;

  if (expected !== closes) {
    console.log(`  ${file}`);
    console.log(`      opens ${expected}  closes ${closes}  (off by ${expected - closes})`);
    bad++;
  }
}

if (bad) {
  console.log(`\n  ${bad} file(s) look unbalanced.`);
  process.exit(1);
}
console.log(`  ${files.length} Lua files balanced.`);
