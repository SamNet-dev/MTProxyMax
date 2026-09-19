#!/bin/bash
# Tests that no bot reply renders inside a Markdown code fence.
#
# Telegram draws a fenced block as a monospace box with a copy button, which is
# the wrong shape for a status reply: it reads as pasted console output, it
# cannot wrap, and every line gets a tap target the reader did not ask for.
#
# The commands below used to dump CLI output straight into ```…```. The rule
# this file pins is that they now emit one line per fact. The value must survive
# the change, so each case asserts BOTH that no fence is present AND that the
# data still reaches the reader — a rewrite that quietly dropped the content
# would pass a fence-only check.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

TEST_TMPDIR=$(mktemp -d)
INSTALL_DIR="$TEST_TMPDIR/install"
mkdir -p "$INSTALL_DIR/relay_stats"
OFFSET_FILE="$INSTALL_DIR/relay_stats/tg_offset"
ADMINS_FILE="$INSTALL_DIR/admins.conf"
AUDIT_LOG="$INSTALL_DIR/audit.log"
SECRETS_FILE="$INSTALL_DIR/secrets.conf"
VOUCHERS_FILE="$INSTALL_DIR/vouchers.conf"
UPSTREAMS_FILE="$INSTALL_DIR/upstreams.conf"

printf 'alice|%s|1700000000|true|0|0|0|0||\n' "$(printf 'a%.0s' $(seq 1 32))" > "$SECRETS_FILE"

# The voucher reply reads the vault rather than the CLI's padded table, so the
# fixture has to look like a real one: code|quota_bytes|days|conns|ips|tier|
# status|created|redeemed_by|redeemed_at.
cat > "$VOUCHERS_FILE" <<'EOF'
MTP-AAAA-BBBB|10737418240|30|15|5|standard|ACTIVE|2026-01-01 00:00:00 UTC|-|-
MTP-CCCC-DDDD|5368709120|7|15|5|standard|ACTIVE|2026-01-02 00:00:00 UTC|-|-
MTP-OLD1-OLD2|10737418240|30|15|5|standard|REDEEMED|2025-12-01 00:00:00 UTC|tg_5|2025-12-02 00:00:00 UTC
EOF

MTPROXYMAX_SOURCE_ONLY=true source "$(dirname "${BASH_SOURCE[0]}")/../mtproxymax.sh"
set +e
trap 'rm -rf "$TEST_TMPDIR"' EXIT

TESTS_RUN=0
TESTS_FAILED=0

assert_not_contains() {
    local name="$1" needle="$2" haystack="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s (unexpected %q in %q)\n' "$name" "$needle" "$haystack"
    else
        printf '  PASS  %s\n' "$name"
    fi
}
assert_contains() {
    local name="$1" needle="$2" haystack="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '  PASS  %s\n' "$name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s (missing %q in %q)\n' "$name" "$needle" "$haystack"
    fi
}
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

# ── Extract the shipped command dispatcher ───────────────────────────────────
telegram_generate_service_script
DAEMON="$INSTALL_DIR/mtproxymax-telegram.sh"
FNS="$TEST_TMPDIR/daemon-fns.sh"
: > "$FNS"
for _fn in _tg_security_log _cb_label_ok _cb_enc _cb_dec _esc _process_cmd \
           _tg_pending_file _tg_pending_set _tg_pending_take _tg_pending_clear \
           _tg_pending_try _tg_pending_run _tg_new_secret_link; do
    awk "/^${_fn}\\(\\)/,/^}\$/" "$DAEMON" >> "$FNS"
done
awk '/^# >>> TG_MENU_BEGIN$/,/^# <<< TG_MENU_END$/' "$DAEMON" >> "$FNS"
# The analytics views read the rolling history, so their block comes too.
awk '/^# >>> TG_HISTORY_BEGIN$/,/^# <<< TG_HISTORY_END$/' "$DAEMON" >> "$FNS"
awk '/^# >>> TG_REPORT_BEGIN$/,/^# <<< TG_REPORT_END$/' "$DAEMON" >> "$FNS"
assert_eq "dispatcher extraction is valid bash" 0 \
    "$(bash -n "$FNS" 2>/dev/null; echo $?)"
assert_eq "menu block was found in the daemon" 1 \
    "$(grep -c '^# >>> TG_MENU_BEGIN$' "$FNS")"

# ── Stubs ────────────────────────────────────────────────────────────────────
SENDS="$TEST_TMPDIR/sends.log"
CALLS="$TEST_TMPDIR/calls.log"

_check_tg_role() { echo "superadmin"; }
EDIT="$TEST_TMPDIR/edit.txt"
tg_edit() { printf '%s\n%s' "$3" "$4" > "$EDIT"; }
tg_edit_markup() { printf '%s' "$3" > "$EDIT"; }
tg_answer_cb() { :; }
tg_send() { printf 'admin|%s\n' "$*" >> "$SENDS"; }
tg_send_to() { printf '%s|%s\n' "$1" "$2" >> "$SENDS"; }
tg_send_kb() { printf 'admin|%s\n' "$1" >> "$SENDS"; }
tg_send_to_kb() { printf '%s|%s\n' "$1" "$2" >> "$SENDS"; }
load_tg_settings() { :; }
is_running() { return 0; }
is_proxy_running() { return 0; }
log_warn() { :; }
get_cached_ip() { echo "203.0.113.9"; }
get_stats() { echo "1024 2048 7"; }
get_uptime() { echo "98123"; }
get_active_connections() { echo "7"; }
get_container_uptime() { echo "98123"; }
get_cum_user_traffic() { echo "1024 2048"; }
format_duration() { echo "1d 3h 15m"; }
get_stats_dummy() { :; }
_esc() { printf '%s' "$1"; }
_tg_metrics_raw() { printf ''; }
mkdir -p "$INSTALL_DIR/relay_stats"
load_traffic() { :; }

# The manager stub reproduces the REAL output shape of each verb, padding
# included, so the parsing in the rewritten handlers is exercised against
# something that looks like what actually ships.
cat > "$INSTALL_DIR/mtproxymax" <<'EOS'
#!/bin/bash
printf '%s\n' "$*" >> "$MTPX_CALLS"
case "$1" in
    voucher)
        case "$2" in
            list)
                cat <<'OUT'
CODE           QUOTA      DAYS  STATUS
MTP-AAAA-BBBB  10.00 GB   30    active
MTP-CCCC-DDDD  5.00 GB    7     active
OUT
                ;;
            create) exit 0 ;;
        esac
        ;;
    health)
        cat <<'OUT'
  Engine:          running
  Port 443:        listening
  Metrics:         ok
  Secrets:         1 active
OUT
        ;;
    update) echo "Already on the latest version (v1.4.1-LTS)" ;;
    fleet)
        cat <<'OUT'
HOSTNAME       IP             USERS   TRAFFIC     LOAD
node-a         203.0.113.9    42      12.30 GB    0.41
node-b         198.51.100.4   7        1.10 GB    0.05
OUT
        ;;
esac
exit 0
EOS
chmod +x "$INSTALL_DIR/mtproxymax"
export MTPX_CALLS="$CALLS"

source "$FNS"

PROXY_PORT=443
PROXY_DOMAIN="cloudflare.com"
MASKING_ENABLED="true"
VERSION="v1.4.1-LTS"

run_cmd() {   # run_cmd <text>
    : > "$SENDS"; : > "$CALLS"
    _process_cmd "1" "111" "$1" >/dev/null 2>&1
    cat "$SENDS"
}

# ── /mp_voucher ──────────────────────────────────────────────────────────────
_out=$(run_cmd "/mp_voucher list")
assert_not_contains "voucher list draws no code box" '```' "$_out"
assert_contains "voucher list still shows the codes" "MTP-AAAA-BBBB" "$_out"
assert_contains "voucher list still shows the second code" "MTP-CCCC-DDDD" "$_out"
assert_contains "voucher list still shows the quota" "10.00 GB" "$_out"
assert_not_contains "voucher list hides redeemed codes" "MTP-OLD1-OLD2" "$_out"

_out=$(run_cmd "/mp_voucher create 2 10G 30")
assert_not_contains "voucher create draws no code box" '```' "$_out"
assert_contains "voucher create still reaches the CLI" "voucher create 2 10G 30" "$(cat "$CALLS")"
# The create reply must not repeat the two codes that were already there.
assert_not_contains "voucher create does not re-announce the existing vault" "MTP-AAAA-BBBB" "$_out"

# ── /mp_health ───────────────────────────────────────────────────────────────
_out=$(run_cmd "/mp_health")
assert_not_contains "health draws no code box" '```' "$_out"
assert_contains "health still reports the engine state" "Engine" "$_out"
assert_contains "health still reports the metrics check" "Metrics" "$_out"

# ── /mp_update ───────────────────────────────────────────────────────────────
_out=$(run_cmd "/mp_update")
assert_not_contains "update draws no code box" '```' "$_out"
assert_contains "update still reports the version" "v1.4.1-LTS" "$_out"

# ── /mp_fleet ────────────────────────────────────────────────────────────────
_out=$(run_cmd "/mp_fleet")
assert_not_contains "fleet draws no code box" '```' "$_out"
assert_contains "fleet still lists the first node" "node-a" "$_out"
assert_contains "fleet still lists the second node" "node-b" "$_out"
# Column padding only reads as columns inside a fence; outside one it is just a
# ragged gap, so the rewritten view must not carry it.
assert_not_contains "fleet does not smuggle back column padding" "     " "$_out"

# ── /mp_lockdown usage ───────────────────────────────────────────────────────
_out=$(run_cmd "/mp_lockdown status")
assert_not_contains "lockdown usage draws no code box" '```' "$_out"

# ── The whole surface, swept for fences ──────────────────────────────────────
# A per-command check can miss a fence added to a command nobody thought to
# list, so sweep every administrative command once.
for _c in "/mp_help" "/mp_status" "/mp_secrets" "/mp_link" "/mp_limits" \
          "/mp_traffic" "/mp_upstreams" "/mp_digest" "/mp_restart" "/mp_lockdown"; do
    _out=$(run_cmd "$_c")
    assert_not_contains "$_c draws no code box" '```' "$_out"
done

# ── The views reachable by button ────────────────────────────────────────────
# ── The analytics views ──────────────────────────────────────────────────────
# These two draw a sparkline. It used to sit in a fence "for monospace
# alignment"; the glyphs are block elements, which share an advance width in a
# proportional font, so the fence bought nothing and cost a code box.
HISTORY="$TEST_TMPDIR/history"
HISTORY_DIR="$HISTORY"
mkdir -p "$HISTORY"
_now=$(date +%s)
for _i in $(seq 0 23); do
    printf '%s|%s|%s|%s|-\n' "$(( _now - _i * 3600 ))" "$(( _i * 1024 ))" "$(( _i * 2048 ))" "3" >> "$HISTORY/global.tsv"
done
printf '%s|alice|5000|9000\n' "$_now" > "$HISTORY/users.tsv"

EDIT="$TEST_TMPDIR/edit-traffic.txt"; : > "$EDIT"
_cb_render_traffic "24h"
assert_not_contains "the traffic view draws no code box" '```' "$(cat "$EDIT")"
assert_contains "the traffic view still draws a sparkline" "▁" "$(cat "$EDIT")"

# The periodic report is a push, not an edit — it goes out through tg_send_kb.
: > "$SENDS"
_tg_periodic_report "$_now" 86400
assert_not_contains "the periodic report draws no code box" '```' "$(cat "$SENDS")"
assert_contains "the periodic report still draws a sparkline" "▁" "$(cat "$SENDS")"

for _v in hub help user_list engine settings; do
    EDIT="$TEST_TMPDIR/edit-$_v.txt"
    : > "$EDIT"
    _CB_CHAT="111"; _CB_MID="77"; _CB_DATA=""; _UI_ROLE="superadmin"
    case "$_v" in
        hub)          _cb_render_hub ;;
        help)         _cb_render_help ;;
        user_list)    _cb_render_user_list 0 ;;
        engine)       _cb_render_engine ;;
        settings)     _cb_render_settings ;;
    esac
    assert_not_contains "$_v view draws no code box" '```' "$(cat "$EDIT")"
done

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
