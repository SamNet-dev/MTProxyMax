#!/bin/bash
# Aggregate runner for the unit test suite (tests/test_*.sh).
#
# Each test is a self-contained script that sources mtproxymax.sh with
# MTPROXYMAX_SOURCE_ONLY=true, stubs the side-effecting helpers, and exits non-zero
# on any failed assertion. A test that cannot run on this host (e.g. bash too old)
# prints a "SKIP:" line and exits 0 — that is reported as SKIP, never as PASS, so a
# suite that has quietly stopped testing anything stays visible.
#
# Usage:
#   tests/run-all.sh                  # run every tests/test_*.sh
#   tests/run-all.sh guest secret     # only tests whose name contains a substring
#
# Exits non-zero if any test failed or if the selection matched nothing.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# The tests themselves skip on bash < 4.2. Failing loudly here instead is deliberate:
# if the runner exits 0 on an unsupported shell, every test SKIPs and the suite reports
# a misleading green.
if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ] ||
    { [ "${BASH_VERSINFO[0]}" -eq 4 ] && [ "${BASH_VERSINFO[1]:-0}" -lt 2 ]; }; then
    echo "ERROR: bash 4.2+ required to run the suite (got ${BASH_VERSION:-unknown})" >&2
    exit 1
fi

shopt -s nullglob
ALL_TESTS=(tests/test_*.sh)
shopt -u nullglob

if [ "${#ALL_TESTS[@]}" -eq 0 ]; then
    echo "ERROR: no tests/test_*.sh found — run from the repository root" >&2
    exit 1
fi

if [ "$#" -eq 0 ]; then
    SELECTED=("${ALL_TESTS[@]}")
else
    SELECTED=()
    for t in "${ALL_TESTS[@]}"; do
        for f in "$@"; do
            case "$t" in
            *"$f"*)
                SELECTED+=("$t")
                break
                ;;
            esac
        done
    done
    if [ "${#SELECTED[@]}" -eq 0 ]; then
        printf 'ERROR: no test matched: %s\n' "$*" >&2
        exit 1
    fi
fi

# Tests are invoked as `bash tests/<name>.sh` from the repo root. That matters:
# some tests resolve the script under test via $(dirname "$0") and others via
# ${BASH_SOURCE[0]}, and the two only agree for a repo-root-relative path.

# Comma- or space-separated basenames known to fail on this platform. A quarantined test
# still RUNS; its failure is reported as QUARANTINE and does not fail the build. The entry
# is deliberately loud and is expected to be deleted once the underlying bug is fixed —
# this is a way to land CI that is honest about what it cannot yet assert, not a way to
# make red things look green. Callers set it (the CI matrix scopes it per distro).
QUARANTINE="${MTPROXYMAX_QUARANTINE:-}"

is_quarantined() {
    local base name
    base=$(basename "$1")
    for name in ${QUARANTINE//,/ }; do
        [ "$name" = "$base" ] && return 0
    done
    return 1
}

PASSED=0
FAILED=0
SKIPPED=0
QUARANTINED=0
STALE_QUARANTINE=0
FAILED_TESTS=()
SUMMARY_ROWS=""

printf 'Running %d test script(s) in %s\n\n' "${#SELECTED[@]}" "$PWD"

for t in "${SELECTED[@]}"; do
    SECONDS=0
    output=$(bash "$t" 2>&1)
    rc=$?
    elapsed=$SECONDS

    n_pass=$(printf '%s\n' "$output" | grep -c '^  PASS' || true)
    n_fail=$(printf '%s\n' "$output" | grep -c '^  FAIL' || true)

    if [ "$rc" -ne 0 ]; then
        if is_quarantined "$t"; then
            status="QUARANTINE"
            QUARANTINED=$((QUARANTINED + 1))
            printf 'QUARANTINE  %-36s exit=%d  %ds  (known failure — not gating)\n' \
                "$t" "$rc" "$elapsed"
            printf '            %s\n' \
                "$(printf '%s\n' "$output" | grep -m1 '^  FAIL' || echo 'failed')"
        else
            status="FAIL"
            FAILED=$((FAILED + 1))
            FAILED_TESTS+=("$t")
            printf 'FAIL  %-40s exit=%d  %ds\n' "$t" "$rc" "$elapsed"
            # Indent the captured output so a failing test is readable in the log.
            printf '%s\n' "$output" | sed 's/^/      | /'
            echo
        fi
    elif printf '%s\n' "$output" | grep -q '^SKIP:'; then
        status="SKIP"
        SKIPPED=$((SKIPPED + 1))
        printf 'SKIP  %-40s %s\n' "$t" "$(printf '%s\n' "$output" | grep -m1 '^SKIP:')"
    else
        status="PASS"
        PASSED=$((PASSED + 1))
        printf 'PASS  %-40s %d/%d assertions  %ds\n' "$t" "$n_pass" "$((n_pass + n_fail))" "$elapsed"
        # A green test that reported no assertions is worth flagging: it usually means
        # the harness never ran, not that everything is fine.
        if [ "$n_pass" -eq 0 ]; then
            printf '      ! no PASS lines reported — did the test actually run?\n'
        fi
        # A quarantined test that now passes means the entry is stale. That is the way a
        # quarantine list rots: the upstream fix lands, the entry stays, and the suite
        # keeps advertising a failure it no longer has. Report it so it gets removed.
        if is_quarantined "$t"; then
            STALE_QUARANTINE=$((STALE_QUARANTINE + 1))
            printf '      ! still listed as quarantined, but passing — the entry can be removed\n'
        fi
    fi

    SUMMARY_ROWS="${SUMMARY_ROWS}| \`${t}\` | ${status} | ${n_pass} | ${n_fail} | ${elapsed}s |
"
done

printf '\n%s\n' "----------------------------------------"
printf 'total=%d  passed=%d  failed=%d  skipped=%d  quarantined=%d  stale-quarantine=%d\n' \
    "${#SELECTED[@]}" "$PASSED" "$FAILED" "$SKIPPED" "$QUARANTINED" "$STALE_QUARANTINE"

if [ "${#FAILED_TESTS[@]}" -gt 0 ]; then
    printf '\nfailed:\n'
    printf '  - %s\n' "${FAILED_TESTS[@]}"
fi

if [ "$QUARANTINED" -gt 0 ]; then
    printf '\nquarantined (known failures, NOT counted as passing — fix and remove from the list):\n'
    printf '  - %s\n' "${QUARANTINE//,/ }"
fi

if [ "$STALE_QUARANTINE" -gt 0 ]; then
    printf '\n%d quarantined test(s) now pass — remove those entries from MTPROXYMAX_QUARANTINE:\n' \
        "$STALE_QUARANTINE"
    printf '  see the "! still listed as quarantined" markers above\n'
fi

# Surface the same summary in the GitHub Actions job page when running under CI.
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
        echo "## Unit tests"
        echo
        echo "| test | result | pass | fail | time |"
        echo "|---|---|---|---|---|"
        printf '%s' "$SUMMARY_ROWS"
        echo
        printf '**total=%d passed=%d failed=%d skipped=%d quarantined=%d stale-quarantine=%d**\n' \
            "${#SELECTED[@]}" "$PASSED" "$FAILED" "$SKIPPED" "$QUARANTINED" "$STALE_QUARANTINE"
    } >>"$GITHUB_STEP_SUMMARY"
fi

[ "$FAILED" -eq 0 ]
