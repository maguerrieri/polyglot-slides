#!/usr/bin/env bash
# Self-test for tools/preflight.sh against a stubbed clasp (no network, no
# auth). Asserts that the preflight makes exactly one read-only call and maps
# each known failure to the hint that names its fix -- the raw Google error
# for a Workspace session-control rejection (invalid_rapt) reads like a bad
# token, and the fix is in the Admin console, not a re-mint (#51).
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/bin"
cp "$repo_root/tools/preflight.sh" "$work/"

# Stub clasp: logs every invocation; CLASP_STUB_OUT / CLASP_STUB_STATUS drive
# what list-versions prints and how it exits.
cat >"$work/bin/clasp" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"$CLASP_LOG"
printf '%s\n' "${CLASP_STUB_OUT:-}"
exit "${CLASP_STUB_STATUS:-0}"
STUB
chmod +x "$work/bin/clasp"
export PATH="$work/bin:$PATH"
unset GITHUB_ACTIONS

fail() { echo "FAIL: $*" >&2; exit 1; }

run_case() { # run_case <name> <stub-output> <stub-status>; sets $status, $out
  export CLASP_LOG="$work/log.$1"; : >"$CLASP_LOG"
  export CLASP_STUB_OUT="$2" CLASP_STUB_STATUS="$3"
  status=0
  out="$("$work/preflight.sh" 2>&1)" || status=$?
  [ "$(cat "$CLASP_LOG")" = "list-versions" ] || fail "$1: preflight must run exactly 'clasp list-versions' (got: $(cat "$CLASP_LOG"))"
}

# --- Case 1: success -> exit 0, no hint.
run_case ok '~ 3 Versions ~' 0
[ "$status" -eq 0 ] || fail "case 1: success must exit 0"
grep -q 'preflight ok' <<<"$out" || fail "case 1: success must say so"
grep -qi 'preflight failed' <<<"$out" && fail "case 1: no failure hint on success"
echo "ok   a passing list-versions passes the preflight"

# --- Case 2: Workspace session control rejects the refresh token.
rapt='{"error":"invalid_grant","error_description":"reauth related error (invalid_rapt)","error_uri":"https://support.google.com/a/answer/9368756","error_subtype":"invalid_rapt"}'
run_case rapt "$rapt" 1
[ "$status" -ne 0 ] || fail "case 2: invalid_rapt must fail the preflight"
grep -q 'session-control' <<<"$out" || fail "case 2: invalid_rapt must be diagnosed as Workspace session control"
grep -q 'trusted-app' <<<"$out" || fail "case 2: hint must name the trusted-app exemption"
grep -q 'CLAUDE.md' <<<"$out" || fail "case 2: hint must point at CLAUDE.md"
grep -q 'invalid_rapt' <<<"$out" || fail "case 2: raw clasp output must still be shown"
grep -q 'usersettings' <<<"$out" && fail "case 2: invalid_rapt must not be blamed on the per-user toggle"
echo "ok   invalid_rapt is diagnosed as session control, not the toggle"

# --- Case 3: the per-user Apps Script API toggle is off.
run_case toggle 'Error: User has not enabled the Apps Script API. Enable it by visiting https://script.google.com/home/usersettings then retry.' 1
[ "$status" -ne 0 ] || fail "case 3: toggle error must fail the preflight"
grep -q 'per-user Apps Script API toggle' <<<"$out" || fail "case 3: toggle error must produce the toggle hint"
grep -q 'usersettings' <<<"$out" || fail "case 3: toggle hint must link the toggle page"
grep -q 'session-control' <<<"$out" && fail "case 3: toggle error must not produce the session-control hint"
echo "ok   the per-user toggle error still produces the toggle hint"

# --- Case 4: anything else -> raw output, generic failure, clasp's exit code.
run_case other 'Error: something new and unexpected' 3
[ "$status" -eq 3 ] || fail "case 4: unknown failures must propagate clasp's exit code (got $status)"
grep -q 'something new and unexpected' <<<"$out" || fail "case 4: raw output must be shown"
grep -q 'raw output above' <<<"$out" || fail "case 4: unknown failure must say it is undiagnosed"
grep -Eq 'session-control|usersettings' <<<"$out" && fail "case 4: unknown failures must not get a specific hint"
echo "ok   unknown failures surface raw output and exit code"

# --- Case 5: under GitHub Actions, the hint is also an ::error annotation.
export GITHUB_ACTIONS=true
run_case annot "$rapt" 1
grep -q '^::error::.*session-control' <<<"$out" || fail "case 5: hint must be emitted as an Actions error annotation"
unset GITHUB_ACTIONS
echo "ok   hints become Actions error annotations in CI"

echo "all preflight.sh tests passed"
