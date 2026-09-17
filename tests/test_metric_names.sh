#!/bin/bash
# Regression tests for the Prometheus counter names the script scrapes.
#
# telemt publishes conventional Prometheus counters, i.e. with a `_total` suffix. The
# script matched the older names, which required `{` immediately after `client`, so
# against telemt 3.5.6+ nothing matched and every traffic figure read 0. That failure is
# silent by construction: an awk sum over a pattern matching nothing yields 0, not an
# error, so nothing anywhere reports a problem.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

TEST_TMPDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'mtp_metrics_XXXXXX')
INSTALL_DIR="$TEST_TMPDIR/install"
mkdir -p "$INSTALL_DIR/relay_stats"

MTPROXYMAX_SOURCE_ONLY=true source "$(dirname "${BASH_SOURCE[0]}")/../mtproxymax.sh"
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

# A realistic scrape: telemt emits only the _total spelling. This is the payload shape
# against which every traffic figure read 0.
METRICS='# HELP telemt_user_octets_from_client_total Bytes received from clients
# TYPE telemt_user_octets_from_client_total counter
telemt_user_octets_from_client_total{user="alice"} 801502131
telemt_user_octets_to_client_total{user="alice"} 39774071544
telemt_user_octets_from_client_total{user="bob"} 100
telemt_user_octets_to_client_total{user="bob"} 200
telemt_user_connections_current{user="alice"} 3
telemt_user_connections_current{user="bob"} 1'

_fetch_metrics() { printf '%s\n' "$METRICS"; }
is_proxy_running() { return 0; }

echo "telemt metric name tests"

# The fixture must really contain the _total names, or every assertion below could pass
# for the wrong reason.
assert_eq "fixture carries the _total counter names" "4" \
    "$(printf '%s\n' "$METRICS" | grep -c '^telemt_user_octets_.*_total{')"

assert_eq "global totals come from the _total counters" \
    "801502231 39774071744 4" "$(get_proxy_stats)"

assert_eq "per-user totals come from the _total counters" \
    "801502131 39774071544 3" "$(get_user_stats alice)"

# telemt_user_connections_current never drifted, so it still matches unmodified. This
# guards against "fixing" the whole family instead of the two counters that were renamed.
assert_eq "an unrenamed counter still parses" "3" \
    "$(get_user_stats alice | awk '{print $3}')"

# We deliberately match only the _total spelling. A tolerant `(_total)?` pattern would
# also work today, but would double-count if a future telemt ever published both — so
# pin the exclusive behaviour here.
_fetch_metrics() {
    printf '%s\n' "$METRICS"
    printf '%s\n' 'telemt_user_octets_from_client{user="legacy"} 999999'
}
assert_eq "a legacy-named line is not also counted" "801502231" \
    "$(get_proxy_stats | awk '{print $1}')"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
