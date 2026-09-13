# Polyglot Slides

Google Slides Editor add-on: pick your languages once, then translate anything
in the deck with one click. Uses Apps Script's built-in `LanguageApp` (Google
Translate) — free, no API key, no billing. Quota is charged to whoever clicks,
so it scales to many users without a shared limit.

## Install

Marketplace listing: not live yet — see [Distribution](#distribution) for the
status. Until then, **[INSTALL.md](INSTALL.md)** — copy one template deck,
click through one authorization screen, done. No command line, no Apps Script
editor.

## Modes

All three are available from the sidebar and the Extensions menu (menu actions
reuse the last language selection; default is Spanish + Simplified Chinese):

- **Duplicate selection per language** — clones the selected elements as a
  cluster (relative layout preserved), one translated cluster per language,
  stacked below the originals. If text is highlighted inside a box instead,
  the translations are appended as new paragraphs at the bottom of that box
  (works in table cells too).
- **Duplicate current slide per language** — inserts one translated copy of
  the slide per language, directly after it.
- **Duplicate all slides per language** — the same for every slide:
  `slide 1, slide 1 ES, slide 1 ZH, slide 2, …` (asks for confirmation first).

Selection mode understands text boxes, whole tables, and grouped shapes.
Language choice is a per-user multi-select in
the sidebar, persisted via `UserProperties`; the offered list is
`AVAILABLE_LANGUAGES` at the top of `Code.js` — any Google Translate code works.

### Robustness properties

- Translations are fetched **before** anything is mutated; a mid-run failure
  (quota, network) leaves the deck untouched, and a slide copy that fails while
  being filled in is removed.
- Whole-deck runs are size-guarded (refused above ~600 translation calls) and
  time-boxed under the Apps Script 6-minute cap; if time runs out, finished
  slides are complete and the message says how many remain.

### Known limitations

- Speaker notes are not translated.
- Mid-text character formatting (e.g. one bolded word) is flattened in
  translated copies; the box/paragraph base style is preserved.
- Duplicated clusters can land past the bottom slide edge — they're still
  selectable, just drag them where you want.

## Layout

- `src/Code.js` — menu, modes, selection handling, translation
- `src/Sidebar.html` — sidebar UI (language multi-select + mode buttons)
- `src/appsscript.json` — manifest (scopes: current presentation only + container UI)
- `tools/sync-template.sh` — push `src/` to the template deck's bound script
- `tools/release.sh` — cut a numbered script version for a tagged release (CI and local)
- `tools/check-listing.sh`, `tools/render-icons.sh` — Marketplace listing consistency check and icon rendering; both use `tools/png-check.js` to verify the icon artwork fills its canvas
- `wrangler.jsonc` — the Cloudflare Worker that serves `docs/` (see [Docs site](#docs-site)); `tools/test-docs-worker.sh` pins what it serves
- `terraform/` — the `polyglot.sprue.works` DNS record and Workers route (see [Terraform](#terraform)); applied from `main` by `.github/workflows/terraform.yml`
- `marketplace/` — Marketplace listing config, assets, and the publishing runbook
- `docs/` — the docs site: homepage, privacy policy, terms (brand verification); styled by the sprue.works brand theme via `docs/site.css`, checked by `tools/test-docs-theme.sh`
- `tools/lint.sh`, `tools/lint-workflows.sh`, `tools/test-*.sh` — what the CI
  workflow runs
- `.github/workflows/` — `ci.yml` (lint on PRs), `deploy.yml` (push on
  `main`; on `v*` tags cut a version and open the "bump script version"
  tracking issue), `terraform.yml` (validate on PRs; plan and apply
  `terraform/` on `main`), and `oidc-isolation-check.yml` (manual: proves a
  non-`main` ref cannot reach the state bucket). The docs site itself
  deploys from Cloudflare Workers Builds, not from Actions
  ([Docs site](#docs-site))
- `INSTALL.md` — end-user install runbook (and the owner-side sharing setup)

## Develop

```bash
clasp push        # upload src/ to the Apps Script project
clasp open-script # open the project in the browser editor
tools/lint.sh     # what CI runs: syntax-check src/, validate the JSON files
tools/lint-workflows.sh # validate Actions syntax, expressions, and contexts
```

Workflow validation uses `actionlint` when it is installed, or its official
Docker image when Docker is available.

Merging to `main` also pushes automatically — see [Release pipeline](#release-pipeline).

## Test on a real deck (one-time setup)

Editor add-on test deployments can only be created in the Apps Script UI.
This is the developer-side version of [INSTALL.md](INSTALL.md)'s Path B:

1. `clasp open-script`
2. **Deploy → Test deployments**
3. Under *Application(s): Slides*, click **Add test**, pick a presentation, save.
4. Select the test and click **Execute** — the deck opens with the add-on
   loaded under **Extensions → Polyglot Slides**.
5. First run: approve the OAuth prompt (unverified-app warning is expected —
   Advanced → continue).

After that, iterate with `clasp push` and reload the deck.

## Distribution

Target: the **Google Workspace Marketplace**, so a teacher installs with one
click (or an admin installs it for the whole domain). Every install runs the
**script version number** pinned in the Marketplace SDK App Configuration;
a tagged release creates the next number, and a human bumps the pin
(`marketplace/RUNBOOK.md` §4).

What the repo holds — CI validates it (`tools/check-listing.sh`), a human
pastes it:

- `marketplace/listing.json` — everything the Marketplace SDK and OAuth
  consent screen ask for: name, descriptions, category, publisher identity
  (`sprue.works`, with `help@sprue.works` as the public support address and a
  separate developer-contact address), URLs, scopes, the distribution flavor,
  and the script ID the Editor-add-on form pins (a reference to
  `.clasp.json`). The version number that form also pins lives only in the
  console; the repo keeps no copy because it could not verify one.
- `marketplace/description.md` — the store's detailed description.
- `marketplace/assets/` — the icon (`icon.svg`, rendered to the required PNG
  sizes plus `docs/icon.png` by `tools/render-icons.sh`) and, once captured, the 1280×800
  screenshots listed in `marketplace/screenshots.json`.
- `docs/` — the homepage, privacy policy, and terms of service served by
  a Cloudflare Worker ([Docs site](#docs-site)); brand verification requires them. Their colours and type come
  from the sprue.works brand theme (`https://sprue.works/brand/v1/theme.css`)
  through `docs/site.css`; `tools/test-docs-theme.sh` keeps that so and pins
  the legal pages' wording, which OAuth verification reviews.

What stays manual — Google has no write API for any of it — is a one-time
click-through documented step by step in
**[marketplace/RUNBOOK.md](marketplace/RUNBOOK.md)**: pick private-domain vs.
unlisted, connect the docs Worker, attach the script to a GCP project, fill the OAuth
consent screen and Marketplace SDK from `listing.json`, capture screenshots,
publish, and verify from a second account. The listing pins a **script
version number**; after each release someone bumps that field (no re-review
for a version bump alone) before installed users see the new code.

**Until the listing is live**, the template-deck flow in
[INSTALL.md](INSTALL.md) remains the install path (and the dev/testing path
afterwards); push `src/` changes into it with `tools/sync-template.sh`.

## Docs site

`docs/` (https://polyglot.sprue.works: homepage, privacy policy, terms) is a
**Cloudflare Worker with static assets** — assets only, no script — configured
in `wrangler.jsonc` and deployed by **Workers Builds** from this repo, the
same setup as sprue-works/website. There is no build step; the committed
files are what is served.

- **Production:** every push to `main` runs `npx wrangler deploy`, which
  publishes `https://polyglot-slides.igneus-fdc.workers.dev`. That is also
  what https://polyglot.sprue.works serves **once the Terraform cutover has
  run** (`marketplace/RUNBOOK.md` §1c); before it, the hostname still points
  at GitHub Pages.
- **Previews:** every other branch runs `npx wrangler versions upload`, which
  publishes a preview aliased by branch name at
  `https://<alias>-polyglot-slides.igneus-fdc.workers.dev`, where `<alias>` is
  the branch name lowercased with `/` replaced by `-`. PRs get the URL as a
  Workers Builds comment. Check a docs change there, not on `main`.
- **Exact URLs are load-bearing.** `/privacy.html` and `/terms.html` are the
  URLs pasted into the OAuth consent screen and the Marketplace listing, so
  `wrangler.jsonc` sets `html_handling` to `none` (the default would 307 them
  to the extensionless path) and `docs/_redirects` rewrites `/` to
  `index.html` with a 200. `tools/test-docs-worker.sh` (CI) serves `docs/`
  with `wrangler dev` and fails if any of the three URLs redirects or differs
  from the file; `tools/test-docs-theme.sh` pins the legal pages' wording.
- **Hostname and DNS:** `polyglot.sprue.works` is *not* in `wrangler.jsonc`
  (`tools/check-listing.sh` rejects any route there). Its DNS record and the
  Workers route that sends it to this Worker live in [`terraform/`](#terraform),
  where one variable, `cutover`, switches the hostname between GitHub Pages
  and the Worker in a reviewed plan. Declaring it as a `custom_domain` would
  let a production deploy replace the DNS record without asking. The
  one-time cutover is `marketplace/RUNBOOK.md` §1c; until it runs, the live
  hostname still points at GitHub Pages.

Run it locally the way production does with `npx wrangler dev`.

## Terraform

`terraform/` holds the Cloudflare configuration for `polyglot.sprue.works`
that must not live in `wrangler.jsonc`: the hostname's DNS record (imported
from the retired shell reconciler) and, once `variable "cutover"` is `true`,
the Workers route to the docs Worker. Nothing in it is applied by hand. It
mirrors sprue-works/website's `terraform/`:

- **State** lives in the GCS bucket `sprue-works-polyglot-slides-tfstate`
  under the prefix `terraform/polyglot-slides/dns`, provisioned by
  sprue-works/infrastructure as this repo's consumer entry (its issue #1).
  `terraform/backend.tf` declares an empty `gcs` backend; the bucket and
  prefix are passed at `init` from the repository variables
  `TF_STATE_BUCKET` and `TF_STATE_PREFIX`.
- **Identity.** The workflow authenticates to Google with GitHub OIDC
  through the workload identity provider named in the repository variable
  `GCP_WORKLOAD_IDENTITY_PROVIDER`. The provider trusts exactly this
  repository's `refs/heads/main` ref subject, so only the apply job on a push
  to `main` can reach the bucket; the job must not name a GitHub
  Environment, which would change the subject. That is also why there is no
  approval gate and no `workflow_dispatch`: the protected `main` branch is
  the authorization boundary, and a failed apply is re-run with `gh run
  rerun <id>`, which keeps the push event and ref.
  Dispatch `oidc-isolation-check.yml` from a non-`main` branch to confirm
  the rejection.
- **Workflow.** `.github/workflows/terraform.yml` runs on changes under
  `terraform/`. Pull requests get `fmt -check`, `init -backend=false`, and
  `validate` only; a push to `main` that touches those paths additionally
  plans and applies. Between plan and apply, a guard step fails the run if
  any resource being imported would also be changed, so a drifted live
  record is never "corrected" unattended. The apply job is the only place
  the Cloudflare token appears; it needs `Zone:Read`, `DNS:Edit`, and
  `Workers Routes:Edit` on the `sprue.works` zone.
- **Import.** The CNAME was created through the Cloudflare API before this
  Terraform existed. An `import` block adopts it on the first apply from
  `main`; that plan must read `1 to import, 0 to add, 0 to change, 0 to
  destroy`. An in-place change there means live and HCL have drifted: stop
  and reconcile. The record carries `prevent_destroy`.
- **Cutover.** `variable "cutover"` defaults to `false` (DNS-only CNAME to
  GitHub Pages, no route). A PR flipping it to `true` makes the record
  proxied and adds the route: two in-place changes, no gap, and flipping it
  back is the rollback. `tools/check-listing.sh` reads the same default and
  keeps the Pages control files in `docs/` while it is `false`. The
  procedure is `marketplace/RUNBOOK.md` §1c.
- **Local loop.** `terraform -chdir=terraform fmt -recursive`, then
  `terraform -chdir=terraform init -backend=false && terraform -chdir=terraform
  validate`. Plans need the bucket, so they only run from `main` via the
  workflow.

## Release pipeline

`main` is the source of truth for the Apps Script project in `.clasp.json`;
GitHub Actions does the pushing.

| Event | Workflow | What happens |
|---|---|---|
| Pull request | `ci.yml` | App/JSON and Marketplace-listing consistency checks, Actions-aware workflow validation, and stubbed self-tests for release/listing tooling |
| Push to `main` touching `src/`, `.clasp.json`, `tools/release.sh`, `tools/preflight.sh`, or the workflow | `deploy.yml` | `clasp push --force` — the script project's HEAD now matches `main`. A merge that touches none of those (docs, tooling) produces **no Deploy run**; that silence is intended, not a broken trigger |
| Tag `v*` pushed | `deploy.yml` | `tools/release.sh <tag>`: push, then `clasp version "<tag>"`. Nothing is deployed — the Marketplace pins a version *number*. **The number it prints is what a human then pastes into Marketplace SDK → App Configuration → *Slides add-on script version*** (RUNBOOK §4); the workflow opens a tracking issue for that bump |

Cut a release:

```bash
git tag v1.0.0 && git push origin v1.0.0     # or: gh release create v1.0.0
```

The run's summary shows the new version number, and the workflow opens an
issue titled *release vX: bump Slides add-on script version to N*, assigned
to whoever pushed the tag (so the instruction and a direct link to App
Configuration land in their email; set the `RELEASE_BUMP_ASSIGNEE` Actions
variable to route it elsewhere). **After every release**, work that issue:
open Marketplace SDK → App Configuration, enter the new number in *Slides
add-on script version*, Save, and close the issue. Installed users stay on
the old version until then (Google: "update the version number on the App
Configuration page"; no Marketplace re-review for that alone). The repo keeps
no copy of the pinned number, since it has no way to verify one; the open or
closed tracking issue is the record of whether the console is current.

`tools/release.sh v1.0.0` does the same thing locally with a `clasp login`
session (it prints the same instruction but opens no issue).

### One-time setup (needs a human — CI cannot create secrets)

The workflow authenticates as a real Google account: Apps Script's API does
not accept service accounts for script projects, so a user OAuth refresh
token is the only unattended option. That token acts **as the account that
minted it**, with full Apps Script access to every script project that
account can reach. Mint it as the `@sprue.works`
publishing account, which owns the script project in `.clasp.json` (#36);
a personal account's token would only work while that account is shared in
as editor, and ownership cannot be transferred to it later (see `CLAUDE.md`).

1. Signed in as the deploying account, turn on the **Apps Script API** at
   <https://script.google.com/home/usersettings>. This is a per-user toggle,
   separate from enabling the API on the GCP project (RUNBOOK §2), and only
   the deploying account itself can flip it. `clasp push` works without it;
   `clasp version` does not — the first tag after #36 failed there with
   `User has not enabled the Apps Script API` after a successful push. The
   workflow runs `tools/preflight.sh` (`clasp list-versions`) right after
   authenticating so a missing toggle fails every deploy at auth setup, not
   the tag job after its push.
2. **Workspace accounts only:** exempt clasp from Google Cloud session
   control *before* minting the token. A Workspace account under a
   session-control policy must re-authenticate interactively on a schedule,
   which a headless runner cannot do; the deploy then fails at the preflight
   with `invalid_grant` / `invalid_rapt`, and a freshly minted token fails
   the same way after one session. In the Admin console: *Security → Access
   and data control → Google Cloud session control* → enable **Never require
   reauthentication for trusted apps**, then *Security → API controls → App
   access control* → mark **clasp's OAuth client as a trusted app**. This is
   narrower than exempting the account or OU; the policy stays in force for
   everything except clasp. Personal Gmail accounts have no such policy and
   can skip this step.
3. On a machine with clasp 3 installed, log in as the deploying account:
   `clasp login` (add `--no-localhost` on a headless box). Check with
   `clasp show-authorized-user`.
4. Copy the resulting `~/.clasprc.json` **verbatim** — the whole file,
   including `{"tokens":{"default":{...}}}` — into a repo secret named
   **`CLASPRC_JSON`**: *Settings → Secrets and variables → Actions → New
   repository secret*, or
   `gh secret set CLASPRC_JSON < ~/.clasprc.json`.
   The workflow writes the secret to a temp file and passes it to clasp via
   `clasp_config_auth`.
5. (Optional) The job runs in the `apps-script` environment. GitHub creates it
   on the first run; add required reviewers or a `main`/tag deployment-branch
   rule there if you want an approval gate on deploys.
6. Re-run the *Deploy* workflow from the Actions tab via *Run workflow* (a
   push to `main` only triggers it when it touches `src/` or the pipeline
   files) and confirm `clasp show-authorized-user` in the log shows the
   expected account and the `tools/preflight.sh` step passes.

The refresh token stays valid until revoked or the account's password / 2SV
setup changes; if a deploy fails on auth, redo steps 3–4. The preflight step
names the two failures that look alike: `User has not enabled the Apps Script
API` means the deploying account skipped step 1; `invalid_rapt` means
Workspace session control rejected the token and the fix is step 2, not a
re-mint (the token is fine; see `CLAUDE.md`). If the project's
OAuth consent screen (runbook step 3) is in *Testing*, Google expires
refresh tokens after 7 days — the deploying account's login uses clasp's own
client, not the project's, so that limit does not apply here.

### What stays manual

Everything below lives in the Google Cloud console / Apps Script editor and
has no API that a CI job could drive:

- **Marketplace SDK configuration and listing** (app name, icon, screenshots,
  description, visibility, the *Editor add-on* script ID + **script version
  number**). Google's Marketplace API is read-only for listings. The Editor
  add-on form pins a version *number* (there is no deployment-ID field on that
  path — that belongs to the *Google Workspace add-on* type), so **every
  release needs a human to bump the version in App Configuration**. Listing
  text/assets are kept in `marketplace/` so a human can paste them, but the
  paste is manual — [marketplace/RUNBOOK.md](marketplace/RUNBOOK.md).
- **OAuth consent screen** (scopes, branding, verification status) and
  **OAuth verification** for an unlisted listing — brand verification plus
  sensitive-scope review, because `script.container.ui` is classified
  sensitive (runbook steps 1 and 3).
- **Attaching the script to a standard GCP project** (Apps Script editor →
  Project settings) — a prerequisite for Marketplace publishing.
- **Test deployments** for editor add-ons (Apps Script UI only; see above).
- **Publishing / re-submitting** the listing after a change that needs review
  (new scopes, name/branding changes). Bumping the pinned script version
  number does not need re-review, but it is still a console edit per release.
- The **template deck** (`tools/sync-template.sh`) — its bound script is a
  separate project with no CI hook, and it goes away once the listing is live.
