#!/bin/bash
# Regression tests for traffic resets while the Telegram daemon is running.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

TEST_TMPDIR=$(mktemp -d)
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
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s (got=%q want=%q)\n' "$name" "$got" "$want"
    fi
}

check_root() { :; }
load_settings() { :; }
reload_proxy_config() { :; }
log_info() { :; }
log_success() { :; }
log_error() { LAST_ERROR="$*"; }
audit_log() { :; }

SECRETS_LABELS=(alice bob)
SECRETS_ENABLED=(true true)

METRICS='# HELP test test
telemt_user_octets_from_client{user="alice"} 120
telemt_user_octets_to_client{user="alice"} 340
telemt_user_octets_from_client{user="bob"} 50
telemt_user_octets_to_client{user="bob"} 70'

_fetch_metrics() {
    [ "${METRICS_AVAILABLE:-true}" = "true" ] || return 1
    printf '%s\n' "$METRICS"
}

curl() {
    [ "${METRICS_AVAILABLE:-true}" = "true" ] || return 22
    printf '%s\n' "$METRICS"
}

echo "Traffic reset tests"

printf 'alice|1000|2000\nbob|3000|4000\n' > "$STATS_DIR/user_traffic"
printf 'alice|10|20\nbob|30|40\n' > "$STATS_DIR/user_traffic_snapshot"

secret_reset_traffic alice no_reload
assert_eq "user reset succeeds" 0 "$?"
assert_eq "user cumulative row is removed" "bob|3000|4000" "$(cat "$STATS_DIR/user_traffic")"
assert_eq "user live baseline is saved" "alice|120|340" "$(grep '^alice|' "$STATS_DIR/user_traffic_snapshot")"
assert_eq "daemon reset command is queued" "user|alice|120|340" "$(cat "$STATS_DIR/.traffic_reset_pending")"

# Extract and exercise the exact self-contained daemon helper. Its stale
# in-memory counters must be replaced before save_traffic writes again.
telegram_generate_service_script
awk '/^apply_pending_traffic_resets\(\)/,/^}/' "$INSTALL_DIR/mtproxymax-telegram.sh" > "$TEST_TMPDIR/apply-reset.sh"
source "$TEST_TMPDIR/apply-reset.sh"
_cum_user_in[alice]=1000
_cum_user_out[alice]=2000
_prev_user_in[alice]=10
_prev_user_out[alice]=20
apply_pending_traffic_resets
assert_eq "daemon cumulative input is cleared" 0 "${_cum_user_in[alice]}"
assert_eq "daemon cumulative output is cleared" 0 "${_cum_user_out[alice]}"
assert_eq "daemon input baseline is updated" 120 "${_prev_user_in[alice]}"
assert_eq "daemon output baseline is updated" 340 "${_prev_user_out[alice]}"
assert_eq "daemon consumes reset command" "missing" "$([ -e "$STATS_DIR/.traffic_reset_pending" ] && echo present || echo missing)"

printf '999|888\n' > "$STATS_DIR/cumulative_traffic"
printf '1|2\n' > "$STATS_DIR/global_traffic_snapshot"
run_traffic_reset_global --force
assert_eq "global reset succeeds" 0 "$?"
assert_eq "global cumulative counter is zero" "0|0" "$(cat "$STATS_DIR/cumulative_traffic")"
assert_eq "global live baseline is saved" "170|410" "$(cat "$STATS_DIR/global_traffic_snapshot")"
assert_eq "global daemon reset is queued" "global|170|410" "$(cat "$STATS_DIR/.traffic_reset_pending")"

_cum_in=999
_cum_out=888
_prev_total_in=1
_prev_total_out=2
apply_pending_traffic_resets
assert_eq "daemon global input is cleared" 0 "$_cum_in"
assert_eq "daemon global output is cleared" 0 "$_cum_out"
assert_eq "daemon global input baseline is updated" 170 "$_prev_total_in"
assert_eq "daemon global output baseline is updated" 410 "$_prev_total_out"

METRICS_AVAILABLE=false
printf '5|6\n' > "$STATS_DIR/cumulative_traffic"
run_traffic_reset_global --force >/dev/null
assert_eq "global reset fails without metrics" 1 "$?"
assert_eq "failed reset preserves counters" "5|6" "$(cat "$STATS_DIR/cumulative_traffic")"

METRICS_AVAILABLE=true
printf 'bob|3000|4000\n' > "$STATS_DIR/user_traffic"
printf 'bob|30|40\n' > "$STATS_DIR/user_traffic_snapshot"
printf 'bob|1\n' > "$INSTALL_DIR/secrets_quota_reset.conf"
: > "$STATS_DIR/.quota_reset_log"
secret_check_quota_resets
assert_eq "monthly reset records the current period" "bob|$(date +%Y-%m)" "$(cat "$STATS_DIR/.quota_reset_log")"
assert_eq "monthly reset clears the user's disk counter" "" "$(cat "$STATS_DIR/user_traffic")"
assert_eq "monthly reset queues daemon synchronization" "user|bob|50|70" "$(cat "$STATS_DIR/.traffic_reset_pending")"
_cum_user_in[bob]=3000
_cum_user_out[bob]=4000
apply_pending_traffic_resets
assert_eq "monthly reset clears stale daemon input" 0 "${_cum_user_in[bob]}"
assert_eq "monthly reset clears stale daemon output" 0 "${_cum_user_out[bob]}"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
