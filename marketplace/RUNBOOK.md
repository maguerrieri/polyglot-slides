# Marketplace publishing runbook

Everything the repo can hold for the Workspace Marketplace listing is in this
directory; everything below is what a **human with the right Google account**
still has to click through. Google exposes no write API for the Marketplace
SDK listing or the OAuth consent screen, so this is a paste-from-repo job, not
a CI job. Budget an hour of clicking plus (unlisted path only) several weeks
of Google review (step 3 explains why).

Paste sources, so nothing is retyped:

| What Google asks for | Where it lives in the repo |
|---|---|
| App name, short description, category, developer name, support + contact emails | `marketplace/listing.json` → `app` |
| Detailed description | `marketplace/description.md` |
| Homepage / privacy policy / terms URLs | `listing.json` → `urls` (served from `docs/` by the Cloudflare Worker in `wrangler.jsonc`) |
| OAuth scopes | `listing.json` → `oauth.scopes` (== `src/appsscript.json`) |
| App icon 128×128 / 32×32, consent-screen logo 120×120 | `marketplace/assets/icon-*.png` |
| Screenshots 1280×800 | `marketplace/assets/` + `marketplace/screenshots.json` (step 7) |
| Editor add-on *Project Script ID* + *script version* | `.clasp.json` → `scriptId` (`listing.json` → `extension.script` points there); the version number the latest `tools/release.sh` run printed (step 4; not recorded in the repo — the release's tracking issue is the record). No deployment ID: the Editor-add-on form never asks for one |
| GCP project number | `556097262294` (step 2) |

`tools/check-listing.sh` (run by CI) fails if any of those drift from the
code, so treat the repo as authoritative and re-paste when it changes.

## 0. Decide the distribution flavor (blocking)

Two options; `listing.json` → `distribution.visibility` records the choice.

| | **`private`** — one school domain | **`unlisted`** — any Google account |
|---|---|---|
| Who can install | Users (and admins, for everyone) in **one** Workspace domain | Anyone with the listing link; not searchable |
| Google review | None | Marketplace listing review + OAuth verification (brand + one sensitive scope) |
| Publishing account | Must be a user **in that domain** with the *Marketplace publisher* role → hand the finished project to the school's IT | The `@sprue.works` publishing account (see "Publishing account" below) |
| Consent screen | Internal user type, no verification | External, verified |
| Time to live | Same day | Marketplace listing review: a few business days. OAuth verification: `script.container.ui` is a **sensitive** scope, so plan on weeks (step 3) |

The question to answer with the requesting teacher: *are all the teachers on
the same school Workspace domain?* Yes → `private` (set
`distribution.privateDomain` to the domain). Mixed / personal Gmail → `unlisted`.
The steps below are written for `unlisted` and mark what `private` skips.

## 1. Publish the static pages (Cloudflare Worker)

The homepage, privacy policy, and terms of service in `docs/` are required
fields on the consent screen and the listing. They are served by a
**Cloudflare Worker with static assets** (assets only, no script) configured
in `wrangler.jsonc` and deployed by **Workers Builds** from this repo, the
same arrangement as sprue-works/website. Production is `main`; every other
branch gets a preview URL (README "Docs site"). CI pins what Google depends
on: `tools/test-docs-worker.sh` serves `docs/` with `wrangler dev` and checks
that `/`, `/privacy.html`, and `/terms.html` answer 200 with no redirect and
byte-identical bodies; `tools/check-listing.sh` checks the config routes
`polyglot.sprue.works` and keeps `html_handling` at `none`.

Until the cutover in 1c has happened, the *live* site is still the legacy
GitHub Pages build of `main:/docs` behind a DNS-only Cloudflare CNAME to
`sprue-works.github.io`. The two coexist: nothing in 1a–1b touches the live
hostname.

### 1a. Connect the repo to Workers Builds (one-time)

From an account with access to the sprue.works Cloudflare account:

1. Cloudflare dashboard → Workers & Pages → Create → **Continue with GitHub**
   → the Cloudflare GitHub App is already authorised for the `sprue-works`
   org from the website; select `sprue-works/polyglot-slides`.
2. Worker name **`polyglot-slides`** (must match `name` in `wrangler.jsonc`),
   production branch `main`, no build command, deploy command left at the
   default. Create and deploy.
3. In the Worker: Settings → Build → enable **non-production branch builds**
   and **pull request comments**. Settings → Domains & Routes should show the
   `workers.dev` route and preview URLs enabled, from `wrangler.jsonc`.

**Expect the production build to fail** at its last step until 1c is done.
`wrangler deploy` uploads the assets, then tries to attach the
`polyglot.sprue.works` custom domain, and Cloudflare refuses to create a
Custom Domain on a hostname that already has a CNAME record. That is the
GitHub Pages CNAME, and removing it *is* the cutover. Branch builds run
`wrangler versions upload`, which never touches domains, so previews work
from the first push.

### 1b. Verify the Worker on its own hostnames

Before touching DNS, prove the Worker serves the pages exactly as Pages does:

1. Open the PR's preview URL (the Workers Builds comment, or
   `https://<branch-alias>-polyglot-slides.igneus-fdc.workers.dev/`) and,
   after the merge, the production copy at
   `https://polyglot-slides.igneus-fdc.workers.dev/`.
2. From a checkout of `main`, compare bytes and status codes for the URLs
   Google holds:

   ```bash
   host=polyglot-slides.igneus-fdc.workers.dev
   for p in / /privacy.html /terms.html; do
     curl -s -o /dev/null -w "$p %{http_code} %{redirect_url}\n" "https://$host$p"
   done
   curl -s "https://$host/" | cmp - docs/index.html
   curl -s "https://$host/privacy.html" | cmp - docs/privacy.html
   curl -s "https://$host/terms.html" | cmp - docs/terms.html
   ```

   Every line must be `200` with an empty redirect URL and every `cmp`
   silent. A `307` here means `html_handling` drifted from `none`.

### 1c. Cut over DNS from GitHub Pages (production-affecting; a human does this)

Google's reviewers fetch `https://polyglot.sprue.works/privacy.html` and
`/terms.html` by exactly those URLs while verification is in progress, so
the switch has to be one atomic record change, not a delete-then-add.
Cloudflare's Custom Domain attach can replace the existing record in one
API call, and `wrangler deploy` run **interactively** offers exactly that:

1. From a checkout of `main`, signed in to the sprue.works Cloudflare account:

   ```bash
   npx wrangler@4 login
   npx wrangler@4 deploy
   ```

   Wrangler uploads the assets, detects the existing CNAME on
   `polyglot.sprue.works`, and asks whether to **override the existing DNS
   record**. Answer yes. Cloudflare swaps the CNAME for the Worker's own
   proxied record and the certificate (Universal SSL already covers the
   first-level subdomain), so the hostname never resolves to nothing.
   Wrangler refuses this in non-interactive runs, which is why Workers Builds
   could not do it.

   If the prompt does not appear (wrangler behaviour changed), **stop** rather
   than deleting the CNAME by hand: a dashboard delete-then-add leaves the
   hostname unresolvable for the gap between the two, and one 404 seen by a
   reviewer costs a multi-day review round. Fall back to the Cloudflare API's
   attach-domain call with `override_existing_dns_record` set, or ask in
   sprue-works/website how its domains were first attached.

2. Verify the live hostname the same way as 1b, with
   `host=polyglot.sprue.works`, plus one request through a resolver that has
   not cached the old answer (`curl --resolve` against a Cloudflare edge IP,
   or a phone off wifi). The Pages CNAME had a 1-second TTL, so the switch is
   visible within seconds.

3. Retry the failed Workers Builds production build (Worker → Deployments →
   Retry) so `main` is green, then push a trivial branch to confirm previews
   still comment on the PR.

4. Switch GitHub Pages off so it cannot be re-pointed at the hostname:

   ```bash
   gh api -X DELETE repos/sprue-works/polyglot-slides/pages
   ```

   Organization Settings → Pages → Verified domains may keep `sprue.works`;
   it is harmless and blocks another repo from claiming the hostname on
   GitHub's side.

5. Open the post-cutover cleanup PR: delete `docs/CNAME`, `docs/.nojekyll`
   and the two lines that name them in `docs/.assetsignore` (the
   `check-listing.sh` self-test already covers that shape); delete the
   **`pages-dns`** environment and the `CLOUDFLARE_API_TOKEN` secret /
   `CLOUDFLARE_ZONE_ID` variable in repo settings (nothing reads them any
   more, and the token can be revoked in Cloudflare); drop the
   "Until the cutover" paragraph above and this step. Nothing in that PR
   touches a served byte, so the URLs stay as they are.

**Brand verification needs proof you own the homepage's domain.** Add
`sprue.works` to Search Console and complete its DNS verification before the
OAuth brand-verification step. This is separate from GitHub's organization
domain verification above. *`private` skips the Google verification.*

## Publishing account and support group (prerequisite for steps 2–5)

Do everything from step 2 on as **one `@sprue.works` Google Workspace
account** — not a gmail address and not a personal domain. `sprue.works` is
already a Workspace domain, so no workaround account is needed. Google's
OAuth **brand verification** checks that the publisher name, the support
email, and the verified homepage domain agree; `listing.json` puts all three on
`sprue.works`, and a personal or gmail address fronting a `sprue.works`
homepage is the mismatch that costs a full review round trip.

The publishing account must:

0. **Own the Apps Script project in `.clasp.json`** (ideally via a
   sprue.works Shared Drive, so the org rather than one user owns it). It
   cannot be moved there later from a personal account: Google does not
   transfer Drive ownership across the consumer/Workspace boundary (see
   `CLAUDE.md`, #36). Create it signed in as the publishing account.

1. **Own the GCP project** from step 2 (create it while signed in as that
   account, or be granted *Owner*), and hold the *Marketplace publisher*
   ability that comes with owning the project's Marketplace SDK.
2. **Verify `sprue.works` in Search Console itself.** Verification is per
   account: the `google-site-verification` TXT already on the domain may belong
   to a different account and does not carry over. Add the property from the
   publishing account and add its own TXT record — several verification TXT
   records on one domain coexist fine.
3. **Manage the `help@sprue.works` and `contact@sprue.works` Google Groups.** The consent screen's *User
   support email* is a **dropdown**, not free text: it offers only the signed-in
   account's own address and Google Groups that account owns or manages. If
   `help@sprue.works` is missing from the dropdown, the account is not a
   manager/owner of the group.

Create both groups in **Admin console → Directory → Groups → Create group**
(`help@sprue.works` and `contact@sprue.works`, the publishing account as an
owner of each). Then fix the **external-posting gotcha** on both: groups default
to accepting posts only from inside the organization, which would **silently
bounce a teacher's support email** — and, on `contact@`, Google's own
verification questions, stalling the review with no signal. In each group's
*Access settings*, set **Who can post** to *Anyone on the web* (or at minimum
allow posting from outside the organization) and, under *Who can join /
Membership*, keep external members off — external *posting* is the only
relaxation needed. Send a test message from a non-`sprue.works` address to each
and confirm it arrives before pasting the addresses anywhere.

The two addresses in `listing.json` → `app` have different rules, which is why
there are two:

| Field | Address | Rule |
|---|---|---|
| `app.supportEmail` | `help@sprue.works` | Public. Consent-screen *User support email* (dropdown: account or a managed Google Group) and Marketplace SDK *Developer email*. Shown to users. |
| `app.contactEmail` | `contact@sprue.works` | Not shown to users. Consent-screen *Developer contact information* (free text, several allowed). Where Google emails about verification and project changes — a group so no personal address is published; must be read daily. |

`urls.support` stays the GitHub issues URL; that field is a link, not a mailbox.

## 2. Create a standard GCP project and enable the APIs

Apps Script projects get a hidden default GCP project; Marketplace publishing
needs a standard one. **Order matters:** the Apps Script editor refuses
*Change project* until the target project already has a configured OAuth
consent screen, so this step only *creates* the project — the consent screen
is step 3 and the attach is step 3b. (The original runbook attached first and
failed exactly there.)

1. [console.cloud.google.com](https://console.cloud.google.com), signed in as
   the `@sprue.works` publishing account → create a
   project (suggested name `polyglot-slides`). Note its **project number**
   (Dashboard, not the ID). No billing account needed.

   Done 2026-09-02: the project is **`polyglot-slides`, project number
   `556097262294`**. That number is what step 3b pastes and what
   `https://console.cloud.google.com/...?project=556097262294` links need.
2. In the GCP project, **APIs & Services → Library**, enable:
   - **Google Workspace Marketplace SDK** — its Library page
     ([direct link](https://console.cloud.google.com/apis/api/appsmarket-component.googleapis.com/googleapps_sdk?project=556097262294))
     is also the only way *into* the SDK later: there is no left-nav entry;
     click **Manage** on that page to reach *App Configuration* / *Store
     Listing* (steps 4–5).
   - **Apps Script API**. This project-level enablement is *not* the
     per-user toggle at <https://script.google.com/home/usersettings>, which
     the deploying account must flip itself (README "One-time setup" step 1).
     A green push-to-main deploy proves neither: `clasp push` succeeds without
     the per-user toggle and only `clasp version` fails (the `v1.0.1` tag run
     did exactly that, after #36 moved the project to the publishing
     account). `deploy.yml` now runs `clasp list-versions` at auth setup so
     the gap surfaces on the next deploy rather than on the next tag.

## 3. OAuth consent screen

**APIs & Services → OAuth consent screen** (now under *Google Auth
platform → Branding / Audience / Data access* in newer consoles). Configure
this *before* step 3b — Apps Script checks for it:

| Field | Value |
|---|---|
| User type | `unlisted`: **External**. `private`: **Internal** |
| App name | `listing.json` → `app.name` |
| User support email | `app.supportEmail` (`help@sprue.works`). **Dropdown**, not free text — lists only the signed-in account and Google Groups it owns/manages. If the group is absent, fix the group membership (prerequisite above); do not fall back to a personal address |
| App logo | `marketplace/assets/icon-120.png` |
| App home page | `urls.homepage` |
| Privacy policy | `urls.privacyPolicy` |
| Terms of service | `urls.termsOfService` |
| Authorized domains | `sprue.works` |
| Developer contact information | `app.contactEmail` (`contact@sprue.works`) — free text, several allowed; this is where Google sends verification questions. Keep personal addresses out of it |
| Scopes | exactly `oauth.scopes`. *Data access → Add or remove scopes*: `presentations.currentonly` is in the filter table, but **`script.container.ui` is not listed there at all** — paste it into the **Manually add scopes** box at the bottom of the panel and click *Add to table*, then *Update* and **Save**. Confirm both rows appear before leaving the page |

**`script.container.ui` is classified as a *sensitive* scope** (it lands in
the *Your sensitive scopes* section of the table; `presentations.currentonly`
is non-sensitive). Sensitive-scope verification therefore applies, not brand
verification alone: Google's reviewers expect a **written justification** for
the scope (why the add-on needs to draw a sidebar in the Slides UI — that is
what the scope is; it reads no user data) and a **demo video of the consent
flow** from a test account. Google's own budget is "typically 3–5 business
days" for the sensitive-scope review, but it only starts once branding is
published, each reviewer question is a fresh round through
`contact@sprue.works`, and this is what the 3–5-day estimates elsewhere in
this repo never accounted for — so plan on **weeks end to end**, not days.
What it is **not** is a CASA security assessment; that is required only for
*restricted* scopes, and neither of ours is restricted. Draft the
justification before submitting (step 6) so the reviewer's first email does
not cost a round trip.

**The privacy policy is reviewed against a checklist — match its words.**
Verification round 1 (2026-09-04, #41) rejected `docs/privacy.html` on five
findings even though the page already described the add-on's behavior: the
reviewer pattern-matches for explicit disclosures under headings that use
Google's own vocabulary, literally "Google user data", and a section that
merely implies one of them counts as missing. Before every submission or
resubmission, confirm the page at `urls.privacyPolicy` has a clearly headed
section for **each** of these, in these words:

- [ ] what **Google user data** the app **accesses** (each scope, in plain
      words, plus what it does *not* access);
- [ ] how the app **uses** Google user data (the one purpose; Limited Use
      statement);
- [ ] with whom the app **shares, transfers, or discloses** Google user data
      (every transfer named — for us, the text sent to Google Translate via
      `LanguageApp` — and an explicit "no one else");
- [ ] how the app **protects** Google user data (where it runs, what the
      developer can and cannot access, what is stored where);
- [ ] **retention and deletion** of Google user data (what is kept, for how
      long, how the user gets rid of it);
- [ ] the **AI/ML model-training disclosure** the sensitive-scope email lists
      as a requirement: the app does not use Google user data to develop,
      improve, or train generalized AI/ML models.

Every claim on the page must be true to `src/Code.js` and `src/Sidebar.html`
(no server, one user property, `LanguageApp` only, the open presentation
only); do not pad it with retention periods or certifications that don't
exist. Bump the effective date when the page changes. If a round rejects the
policy, fix the page, confirm the Workers Builds deploy of `main` published it, resubmit in the
Verification Center, **and reply to Google's email** — verification does not
continue without the reply.

Leave the app in **Testing** until the listing is ready, then **Publish app**
and **Prepare for verification** → submit. Google emails questions to the
developer contact; proof of domain ownership (step 1) is the other usual ask.

**Brand verification needs domain control, not a company.** It checks that
the publisher name, support address, and homepage all sit on a domain the
account has verified — no registered legal entity is required. Separately,
the submission flow may ask for an **EU Digital Services Act trader-status
declaration**; for a free add-on from an unregistered brand answer
**non-trader** (revisit if the add-on is ever monetized). Answer it rather
than skipping: an undeclared status shows as "Trader status unspecified" on
the public listing. Separately, the Marketplace program policies require the
*listing* to state the developer's legal business name and a physical
business address — a listing-content rule, not an entity check; decide what
address `sprue.works` publishes before step 5.

While the consent screen is in *Testing* only listed test users can authorize
(and refresh tokens expire after 7 days — the CI deploy account is unaffected;
it uses clasp's own client).

## 3b. Attach the script to the GCP project

Now that the project has a consent screen, Apps Script will accept it:

Apps Script editor for the script in `.clasp.json` (`clasp open-script`) →
⚙️ **Project settings → Google Cloud Platform (GCP) project → Change
project** → paste the project number (`556097262294`). If this is refused,
the consent screen in step 3 is not saved yet.

Done 2026-09-02 for the *old*, personally owned script; **redo it for the
org-owned project** that #36 puts in `.clasp.json` — the attachment belongs
to the script project, so a new project starts unattached.

## 4. Marketplace SDK configuration

There is no left-nav entry for the SDK. Open its API Library page
([direct link](https://console.cloud.google.com/apis/api/appsmarket-component.googleapis.com/googleapps_sdk?project=556097262294),
or *APIs & Services → Enabled APIs & services → Google Workspace Marketplace
SDK*) and click **Manage**, then the **App Configuration** tab:

| Field | Value |
|---|---|
| App visibility | `distribution.visibility`: **Private** (own domain) or **Public** with *Unlisted* checked. **Private vs Public is irreversible once saved** — the SDK will not let you switch later; only the *Unlisted* checkbox under Public can be changed afterwards. Get `listing.json` → `distribution.visibility` right before clicking Save |
| Installation settings | **Individual + Admin install** (admins can push to a whole domain) |
| App integration | **Editor add-on** → tick **Slides**. Do **not** tick *Google Workspace add-on* — that is a different architecture (an `addOns` manifest block, card-based UI) and this add-on is a classic Editor add-on (`createAddonMenu` + HtmlService sidebar) |
| Slides add-on Project Script ID | `.clasp.json` → `scriptId` — the org-owned project (#36); copy it from the file, never from memory |
| Slides add-on script version | the **version number** to serve — the one `tools/release.sh` printed for the latest tag (`clasp versions` lists them all). Entered as `1` on 2026-09-02 for the old project; the org-owned project's numbering restarts at `1`. Not mirrored in the repo: the release's tracking issue (below) is the record |
| OAuth scopes | the same two scopes, verbatim |
| Developer name / website / email | `app.developerName` (`sprue.works`, exactly that casing), `urls.homepage`, `app.supportEmail` (`help@sprue.works`) |

Save. Configuration was saved as a draft 2026-09-02 with the *old* script
ID and version 1; after #36 merges, **repaste the new Project Script ID and
the new project's version 1** (versions restart at 1 on the new project).

**There is no deployment ID field on this path.** Google's docs are explicit:
"to publish an Editor add-on, you must provide the project script ID and
version"; a deployment ID is what a *Google Workspace add-on* is published
by. The deployment-ID field only appears if you tick *Google Workspace
add-on*, which this add-on is not. Earlier revisions of this runbook, of
`README.md`, and of `CLAUDE.md` said the listing points at a
`deployment.json` → `deploymentId`; that was wrong for this add-on type, and
#29 removed the file and the deployment step from the release pipeline.

**Consequence for releases — a version number is pinned, not a moving
target.** Google's update procedure for a published Editor add-on is: create
a new version, then "update the version number on the App Configuration page
of the Google Workspace Marketplace SDK". So a tagged release
(`tools/release.sh`) does *not* reach installed users by itself: someone must come
back to this form and bump *Slides add-on script version* to the new number.
Changing only that field is not in Google's list of changes that trigger a
new Marketplace review (those are the *App Details* text fields and adding a
new integration type), and users do not reinstall — but if the release added
scopes they re-authorize, and the consent screen + this form's scope list
must be updated first.

The pipeline makes that step hard to forget: each tag's `deploy.yml` run
opens an issue titled *release vX: bump Slides add-on script version to N*,
assigned to whoever pushed the tag, and prints the same instruction in its
step summary. Enter `N` in this form's *Slides add-on script version*, Save,
and close the issue. The repo keeps no copy of the pinned number (it cannot
verify one), so an open bump issue is the signal that the console is behind
the latest release, and a closed one is the record that it caught up.

## 5. Store listing

**Marketplace SDK → Store Listing**:

| Field | Value |
|---|---|
| Category | `app.category` |
| Language | `app.language` |
| Application name | `app.name` |
| Short description | `app.shortDescription` |
| Detailed description | `marketplace/description.md` is the paste source and must match the console **verbatim** — `check-listing.sh` cannot read the console, so the repo file is the only record of what is live (trimmed at submission to the three mode bullets). Markdown is not rendered; paste as plain text, keep the blank lines |
| Application icons | `icon-128.png`, `icon-32.png` |
| Application card banner | `assets.cardBanner220` → `marketplace/assets/banner-220x140.png` (required, exactly 220×140; rendered from `banner.svg` by `tools/render-icons.sh`) |
| Post-install tip | `app.postInstallTip` (required; names the Extensions menu path, so re-check it if the menu labels in `src/Code.js` change) |
| Screenshots | from step 7 (at least one) |
| Support links | Terms `urls.termsOfService`, Privacy `urls.privacyPolicy`, Support `urls.support` (the issue tracker URL, not an email) |
| Developer name / email | `app.developerName` / `app.supportEmail` (prefilled from step 4 in most consoles; confirm they still read `sprue.works` / `help@sprue.works`) |
| Regions | all |
| Draft Tester Email Addresses | the Google accounts that should see the **draft** listing before it is published (up to 100; for a public listing they must be Gmail accounts). Testers are not notified when added |
| Draft Tester Opt-Out URL | `urls.draftTesterOptOut` (required; Google: "a mechanism, such as a web form, that lets testers indicate that they don't want to be draft testers" — ours is the issue tracker, so a tester opts out by filing an issue, and the list above must be pruned by hand) |
| Developer legal name / physical address | required by the Marketplace program policies for every listing (see step 3). Use the `sprue.works` details settled there |

**Two tester lists, two gates** (hit live during the first submission): the
Store Listing's *draft testers* control who can **see** the draft listing on
the Marketplace; the OAuth consent screen's *Test users* (step 3) control who
can **authorize** the add-on while the consent screen is in *Testing*. A
tester who is on only one list either finds no listing or finds it and is
refused at the consent prompt, so add them to both.

## 6. Publish

- `private`: **Publish**. It appears in the domain's Marketplace immediately;
  an admin can install it for everyone from **Admin console → Apps → Google
  Workspace Marketplace apps**.
- `unlisted`: **Submit for review** (the *Publish* button becomes *Submit*).
  Two reviews run: the Marketplace listing review (a few business days) and
  the OAuth verification from step 3, which is a **sensitive-scope** review
  because of `script.container.ui` — expect Google to ask for the scope
  justification and a consent-flow demo video, and expect **several weeks**
  end to end rather than 3–5 days. The submission may also present the EU
  DSA trader-status question (step 3: non-trader). Common Marketplace
  rejections: screenshots that don't show the add-on in Slides, a consent
  screen still in Testing, homepage missing the privacy link (ours has it),
  and a privacy policy that fails the five-disclosure checklist in step 3
  (round 1 did — walk the checklist before resubmitting). Fix and resubmit;
  the Marketplace review thread is in the Marketplace SDK page, the OAuth
  one in the Verification Center plus the email, which needs a reply.

Once live, the listing URL is
`https://workspace.google.com/marketplace/app/polyglot_slides/<app-id>`.
Put it in `docs/index.html` (`#install`) and README "Install" and commit.

## 7. Screenshots (needed before step 5)

Capture at **1280×800** from a deck that shows the add-on doing something
recognisable; three is plenty:

1. The sidebar open with languages selected, next to an untranslated slide.
2. A slide after *Duplicate selection per language* — originals plus the
   translated clusters below.
3. The Extensions → Polyglot Slides menu.

Save as `marketplace/assets/screenshot-<n>.png`, list them in
`marketplace/screenshots.json`, run `tools/check-listing.sh`, commit.

## 8. Verify as a teacher (acceptance)

Use a **second Google account** — the owner's account cannot see the real
consent flow. From the listing link (or, for `private`, the domain
Marketplace): **Install** → the consent screen names *Polyglot Slides*, shows
the icon, lists only "see and edit the presentation this add-on is open in"
and "display content in the Slides UI", and shows **no** "unverified app"
interstitial. Then open any deck → **Extensions → Polyglot Slides** is present
without copying anything. Re-run INSTALL.md's functional checklist from there.

## Ongoing: what changes need what

| Change | CI does | Human does |
|---|---|---|
| Code in `src/` | push on merge; tag → new numbered version + a tracking issue for the bump | **bump *Slides add-on script version* in step 4 to the new number and close the tracking issue** — until then installed users keep the old version. No re-review for a version bump alone |
| `oauthScopes` in `appsscript.json` | CI fails until `listing.json` matches | update consent screen + Marketplace SDK scopes; re-verification |
| Name, icon, description | `check-listing.sh` validates the files | re-paste (steps 3–5); name/logo changes re-trigger brand verification |
| `docs/privacy.html` wording (also `terms.html`) | the PR gets a preview at `https://<branch-alias>-polyglot-slides.igneus-fdc.workers.dev/privacy.html` (Workers Builds comment); Workers Builds redeploys `main` on merge; `check-listing.sh` checks the URL resolves to the file; `test-docs-worker.sh` checks it is served 200 without a redirect; `test-docs-theme.sh` fails until the text fixture is regenerated (`--update-fixtures`), so a wording change is always deliberate | walk the five-disclosure checklist (step 3); the URL is unchanged so nothing to re-paste, but a pending verification round needs a resubmit + email reply. Styling-only changes leave the text pinned and need nothing |
| `developerName`, `supportEmail`, `contactEmail` | `check-listing.sh` enforces `sprue.works` / an `@sprue.works` support address | re-paste (steps 3–5); a publisher-name or support-email change re-triggers brand verification |
