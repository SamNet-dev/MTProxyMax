#!/bin/bash
# Two fixes that the button work exposed but did not cause.
#
# 1. /mp_setlimit silently wiped limits. It called
#    `secret setlimits <label> <conns> <ips> <quota> <expires>`, and
#    secret_set_limits reads "0" as UNLIMITED rather than "leave alone" — so
#    `/mp_setlimit alice 100` also cleared alice's IP cap and quota.
#
# 2. Every QR code handed the credential to a third party. The proxy link IS the
#    key (server, port and secret), and it was posted to api.qrserver.com for
#    Telegram to fetch — on every /mp_link, every /start, and every voucher
#    redemption, including to the customer's own chat.
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

printf 'alice|%s|1700000000|true|7|3|10737418240|2027-01-01||\n' "$(printf 'a%.0s' $(seq 1 32))" > "$SECRETS_FILE"

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

# ── Extract the shipped daemon code ──────────────────────────────────────────
telegram_generate_service_script
DAEMON="$INSTALL_DIR/mtproxymax-telegram.sh"
FNS="$TEST_TMPDIR/daemon-fns.sh"
: > "$FNS"
for _fn in _tg_security_log _esc _cb_label_ok _cb_enc _cb_dec _process_cmd \
           _tg_pending_file _tg_pending_set _tg_pending_take _tg_pending_clear \
           _tg_pending_try _tg_pending_run _tg_new_secret_link \
           _qr_png _proxy_link _tg_send_photo_file _send_qr \
           send_proxy_qr send_proxy_qr_to; do
    awk "/^${_fn}\\(\\)/,/^}\$/" "$DAEMON" >> "$FNS"
done
awk '/^# >>> TG_MENU_BEGIN$/,/^# <<< TG_MENU_END$/' "$DAEMON" >> "$FNS"
assert_eq "extraction is valid bash" 0 "$(bash -n "$FNS" 2>/dev/null; echo $?)"

SENDS="$TEST_TMPDIR/sends.log"
CALLS="$TEST_TMPDIR/calls.log"
CURLS="$TEST_TMPDIR/curls.log"
CURLCFG="$TEST_TMPDIR/curlcfg.log"
QRDIR="$TEST_TMPDIR/qr"

_check_tg_role() { echo "superadmin"; }
tg_send() { printf 'admin|%s\n' "$*" >> "$SENDS"; }
tg_send_to() { printf '%s|%s\n' "$1" "$2" >> "$SENDS"; }
tg_send_kb() { printf 'admin|%s\n' "$1" >> "$SENDS"; }
tg_send_to_kb() { printf '%s|%s\n' "$1" "$2" >> "$SENDS"; }
load_tg_settings() { :; }
is_running() { return 0; }
log_warn() { :; }
get_cached_ip() { echo "203.0.113.9"; }
format_bytes() { printf '%s' "$1"; }
format_duration() { echo "1d"; }
domain_to_hex() { echo "0a0b0c0d"; }
_tg_have_python() { return 1; }
_tg_metrics_raw() { printf ''; }
# Record the curl invocation instead of performing it. The URL — which carries
# the bot token — travels in a -K config file, so argv and the config are logged
# separately: the point of the config file is that argv holds no secret.
curl() {
    printf '%s\n' "$*" >> "$CURLS"
    local _f
    while [ $# -gt 0 ]; do
        case "$1" in
            -K) _f="$2"; [ -r "$_f" ] && cat "$_f" >> "$CURLCFG" ;;
        esac
        shift
    done
    return 0
}

cat > "$INSTALL_DIR/mtproxymax" <<'EOS'
#!/bin/bash
printf '%s\n' "$*" >> "$MTPX_CALLS"
exit 0
EOS
chmod +x "$INSTALL_DIR/mtproxymax"
export MTPX_CALLS="$CALLS"

source "$FNS"

PROXY_PORT=443
PROXY_DOMAIN="cloudflare.com"
MASKING_ENABLED="true"
TELEGRAM_BOT_TOKEN="111:AAA"
TELEGRAM_CHAT_ID="555"
TELEGRAM_SERVER_LABEL="TestBox"

run_cmd() {   # run_cmd <text>
    : > "$SENDS"; : > "$CALLS"
    _process_cmd "1" "111" "$1" >/dev/null 2>&1
    cat "$SENDS"
}

echo "Telegram limit + QR tests"

# ── /mp_setlimit changes only what it was given ──────────────────────────────
_out=$(run_cmd "/mp_setlimit alice 100")
assert_contains "a one-field set reaches the CLI" "secret setlimit alice conns 100" "$(cat "$CALLS")"
assert_not_contains "and never uses the all-fields verb" "setlimits" "$(cat "$CALLS")"

: > "$CALLS"
run_cmd "/mp_setlimit alice 100 5" >/dev/null
assert_contains "a two-field set sends the connection cap" "secret setlimit alice conns 100" "$(cat "$CALLS")"
assert_contains "a two-field set sends the IP cap" "secret setlimit alice ips 5" "$(cat "$CALLS")"
assert_not_contains "and still never uses the all-fields verb" "setlimits" "$(cat "$CALLS")"

: > "$CALLS"
run_cmd "/mp_setlimit alice 100 5 10G" >/dev/null
assert_contains "a three-field set sends the quota" "secret setlimit alice quota 10G" "$(cat "$CALLS")"
assert_not_contains "and still never uses the all-fields verb" "setlimits" "$(cat "$CALLS")"

# An empty field is "leave it alone", so nothing at all must be sent for it —
# the whole point of the fix.
: > "$CALLS"
run_cmd "/mp_setlimit alice 0 0 10G" >/dev/null
assert_contains "an explicit 0 still reaches the CLI as a real 0" "secret setlimit alice conns 0" "$(cat "$CALLS")"

_out=$(run_cmd "/mp_setlimit alice")
assert_contains "a set with no fields is refused" "❌" "$_out"
assert_eq "and reaches the CLI not at all" "" "$(cat "$CALLS")"

# (A bare /mp_setlimit matches no case arm and stays silent. That is how the
# dispatcher has always treated it, and changing it is not part of this fix.)

# ── The QR is rendered here, not fetched from a third party ──────────────────
mkdir -p "$QRDIR" "$TEST_TMPDIR/bin"
# A stand-in renderer: it only has to prove the PNG path is taken.
cat > "$TEST_TMPDIR/bin/qrencode" <<'EOS'
#!/bin/bash
out=""
while [ $# -gt 0 ]; do
    case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac
done
[ -n "$out" ] && printf 'PNGDATA' > "$out"
exit 0
EOS
chmod +x "$TEST_TMPDIR/bin/qrencode"
PATH="$TEST_TMPDIR/bin:$PATH"

: > "$CURLS"; : > "$CURLCFG"
send_proxy_qr_to "777" "203.0.113.9" "443" "eeaaaa0a0b0c0d" "scan me"
_curl_args="$(cat "$CURLS")"
_curl_cfg="$(cat "$CURLCFG")"

assert_not_contains "the QR never goes to a third-party renderer" "qrserver" "$_curl_args$_curl_cfg"
assert_contains "the upload targets sendPhoto" "sendPhoto" "$_curl_cfg"
assert_contains "the QR is uploaded from a file on this host" "photo=@" "$_curl_args"
assert_contains "the upload is multipart, not a URL parameter" "-F" "$_curl_args"
assert_contains "the upload goes to the chat that asked for it" "chat_id=777" "$_curl_args"
# The bot token must travel in the curl config, never in argv where `ps` shows it.
assert_not_contains "the bot token is not on the command line" "111:AAA" "$_curl_args"

# With no renderer at all, the link is still delivered — as the tappable link,
# never by falling back to the third party.
rm -f "$TEST_TMPDIR/bin/qrencode"
: > "$SENDS"; : > "$CURLS"; : > "$CURLCFG"
send_proxy_qr_to "777" "203.0.113.9" "443" "eeaaaa0a0b0c0d" "scan me"
assert_not_contains "no renderer still means no third party" "qrserver" "$(cat "$CURLS")$(cat "$CURLCFG")"
assert_contains "the fallback still delivers a usable link" "t.me/proxy?server=203.0.113.9" "$(cat "$SENDS")"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
