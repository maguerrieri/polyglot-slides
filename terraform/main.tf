# Cloudflare configuration for polyglot.sprue.works: the hostname's DNS record
# and, once cut over, the Workers route that sends it to the docs-site Worker.
#
# Why Terraform owns the hostname rather than a `custom_domain` route in
# wrangler.jsonc: a non-interactive `wrangler deploy` (what Workers Builds
# runs) attaches a Custom Domain by replacing whatever DNS record exists on
# the hostname without asking, and the Terraform provider cannot express that
# replacement atomically either. A Workers *route* over a proxied DNS record
# can be reached with two in-place changes and no gap, so that is the shape
# here, and wrangler.jsonc declares no route at all (tools/check-listing.sh
# enforces that). See marketplace/RUNBOOK.md §1c and CLAUDE.md "The docs site
# is a Worker".
#
# State lives in the GCS bucket that sprue-works/infrastructure provisions for
# this repository (backend.tf). Pushes to main that touch terraform/ (or the
# workflow) plan and apply through .github/workflows/terraform.yml -- push
# only, no manual dispatch -- with CLOUDFLARE_API_TOKEN (Zone:Read,
# Zone:DNS:Edit, Zone:Workers Routes:Edit on sprue.works) from the repository
# secret of that name. Nothing here is applied by hand.

terraform {
  required_version = ">= 1.5"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

provider "cloudflare" {}

variable "zone_id" {
  description = "Cloudflare zone ID for sprue.works"
  type        = string
  default     = "0a2832ed293070b06bd75cb7fc8db4d7"
}

variable "hostname" {
  description = "Hostname the docs site is served on (pinned by the OAuth consent screen and the Marketplace listing)"
  type        = string
  default     = "polyglot.sprue.works"
}

variable "worker_name" {
  description = "Name of the Worker in wrangler.jsonc that serves docs/"
  type        = string
  default     = "polyglot-slides"
}

# The cutover switch. false: the record is the DNS-only CNAME to GitHub Pages
# exactly as it exists today, and there is no route. true: the record becomes
# proxied (an in-place update; GitHub Pages keeps serving through Cloudflare,
# whose SSL mode for the zone is Full) and the route below sends the hostname
# to the Worker instead. Flip it in its own PR (RUNBOOK §1c); flipping it back
# is the rollback.
variable "cutover" {
  description = "Serve polyglot.sprue.works from the Worker (true) or leave it on GitHub Pages (false)"
  type        = bool
  default     = false
}

# The record was created through the Cloudflare API by the retired
# tools/reconcile-pages-dns.sh. This import block adopts it into state on the
# first apply from main; the plan for that apply must read
# "1 to import, 0 to add, 0 to change, 0 to destroy". Once it is in state the
# block is a no-op and stays as a record of where the resource came from.
import {
  to = cloudflare_dns_record.docs_site
  id = "0a2832ed293070b06bd75cb7fc8db4d7/828fa1c4c5c6e6afef6cab8eaf099f6e"
}

resource "cloudflare_dns_record" "docs_site" {
  zone_id = var.zone_id
  name    = var.hostname
  type    = "CNAME"
  content = "sprue-works.github.io"
  ttl     = 1
  proxied = var.cutover
  # No `comment`: the live record has none, and the first plan must be a
  # pure import ("0 to change"). Add one in a later PR if wanted.

  lifecycle {
    # The hostname is what Google holds; a replacement would leave it
    # unresolvable for the gap. Every change here must be in place.
    prevent_destroy = true
  }
}

# Present only after the cutover. A Workers route needs a proxied record on
# the hostname to receive traffic, hence the dependency on the record update.
resource "cloudflare_workers_route" "docs_site" {
  count = var.cutover ? 1 : 0

  zone_id = var.zone_id
  pattern = "${var.hostname}/*"
  script  = var.worker_name

  depends_on = [cloudflare_dns_record.docs_site]
}
