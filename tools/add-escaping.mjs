// One-shot codemod: wraps player-supplied fields in esc() before they reach
// innerHTML.
//
// Deliberately conservative. It rewrites only the simple, unambiguous form
// `${obj.field}` where `field` is a known free-text field, and only outside
// event attributes. Anything with an expression in it — `${a.x || 'y'}`,
// ternaries, nested calls — is left alone for a human to read, because that is
// where a blind rewrite would change behaviour rather than just escape it.
//
// Event attributes are skipped on purpose. An attribute is HTML-decoded before
// the JS inside it is parsed, so `&#39;` becomes a real quote again and
// escaping there provides no protection — those need delegation instead, which
// is a separate change.
import { readFileSync, writeFileSync } from 'node:fs';
import { globSync } from 'node:fs';

// Fields that hold something a person typed.
const FREE_TEXT = [
  'name', 'notes', 'label', 'title', 'location', 'narrative', 'description',
  'officer_name', 'created_by_name', 'patient_name', 'civilian_name',
  'firstname', 'lastname', 'plate', 'tag', 'owner', 'reason', 'address',
  'summary', 'message', 'content', 'comment', 'model', 'make', 'query',
];

const FIELD_RE = new RegExp(`\\$\\{([A-Za-z_$][\\w$]*)\\.(${FREE_TEXT.join('|')})\\}`, 'g');
const EVENT_ATTR_RE = /on\w+="[^"]*"/g;

const files = globSync('html/js/**/*.js', { cwd: process.cwd() });
let total = 0;
const perFile = [];

for (const file of files) {
  const src = readFileSync(file, 'utf8');
  let count = 0;

  const out = src.split('\n').map((line) => {
    // Ranges covered by event attributes on this line; matches inside them are
    // left untouched.
    const skip = [];
    for (const m of line.matchAll(EVENT_ATTR_RE)) skip.push([m.index, m.index + m[0].length]);
    const inSkip = (i) => skip.some(([a, b]) => i >= a && i < b);

    return line.replace(FIELD_RE, (match, obj, field, offset) => {
      if (inSkip(offset)) return match;
      count++;
      return `\${esc(${obj}.${field})}`;
    });
  }).join('\n');

  if (count) {
    writeFileSync(file, out);
    perFile.push([file, count]);
    total += count;
  }
}

for (const [file, count] of perFile.sort((a, b) => b[1] - a[1])) {
  console.log(`  ${String(count).padStart(3)}  ${file}`);
}
console.log(`\n  ${total} interpolations wrapped across ${perFile.length} files.`);
