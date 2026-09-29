#!/bin/bash
# Regression tests for the Telegram bot command menu (setMyCommands).
#
# The bot registers its command list with Telegram so clients render a tappable
# "/" menu. Lists are scoped: everyone gets the public self-service commands,
# admins get the admin control plane, superadmins additionally get the four
# commands the dispatcher gates to superadmin.
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

TEST_TMPDIR=$(mktemp -d)
INSTALL_DIR="$TEST_TMPDIR/install"
mkdir -p "$INSTALL_DIR/relay_stats"
ADMINS_FILE="$INSTALL_DIR/admins.conf"
SETTINGS_FILE="$INSTALL_DIR/settings.conf"

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
log_info() { :; }
log_success() { :; }
log_error() { LAST_ERROR="$*"; }
log_warn() { :; }

# ── Telemetry: record every Bot API call the code under test makes ───────────
CALLS_FILE="$TEST_TMPDIR/calls.tsv"
CALL_N=0

# Sorted, comma-separated normalisation so assertions do not depend on the
# order the tables happen to be written in.
sorted_csv() {
    printf '%s' "$1" | tr ',' '\n' | LC_ALL=C sort | tr '\n' ',' | sed 's/,$//'
}

curl() {
    local _cfg="" _body="" _prev="" _a
    for _a in "$@"; do
        case "$_prev" in
            -K) _cfg="$_a" ;;
            -d) _body="$_a" ;;
        esac
        _prev="$_a"
    done
    local _url=""
    [ -n "$_cfg" ] && [ -f "$_cfg" ] && _url=$(sed -n 's/^url = "\(.*\)"$/\1/p' "$_cfg" 2>/dev/null)
    local _method="${_url##*/}"
    local _chat
    _chat=$(printf '%s' "$_body" | grep -o '"chat_id":[0-9-]*' | head -1 | cut -d: -f2)
    [ -z "$_chat" ] && _chat="-"
    local _cmds
    _cmds=$(printf '%s' "$_body" | grep -o '"command":"[a-z0-9_]*"' | sed 's/"command":"//;s/"//' | tr '\n' ',' | sed 's/,$//')
    # curl runs inside a command-substitution subshell, so a counter would not
    # survive back to this shell. mktemp gives each call a unique body file.
    local _bf
    _bf=$(mktemp "$TEST_TMPDIR/body.XXXXXX")
    printf '%s' "$_body" > "$_bf"
    printf '%s\t%s\t%s\n' "$_method" "$_chat" "$_cmds" >> "$CALLS_FILE"
    if [ "${CURL_OK:-true}" = "true" ]; then
        printf '{"ok":true,"result":true}\n'
    else
        printf '{"ok":false,"error_code":401,"description":"Unauthorized"}\n'
    fi
}

# Command list registered for a scope. "-" is the default (all users) scope.
scope_commands() {
    awk -F'\t' -v c="$1" '$1=="setMyCommands" && $2==c {print $3}' "$CALLS_FILE" | head -1
}
call_methods() { awk -F'\t' '{print $1}' "$CALLS_FILE"; }
call_count() { wc -l < "$CALLS_FILE" 2>/dev/null | tr -d ' '; }
# grep -c . counts non-empty lines, avoiding the trailing-newline off-by-one.
csv_count() { printf '%s' "$1" | tr ',' '\n' | grep -c .; }
csv_uniq_count() { printf '%s' "$1" | tr ',' '\n' | sort -u | grep -c .; }

PUBLIC="my_status,redeem,start,support,voucher"
ADMIN="mp_add,mp_broadcast,mp_digest,mp_disable,mp_enable,mp_fleet,mp_health,mp_help,
mp_limits,mp_link,mp_rotate,mp_secrets,mp_setlimit,mp_status,mp_traffic,mp_upstreams,mp_voucher,reply"
ADMIN=$(printf '%s' "$ADMIN" | tr -d '\n')
SUPERADMIN="mp_add,mp_broadcast,mp_digest,mp_disable,mp_enable,mp_fleet,mp_health,mp_help,
mp_limits,mp_link,mp_lockdown,mp_remove,mp_restart,mp_rotate,mp_secrets,mp_setlimit,mp_status,mp_traffic,mp_update,mp_upstreams,mp_voucher,reply"
SUPERADMIN=$(printf '%s' "$SUPERADMIN" | tr -d '\n')

# ── Fixtures ─────────────────────────────────────────────────────────────────
TELEGRAM_ENABLED="true"
TELEGRAM_BOT_TOKEN="123456:TESTTOKEN"
TELEGRAM_CHAT_ID="111"
printf '222|superadmin|Ops|2025-01-01\n333|reseller|Shop|2025-01-02\n' > "$ADMINS_FILE"

echo "Telegram command menu tests"

# ── Happy path ───────────────────────────────────────────────────────────────
: > "$CALLS_FILE"
CURL_OK=true
telegram_sync_commands
assert_eq "sync returns success" 0 "$?"

assert_eq "all users get the public commands" "$PUBLIC" "$(sorted_csv "$(scope_commands -)")"
assert_eq "root admin chat gets superadmin commands" "$SUPERADMIN" "$(sorted_csv "$(scope_commands 111)")"
assert_eq "admins.conf superadmin gets superadmin commands" "$SUPERADMIN" "$(sorted_csv "$(scope_commands 222)")"
assert_eq "reseller gets the reduced admin commands" "$ADMIN" "$(sorted_csv "$(scope_commands 333)")"

# The scoping guarantee: a reseller must not be shown privileged commands.
for _c in mp_remove mp_restart mp_update mp_lockdown; do
    assert_eq "reseller is not offered /$_c" "" "$(scope_commands 333 | tr ',' '\n' | grep -x "$_c")"
done
# ...while the superadmin must be.
for _c in mp_remove mp_restart mp_update mp_lockdown; do
    assert_eq "superadmin is offered /$_c" "$_c" "$(scope_commands 111 | tr ',' '\n' | grep -x "$_c")"
done

assert_eq "every registered command is namespaced correctly" "" "$(scope_commands 111 | tr ',' '\n' | grep -vE '^(reply|mp_[a-z_]+)$')"
assert_eq "no duplicate commands are registered" \
    "$(csv_uniq_count "$(scope_commands 111)")" "$(csv_count "$(scope_commands 111)")"

# ── Failure and disabled paths are never fatal ───────────────────────────────
CURL_OK=false
: > "$CALLS_FILE"
telegram_sync_commands
assert_eq "sync survives a Bot API failure" 0 "$?"
assert_eq "sync still attempts the public scope on failure" "setMyCommands" "$(call_methods | head -1)"

CURL_OK=true
TELEGRAM_ENABLED=false
: > "$CALLS_FILE"
telegram_sync_commands
assert_eq "disabled bot is a no-op" 0 "$(call_count)"

TELEGRAM_ENABLED=true
_SAVED_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_BOT_TOKEN=""
: > "$CALLS_FILE"
telegram_sync_commands
assert_eq "missing token is a no-op" 0 "$(call_count)"
TELEGRAM_BOT_TOKEN="$_SAVED_TOKEN"

# ── Revoking an admin clears their menu ──────────────────────────────────────
: > "$CALLS_FILE"
telegram_clear_commands 333
assert_eq "clearing an admin uses deleteMyCommands" "deleteMyCommands" "$(call_methods | head -1)"
assert_eq "clearing targets the removed admin chat" "333" "$(awk -F'\t' '{print $2}' "$CALLS_FILE" | head -1)"

# ── Request bodies are well-formed JSON ──────────────────────────────────────
# Dependency-free structural check: always runs, and catches unbalanced braces
# or a truncated payload.
json_shape_ok() {
    local b="$1"
    [ -n "$b" ] || return 1
    [ "${b#\{}" != "$b" ] || return 1
    [ "${b%\}}" != "$b" ] || return 1
    [ "$(printf '%s' "$b" | tr -cd '{' | wc -c)" = "$(printf '%s' "$b" | tr -cd '}' | wc -c)" ] || return 1
    [ "$(printf '%s' "$b" | tr -cd '[' | wc -c)" = "$(printf '%s' "$b" | tr -cd ']' | wc -c)" ] || return 1
    return 0
}

# Note: the Windows Store ships a python3.exe alias that exists on PATH but
# cannot execute, so probe with a real invocation rather than `command -v`.
PY=""
if python3 -c 'import json' >/dev/null 2>&1; then
    PY="python3"
elif python -c 'import json' >/dev/null 2>&1; then
    PY="python"
fi

_shape_bad=0
_parsed_bad=0
_validated=0
for _f in "$TEST_TMPDIR"/body.*; do
    [ -f "$_f" ] || continue
    _validated=$((_validated + 1))
    json_shape_ok "$(cat "$_f")" || _shape_bad=$((_shape_bad + 1))
    if [ -n "$PY" ]; then
        "$PY" -c 'import json,sys; json.load(open(sys.argv[1]))' "$_f" 2>/dev/null || _parsed_bad=$((_parsed_bad + 1))
    fi
done
# Guard against a vacuous pass: with no captured bodies the loop never runs.
assert_eq "request bodies were captured for validation" "yes" \
    "$([ "$_validated" -gt 0 ] && echo yes || echo no)"
assert_eq "every request body is structurally valid JSON" "0" "$_shape_bad"
if [ -n "$PY" ]; then
    assert_eq "every request body parses as JSON ($PY)" "0" "$_parsed_bad"
fi

# Telegram rejects the whole list if a single entry is malformed, so a stray
# control character or quote in a description must not corrupt the payload.
if [ -n "$PY" ]; then
    _tricky=$(printf 'weird|He said "hi" in C:\\path\tand a\rCR')
    assert_eq "descriptions with quotes, backslashes and control chars stay valid JSON" "ok" \
        "$(_tg_commands_json "$_tricky" | "$PY" -c 'import json,sys; json.loads(sys.stdin.read()); print("ok")' 2>/dev/null || echo bad)"
fi

# ── The generated daemon re-syncs the menu on boot ───────────────────────────
telegram_generate_service_script
_DAEMON="$INSTALL_DIR/mtproxymax-telegram.sh"
assert_eq "daemon script is generated" "yes" "$([ -f "$_DAEMON" ] && echo yes || echo no)"
assert_eq "daemon syncs the command menu on boot" "yes" \
    "$(grep -q 'telegram sync-commands' "$_DAEMON" && echo yes || echo no)"
assert_eq "generated daemon is valid bash" 0 "$(bash -n "$_DAEMON" 2>/dev/null; echo $?)"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
