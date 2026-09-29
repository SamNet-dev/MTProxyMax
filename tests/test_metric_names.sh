#!/bin/bash
# Regression tests for the Prometheus counter names the script scrapes.
#
# Every assertion here exists because of a specific upstream telemt change. The failure
# mode they guard is silent by construction: an awk sum over a pattern that matches
# nothing yields 0 rather than an error, so a stale metric name shows up as a plausible
# zero instead of as a problem.
#
# ── 1. Conventional _total suffix on the user octet counters ──────────────────────
#
#   telemt commit ede3314bee356339dca4ca1b378c251ebac15358 — 2026-08-01
#   "Fix name metric counter"
#   https://github.com/telemt/telemt/commit/ede3314bee356339dca4ca1b378c251ebac15358
#
#   First released in telemt 3.5.4 (the names are absent in 3.5.0–3.5.3). It renamed
#   telemt_user_octets_from_client -> telemt_user_octets_from_client_total and the
#   _to_client pair likewise. The old spellings were removed in the same commit, so the
#   two never coexisted in any release — which is why MTProxyMax matches the _total
#   spelling exactly rather than using a tolerant `(_total)?` pattern that would
#   double-count if both ever appeared together.
#
#   MTProxyMax required `{` immediately after `client`, so from 3.5.4 on nothing matched
#   and every traffic figure across the manager read 0.
#
# ── 2. Removal of the aggregate connection gauges ─────────────────────────────────
#
#   telemt commit c07b600acb6bb59762bd96af6ce5b7fa90ec9de1 — 2026-03-19
#   "Integration hardening: reconcile main+flow-sec API drift and restore green suite"
#   https://github.com/telemt/telemt/commit/c07b600acb6bb59762bd96af6ce5b7fa90ec9de1
#
#   It deleted telemt_connections_current, telemt_connections_me_current and
#   telemt_connections_direct_current outright. That predates 3.5.0, so they are absent
#   from every 3.5.x release — the aggregate now has to be derived from the per-user
#   gauge telemt_user_connections_current.
#
#   Note these were referenced with a trailing space (`/^name /`), not `{`, which is why
#   a sweep of `telemt_*{` patterns does not find them.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

TEST_TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'mtp_metrics_XXXXXX')
INSTALL_DIR="$TEST_TMPDIR/install"
mkdir -p "$INSTALL_DIR/relay_stats"
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

MTPROXYMAX_SOURCE_ONLY=true source "$REPO_ROOT/mtproxymax.sh"
set +e
trap 'rm -rf "$TEST_TMPDIR"' EXIT

TESTS_RUN=0
TESTS_FAILED=0

assert_eq() {
    local name="$1" want="$2" got="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$got" = "$want" ]; then
        printf '  PASS  %s\n' "$name"
    else
        printf '  FAIL  %s (got=%q want=%q)\n' "$name" "$got" "$want"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
}

# A realistic scrape: telemt emits the _total spelling and the per-user connection gauge,
# and none of the three deleted aggregates.
METRICS='# HELP telemt_user_octets_from_client_total Bytes received from clients
# TYPE telemt_user_octets_from_client_total counter
telemt_user_octets_from_client_total{user="alice"} 801502131
telemt_user_octets_to_client_total{user="alice"} 39774071544
telemt_user_octets_from_client_total{user="bob"} 100
telemt_user_octets_to_client_total{user="bob"} 200
telemt_user_connections_current{user="alice"} 7
telemt_user_connections_current{user="bob"} 5
telemt_connections_total 42
telemt_connections_bad_total 2'

_fetch_metrics() { printf '%s\n' "$METRICS"; }
is_proxy_running() { return 0; }
_load_all_cumulative_user_stats() { :; }
draw_header() { :; }
log_error() { :; }

echo "telemt metric name tests"

# The fixture must really contain the names under test, or everything below could pass
# for the wrong reason.
assert_eq "fixture carries the _total counter names" "4" \
    "$(printf '%s\n' "$METRICS" | grep -c '^telemt_user_octets_.*_total{')"

# --- 1. the _total rename ------------------------------------------------------
assert_eq "global totals come from the _total counters" \
    "801502231 39774071744 12" "$(get_proxy_stats)"

assert_eq "per-user totals come from the _total counters" \
    "801502131 39774071544 7" "$(get_user_stats alice)"

# The connection figures in the two assertions above come from
# telemt_user_connections_current, which telemt never renamed — so they double as the
# check that an unrenamed counter still parses, guarding against "fixing" the whole
# family instead of the two that actually changed.

# A tolerant `(_total)?` pattern would double-count if both spellings ever coexisted.
# They did not, but the exclusive behaviour is what we depend on, so pin it.
_fetch_metrics() {
    printf '%s\n' "$METRICS"
    printf '%s\n' 'telemt_user_octets_from_client{user="legacy"} 999999'
}
assert_eq "a legacy-named line is not also counted" "801502231" \
    "$(get_proxy_stats | awk '{print $1}')"
_fetch_metrics() { printf '%s\n' "$METRICS"; }

# --- 2. the deleted aggregate connection gauges --------------------------------
# Derived from the per-user gauge, so this must be 7 + 5 and not the stale aggregate.
# $NF rather than a digit match: the label is wrapped in ANSI colour codes, whose escape
# sequences contain digits, so `grep -oE '[0-9]+'` would pick up "[1" from "\e[1m".
assert_eq "active connection total is summed from the per-user gauge" "12" \
    "$(show_connections 2>/dev/null | grep 'Total active:' | awk '{print $NF}')"

# The three deleted names were matched with a trailing space, so they need a source-level
# guard: nothing at runtime can distinguish "metric absent" from "zero connections".
assert_eq "no pattern still reads the deleted aggregate gauges" "0" \
    "$(grep -cE '\^telemt_connections_(me_|direct_)?current ' "$REPO_ROOT/mtproxymax.sh")"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
