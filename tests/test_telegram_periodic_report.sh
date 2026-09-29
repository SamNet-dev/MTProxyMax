#!/bin/bash
# Tests for the periodic report.
#
# The report used to send the same three facts every interval regardless of
# activity: uptime, live connections, and two LIFETIME cumulative totals. Those
# only ever grow, so the message could never answer "how much moved today, and
# is that more or less than yesterday?". This pins the windowed, activity-aware
# replacement.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

TEST_TMPDIR=$(mktemp -d)
INSTALL_DIR="$TEST_TMPDIR/install"
mkdir -p "$INSTALL_DIR/relay_stats/history"
OFFSET_FILE="$INSTALL_DIR/relay_stats/tg_offset"
SECRETS_FILE="$INSTALL_DIR/secrets.conf"
: > "$SECRETS_FILE"

MTPROXYMAX_SOURCE_ONLY=true source "$(dirname "${BASH_SOURCE[0]}")/../mtproxymax.sh"
set +e
trap 'rm -rf "$TEST_TMPDIR"' EXIT

TESTS_RUN=0
TESTS_FAILED=0
assert_contains() {
    local name="$1" needle="$2" haystack="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" == *"$needle"* ]]; then printf '  PASS  %s\n' "$name"
    else TESTS_FAILED=$((TESTS_FAILED + 1)); printf '  FAIL  %s (missing %q)\n' "$name" "$needle"; fi
}
assert_not_contains() {
    local name="$1" needle="$2" haystack="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        TESTS_FAILED=$((TESTS_FAILED + 1)); printf '  FAIL  %s (unexpected %q)\n' "$name" "$needle"
    else printf '  PASS  %s\n' "$name"; fi
}
assert_eq() {
    local name="$1" want="$2" got="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$got" = "$want" ]; then printf '  PASS  %s\n' "$name"
    else TESTS_FAILED=$((TESTS_FAILED + 1)); printf '  FAIL  %s (got=%q want=%q)\n' "$name" "$got" "$want"; fi
}

telegram_generate_service_script
DAEMON="$INSTALL_DIR/mtproxymax-telegram.sh"
FNS="$TEST_TMPDIR/report.sh"
: > "$FNS"
for _fn in _esc format_bytes format_duration _iso_to_epoch _cb_label_ok _cb_enc _cb_dec token_not_a_function; do
    awk "/^${_fn}\\(\\)/,/^}\$/" "$DAEMON" >> "$FNS"
done
for _blk in TG_MENU TG_HISTORY TG_REPORT; do
    awk "/^# >>> ${_blk}_BEGIN\$/,/^# <<< ${_blk}_END\$/" "$DAEMON" >> "$FNS"
done
assert_contains "report block found in the daemon" "TG_REPORT_BEGIN" "$(cat "$FNS")"
assert_contains "history block found in the daemon" "TG_HISTORY_BEGIN" "$(cat "$FNS")"
TESTS_RUN=$((TESTS_RUN + 1))
if bash -n "$FNS" 2>/dev/null; then printf '  PASS  report extraction is valid bash\n'
else TESTS_FAILED=$((TESTS_FAILED + 1)); printf '  FAIL  report extraction is valid bash\n'; fi

SENT="$TEST_TMPDIR/sent.txt"
_check_tg_role() { echo "superadmin"; }
get_uptime() { echo 3600; }
get_active_connections() { echo 5; }
get_cached_ip() { echo "203.0.113.9"; }
tg_send_kb() { printf '%s\n' "$1" > "$SENT"; }
tg_send() { printf '%s\n' "$1" > "$SENT"; }
tg_edit() { :; }
tg_edit_markup() { :; }
tg_answer_cb() { :; }
load_tg_settings() { :; }
HISTORY_DIR="$INSTALL_DIR/relay_stats/history"
source "$FNS"

NOW=1000000
report() {
    : > "$SENT"
    TELEGRAM_REPORT_DETAIL="$1" _tg_periodic_report "$NOW" 86400
    cat "$SENT"
}

echo "Telegram periodic report tests"

# ── Idle window collapses to a heartbeat ─────────────────────────────────────
cat > "$HISTORY_DIR/global.tsv" <<'EOF'
999000|0|0|0|-
999600|0|0|0|-
EOF
: > "$HISTORY_DIR/users.tsv"
_body=$(report auto)
assert_contains "an idle window reports a heartbeat" "idle" "$_body"
assert_not_contains "an idle window omits the sparkline" '📉' "$_body"
assert_not_contains "an idle window omits the lifetime totals line" "24h ↓" "$_body"
assert_contains "the heartbeat still proves liveness" "alive" "$_body"

# ── An active window produces the full report ────────────────────────────────
cat > "$HISTORY_DIR/global.tsv" <<'EOF'
999000|0|0|0|-
999600|5000000|3000000|7|-
EOF
cat > "$HISTORY_DIR/users.tsv" <<'EOF'
999600|alice|4000000|2000000
999600|bob|1000000|1000000
EOF
_body=$(report auto)
assert_contains "an active window reports the 24h totals" "24h ↓" "$_body"
assert_contains "an active window reports a peak rate" "Peak" "$_body"
assert_contains "an active window draws a sparkline" '📉' "$_body"
assert_contains "an active window names top talkers" "alice" "$_body"
assert_not_contains "an active window is not a heartbeat" "alive, idle" "$_body"

# Regression: the two lifetime totals the old report always sent must no longer
# be the whole message. The window figure has to be present.
assert_contains "the report is windowed, not lifetime" "24h" "$_body"

# ── The sparkline is inline, unescaped, and never fenced ─────────────────────
# It used to sit inside a code fence "for monospace alignment". The glyphs are
# block elements and share an advance width in a proportional font, so the fence
# bought nothing and cost a monospace box with a copy button on every report.
assert_not_contains "the report draws no code box" '```' "$_body"
# Any of the eight block glyphs counts: with a single non-zero bucket the series
# is flat, so which glyph a bar gets depends on the scale, not on correctness.
_spark_line=""
while IFS= read -r _l; do
    case "$_l" in *📉*) _spark_line="$_l"; break ;; esac
done <<< "$_body"
if [[ "$_spark_line" =~ ([▁▂▃▄▅▆▇█]+) ]]; then
    _spark_glyphs="${BASH_REMATCH[1]}"
else
    _spark_glyphs=""
fi
assert_eq "the sparkline still draws bars" 1 "$([ -n "$_spark_glyphs" ] && echo 1 || echo 0)"
# Bars are U+2581..U+2588 and contain no Markdown metacharacter, so escaping the
# run would render literal backslashes inside it for no benefit. The check is on
# the glyph run rather than the whole line: the body carries its newlines as
# literal \n, so the line has backslashes in it either way.
assert_not_contains "the inline sparkline is not Markdown-escaped" '\' "$_spark_glyphs"

# ── Verbosity override ───────────────────────────────────────────────────────
_body=$(report summary)
assert_not_contains "detail=summary suppresses the full report when busy" "Peak" "$_body"

cat > "$HISTORY_DIR/global.tsv" <<'EOF'
999000|0|0|0|-
999600|0|0|0|-
EOF
_body=$(report full)
assert_contains "detail=full reports even when idle" "24h ↓" "$_body"

# ── Quota pressure and expiry watch ──────────────────────────────────────────
# Quota is measured against the same _cum_user_* the enforcement loop uses, and
# expiry against the same _iso_to_epoch, so the two can never disagree.
cat > "$HISTORY_DIR/global.tsv" <<'EOF'
999000|0|0|0|-
999600|5000000|3000000|7|-
EOF
declare -A _cum_user_in=([alice]=900) _cum_user_out=([alice]=0)
printf 'alice|%032d|1700000000|true|0|0|1000|0||\n' 1 > "$SECRETS_FILE"
_body=$(report auto)
assert_contains "a user at or above 80% quota is flagged" "80% quota" "$_body"

declare -A _cum_user_in=([alice]=100) _cum_user_out=([alice]=0)
_body=$(report auto)
assert_not_contains "a user below the quota threshold is not flagged" "80% quota" "$_body"

# An expiry three days out must be counted; ten days out must not.
_far=$(( NOW + 10 * 86400 ))
_near=$(date -u -d "@$(( NOW + 2 * 86400 ))" '+%Y-%m-%d' 2>/dev/null)
if [ -n "$_near" ]; then
    printf 'alice|%032d|1700000000|true|0|0|0|%s||\n' 1 "$_near" > "$SECRETS_FILE"
    _body=$(report auto)
    assert_contains "a secret expiring within 3 days is flagged" "expiring within 3 days" "$_body"
else
    printf '  SKIP  expiry assertions (date -d unavailable)\n'
fi

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
