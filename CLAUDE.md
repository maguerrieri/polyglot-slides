# Polyglot Slides — working notes

## Where things live

- `src/` — the add-on itself. `Code.js` (modes, selection, translation),
  `Sidebar.html` (the sidebar UI), `appsscript.json` (manifest + OAuth scopes).
- `README.md` — what it does, the modes, known limitations, and the developer
  loop (`clasp push`, test deployments).
- `INSTALL.md` — how a non-developer installs it today, the owner-side sharing
  setup, the staged template deck's IDs, and the second-account verification
  checklist. **Interim by design** — see its shelf-life note; most of it is
  superseded when #4 lands.
- `tools/sync-template.sh` — pushes `src/` into the template deck's bound script.
- `tools/release.sh` — tagged-release pipeline (push + numbered version;
  nothing is deployed); `.github/workflows/deploy.yml` runs it and opens the
  "bump script version" tracking issue. README "Release pipeline" is the
  human-facing doc, including the secret setup and the manual remainder.
- `marketplace/` — the Workspace Marketplace listing as data: `listing.json`
  (what a human pastes into the Marketplace SDK / consent screen), the icon
  and screenshots, and `RUNBOOK.md` (the click-through). `docs/` is the
  docs site (homepage + privacy + terms) brand verification needs, served
  by the Cloudflare Worker in `wrangler.jsonc` (see "The docs site is a
  Worker" below);
  its look comes from the sprue.works brand theme (see "The docs site is
  styled by the brand theme" below), enforced by `tools/test-docs-theme.sh`.
  `tools/check-listing.sh` is the contract: listing scopes == manifest scopes,
  script reference resolves to `.clasp.json#scriptId` (the one field the
  Editor-add-on console form consumes that the repo can verify; the version
  number it also pins is deliberately not mirrored), assets exist at the
  right sizes,
  publisher is `sprue.works` with an `@sprue.works` support address (brand
  verification checks name, support email, and homepage domain agree).
- `.claude/settings.json` — declares the claude-toolbox plugin marketplace
  (<https://github.com/maguerrieri/claude-toolbox>) and enables its
  `defaults` meta-plugin, so the toolbox plugins load in Claude Code here.
- This file — gotchas that aren't visible from the code.

Two user-facing surfaces deliver messages differently and always have: sidebar
runs write to `#status` in `Sidebar.html`, menu runs call `SlidesApp.getUi()
.alert()` in `menuRun_`. That asymmetry is tracked in #6, not a bug to fix
in passing.

## The script project's *name* is user-visible

`onOpen` uses `Ui.createAddonMenu()`. For a **container-bound** script (which is
how the template deck in [INSTALL.md](INSTALL.md) ships), the Extensions submenu
takes **the script project's name**, not the deck's name and not anything in the
code. Google's reference is explicit: "if the script is bound to the document
directly, the sub-menu name matches the script's name."

So `clasp create --type slides --title "X"` names *both* the new deck and its
bound script `X`, and `X` is then what every recipient is told to click. Create
the bound script with the title **`Polyglot Slides`** and rename the *deck*
afterwards (Drive rename; it does not touch the script project). Getting this
backwards produces an `Extensions → Polyglot Slides — Template` menu that no
documentation matches.

## The template deck holds a second copy of the source

`src/` is pushed to two different script projects:

- the dev project in `.clasp.json` (`clasp push`), used for Path B and for
  day-to-day iteration;
- the template deck's **bound** script (`tools/sync-template.sh`), which is what
  recipients actually copy.

They drift silently — nothing fails, new recipients just get old code. Run
`tools/sync-template.sh` after any `src/` change that should reach new users.
`sync-template.sh` pushes from a scratch directory precisely so it can never
shadow or rewrite the repo's own `.clasp.json`.

Copies already made never update. That is inherent to bound scripts, not a bug
to fix — automatic updates need the Marketplace path (#4).

## Testing the install path needs a second Google account

The owner's account cannot exercise the flow that matters (a non-owner copying
a view-only deck and hitting the unverified-app consent screen). Don't claim the
install path is verified off owner-side testing; INSTALL.md carries the
second-account checklist.

## The Apps Script project is org-owned, and that cannot be undone or redone later

The script project in `.clasp.json` is owned by the `@sprue.works` publishing
account (ideally inside a sprue.works Shared Drive), **not** by a personal
Google account — the same side of the fence as GCP project `556097262294`,
the OAuth consent screen, the Search Console property, and the `help@` /
`contact@` groups. #36 recreated it there before #20 submitted the listing.

Why recreate rather than transfer: **Google does not transfer Drive ownership
across the consumer/Workspace boundary** — an Apps Script project is a Drive
file, and the restriction is a deliberate data-protection rule, not a setting
(<https://support.google.com/a/answer/1247799>). The only alternatives were a
Shared Drive move with several admin-side moving parts, or a new project. A
new project was cheap only while nothing was published and no one had
installed the add-on; after launch the same change is a migration that strands
every existing install, because the Marketplace listing pins the script ID.

Consequences, so nobody "fixes" this back:

- Never point `.clasp.json` at a personally owned project again, even for
  convenience — the personal account can be *shared in* as an editor, but the
  listing must keep pinning the org-owned ID.
- `CLASPRC_JSON` must be minted **by the publishing account** (README
  "One-time setup"); a personal account's token only works while that account
  is shared in, and re-minting is the fix, not re-pointing the script.
- Attaching the script to the GCP project (RUNBOOK §3b) and the Marketplace
  SDK's *Project Script ID* + *version* (§4) are per-project facts that had to be
  redone for the new project; a new project's versions start at `1`.
- The old personal project still exists, orphaned. Leave it; don't delete it.
- `tools/sync-template.sh` is unaffected — it targets the template deck's
  **bound** script, a different project that stays with the deck's owner.

## CI deploys authenticate as a user, and the deployment ID is *not* what the Marketplace pins

- Apps Script's API rejects service accounts for script projects, so
  `deploy.yml` uses a copied `~/.clasprc.json` (secret `CLASPRC_JSON`) handed to
  clasp 3 via the `clasp_config_auth` env var. The secret is the **whole** file
  (`{"tokens":{"default":{...}}}`), not a token; clasp 3 also reads the legacy
  `{token, oauth2ClientSettings}` shape, so a clasp 2 file works too. Don't
  read the local `~/.clasprc.json` — it's a credential file.
- The Apps Script API has **two** switches: the GCP project's API
  enablement (RUNBOOK §2) and a **per-user** toggle at
  `script.google.com/home/usersettings` that only the deploying account can
  flip. `clasp push` works with the per-user toggle off; `clasp version`
  fails (`User has not enabled the Apps Script API`) — so a green
  push-to-main deploy is not proof the account can cut versions. The
  `v1.0.1` tag run after #36 failed exactly that way. `deploy.yml` runs
  `clasp list-versions` right after auth as a preflight (#38); if that step
  fails, the fix is the toggle, not the token.
- GitHub Actions expression contexts are placement-sensitive: `runner.*` is
  unavailable in job-level `env`, even though the file is valid YAML. Run
  `tools/lint-workflows.sh` after workflow edits; it uses actionlint to catch
  expression-context failures before GitHub rejects the workflow definition.
- **Corrected 2026-09-02 (#19):** the Marketplace SDK App Configuration for an
  *Editor add-on* pins **Project Script ID + script version number**, and has
  no deployment-ID field at all — that field exists only for the *Google
  Workspace add-on* integration type, a different architecture (`addOns`
  manifest block, card UI) this add-on does not use. Google's docs: "to
  publish an Editor add-on, you must provide the project script ID and
  version", and to ship an update, "update the version number on the App
  Configuration page". Earlier notes here claimed the listing points at a
  deployment ID and that releases reach installed users automatically; both
  were wrong. The real path is: tag → `tools/release.sh` creates version *n*
  → **a human bumps *Slides add-on script version* to *n*** in App
  Configuration (RUNBOOK §4). A version bump alone does not trigger
  Marketplace re-review; users don't reinstall.
- **Since #29** the pipeline matches that: `tools/release.sh` is `clasp push`
  + `clasp version` and nothing else — no deployment, no `deployment.json`
  (the old deployment still exists in Apps Script, orphaned and harmless).
  The **pinned version number is not mirrored in the repo** — `check-listing.sh`
  fails if a `publishedVersion` key appears. #29 first added one (recording
  "what is live", bumped by hand after the paste) and then removed it: the
  repo can neither read nor write the console, so the copy was pure
  bookkeeping that could only drift, and it cost a second manual step per
  release. The record is the tag workflow's tracking issue (*release vX: bump
  Slides add-on script version to N*, assigned to whoever pushed the tag):
  open means the bump is owed, closed means it was done. The step summary
  carries the same instruction.
- `tools/test-release.sh` pins the exact clasp call sequence with a stub. Change
  the sequence deliberately and update the expectations together.

## The listing is data the human pastes, and CI guards the paste

Google has no write API for the Marketplace SDK listing or the OAuth consent
screen, so `marketplace/listing.json` can't be *applied* — it's the paste
source, and `tools/check-listing.sh` is what keeps the paste honest. Two
consequences:

- Changing `oauthScopes` in `appsscript.json` fails CI until `listing.json`
  matches — on purpose. A scope change also needs the consent screen and the
  Marketplace SDK updated by hand and triggers re-verification; the CI failure
  is the reminder.
- The Editor-add-on listing is pinned to the **script ID plus a version
  number** (RUNBOOK §4), not to a deployment and not to HEAD. A tagged
  release does nothing for installed users until that version field is
  bumped by hand; `listing.json`'s `extension.script` mirrors the script-ID
  field, the version number stays console-only (see above), and
  `check-listing.sh` rejects both the old `extension.deployment` pointer and
  a `publishedVersion` key if either comes back.
- Console facts the runbook now carries because they aren't in Google's docs:
  Apps Script refuses *Change GCP project* until the target project has a
  saved OAuth consent screen (so consent screen before attach);
  `script.container.ui` is absent from the *Add or remove scopes* table and
  must be pasted into *Manually add scopes*; it is classified **sensitive**
  (sensitive-scope verification — justification + demo video — not brand
  verification alone; CASA is for *restricted* scopes only); the Marketplace
  SDK has no left-nav entry (its API Library page → *Manage*); App visibility
  Private/Public is irreversible once saved. GCP project number: 556097262294.

## The docs site is styled by the brand theme, and the legal pages' text is pinned

`docs/*.html` carry no inline `<style>`. Each links
`https://sprue.works/brand/v1/theme.css` (the org's CSS custom properties,
`--sw-*`; usage notes in `brand/README.md` of sprue-works/website) and then
`docs/site.css`, which maps those tokens onto elements and defines no colour
or font of its own. Every `var(--sw-*)` carries a fallback so an unreachable
sprue.works degrades to readable, not to invalid CSS — and the theme only
ships light-scheme fallbacks that way, so with the theme blocked the pages
render light in both schemes; that is the intended degradation. Missing tokens
are an issue on sprue-works/website, not a literal here; product-specific
branding is the icon, an image, so nothing overrides the theme. The theme is
served `immutable` for a year, so a value change upstream reaches repeat
visitors slowly.

`tools/test-docs-theme.sh` (CI) enforces the link order, no literal colours or
font-families, and the fallbacks — sizes and spacing follow the theme scale by
convention only, since a checker can't tell a layout constant from a missed
token — and pins the **text content** of `docs/privacy.html` and
`docs/terms.html` to `tools/fixtures/docs-text/*.txt`. Google's OAuth
verification reviews those pages' wording and a change restarts the round
(#41), so styling work must leave the text byte-identical and CI fails if it
doesn't. A deliberate wording change regenerates the fixtures in the same
commit with `tools/test-docs-theme.sh --update-fixtures`.

## QuickLook thumbnails don't scale SVGs with an intrinsic size

`tools/render-icons.sh` falls back to macOS `qlmanage -t -s 512` when
`rsvg-convert` is missing. QuickLook draws the SVG at its **intrinsic**
`width`/`height` (128×128 on `icon.svg`) onto the requested canvas without
scaling, so the mark lands in the top-left quarter of a 512×512 white square
and `sips -z` then shrinks that whole padded canvas. Every icon PNG passed the
dimensions-only check that way (#27). The script now rewrites the root
`width`/`height` to the render size in a scratch copy before thumbnailing, and
`tools/png-check.js` (shared with `tools/check-listing.sh`) fails any icon
whose artwork doesn't reach all four quadrants. Don't infer a render is right
from its pixel size — open the PNG.

QuickLook also mishandles a **non-square viewBox**: `banner.svg` (viewBox
220×140) thumbnailed at an intrinsic 880×560 came out 880×642, scaled
non-uniformly and clipped at the sides (#31). `render-icons.sh` therefore pads
the scratch copy's viewBox to a square (`0 -40 220 220`) at a square intrinsic
size, renders, and crops the banner band back out with `sips -c … --cropOffset`
before downsampling. Keep the viewBox aspect equal to the intrinsic aspect,
and square, whenever qlmanage is the renderer.

## The docs site is a Worker; `html_handling` stays `none`, and the custom domain is the cutover

`docs/` is served by a Cloudflare Worker with static assets (`wrangler.jsonc`,
deployed by Workers Builds; README "Docs site", RUNBOOK §1). Three things
about it are not the obvious configuration:

- **`html_handling: "none"`, not the `auto-trailing-slash` default the main
  sprue.works site uses.** The default answers `/privacy.html` with a
  `307` to `/privacy` — verified with `wrangler dev` (#47) — and
  `/privacy.html` / `/terms.html` are the exact URLs Google holds for OAuth
  verification, where a redirect or 404 restarts the round. `none` serves the
  `.html` paths as-is but then returns 404 for `/`, so `docs/_redirects`
  carries `/ /index.html 200` (a rewrite, not a redirect) plus the
  extensionless paths GitHub Pages used to serve. `tools/test-docs-worker.sh`
  pins all of it in CI and `tools/check-listing.sh` rejects any other
  `html_handling` value. Don't "align it with the website repo".
- **A non-interactive `wrangler deploy` overrides the DNS record on a declared
  custom domain without asking.** #47 first documented the opposite —
  "production builds fail at the domain step until a human cuts over" — from
  Cloudflare's doc line that a Custom Domain can't be created over an
  existing CNAME. Reading wrangler 4.131.1's `publishCustomDomains` showed
  the real behaviour: when stdout is not a TTY it sets
  `override_existing_origin` and `override_existing_dns_record` to `true`
  and proceeds; only an interactive run asks *"You already have DNS records
  that conflict for these Custom Domains … Update them?"*. Workers Builds is
  non-interactive, so **the `routes` entry for `polyglot.sprue.works` is
  commented out in `wrangler.jsonc` until the human-run cutover** (RUNBOOK
  §1c): uncommenting it and merging *is* the DNS switch. `check-listing.sh`
  allows either no routes or exactly that one custom domain, nothing else.
  Check the harness's actual code path before writing a runbook step around
  a prompt.
- **Copilot's version of that concern was wrong in detail but right in
  effect** (PR #48): it claimed the override applies only to records owned by
  another Worker. wrangler has two separate prompts — one for domains used by
  other Workers (`override_existing_origin`) and one for conflicting DNS
  records generally (`override_existing_dns_record`). Whether Cloudflare's
  API honours the latter over a plain CNAME is still unverified on this
  account, which is why §1c makes a human run it interactively first.

Until that cutover, `docs/CNAME` and `docs/.nojekyll` stay in the repo:
GitHub Pages still serves the live hostname from `main:/docs`, and removing
`CNAME` from the published branch drops its custom domain immediately.
`docs/.assetsignore` keeps them out of the Worker. `check-listing.sh`
enforces the sequencing: while `wrangler.jsonc` declares no route, both
files must exist and be ignored; once the custom domain is declared, all
three may go. Removing them is the last step of RUNBOOK §1c. The old Pages DNS
tooling (`tools/reconcile-pages-dns.sh`, `pages-dns.yml`, the DNS-only
CNAME rule) was retired in #47; don't recreate it — the Worker's custom
domain owns the record after the cutover.
