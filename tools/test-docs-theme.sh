#!/usr/bin/env bash
# The docs/ site takes its look from the sprue.works brand theme
# (https://sprue.works/brand/v1/theme.css; usage notes in brand/README.md of
# sprue-works/website). This check keeps that adoption honest, and keeps the
# legal pages' wording pinned while OAuth verification reviews them:
#
#   - every docs/*.html links the theme, then site.css, in that order, and
#     carries no inline <style> (all styling lives in site.css);
#   - site.css takes colours and typefaces from --sw-* tokens only: no literal
#     colour or font-family outside a var() fallback, no local --sw-*
#     definition, and every var(--sw-*) carries a fallback so an unreachable
#     sprue.works degrades to readable, not to invalid CSS. Sizes and spacing
#     use the theme's scale by convention, not enforcement: the checker cannot
#     tell a layout constant (the 44rem measure, the 64px icon, a relative
#     0.95em) from a value that should have been a token, so review covers
#     those;
#   - the text content of docs/privacy.html and docs/terms.html (tags and
#     <style> stripped, whitespace collapsed) is byte-identical to the fixture
#     in tools/fixtures/docs-text/. Google's OAuth verification reviews those
#     pages' text and a change restarts it, so a wording edit must be
#     deliberate: update the fixture in the same commit.
#
# Used by .github/workflows/ci.yml; run locally before pushing. Needs node.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

node - "$@" <<'JS'
const fs = require('fs');
const path = require('path');
let failures = 0;
const update = process.argv.includes('--update-fixtures');
const fail = (m) => { console.error(`FAIL ${m}`); failures++; };
const ok = (m) => console.log(`ok   ${m}`);

const THEME = 'https://sprue.works/brand/v1/theme.css';
const pages = fs.readdirSync('docs').filter((f) => f.endsWith('.html')).sort();
if (!pages.length) fail('no docs/*.html found');

for (const f of pages) {
  const file = path.join('docs', f);
  const html = fs.readFileSync(file, 'utf8');
  const head = (html.match(/<head>[\s\S]*?<\/head>/i) || [''])[0];
  const theme = head.indexOf(`href="${THEME}"`);
  const site = head.indexOf('href="site.css"');
  if (theme < 0) fail(`${file}: <head> does not link ${THEME}`);
  if (site < 0) fail(`${file}: <head> does not link site.css`);
  if (theme >= 0 && site >= 0 && theme > site) fail(`${file}: the theme must be linked before site.css so site.css can read its tokens`);
  if (/<style[\s>]/i.test(html)) fail(`${file}: inline <style>; styling belongs in docs/site.css`);
  if (theme >= 0 && site >= 0 && theme < site && !/<style[\s>]/i.test(html)) ok(`${file} links theme then site.css, no inline style`);
}

// site.css: tokens only, every token with a fallback.
const cssFile = 'docs/site.css';
if (!fs.existsSync(cssFile)) fail(`${cssFile} missing`);
else {
  const css = fs.readFileSync(cssFile, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');
  // var(--sw-x) with no comma before the closing paren has no fallback.
  for (const m of css.matchAll(/var\(\s*(--sw-[\w-]+)\s*\)/g)) fail(`${cssFile}: ${m[1]} has no fallback`);
  // Strip every var(...) (fallbacks included) and look for literals left over.
  let stripped = css;
  let prev;
  do { prev = stripped; stripped = stripped.replace(/var\((?:[^()]|\([^()]*\))*\)/g, ''); } while (stripped !== prev);
  for (const m of stripped.matchAll(/#[0-9a-fA-F]{3,8}\b|\b(?:rgba?|hsla?|color-mix)\(/g)) fail(`${cssFile}: literal colour ${m[0]} outside a var() fallback; use a --sw-* token`);
  for (const m of stripped.matchAll(/font(?:-family)?\s*:\s*([^;\s][^;]*);/g)) fail(`${cssFile}: literal font-family '${m[1].trim()}' outside a var() fallback; use a --sw-font-* token`);
  const themeLocal = css.match(/^\s*--sw-[\w-]+\s*:/m);
  if (themeLocal) fail(`${cssFile}: defines ${themeLocal[0].trim()}; --sw-* tokens are the theme's, not ours (product overrides use another prefix)`);
  if (!failures) ok(`${cssFile} reads colours and typefaces only through --sw-* tokens, all with fallbacks`);
}

// Legal pages: text content pinned to the fixtures.
const extract = (html) => html
  .replace(/<style[\s\S]*?<\/style>/gi, '')
  .replace(/<script[\s\S]*?<\/script>/gi, '')
  .replace(/<[^>]+>/g, ' ')
  .replace(/\s+/g, ' ')
  .trim() + '\n';
if (update) {
  fs.mkdirSync('tools/fixtures/docs-text', { recursive: true });
  for (const page of ['privacy', 'terms']) {
    fs.writeFileSync(path.join('tools/fixtures/docs-text', `${page}.txt`), extract(fs.readFileSync(path.join('docs', `${page}.html`), 'utf8')));
  }
  console.log('note fixtures regenerated from docs/; commit them together with the wording change');
}
for (const page of ['privacy', 'terms']) {
  const fixture = path.join('tools/fixtures/docs-text', `${page}.txt`);
  const file = path.join('docs', `${page}.html`);
  if (!fs.existsSync(fixture)) { fail(`${fixture} missing`); continue; }
  const actual = extract(fs.readFileSync(file, 'utf8'));
  const expected = fs.readFileSync(fixture, 'utf8');
  if (actual !== expected) {
    fail(`${file}: text content differs from ${fixture}. Google's OAuth verification reviews this page's wording and a change restarts it; if the change is deliberate, regenerate the fixture: tools/test-docs-theme.sh --update-fixtures`);
  } else ok(`${file} text matches ${fixture}`);
}

if (failures) { console.error(`${failures} docs theme check(s) failed`); process.exit(1); }
console.log('docs theme checks passed');
JS
