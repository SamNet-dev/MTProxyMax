#!/bin/bash
# Regression tests for reseller RBAC enforcement in the Telegram bot.
#
# The README restricts a `reseller` to voucher redemption and voucher
# create/list, but the dispatcher only blocked `role == none` plus four
# superadmin-only commands, so a reseller could drive nearly the whole admin
# control plane. These tests pin the documented contract.
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

MTPROXYMAX_SOURCE_ONLY=true source "$(dirname "${BASH_SOURCE[0]}")/../mtproxymax.sh"
set +e
trap 'rm -rf "$TEST_TMPDIR"' EXIT

TESTS_RUN=0
TESTS_FAILED=0

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

# ── Stubs ────────────────────────────────────────────────────────────────────
REPLIES="$TEST_TMPDIR/replies.log"
MANAGER_CALLS="$TEST_TMPDIR/manager-calls.log"
export MANAGER_CALLS
ROLE_TO_RETURN="reseller"

_check_tg_role() { echo "$ROLE_TO_RETURN"; }
tg_send() { printf 'admin|%s\n' "$*" >> "$REPLIES"; }
tg_send_to() { printf 'to:%s|%s\n' "$1" "$2" >> "$REPLIES"; }
load_tg_settings() { :; }
is_running() { return 1; }
log_warn() { :; }

# Stand-in for the manager binary the voucher handler shells out to.
cat > "$INSTALL_DIR/mtproxymax" <<'EOS'
#!/bin/bash
case "$1 $2" in
    # Three lines so the create path (which does `tail -n +3`) still yields one.
    "voucher list") printf 'HEADER\nSEPARATOR\nMTP-AAAA-BBBB\n' ;;
    "voucher create") : ;;
    "voucher redeem") printf '%s\n' "$*" >> "$MANAGER_CALLS" ;;
    *) : ;;
esac
EOS
chmod +x "$INSTALL_DIR/mtproxymax"

# Exercise the exact dispatcher shipped in the generated bot daemon.
telegram_generate_service_script
DAEMON="$INSTALL_DIR/mtproxymax-telegram.sh"
awk '/^_tg_security_log\(\)/,/^}$/' "$DAEMON" > "$TEST_TMPDIR/daemon-fns.sh"
awk '/^_process_cmd\(\)/,/^}$/' "$DAEMON" >> "$TEST_TMPDIR/daemon-fns.sh"
assert_eq "daemon helper extraction is valid bash" 0 \
    "$(bash -n "$TEST_TMPDIR/daemon-fns.sh" 2>/dev/null; echo $?)"
source "$TEST_TMPDIR/daemon-fns.sh"

# run <role> <chat_id> <text> -> replies in $REPLIES
run() {
    : > "$REPLIES"
    ROLE_TO_RETURN="$1"
    _process_cmd 1 "$2" "$3" 2>/dev/null
}
audit_now() { cat "$AUDIT_LOG" 2>/dev/null || printf ''; }
reset_audit() { : > "$AUDIT_LOG"; }

echo "Telegram reseller RBAC tests"

# ── A reseller is limited to vouchers ────────────────────────────────────────
reset_audit
run reseller 333 "/mp_status"
assert_contains "reseller is denied /mp_status" "Permission denied" "$(cat "$REPLIES")"
assert_contains "denial is logged" "SECURITY" "$(audit_now)"
assert_contains "log records the denied command" "/mp_status" "$(audit_now)"
assert_contains "log records the offending chat" "333" "$(audit_now)"
assert_contains "denial goes to the sender, not the admin chat" "to:333|" "$(cat "$REPLIES")"
assert_not_contains "denial is not sent to the admin chat" "admin|" "$(cat "$REPLIES")"

for _cmd in /mp_restart /mp_lockdown /mp_update /mp_remove /mp_add /mp_broadcast \
            /mp_secrets /mp_link /mp_setlimit /mp_help /mp_traffic /reply; do
    reset_audit
    run reseller 333 "$_cmd"
    assert_contains "reseller is denied $_cmd" "Permission denied" "$(cat "$REPLIES")"
    assert_contains "denial of $_cmd is logged" "SECURITY" "$(audit_now)"
done

# ── ...but vouchers and public commands still work ───────────────────────────
for _cmd in "/mp_voucher list" "/mp_voucher create 5 10G 30"; do
    reset_audit
    run reseller 333 "$_cmd"
    assert_not_contains "reseller is allowed $_cmd" "Permission denied" "$(cat "$REPLIES")"
    assert_eq "allowed $_cmd is not logged as a violation" "" "$(audit_now)"
    assert_contains "allowed $_cmd reaches the voucher engine" "MTP-AAAA-BBBB" "$(cat "$REPLIES")"
done

reset_audit
run reseller 333 "/start"
assert_not_contains "reseller keeps the public /start" "Permission denied" "$(cat "$REPLIES")"
assert_contains "reseller gets the self-service welcome" "Welcome to MTProxyMax" "$(cat "$REPLIES")"

# Public voucher aliases must have identical behavior and bind redemption to
# the sender's Telegram chat ID instead of accepting an arbitrary account.
for _cmd in voucher redeem; do
    : > "$MANAGER_CALLS"
    run none 8393457899 "/${_cmd} MTP-AAAA-BBBB чужой_label"
    assert_contains "/${_cmd} reaches voucher redemption" "voucher redeem MTP-AAAA-BBBB" "$(cat "$MANAGER_CALLS")"
    assert_contains "/${_cmd} binds the sender chat ID" "tg_8393457899" "$(cat "$MANAGER_CALLS")"
    assert_not_contains "/${_cmd} ignores a supplied account label" "чужой_label" "$(cat "$MANAGER_CALLS")"
done

# ── Superadmins are unaffected ───────────────────────────────────────────────
reset_audit
run superadmin 111 "/mp_status"
assert_not_contains "superadmin is not denied /mp_status" "Permission denied" "$(cat "$REPLIES")"
assert_eq "superadmin action is not logged as a violation" "" "$(audit_now)"

# ── Unauthenticated users still get nothing ──────────────────────────────────
reset_audit
run none 999 "/mp_status"
assert_eq "unauthenticated user gets no admin reply" "" "$(cat "$REPLIES")"
assert_eq "unauthenticated user is not logged as a violation" "" "$(audit_now)"

# ── Unrecognised roles fail closed ───────────────────────────────────────────
# _check_tg_role returns whatever admins.conf holds, and admins.conf is a plain
# file an operator can hand-edit. Anything that is not exactly 'superadmin' or
# 'reseller' must be refused rather than granted the admin control plane.
for _role in operator administrator root SUPERADMIN superadmin2; do
    reset_audit
    run "$_role" 444 "/mp_status"
    assert_contains "role '$_role' is denied the control plane" "Permission denied" "$(cat "$REPLIES")"
    assert_contains "role '$_role' denial is logged" "SECURITY" "$(audit_now)"
    assert_contains "role '$_role' denial names the role" "$_role" "$(audit_now)"
done

reset_audit
run operator 444 "/mp_voucher list"
assert_contains "unrecognised role cannot reach the voucher engine" "Permission denied" "$(cat "$REPLIES")"

reset_audit
run operator 444 "/start"
assert_not_contains "unrecognised role still gets public commands" "Permission denied" "$(cat "$REPLIES")"
assert_contains "unrecognised role gets the self-service welcome" "Welcome to MTProxyMax" "$(cat "$REPLIES")"
assert_eq "a public command is not logged as a violation" "" "$(audit_now)"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
