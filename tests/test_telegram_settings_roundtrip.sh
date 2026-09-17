#!/bin/bash
# Tests that the Telegram settings keys survive a save/load round trip.
#
# There are FOUR places a key must be registered, and the fourth is the one
# that gets missed: the bot daemon carries its OWN load_tg_settings whitelist,
# independent of the manager's load_settings. A key added to only one of them
# means the daemon silently runs on the default while `telegram status` reports
# the configured value — a wrong-behaviour bug with no error anywhere.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

TEST_TMPDIR=$(mktemp -d)
INSTALL_DIR="$TEST_TMPDIR/install"
mkdir -p "$INSTALL_DIR/relay_stats"
SETTINGS_FILE="$INSTALL_DIR/settings.conf"
OFFSET_FILE="$INSTALL_DIR/relay_stats/tg_offset"

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

echo "Telegram settings round-trip tests"

KEYS="TELEGRAM_HISTORY_ENABLED TELEGRAM_HISTORY_INTERVAL_MIN TELEGRAM_HISTORY_RETENTION_DAYS TELEGRAM_REPORT_DETAIL"

# ── save_settings writes them ────────────────────────────────────────────────
TELEGRAM_HISTORY_ENABLED="false"
TELEGRAM_HISTORY_INTERVAL_MIN="11"
TELEGRAM_HISTORY_RETENTION_DAYS="3"
TELEGRAM_REPORT_DETAIL="full"
save_settings 2>/dev/null

for _k in $KEYS; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q "^${_k}=" "$SETTINGS_FILE" 2>/dev/null; then
        printf '  PASS  %s is written to settings.conf\n' "$_k"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s is written to settings.conf\n' "$_k"
    fi
done

# ── load_settings reads them back ────────────────────────────────────────────
TELEGRAM_HISTORY_ENABLED="true"
TELEGRAM_HISTORY_INTERVAL_MIN="5"
TELEGRAM_HISTORY_RETENTION_DAYS="7"
TELEGRAM_REPORT_DETAIL="auto"
load_settings 2>/dev/null

assert_eq "load_settings restores TELEGRAM_HISTORY_ENABLED" "false" "$TELEGRAM_HISTORY_ENABLED"
assert_eq "load_settings restores TELEGRAM_HISTORY_INTERVAL_MIN" "11" "$TELEGRAM_HISTORY_INTERVAL_MIN"
assert_eq "load_settings restores TELEGRAM_HISTORY_RETENTION_DAYS" "3" "$TELEGRAM_HISTORY_RETENTION_DAYS"
assert_eq "load_settings restores TELEGRAM_REPORT_DETAIL" "full" "$TELEGRAM_REPORT_DETAIL"

# ── The daemon's own whitelist must know them too ────────────────────────────
telegram_generate_service_script
DAEMON="$INSTALL_DIR/mtproxymax-telegram.sh"
FNS="$TEST_TMPDIR/daemon-settings.sh"
awk '/^load_tg_settings\(\)/,/^}$/' "$DAEMON" > "$FNS"
assert_eq "load_tg_settings extraction is valid bash" 0 \
    "$(bash -n "$FNS" 2>/dev/null; echo $?)"
source "$FNS"

for _k in $KEYS; do
    TESTS_RUN=$((TESTS_RUN + 1))
    if grep -q "$_k" "$FNS"; then
        printf '  PASS  the daemon whitelists %s\n' "$_k"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  the daemon whitelists %s\n' "$_k"
    fi
done

# And it must actually pick the configured value up, not just name the key.
TELEGRAM_HISTORY_ENABLED="unset-sentinel"
TELEGRAM_HISTORY_INTERVAL_MIN="unset-sentinel"
TELEGRAM_HISTORY_RETENTION_DAYS="unset-sentinel"
TELEGRAM_REPORT_DETAIL="unset-sentinel"
load_tg_settings

assert_eq "the daemon picks up TELEGRAM_HISTORY_ENABLED" "false" "$TELEGRAM_HISTORY_ENABLED"
assert_eq "the daemon picks up TELEGRAM_HISTORY_INTERVAL_MIN" "11" "$TELEGRAM_HISTORY_INTERVAL_MIN"
assert_eq "the daemon picks up TELEGRAM_HISTORY_RETENTION_DAYS" "3" "$TELEGRAM_HISTORY_RETENTION_DAYS"
assert_eq "the daemon picks up TELEGRAM_REPORT_DETAIL" "full" "$TELEGRAM_REPORT_DETAIL"

# No clamp is needed on the interval: sampling is driven from inside the 60s
# traffic tick, so the tick itself is the floor however the config is set.
TELEGRAM_HISTORY_INTERVAL_MIN="unset-sentinel"
printf "TELEGRAM_HISTORY_INTERVAL_MIN='0'\n" > "$SETTINGS_FILE"
load_tg_settings
assert_eq "a zero interval passes through the parser" "0" "$TELEGRAM_HISTORY_INTERVAL_MIN"
assert_eq "the tick bounds sampling to one per minute" 1 \
    "$(grep -c '_last_hist_sample )) -ge' "$DAEMON")"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
