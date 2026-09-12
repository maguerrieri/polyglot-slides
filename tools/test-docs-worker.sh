#!/usr/bin/env bash
# Serve docs/ the way production does (wrangler dev, local mode, using the
# committed wrangler.jsonc) and pin what the OAuth-verification and
# Marketplace URLs depend on:
#
#   - /, /privacy.html, /terms.html answer 200 directly -- no redirect of any
#     kind, because Google holds those exact URLs (marketplace/RUNBOOK.md);
#   - each body is byte-identical to the file under docs/;
#   - the extensionless paths GitHub Pages served (/privacy, /terms) still
#     resolve, and an unknown path is a 404;
#   - Pages control files and _redirects itself are not served.
#
# Needs node + network on first run (npx fetches wrangler). Used by
# .github/workflows/ci.yml; run locally before changing wrangler.jsonc or
# docs/_redirects.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

work="$(mktemp -d)"
port="${DOCS_WORKER_PORT:-8791}"
pid=
cleanup() {
  # wait reports wrangler's SIGTERM status; that must not become ours.
  if [[ -n "$pid" ]]; then kill "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
  rm -rf "$work"
}
trap cleanup EXIT

failures=0
fail() { echo "FAIL $*" >&2; failures=$((failures + 1)); }
ok() { echo "ok   $*"; }

# Pin the wrangler major: html_handling semantics are what this test guards.
npx --yes wrangler@4 dev --local --port "$port" --ip 127.0.0.1 >"$work/wrangler.log" 2>&1 &
pid=$!
for _ in $(seq 1 90); do
  curl -sf -o /dev/null "http://127.0.0.1:$port/privacy.html" 2>/dev/null && break
  kill -0 "$pid" 2>/dev/null || break
  sleep 1
done
if ! curl -sf -o /dev/null "http://127.0.0.1:$port/privacy.html" 2>/dev/null; then
  cat "$work/wrangler.log" >&2
  echo "FAIL wrangler dev did not come up on port $port" >&2
  exit 1
fi

# status <path> -> "<code> <redirect-url>"
status() { curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "http://127.0.0.1:$port$1"; }

# The pinned URLs: 200, no Location, bytes equal to the source file.
for pair in "/:index.html" "/privacy.html:privacy.html" "/terms.html:terms.html"; do
  path="${pair%%:*}"; file="${pair#*:}"
  s="$(status "$path")"
  [[ "$s" == "200 " ]] || fail "$path returned '$s'; must be 200 with no redirect (Google holds this exact URL)"
  curl -s "http://127.0.0.1:$port$path" >"$work/body"
  if cmp -s "$work/body" "docs/$file"; then ok "$path is 200 and byte-identical to docs/$file"
  else fail "$path body differs from docs/$file"; fi
done

# Extensionless parity with GitHub Pages (a rewrite, still no redirect).
for pair in "/privacy:privacy.html" "/terms:terms.html"; do
  path="${pair%%:*}"; file="${pair#*:}"
  s="$(status "$path")"
  [[ "$s" == "200 " ]] || fail "$path returned '$s'; expected a 200 rewrite to /$file"
  curl -s "http://127.0.0.1:$port$path" | cmp -s - "docs/$file" || fail "$path body differs from docs/$file"
done
ok "/privacy and /terms rewrite to the .html files"

# Nothing redirects: html_handling must stay "none" (auto-trailing-slash
# would 307 /privacy.html -> /privacy).
s="$(status "/index.html")"
[[ "$s" == "200 " ]] || fail "/index.html returned '$s'; html_handling must not redirect .html paths"

[[ "$(status /nope)" == 404* ]] || fail "/nope should be a 404"
for hidden in /_redirects /.assetsignore /CNAME /.nojekyll; do
  [[ "$(status "$hidden")" == 404* ]] || fail "$hidden must not be served"
done
ok "unknown paths and control files are 404"

if (( failures )); then echo "$failures docs-worker check(s) failed" >&2; exit 1; fi
echo "docs worker checks passed"
