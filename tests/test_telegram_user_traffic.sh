#!/bin/bash
# Tests for the per-user traffic card.
#
# users.tsv has been written since the history subsystem landed, but nothing
# ever read it back per user: the user card showed only the cumulative total
# since the last reset, which cannot answer "how much did they move today, and
# is that up or down?". This pins the per-user reader and the card that shows
# it, including the two ways a per-user series goes wrong — counting another
# user's rows, and going missing (rather than reporting zero) for a user with no
# rows at all, which is the common case for a quiet account.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

TEST_TMPDIR=$(mktemp -d)
INSTALL_DIR="$TEST_TMPDIR/install"
mkdir -p "$INSTALL_DIR/relay_stats/history"
OFFSET_FILE="$INSTALL_DIR/relay_stats/tg_offset"
ADMINS_FILE="$INSTALL_DIR/admins.conf"
AUDIT_LOG="$INSTALL_DIR/audit.log"
SECRETS_FILE="$INSTALL_DIR/secrets.conf"
HISTORY_DIR="$INSTALL_DIR/relay_stats/history"

printf 'alice|%s|1700000000|true|7|3|10737418240|2027-01-01||\n' "$(printf 'a%.0s' $(seq 1 32))" > "$SECRETS_FILE"
printf 'quiet|%s|1700000000|true|0|0|0|0||\n' "$(printf 'q%.0s' $(seq 1 32))" >> "$SECRETS_FILE"

MTPROXYMAX_SOURCE_ONLY=true source "$(dirname "${BASH_SOURCE[0]}")/../mtproxymax.sh"
set +e
trap 'rm -rf "$TEST_TMPDIR"' EXIT

TESTS_RUN=0
TESTS_FAILED=0

assert_eq() {
    local name="$1" want="$2" got="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$got" = "$want" ]; then printf '  PASS  %s\n' "$name"
    else TESTS_FAILED=$((TESTS_FAILED + 1)); printf '  FAIL  %s (got=%q want=%q)\n' "$name" "$got" "$want"; fi
}
assert_contains() {
    local name="$1" needle="$2" haystack="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" == *"$needle"* ]]; then printf '  PASS  %s\n' "$name"
    else TESTS_FAILED=$((TESTS_FAILED + 1)); printf '  FAIL  %s (missing %q in %q)\n' "$name" "$needle" "$haystack"; fi
}
assert_not_contains() {
    local name="$1" needle="$2" haystack="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        TESTS_FAILED=$((TESTS_FAILED + 1)); printf '  FAIL  %s (unexpected %q in %q)\n' "$name" "$needle" "$haystack"
    else printf '  PASS  %s\n' "$name"; fi
}

telegram_generate_service_script
DAEMON="$INSTALL_DIR/mtproxymax-telegram.sh"
FNS="$TEST_TMPDIR/daemon-fns.sh"
: > "$FNS"
for _fn in _tg_security_log _esc _cb_label_ok _cb_enc _cb_dec _iso_to_epoch; do
    awk "/^${_fn}\\(\\)/,/^}\$/" "$DAEMON" >> "$FNS"
done
awk '/^# >>> TG_MENU_BEGIN$/,/^# <<< TG_MENU_END$/' "$DAEMON" >> "$FNS"
awk '/^# >>> TG_HISTORY_BEGIN$/,/^# <<< TG_HISTORY_END$/' "$DAEMON" >> "$FNS"
assert_eq "extraction is valid bash" 0 "$(bash -n "$FNS" 2>/dev/null; echo $?)"
assert_contains "the user-traffic reader ships in the daemon" "history_user_series()" "$(cat "$FNS")"

SENDS="$TEST_TMPDIR/sends.log"
EDITS="$TEST_TMPDIR/edits.log"
_check_tg_role() { echo "superadmin"; }
tg_send() { printf 'admin|%s\n' "$*" >> "$SENDS"; }
tg_send_to() { printf '%s|%s\n' "$1" "$2" >> "$SENDS"; }
tg_send_kb() { printf 'admin|%s\n' "$1" >> "$SENDS"; }
tg_send_to_kb() { printf '%s|%s\n' "$1" "$2" >> "$SENDS"; }
tg_answer_cb() { :; }
tg_edit() { printf '%s\n---\n%s\n' "$3" "$4" > "$EDITS"; }
tg_edit_markup() { :; }
load_tg_settings() { :; }
is_running() { return 1; }
log_warn() { :; }
get_cached_ip() { echo "203.0.113.9"; }
_tg_metrics_raw() { printf ''; }
_tg_have_python() { return 1; }

source "$FNS"

NOW=1000000
# alice: a rising ramp across the last 24h, all in 4 hourly buckets.
# Another user's rows sit in the same file to prove the reader filters.
: > "$HISTORY_DIR/users.tsv"
for _i in 1 2 3 4; do
    printf '%s|alice|%s|%s\n' "$(( NOW - _i * 3600 ))" "$(( _i * 1000 ))" "$(( _i * 2000 ))" >> "$HISTORY_DIR/users.tsv"
    printf '%s|bob|%s|%s\n' "$(( NOW - _i * 3600 ))" "$(( _i * 999999 ))" "$(( _i * 999999 ))" >> "$HISTORY_DIR/users.tsv"
done

# ── The reader ───────────────────────────────────────────────────────────────
_series=$(history_user_series alice 86400 "$NOW" 24)
assert_eq "the series has one bucket per slot" 24 "$(printf '%s' "$_series" | wc -w | tr -d ' ')"
# alice's four buckets total 1000+2000+3000+4000 = 10000 in, 20000 out.
assert_eq "the series sums only this user's rows" "30000" \
    "$(printf '%s' "$_series" | tr ' ' '\n' | awk '{s+=$1} END {printf "%d", s+0}')"
assert_eq "another user's rows are not counted" "0" \
    "$(printf '%s' "$(history_user_series alice 86400 "$NOW" 24)" | grep -c '999999' || true)"

# A user with no rows must report zeros, not nothing: an empty string would make
# the card lose its sparkline row silently rather than drawing a flat one.
_quiet=$(history_user_series quiet 86400 "$NOW" 24)
assert_eq "a silent user still yields a full series" 24 "$(printf '%s' "$_quiet" | wc -w | tr -d ' ')"
assert_eq "and it is all zeros" "0" "$(printf '%s' "$_quiet" | tr ' ' '\n' | awk '{s+=$1} END {printf "%d", s+0}')"

# ── The card ─────────────────────────────────────────────────────────────────
# The card reads the wall clock (a real tap has no other notion of "now"), so
# the fixture has to be laid down relative to it rather than to the fixed epoch
# the reader tests above use.
_now=$(date +%s)
: > "$HISTORY_DIR/users.tsv"
for _i in 1 2 3 4; do
    printf '%s|alice|%s|%s\n' "$(( _now - _i * 3600 ))" "$(( _i * 1000 ))" "$(( _i * 2000 ))" >> "$HISTORY_DIR/users.tsv"
    printf '%s|bob|%s|%s\n' "$(( _now - _i * 3600 ))" "$(( _i * 999999 ))" "$(( _i * 999999 ))" >> "$HISTORY_DIR/users.tsv"
done

_UI_ROLE="superadmin"; _CB_CHAT="111"; _CB_MID="77"
render_detail() { : > "$EDITS"; _cb_render_user_detail "${1:-alice}" 0; cat "$EDITS"; }
render_card()   { : > "$EDITS"; _cb_render_user_traffic "${1:-alice}" 0 2>/dev/null; cat "$EDITS"; }

_out=$(render_detail)
assert_contains "the user card offers the traffic view" "u:t:alice:0" "$_out"

_out=$(render_card)
assert_contains "the traffic card reports the 24h window" "24h" "$_out"
assert_contains "the traffic card reports the 7d window"  "7d"  "$_out"
assert_contains "the traffic card reports the 30d window" "30d" "$_out"
# 1000+2000+3000+4000 = 10000 bytes in and 20000 out, which format_bytes
# renders in binary units: 9.8 KB up, 19.5 KB down.
assert_contains "the traffic card reports this user's upload"   "↑ 9.8 KB"  "$_out"
assert_contains "the traffic card reports this user's download" "↓ 19.5 KB" "$_out"
assert_not_contains "the traffic card does not count another user" "3.8 MB" "$_out"
assert_not_contains "the traffic card draws no code box" '```' "$_out"
assert_contains "the traffic card goes back to the user card" "u:s:alice:0" "$_out"
_bars=0
for _g in ▁ ▂ ▃ ▄ ▅ ▆ ▇ █; do [[ "$_out" == *"$_g"* ]] && { _bars=1; break; }; done
assert_eq "the traffic card draws a sparkline" 1 "$_bars"

# A quiet user gets a flat line, not a missing row.
_out=$(render_card quiet)
assert_contains "a silent user still gets a card" "quiet" "$_out"
assert_not_contains "a silent user's card draws no code box" '```' "$_out"

# A label that is not a secret must not render a card. The label arrives through
# callback_data, so it is attacker-controlled.
assert_eq "a non-secret label renders nothing" "" "$(render_card '../etc')"

# ── RBAC ─────────────────────────────────────────────────────────────────────
assert_eq "the traffic card has a capability" "admin" "$(_tg_cap_for u t)"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
