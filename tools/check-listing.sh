#!/usr/bin/env bash
# Consistency check for the in-repo Marketplace listing (marketplace/).
# Nothing here talks to Google -- it verifies that what a human will paste into
# the Marketplace SDK / OAuth consent screen agrees with the code:
#
#   - marketplace/listing.json and screenshots.json parse
#   - listing OAuth scopes == src/appsscript.json oauthScopes
#   - the listing's script reference resolves to .clasp.json#scriptId (the
#     Project Script ID the Editor-add-on App Configuration form takes; the
#     version number it also takes lives only in the console -- RUNBOOK
#     section 4 -- so nothing here mirrors it)
#   - every referenced asset exists, is a PNG, and has the declared size
#   - the 220x140 card banner exists at exactly that size (#31)
#   - the Store Listing post-install tip is present and within a sane length
#   - every icon's (and the banner's) artwork fills its canvas (tools/png-check.js), and
#     docs/icon.png is the same pixels as icon-128.png -- a renderer that
#     thumbnails the SVG at its intrinsic size passes the size check with the
#     mark in one corner (#27)
#   - the listing URLs point at pages that exist under docs/, and the Store
#     Listing's required Draft Tester Opt-Out URL is a well-formed https URL
#   - wrangler.jsonc hosts docs/ with html_handling "none" (anything else
#     redirects the .html URLs Google holds), routes nothing or exactly the
#     listing's hostname as a custom domain (adding it is the DNS cutover),
#     and docs/_redirects restores / -> index.html; the GitHub Pages control
#     files, while still present, are kept out of the Worker and docs/CNAME
#     names the same host
#   - the publisher identity is sprue.works: developerName and the public
#     supportEmail's domain (brand verification checks these against the
#     verified homepage domain); contactEmail is on the domain too so no
#     personal address is ever published
#
# Used by .github/workflows/ci.yml; run locally before pushing.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

node - <<'JS'
const fs = require('fs');
const path = require('path');
let failures = 0;
const fail = (msg) => { console.error('FAIL ' + msg); failures++; };
const ok = (msg) => console.log('ok   ' + msg);
const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const { checkCoverage } = require(path.resolve('tools/png-check.js'));

const listing = readJson('marketplace/listing.json');
const manifest = readJson('src/appsscript.json');
let clasp = {};
try { clasp = readJson('.clasp.json'); } catch (e) { fail(`.clasp.json is missing or not valid JSON (${e.message}); it holds the Project Script ID the Marketplace SDK pins`); }
const shots = readJson('marketplace/screenshots.json');
ok('marketplace/listing.json, screenshots.json parse');

// Required text fields.
for (const [obj, keys, label] of [
  [listing.app, ['name', 'shortDescription', 'detailedDescriptionFile', 'category', 'developerName', 'supportEmail', 'contactEmail'], 'app'],
  [listing.urls, ['homepage', 'privacyPolicy', 'termsOfService', 'support', 'draftTesterOptOut'], 'urls'],
]) {
  for (const k of keys) if (!obj || typeof obj[k] !== 'string' || !obj[k].trim()) fail(`listing.${label}.${k} is missing or empty`);
}
const app = listing.app || {};
if (typeof app.shortDescription === 'string' && app.shortDescription.length > 120) fail(`app.shortDescription is ${app.shortDescription.length} chars; keep it under 120 for the store card`);
// Post-install tip: required by the Store Listing form (#31). Google documents no
// limit for this field; 200 is the limit Google documents for the store short
// description (this repo holds its own shortDescription tighter, at 120) and is
// the conservative cap until a real one turns up.
const POST_INSTALL_TIP_MAX = 200;
if (typeof app.postInstallTip !== 'string' || !app.postInstallTip.trim()) fail('listing.app.postInstallTip is missing or empty (the Store Listing form requires it)');
else if (app.postInstallTip.length > POST_INSTALL_TIP_MAX) fail(`app.postInstallTip is ${app.postInstallTip.length} chars; keep it at most ${POST_INSTALL_TIP_MAX} (Google truncates it)`);
else ok(`postInstallTip (${app.postInstallTip.length} chars)`);
if (typeof app.detailedDescriptionFile === 'string') {
  if (!fs.existsSync(app.detailedDescriptionFile)) fail(`detailedDescriptionFile ${app.detailedDescriptionFile} does not exist`);
  else ok(`description file ${app.detailedDescriptionFile}`);
}

// Publisher identity. Brand verification checks the publisher name, the public
// support address, and the homepage domain for consistency, so all three live on
// sprue.works. contactEmail is Google's private channel to the developer; it is
// a domain group too, so no personal address is published.
const emailRe = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
if (app.developerName !== 'sprue.works') fail(`app.developerName must be exactly "sprue.works" (lowercase, with the dot; got ${JSON.stringify(app.developerName)})`);
else ok('developerName is sprue.works');
if (typeof app.supportEmail === 'string') {
  if (!emailRe.test(app.supportEmail)) fail(`app.supportEmail is not an email address (got ${app.supportEmail})`);
  else if (!app.supportEmail.toLowerCase().endsWith('@sprue.works')) fail(`app.supportEmail must be an @sprue.works address (the consent-screen dropdown only offers the publishing account or a Google Group it manages; got ${app.supportEmail})`);
  else ok(`supportEmail ${app.supportEmail}`);
}
if (typeof app.contactEmail === 'string') {
  if (!emailRe.test(app.contactEmail)) fail(`app.contactEmail is not an email address (got ${app.contactEmail})`);
  else if (!app.contactEmail.toLowerCase().endsWith('@sprue.works')) fail(`app.contactEmail must be an @sprue.works address, never a personal one (got ${app.contactEmail})`);
  else ok(`contactEmail ${app.contactEmail}`);
}

// Scopes must match the manifest exactly (order-insensitive).
const want = [...manifest.oauthScopes].sort();
const have = [...(listing.oauth?.scopes || [])].sort();
if (JSON.stringify(want) !== JSON.stringify(have)) {
  fail(`listing.oauth.scopes differ from src/appsscript.json oauthScopes\n     manifest: ${want.join(', ')}\n     listing:  ${have.join(', ')}`);
} else ok(`OAuth scopes match src/appsscript.json (${want.length})`);

// What the Editor-add-on App Configuration form pins: the Project Script ID
// and a script version number. (No deployment ID -- that field belongs to the
// Google Workspace add-on integration type.)
const ext = listing.extension || {};
const script = ext.script || {};
if (script.source !== '.clasp.json' || script.field !== 'scriptId') {
  fail(`listing.extension.script must reference .clasp.json#scriptId (got ${JSON.stringify(script)})`);
} else if (typeof clasp.scriptId !== 'string' || !clasp.scriptId.trim()) {
  fail('.clasp.json has no scriptId; the Marketplace SDK needs the Project Script ID');
} else ok(`script reference resolves to .clasp.json#scriptId (${clasp.scriptId})`);
if ('deployment' in ext) fail('listing.extension.deployment is obsolete: the Editor-add-on form pins a script version number, not a deployment ID (RUNBOOK section 4)');
// The version number the form also pins lives only in the console; a copy here
// could not be verified and would drift, so its presence is a mistake.
if ('publishedVersion' in ext) fail('listing.extension.publishedVersion is not tracked in the repo: the pinned version lives in App Configuration and each release opens a tracking issue for the bump (RUNBOOK section 4)');
if (listing.extension?.type !== 'editorAddOn' || listing.extension?.application !== 'slides') fail('listing.extension must be an editorAddOn for slides');

// Distribution choice.
const vis = listing.distribution?.visibility;
if (!['private', 'unlisted', 'public'].includes(vis)) fail(`distribution.visibility must be private|unlisted|public (got ${vis})`);
if (vis === 'private' && !listing.distribution.privateDomain) fail('distribution.visibility=private needs distribution.privateDomain');

// PNG dimensions from the IHDR chunk (no image library needed).
function pngSize(file) {
  const b = fs.readFileSync(file);
  if (b.length < 24 || b.toString('hex', 0, 8) !== '89504e470d0a1a0a') return null;
  return [b.readUInt32BE(16), b.readUInt32BE(20)];
}
function checkPng(file, w, h, label, { content = false } = {}) {
  if (typeof file !== 'string' || !file) return fail(`${label}: no file path given`);
  if (!fs.existsSync(file)) return fail(`${label}: ${file} does not exist`);
  const size = pngSize(file);
  if (!size) return fail(`${label}: ${file} is not a PNG`);
  if (size[0] !== w || size[1] !== h) return fail(`${label}: ${file} is ${size[0]}x${size[1]}, expected ${w}x${h}`);
  if (content) {
    // Icons: the mark must fill the canvas, not sit in one quadrant.
    let reason;
    try { reason = checkCoverage(file); } catch (e) { reason = e.message; }
    if (reason) return fail(`${label}: ${file} ${reason}`);
  }
  ok(`${label} ${file} (${w}x${h}${content ? ', artwork fills the canvas' : ''})`);
}
const a = listing.assets || {};
checkPng(a.icon128, 128, 128, 'icon128', { content: true });
checkPng(a.icon32, 32, 32, 'icon32', { content: true });
checkPng(a.consentLogo120, 120, 120, 'consentLogo120', { content: true });
// Application card banner: the Store Listing requires exactly 220x140 (#31).
// The gradient ground fills every quadrant, so the icon coverage check applies unchanged.
checkPng(a.cardBanner220, 220, 140, 'cardBanner220', { content: true });
// The homepage serves its own copy of the 128px icon; render-icons.sh writes it.
checkPng('docs/icon.png', 128, 128, 'docs icon', { content: true });
if (typeof a.icon128 === 'string' && fs.existsSync(a.icon128) && fs.existsSync('docs/icon.png')
    && !fs.readFileSync(a.icon128).equals(fs.readFileSync('docs/icon.png'))) {
  fail(`docs/icon.png differs from ${a.icon128}; re-run tools/render-icons.sh so the homepage shows the same icon`);
}
const [sw, sh] = a.screenshotSize || [1280, 800];
if (a.screenshotsFile !== 'marketplace/screenshots.json') fail('assets.screenshotsFile must be marketplace/screenshots.json');
for (const s of shots.screenshots || []) {
  const file = typeof s === 'string' ? s : s.file;
  checkPng(file, sw, sh, 'screenshot');
}
if (!(shots.screenshots || []).length) console.log('note screenshots.json lists no screenshots yet; the store listing form requires at least one (RUNBOOK step 7)');

// The homepage / privacy / terms URLs must be served from docs/.
const urls = listing.urls || {};
const base = typeof urls.homepage === 'string' ? urls.homepage.replace(/\/$/, '') : '';
const publicBase = 'https://polyglot.sprue.works';
if (urls.homepage !== `${publicBase}/`) fail(`urls.homepage must be exactly ${publicBase}/ (got ${urls.homepage})`);
if (urls.support !== 'https://github.com/sprue-works/polyglot-slides/issues') {
  fail(`urls.support must use the sprue.works issue tracker (got ${urls.support})`);
}
// Store Listing "Draft Tester Opt-Out URL" (required). Google only asks for a
// mechanism testers can use to opt out, so the shape is all that can be checked.
if (typeof urls.draftTesterOptOut === 'string') {
  let parsed = null;
  try { parsed = new URL(urls.draftTesterOptOut); } catch (e) { /* reported below */ }
  if (!parsed || parsed.protocol !== 'https:' || !parsed.hostname) fail(`urls.draftTesterOptOut must be a well-formed https URL (got ${urls.draftTesterOptOut})`);
  else ok(`urls.draftTesterOptOut ${urls.draftTesterOptOut}`);
}
for (const [k, expectFile] of [['homepage', 'index.html'], ['privacyPolicy', 'privacy.html'], ['termsOfService', 'terms.html']]) {
  const url = urls[k];
  if (typeof url !== 'string') continue; // already reported as missing above
  if (!base || !url.startsWith(base)) { fail(`urls.${k} (${url}) is not under urls.homepage (${base})`); continue; }
  const rel = url.slice(base.length).replace(/^\//, '') || 'index.html';
  const file = path.join('docs', rel);
  if (!fs.existsSync(file)) fail(`urls.${k} -> ${file} does not exist`);
  else if (rel !== expectFile) fail(`urls.${k} should point at ${expectFile}, points at ${rel}`);
  else ok(`urls.${k} -> ${file}`);
}
// Hosting: docs/ is served by a Cloudflare Worker (wrangler.jsonc). The
// listing URLs above only hold if the Worker routes the hostname and serves
// the .html paths without redirecting them (see the comments in wrangler.jsonc
// and docs/_redirects; tools/test-docs-worker.sh checks the served responses).
const publicHost = new URL(publicBase).hostname;
const stripJsonc = (s) => s.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '').replace(/,(\s*[}\]])/g, '$1');
let wrangler = null;
try { wrangler = JSON.parse(stripJsonc(fs.readFileSync('wrangler.jsonc', 'utf8'))); }
catch (e) { fail(`wrangler.jsonc is missing or not valid JSONC (${e.message}); it is how docs/ is hosted`); }
if (wrangler) {
  const assets = wrangler.assets || {};
  if (assets.directory !== './docs') fail(`wrangler.jsonc assets.directory must be ./docs (got ${assets.directory})`);
  if (assets.html_handling !== 'none') fail(`wrangler.jsonc assets.html_handling must be "none" (got ${assets.html_handling}); any other mode redirects /privacy.html, a URL Google holds`);
  // Routes: none before the DNS cutover (production is workers.dev only), and
  // afterwards exactly the listing hostname as a custom domain. Anything else
  // would move traffic for a hostname this repo does not own -- and a
  // non-interactive deploy overrides the existing DNS record without asking.
  const routes = Array.isArray(wrangler.routes) ? wrangler.routes : [];
  const okRoute = (r) => r && r.pattern === publicHost && r.custom_domain === true;
  if (routes.length && !routes.some(okRoute)) fail(`wrangler.jsonc routes must be { pattern: "${publicHost}", custom_domain: true } (got ${JSON.stringify(routes)})`);
  for (const r of routes) if (!okRoute(r)) fail(`wrangler.jsonc routes an unexpected pattern: ${JSON.stringify(r)}`);
  if (wrangler.workers_dev !== true || wrangler.preview_urls !== true) fail('wrangler.jsonc must keep workers_dev and preview_urls on (branch previews)');
  // While either GitHub Pages control file is still in docs/, it must be kept
  // out of the Worker's assets. Once both are gone the ignore file is optional.
  const pagesFiles = ['CNAME', '.nojekyll'].filter((f) => fs.existsSync(path.join('docs', f)));
  // ...and they may only go once the custom domain is declared: until the
  // Worker holds the hostname, GitHub Pages still serves it from main:/docs
  // and dropping CNAME from the published branch drops the live domain.
  if (!routes.length && pagesFiles.length < 2) fail(`docs/CNAME and docs/.nojekyll must stay until wrangler.jsonc routes ${publicHost} (RUNBOOK 1c); GitHub Pages is still the live site`);
  if (pagesFiles.length) {
    const ignored = fs.existsSync('docs/.assetsignore') ? fs.readFileSync('docs/.assetsignore', 'utf8').split(/\r?\n/) : [];
    for (const f of pagesFiles) if (!ignored.includes(f)) fail(`docs/.assetsignore must list ${f} while docs/${f} exists (GitHub Pages control file, not a page)`);
  }
  if (!failures) ok(`wrangler.jsonc serves docs/ with html_handling none${routes.length ? ` on ${publicHost}` : ' (no custom domain yet: pre-cutover)'}`);
}
if (!fs.existsSync('docs/_redirects') || !/^\/ \/index\.html 200$/m.test(fs.readFileSync('docs/_redirects', 'utf8'))) {
  fail('docs/_redirects must rewrite "/ /index.html 200" (html_handling none does not serve index.html at /)');
}
// Transitional: the GitHub Pages site stays live until the cutover in
// marketplace/RUNBOOK.md §1c. Until then its custom domain lives in docs/CNAME,
// so if the file is present it must still name the right host. Removing both
// control files is the post-cutover cleanup, not an error here.
if (fs.existsSync('docs/CNAME') && fs.readFileSync('docs/CNAME', 'utf8').trim() !== publicHost) fail(`docs/CNAME must contain ${publicHost} while GitHub Pages is still serving`);

if (failures) { console.error(`${failures} listing check(s) failed`); process.exit(1); }
console.log('listing checks passed');
JS
