#!/bin/bash
# Tests for the inline-keyboard callback dispatcher.
#
# The security property under test is that a button must never grant more than
# typing the equivalent command would. _process_cmd is the reference: public
# commands run before any role check, an unauthenticated chatter is ignored
# SILENTLY, a recognised-but-underprivileged role is refused loudly, and an
# unrecognised role string (admins.conf is hand-editable) fails closed.
#
# The dispatcher must reproduce all four behaviours, because callback_data is
# entirely attacker-controlled — a user can send any payload they like.
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

printf 'alice|%s|1700000000|true|0|0|0|0||\n' "$(printf 'a%.0s' $(seq 1 32))" > "$SECRETS_FILE"
printf 'bob|%s|1700000000|false|0|0|0|0||\n' "$(printf 'b%.0s' $(seq 1 32))" >> "$SECRETS_FILE"

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
assert_contains() {
    local name="$1" needle="$2" haystack="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        printf '  PASS  %s\n' "$name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s (missing %q in %q)\n' "$name" "$needle" "$haystack"
    fi
}
assert_not_contains() {
    local name="$1" needle="$2" haystack="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s (unexpected %q in %q)\n' "$name" "$needle" "$haystack"
    else
        printf '  PASS  %s\n' "$name"
    fi
}

# ── Extract the shipped dispatcher ───────────────────────────────────────────
telegram_generate_service_script
DAEMON="$INSTALL_DIR/mtproxymax-telegram.sh"
FNS="$TEST_TMPDIR/daemon-fns.sh"
: > "$FNS"
# NOTE: _check_tg_role is deliberately NOT extracted. Role resolution is
# exercised elsewhere; here it is stubbed, and extracting the real one would
# silently clobber that stub and make every role resolve to "none".
for _fn in _tg_security_log _cb_label_ok _cb_enc _cb_dec; do
    awk "/^${_fn}\\(\\)/,/^}\$/" "$DAEMON" >> "$FNS"
done
# The menu block is delimited by markers so the test exercises exactly what
# ships rather than a copy that can silently drift.
awk '/^# >>> TG_MENU_BEGIN$/,/^# <<< TG_MENU_END$/' "$DAEMON" >> "$FNS"
assert_eq "dispatcher extraction is valid bash" 0 \
    "$(bash -n "$FNS" 2>/dev/null; echo $?)"
assert_eq "menu block was found in the daemon" 1 \
    "$(grep -c '^# >>> TG_MENU_BEGIN$' "$FNS")"

# ── Stubs ────────────────────────────────────────────────────────────────────
ANSWERS="$TEST_TMPDIR/answers.log"
EDITS="$TEST_TMPDIR/edits.log"
SENDS="$TEST_TMPDIR/sends.log"
CALLS="$TEST_TMPDIR/calls.log"
ROLE_TO_RETURN="superadmin"

_check_tg_role() { echo "$ROLE_TO_RETURN"; }
tg_answer_cb() { printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$ANSWERS"; }
# $4 is the keyboard markup — the assertions about which buttons a view offers
# read it, so it must be captured alongside the body.
tg_edit() { printf 'edit|%s|%s|%s|%s\n' "$1" "$2" "$3" "$4" >> "$EDITS"; }
tg_edit_markup() { printf 'markup|%s|%s|%s\n' "$1" "$2" "$3" >> "$EDITS"; }
tg_send_to() { printf '%s|%s\n' "$1" "$2" >> "$SENDS"; }
tg_send() { printf 'admin|%s\n' "$*" >> "$SENDS"; }
load_tg_settings() { :; }
is_running() { return 1; }
log_warn() { :; }
get_cached_ip() { echo "203.0.113.9"; }
_tg_metrics_raw() { printf ''; }

cat > "$INSTALL_DIR/mtproxymax" <<'EOS'
#!/bin/bash
printf '%s\n' "$*" >> "$MTPX_CALLS"
exit 0
EOS
chmod +x "$INSTALL_DIR/mtproxymax"
export MTPX_CALLS="$CALLS"

source "$FNS"

run_cb() {   # run_cb <role> <chat> <payload>
    : > "$ANSWERS"; : > "$EDITS"; : > "$SENDS"; : > "$CALLS"
    ROLE_TO_RETURN="$1"
    _process_callback "$2" 77 "cb-1" "$3" 2>/dev/null
}
audit_now() { cat "$AUDIT_LOG" 2>/dev/null || printf ''; }
reset_audit() { : > "$AUDIT_LOG"; }

echo "Telegram callback dispatcher tests"

# ── Every path answers the callback exactly once ─────────────────────────────
# Without this the client spins forever, so it must hold on denial, error and
# stale-menu paths too — not just the happy path.
for _case in "superadmin:111:m" "reseller:333:m" "none:999:m" \
             "operator:444:m" "superadmin:111:a:disable:alice" \
             "reseller:333:a:disable:alice" "superadmin:111:u:s:ghost:0" \
             "superadmin:111:not-a-real-payload" "superadmin:111:zz"; do
    _r="${_case%%:*}"; _p="${_case#*:}"; _c="${_p%%:*}"; _data="${_p#*:}"
    run_cb "$_r" "$_c" "$_data"
    assert_eq "answers exactly once (role=$_r data=$_data)" 1 "$(wc -l < "$ANSWERS" | tr -d ' ')"
done

# ── A reseller cannot drive the control plane from a button ──────────────────
reset_audit
run_cb reseller 333 "a:disable:alice"
assert_eq "reseller button cannot disable a secret" "" "$(cat "$CALLS")"
assert_contains "reseller button denial is toasted" "Permission denied" "$(cat "$ANSWERS")"
assert_contains "reseller button denial is logged" "SECURITY" "$(audit_now)"
assert_contains "log records the offending chat" "333" "$(audit_now)"
assert_contains "log records the payload" "a:disable:alice" "$(audit_now)"
assert_eq "reseller button denial does not edit the message" "" "$(cat "$EDITS")"

reset_audit
run_cb reseller 333 "u:s:alice:0"
assert_contains "reseller cannot open a user detail card" "Permission denied" "$(cat "$ANSWERS")"
assert_contains "user-list denial is logged" "SECURITY" "$(audit_now)"
assert_eq "user-list denial does not edit" "" "$(cat "$EDITS")"

reset_audit
run_cb reseller 333 "c:remove:alice"
assert_contains "reseller cannot confirm a removal" "Permission denied" "$(cat "$ANSWERS")"
assert_eq "reseller confirmed removal never runs" "" "$(cat "$CALLS")"

# ── The rendered hub must not advertise what the role cannot do ──────────────
reset_audit
run_cb reseller 333 "m"
_hub_reseller="$(cat "$EDITS")"
assert_not_contains "reseller hub hides the user list" "u:l" "$_hub_reseller"
assert_not_contains "reseller hub hides disable"     "a:disable" "$_hub_reseller"
assert_not_contains "reseller hub hides removal"     "a:remove" "$_hub_reseller"
assert_not_contains "reseller hub hides lockdown"    "lockdown" "$_hub_reseller"

run_cb superadmin 111 "m"
_hub_super="$(cat "$EDITS")"
assert_contains "superadmin hub offers the user list" "u:l" "$_hub_super"

# ── An unauthenticated chatter is answered but ignored silently ──────────────
# This mirrors _process_cmd, where role "none" returns before any reply and
# before any audit entry.
reset_audit
run_cb none 999 "a:disable:alice"
assert_eq "unauthenticated callback runs nothing" "" "$(cat "$CALLS")"
assert_eq "unauthenticated callback is not logged" "" "$(audit_now)"
assert_eq "unauthenticated callback does not edit" "" "$(cat "$EDITS")"
assert_eq "unauthenticated callback is still answered" 1 "$(wc -l < "$ANSWERS" | tr -d ' ')"

# ── Unrecognised roles fail closed ───────────────────────────────────────────
for _role in operator administrator root SUPERADMIN superadmin2; do
    reset_audit
    run_cb "$_role" 444 "a:disable:alice"
    assert_eq "role '$_role' cannot disable a secret" "" "$(cat "$CALLS")"
    assert_contains "role '$_role' is refused" "Permission denied" "$(cat "$ANSWERS")"
    assert_contains "role '$_role' refusal is logged" "SECURITY" "$(audit_now)"
done

# ── Destructive actions require an explicit confirmation ─────────────────────
# A destructive button must never be one tap away: the a: namespace only
# renders a confirmation, and only c: executes.
reset_audit
run_cb superadmin 111 "a:disable:alice"
assert_eq "action request does not mutate anything" "" "$(cat "$CALLS")"
assert_contains "action request renders a confirmation" "c:disable:alice" "$(cat "$EDITS")"
assert_contains "confirmation names the target" "alice" "$(cat "$EDITS")"

run_cb superadmin 111 "c:disable:alice"
assert_contains "confirmed action reaches the manager" "secret disable alice" "$(cat "$CALLS")"
assert_eq "confirmed action runs exactly once" 1 "$(grep -c 'secret disable' "$CALLS")"

run_cb superadmin 111 "c:enable:alice"
assert_contains "confirmed enable reaches the manager" "secret enable alice" "$(cat "$CALLS")"

run_cb superadmin 111 "c:rotate:alice"
assert_contains "confirmed rotate reaches the manager" "secret rotate alice" "$(cat "$CALLS")"

run_cb superadmin 111 "c:remove:alice"
assert_contains "confirmed remove reaches the manager" "secret remove alice" "$(cat "$CALLS")"

# ── A stale label must not reach the manager ─────────────────────────────────
# secrets.conf is editable and a menu can outlive the secret it names.
reset_audit
run_cb superadmin 111 "c:disable:ghost"
assert_eq "confirmed action on an unknown label runs nothing" "" "$(cat "$CALLS")"
assert_contains "unknown label is reported" "not found" "$(cat "$ANSWERS")"

reset_audit
run_cb superadmin 111 "u:s:ghost:0"
assert_eq "detail card for an unknown label runs nothing" "" "$(cat "$CALLS")"
assert_contains "unknown label detail card is answered with a toast" "not found" "$(cat "$ANSWERS")"

# ── An injected payload is inert ─────────────────────────────────────────────
reset_audit
run_cb superadmin 111 'a:disable:$(id)'
assert_eq "injected payload runs nothing" "" "$(cat "$CALLS")"
assert_eq "injected payload is answered" 1 "$(wc -l < "$ANSWERS" | tr -d ' ')"

# ── Capability parity with _process_cmd ──────────────────────────────────────
# The table both the renderer and the enforcer read must not drift from the
# gates _process_cmd applies, or a button becomes a privilege-escalation path.
cap_leaks() {
    local line key cap _ns _rest
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        key="${line%%=*}"; cap="${line#*=}"
        case "$key" in
            # Destructive verbs must be superadmin because _process_cmd
            # re-checks superadmin inside /mp_remove.
            a:remove|c:remove)
                [ "$cap" = "superadmin" ] || { printf '%s=%s\n' "$key" "$cap"; } ;;
            a:enable|a:disable|a:rotate|c:enable|c:disable|c:rotate|u:l|u:s|t|t:w|t:u|y|y:e|s)
                [ "$cap" = "admin" ] || { printf '%s=%s\n' "$key" "$cap"; } ;;
            n|m|m:h)
                [ "$cap" = "public" ] || { printf '%s=%s\n' "$key" "$cap"; } ;;
            *)
                printf 'unclassified:%s\n' "$key" ;;
        esac
    done <<< "$TG_CB_CAPS"
}
assert_eq "capability table matches _process_cmd's gates" "" "$(cap_leaks)"

# Every namespace the renderers can emit must have a capability, or the
# dispatcher would fail open on an unclassified action.
assert_contains "capability table covers a:disable" "a:disable=admin" "$TG_CB_CAPS"
assert_contains "capability table covers c:remove"  "c:remove=superadmin" "$TG_CB_CAPS"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
