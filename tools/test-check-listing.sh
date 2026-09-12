#!/usr/bin/env bash
# Self-test for tools/check-listing.sh: the real repo passes, and each kind of
# drift it exists to catch makes it fail.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

# Fresh copy of just what the check reads.
fresh() {
  rm -rf "$work/repo"
  mkdir -p "$work/repo/tools" "$work/repo/src"
  cp -R "$repo_root/marketplace" "$repo_root/docs" "$work/repo/"
  cp "$repo_root/tools/check-listing.sh" "$repo_root/tools/png-check.js" "$work/repo/tools/"
  cp "$repo_root/src/appsscript.json" "$work/repo/src/"
  cp "$repo_root/.clasp.json" "$repo_root/wrangler.jsonc" "$work/repo/"
}
# Edit wrangler.jsonc in the fresh copy with a JS expression over the parsed
# config; the check reads JSONC, so plain JSON output is fine.
edit_wrangler() { # edit_wrangler <js mutating `j`>
  (cd "$work/repo" && node -e 'const fs=require("fs"),f="wrangler.jsonc";const s=fs.readFileSync(f,"utf8").replace(/\/\*[\s\S]*?\*\//g,"").replace(/^\s*\/\/.*$/gm,"").replace(/,(\s*[}\]])/g,"$1");const j=JSON.parse(s);'"$1"';fs.writeFileSync(f,JSON.stringify(j))')
}

expect_pass() { # expect_pass <label>
  (cd "$work/repo" && tools/check-listing.sh >"$work/out" 2>&1) || { cat "$work/out"; fail "$1: expected pass"; }
  echo "ok   $1 passes"
}
expect_fail() { # expect_fail <label> <literal-substring>
  if (cd "$work/repo" && tools/check-listing.sh >"$work/out" 2>&1); then cat "$work/out"; fail "$1: expected failure"; fi
  grep -qF "$2" "$work/out" || { cat "$work/out"; fail "$1: failure message should mention '$2'"; }
  echo "ok   $1 is rejected"
}

fresh; expect_pass "repo as committed"

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f="src/appsscript.json",j=JSON.parse(fs.readFileSync(f));j.oauthScopes.push("https://www.googleapis.com/auth/drive");fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "manifest scope not in listing" "scopes differ"

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/listing.json",j=JSON.parse(fs.readFileSync(f));j.extension.script.source="somewhere-else.json";fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "script reference not .clasp.json" ".clasp.json#scriptId"

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f=".clasp.json",j=JSON.parse(fs.readFileSync(f));delete j.scriptId;fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "clasp project without a scriptId" ".clasp.json has no scriptId"

fresh
rm "$work/repo/.clasp.json"
expect_fail "clasp project file missing reports cleanly" ".clasp.json is missing or not valid JSON"
grep -Eq "at Object|at Module|node:internal" "$work/out" && fail "missing .clasp.json must not produce a stack trace"

fresh
# A pinned-version copy in the repo cannot be verified against the console and only drifts.
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/listing.json",j=JSON.parse(fs.readFileSync(f));j.extension.publishedVersion=1;fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "publishedVersion copy in the repo" "publishedVersion is not tracked in the repo"

fresh
# The pre-#29 shape: a pointer at a deployment ID the Editor-add-on form never reads.
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/listing.json",j=JSON.parse(fs.readFileSync(f));j.extension.deployment={source:"deployment.json",field:"deploymentId"};fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "legacy deployment pointer" "listing.extension.deployment is obsolete"

fresh
rm "$work/repo/marketplace/assets/icon-32.png"
expect_fail "missing icon" "icon-32.png does not exist"

fresh
cp "$work/repo/marketplace/assets/icon-48.png" "$work/repo/marketplace/assets/icon-32.png"
expect_fail "wrong icon size" "expected 32x32"

# A PNG of the right size whose artwork sits in the top-left quarter on white:
# what qlmanage produces from the 128x128-intrinsic SVG (#27).
quarter_icon() { # quarter_icon <out.png> <size>
  node -e '
    const fs=require("fs"),zlib=require("zlib"),[out,n]=[process.argv[1],+process.argv[2]];
    const crcT=[...Array(256)].map((_,i)=>{let c=i;for(let k=0;k<8;k++)c=c&1?0xedb88320^(c>>>1):c>>>1;return c>>>0;});
    const crc=b=>{let c=~0;for(const x of b)c=crcT[(c^x)&255]^(c>>>8);return (~c)>>>0;};
    const chunk=(t,d)=>{const l=Buffer.alloc(4);l.writeUInt32BE(d.length);const td=Buffer.concat([Buffer.from(t),d]);const c=Buffer.alloc(4);c.writeUInt32BE(crc(td));return Buffer.concat([l,td,c]);};
    const raw=Buffer.alloc((n*4+1)*n,255);
    for(let y=0;y<n;y++){raw[y*(n*4+1)]=0;for(let x=0;x<n;x++){const o=y*(n*4+1)+1+x*4;if(x<n/2&&y<n/2){raw[o]=0x1a;raw[o+1]=0x73;raw[o+2]=0xe8;}}}
    const ihdr=Buffer.alloc(13);ihdr.writeUInt32BE(n,0);ihdr.writeUInt32BE(n,4);ihdr[8]=8;ihdr[9]=6;
    fs.writeFileSync(out,Buffer.concat([Buffer.from("89504e470d0a1a0a","hex"),chunk("IHDR",ihdr),chunk("IDAT",zlib.deflateSync(raw)),chunk("IEND",Buffer.alloc(0))]));
  ' "$1" "$2"
}

fresh
quarter_icon "$work/repo/marketplace/assets/icon-120.png" 120
expect_fail "icon artwork in the top-left quarter" "artwork does not fill the canvas"

fresh
src="$repo_root/marketplace/assets/icon-128.png"
head -c "$(( $(wc -c <"$src") / 2 ))" "$src" >"$work/repo/marketplace/assets/icon-128.png"
expect_fail "truncated icon is a clear failure, not a coverage verdict" "truncated PNG"

fresh
quarter_icon "$work/repo/docs/icon.png" 128
expect_fail "homepage icon artwork in the top-left quarter" "docs icon: docs/icon.png artwork does not fill"

fresh
# Same image, one trailing byte after IEND: dimensions and content still pass.
(cd "$work/repo" && node -e 'const fs=require("fs"),f="docs/icon.png";fs.writeFileSync(f,Buffer.concat([fs.readFileSync(f),Buffer.from([0])]))')
expect_fail "homepage icon differs from icon-128" "docs/icon.png differs from marketplace/assets/icon-128.png"

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/screenshots.json",j=JSON.parse(fs.readFileSync(f));j.screenshots=["marketplace/assets/icon-128.png"];fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "screenshot with wrong size" "expected 1280x800"

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/listing.json",j=JSON.parse(fs.readFileSync(f));delete j.app.shortDescription;delete j.urls.homepage;fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "missing required fields report cleanly" "listing.app.shortDescription is missing"
grep -q "TypeError" "$work/out" && fail "missing fields must not produce a stack trace"

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/listing.json",j=JSON.parse(fs.readFileSync(f));delete j.assets.icon32;fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "missing asset path reports cleanly" "icon32: no file path given"
grep -q "TypeError" "$work/out" && fail "missing asset path must not produce a stack trace"

fresh
rm "$work/repo/docs/privacy.html"
expect_fail "privacy page missing" "privacy.html does not exist"

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/listing.json",j=JSON.parse(fs.readFileSync(f));j.distribution.visibility="private";fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "private without domain" "privateDomain"

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/listing.json",j=JSON.parse(fs.readFileSync(f));j.urls.homepage="https://example.com/";j.urls.privacyPolicy="https://example.com/privacy.html";j.urls.termsOfService="https://example.com/terms.html";fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "listing on an unverified host" "polyglot.sprue.works"

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/listing.json",j=JSON.parse(fs.readFileSync(f));j.app.developerName="Sprue Works";fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "publisher name not stylized sprue.works" 'developerName must be exactly "sprue.works"'

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/listing.json",j=JSON.parse(fs.readFileSync(f));j.app.supportEmail="someone@gmail.com";fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "support email off the sprue.works domain" "supportEmail must be an @sprue.works address"

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/listing.json",j=JSON.parse(fs.readFileSync(f));j.app.contactEmail="not-an-address";fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "contact email malformed" "contactEmail is not an email address"

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/listing.json",j=JSON.parse(fs.readFileSync(f));j.app.contactEmail="mario@guerrieri.codes";fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "personal contact email" "contactEmail must be an @sprue.works address"

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/listing.json",j=JSON.parse(fs.readFileSync(f));j.app.developerEmail=j.app.supportEmail;delete j.app.supportEmail;delete j.app.contactEmail;fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "old single developerEmail shape" "listing.app.supportEmail is missing"
grep -q "listing.app.contactEmail is missing" "$work/out" || { cat "$work/out"; fail "old shape must also report contactEmail missing"; }

fresh
rm "$work/repo/marketplace/assets/banner-220x140.png"
expect_fail "missing card banner" "banner-220x140.png does not exist"

fresh
cp "$work/repo/marketplace/assets/icon-128.png" "$work/repo/marketplace/assets/banner-220x140.png"
expect_fail "wrong card banner size" "expected 220x140"

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/listing.json",j=JSON.parse(fs.readFileSync(f));delete j.app.postInstallTip;fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "missing post-install tip" "listing.app.postInstallTip is missing"

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/listing.json",j=JSON.parse(fs.readFileSync(f));j.app.postInstallTip="x".repeat(201);fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "over-long post-install tip" "postInstallTip is 201 chars"

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/listing.json",j=JSON.parse(fs.readFileSync(f));delete j.urls.draftTesterOptOut;fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "missing draft tester opt-out URL" "listing.urls.draftTesterOptOut is missing"

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/listing.json",j=JSON.parse(fs.readFileSync(f));j.urls.draftTesterOptOut="http://github.com/sprue-works/polyglot-slides/issues";fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "plain-http draft tester opt-out URL" "draftTesterOptOut must be a well-formed https URL"

fresh
(cd "$work/repo" && node -e 'const fs=require("fs"),f="marketplace/listing.json",j=JSON.parse(fs.readFileSync(f));j.urls.draftTesterOptOut="file an issue";fs.writeFileSync(f,JSON.stringify(j))')
expect_fail "non-URL draft tester opt-out" "draftTesterOptOut must be a well-formed https URL"

# Hosting invariants (#47): docs/ is served by a Cloudflare Worker.
fresh
rm "$work/repo/wrangler.jsonc"
expect_fail "wrangler config missing reports cleanly" "wrangler.jsonc is missing or not valid JSONC"

fresh
edit_wrangler 'j.assets.html_handling="auto-trailing-slash"'
expect_fail "html_handling that redirects .html URLs" 'html_handling must be "none"'

fresh
edit_wrangler 'j.routes=[{pattern:"polyglot.sprue.works/*",zone_name:"sprue.works"}]'
expect_fail "hostname routed but not as a custom domain" 'custom_domain: true'

fresh
edit_wrangler 'j.routes=[{pattern:"polyglot.sprue.works",custom_domain:true},{pattern:"sprue.works",custom_domain:true}]'
expect_fail "a hostname this repo does not own" "routes an unexpected pattern"

fresh
# The post-cutover shape: the custom domain declared (RUNBOOK section 1c).
edit_wrangler 'j.routes=[{pattern:"polyglot.sprue.works",custom_domain:true}]'
expect_pass "custom domain declared after the cutover"

fresh
# CNAME still present but no longer kept out of the Worker's assets.
rm "$work/repo/docs/.assetsignore"
expect_fail "Pages control file would be served by the Worker" "docs/.assetsignore must list CNAME"

fresh
edit_wrangler 'j.preview_urls=false'
expect_fail "branch previews switched off" "preview_urls"

fresh
rm "$work/repo/docs/_redirects"
expect_fail "root rewrite missing" "docs/_redirects must rewrite"

fresh
printf 'polyglot-slides.pages.dev\n' >"$work/repo/docs/CNAME"
expect_fail "stale Pages CNAME" "docs/CNAME must contain polyglot.sprue.works"

fresh
# Post-cutover cleanup shape: the Pages control files and their ignore file
# are all gone (RUNBOOK section 1c, last step). Not an error.
rm "$work/repo/docs/CNAME" "$work/repo/docs/.nojekyll" "$work/repo/docs/.assetsignore"
expect_pass "Pages control files and .assetsignore removed after cutover"

echo "all check-listing.sh tests passed"
