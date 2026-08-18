// Finds top-level names declared in more than one script loaded into the same
// page.
//
// These files are classic scripts, not modules, so there is no per-file scope:
// every top-level `function`, `const`, `let` and `var` lands in one shared
// namespace. Two files declaring the same name is not a warning, it is a bug —
// and the two forms fail differently, which is why it keeps being missed:
//
//   function f(){}   the later file silently wins; no error, wrong code runs
//   const f = ...    a load-time SyntaxError that kills the whole panel
//
// This repo has had both. `renderArrestsList` was declared in civilians.js and
// records.js; records.js loaded second, so the civilian profile silently
// rendered with the records-panel layout.
//
//   node tools/check-globals.mjs        exits non-zero if anything collides
import { readFileSync } from 'node:fs';
import { globSync } from 'node:fs';

const pages = globSync('html/*.html', { cwd: process.cwd() });
let failures = 0;

for (const page of pages) {
  const html = readFileSync(page, 'utf8');

  // Script order matters: the last declaration of a name is the one that wins.
  const files = [...html.matchAll(/<script src="([^"]+)"/g)].map((m) => m[1])
    .filter((src) => !src.startsWith('http'));

  const seen = new Map();
  const collisions = new Map();

  for (const src of files) {
    let code;
    try {
      code = readFileSync(new URL(src, `file:///${process.cwd().replace(/\\/g, '/')}/html/`), 'utf8');
    } catch {
      continue;
    }

    // Top-level only — anything indented is inside a function or block and has
    // its own scope.
    const names = new Set();
    for (const m of code.matchAll(/^(?:function|const|let|var)\s+([A-Za-z_$][\w$]*)/gm)) {
      names.add(m[1]);
    }

    for (const name of names) {
      if (seen.has(name)) {
        const list = collisions.get(name) || [seen.get(name)];
        list.push(src);
        collisions.set(name, list);
      }
      seen.set(name, src);
    }
  }

  if (collisions.size) {
    console.log(`\n${page}`);
    for (const [name, files] of collisions) {
      console.log(`  ${name}  —  ${files.join('  →  ')}   (last wins)`);
      failures++;
    }
  }
}

if (failures) {
  console.log(`\n${failures} colliding name${failures === 1 ? '' : 's'}.`);
  process.exit(1);
}

console.log(`No colliding top-level names across ${pages.length} page${pages.length === 1 ? '' : 's'}.`);
