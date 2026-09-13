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
#     redirects the .html URLs Google holds), declares no routes (the
#     hostname is routed by terraform/, whose `cutover` variable is the DNS
#     switch), and docs/_redirects restores / -> index.html; the GitHub Pages
#     control files stay until terraform/ has cut over, are kept out of the
#     Worker meanwhile, and docs/CNAME names the same host
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
  // Routes: none, ever. The hostname reaches the Worker through the Workers
  // route terraform/ owns over the DNS record. A route here -- above all a
  // custom_domain -- would have Workers Builds' non-interactive deploy
  // replace that DNS record without asking (wrangler passes
  // override_existing_dns_record=true when stdout is not a TTY).
  if (wrangler.routes !== undefined && wrangler.routes !== null) fail(`wrangler.jsonc must not declare routes; ${publicHost} is routed by terraform/ (got ${JSON.stringify(wrangler.routes)})`);
  if (wrangler.workers_dev !== true || wrangler.preview_urls !== true) fail('wrangler.jsonc must keep workers_dev and preview_urls on (branch previews)');
  // While either GitHub Pages control file is still in docs/, it must be kept
  // out of the Worker's assets. Once both are gone the ignore file is optional.
  const pagesFiles = ['CNAME', '.nojekyll'].filter((f) => fs.existsSync(path.join('docs', f)));
  // ...and they may only go once terraform/ has cut the hostname over: until
  // then GitHub Pages still serves it from main:/docs and dropping CNAME from
  // the published branch drops the live domain.
  const tfMain = fs.existsSync('terraform/main.tf') ? fs.readFileSync('terraform/main.tf', 'utf8') : '';
  const cutoverDefault = tfMain.match(/variable\s+"cutover"[\s\S]*?default\s*=\s*(true|false)/);
  if (!cutoverDefault) fail('terraform/main.tf must declare variable "cutover" with a boolean default (the route-based cutover switch, RUNBOOK 1c)');
  const cutOver = cutoverDefault && cutoverDefault[1] === 'true';
  // Flipping the switch and deleting the control files must not happen in
  // one commit: the Terraform apply is a separate operation from the Pages
  // build that would drop the live domain, and the route has to be verified
  // live first. The cleanup PR therefore also adds terraform/CUTOVER.md, an
  // explicit attestation naming the apply run that added the route (RUNBOOK
  // 1c); only with both in place may the control files go.
  const attestation = fs.existsSync('terraform/CUTOVER.md') ? fs.readFileSync('terraform/CUTOVER.md', 'utf8') : '';
  const attested = /https:\/\/github\.com\/sprue-works\/polyglot-slides\/actions\/runs\/\d+/.test(attestation);
  if (attestation && !attested) fail('terraform/CUTOVER.md must name the Terraform apply run (a https://github.com/sprue-works/polyglot-slides/actions/runs/<id> URL) that added the route');
  if (pagesFiles.length < 2) {
    if (!cutOver) fail('docs/CNAME and docs/.nojekyll must stay until terraform/main.tf sets cutover = true (RUNBOOK 1c); GitHub Pages is still the live site');
    else if (!attested) fail('docs/CNAME and docs/.nojekyll may only go once terraform/CUTOVER.md attests the applied, verified cutover (RUNBOOK 1c); flipping the switch and deleting them in one commit is not allowed');
  }
  // The switch is only proof of routing if the stack still routes this
  // hostname to this Worker: the route resource keyed on `cutover`, the
  // hostname default equal to the listing's, and the Worker name equal to
  // wrangler.jsonc's. Otherwise a proxied hostname would serve GitHub Pages
  // through Cloudflare with no Worker in front -- or nothing at all once the
  // control files are gone.
  if (tfMain) {
    const tfDefault = (name) => (tfMain.match(new RegExp(`variable\\s+"${name}"[\\s\\S]*?default\\s*=\\s*"([^"]*)"`)) || [])[1];
    if (tfDefault('hostname') !== publicHost) fail(`terraform/main.tf variable "hostname" must default to ${publicHost} (got ${tfDefault('hostname')})`);
    if (tfDefault('worker_name') !== wrangler.name) fail(`terraform/main.tf variable "worker_name" must default to wrangler.jsonc's name ${wrangler.name} (got ${tfDefault('worker_name')})`);
    const route = tfMain.match(/resource\s+"cloudflare_workers_route"\s+"[^"]+"\s*\{([\s\S]*?)\n\}/);
    if (!route) fail('terraform/main.tf must declare a cloudflare_workers_route for the hostname (the cutover has nothing to route to otherwise)');
    else {
      const body = route[1];
      if (!/count\s*=\s*var\.cutover\s*\?\s*1\s*:\s*0/.test(body)) fail('the cloudflare_workers_route must be keyed on var.cutover (count = var.cutover ? 1 : 0)');
      if (!/pattern\s*=\s*"\$\{var\.hostname\}\/\*"/.test(body)) fail('the cloudflare_workers_route pattern must be "${var.hostname}/*"');
      if (!/script\s*=\s*var\.worker_name\b/.test(body)) fail('the cloudflare_workers_route script must be var.worker_name');
    }
    // The record the route rides on must be this hostname's CNAME to GitHub
    // Pages, proxied by the same switch -- not some other record that
    // happens to reference var.cutover.
    const record = tfMain.match(/resource\s+"cloudflare_dns_record"\s+"[^"]+"\s*\{([\s\S]*?)\n\}/);
    if (!record) fail('terraform/main.tf must declare the cloudflare_dns_record for the hostname');
    else {
      const body = record[1];
      if (!/\bname\s*=\s*var\.hostname\b/.test(body)) fail('the cloudflare_dns_record name must be var.hostname');
      if (!/\btype\s*=\s*"CNAME"/.test(body)) fail('the cloudflare_dns_record must stay a CNAME (a type change is a replacement the hostname cannot afford)');
      if (!/\bcontent\s*=\s*"sprue-works\.github\.io"/.test(body)) fail('the cloudflare_dns_record must keep pointing at sprue-works.github.io (GitHub Pages is the origin until the route is in front)');
      if (!/\bproxied\s*=\s*var\.cutover\b/.test(body)) fail('the cloudflare_dns_record must set proxied = var.cutover (a route only receives traffic over a proxied record)');
      if (!/prevent_destroy\s*=\s*true/.test(body)) fail('the cloudflare_dns_record must keep prevent_destroy = true');
    }
  }
  if (pagesFiles.length) {
    const ignored = fs.existsSync('docs/.assetsignore') ? fs.readFileSync('docs/.assetsignore', 'utf8').split(/\r?\n/) : [];
    for (const f of pagesFiles) if (!ignored.includes(f)) fail(`docs/.assetsignore must list ${f} while docs/${f} exists (GitHub Pages control file, not a page)`);
  }
  if (!failures) ok(`wrangler.jsonc serves docs/ with html_handling none; terraform/ ${cutOver ? 'routes' : 'has not yet cut over'} ${publicHost}`);
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
