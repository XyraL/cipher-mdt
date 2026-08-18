// Second escaping pass: the `${obj.field || fallback}` form.
//
// Split from tools/add-escaping.mjs because the two need different confidence.
// The first pass rewrites bare `${obj.field}`; this one covers the very common
// "field or a default" idiom, which is equally safe to wrap — the whole
// expression still evaluates to one string headed for innerHTML.
//
// Event attributes are skipped here too. Escaping inside one does not protect
// it, since the attribute is HTML-decoded before its JS is parsed.
import { readFileSync, writeFileSync, globSync } from 'node:fs';

const FIELDS = [
  'name', 'notes', 'label', 'title', 'location', 'narrative', 'description',
  'officer_name', 'created_by_name', 'patient_name', 'civilian_name',
  'firstname', 'lastname', 'plate', 'reason', 'address', 'summary',
  'message', 'content', 'comment',
].join('|');

const RE = new RegExp(
  '\\$\\{([A-Za-z_$][\\w$]*\\.(?:' + FIELDS + ')\\s*\\|\\|\\s*[^}{]+?)\\}',
  'g',
);
const EVENT_ATTR = /on\w+="[^"]*"/g;

let total = 0;
const rows = [];

for (const file of globSync('html/js/**/*.js', { cwd: process.cwd() })) {
  const src = readFileSync(file, 'utf8');
  let n = 0;

  const out = src.split('\n').map((line) => {
    const skip = [];
    for (const m of line.matchAll(EVENT_ATTR)) skip.push([m.index, m.index + m[0].length]);

    return line.replace(RE, (match, inner, offset) => {
      if (skip.some((r) => offset >= r[0] && offset < r[1])) return match;
      if (inner.indexOf('esc(') !== -1) return match;
      n++;
      return '${esc(' + inner + ')}';
    });
  }).join('\n');

  if (n) {
    writeFileSync(file, out);
    rows.push([file, n]);
    total += n;
  }
}

for (const [file, n] of rows.sort((a, b) => b[1] - a[1])) {
  console.log('  ' + String(n).padStart(3) + '  ' + file);
}
console.log('\n  ' + total + ' wrapped.');
