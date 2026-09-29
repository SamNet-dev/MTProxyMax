#!/bin/bash
# Tests for the pending-input primitive.
#
# Inline buttons cannot collect typed text, so a flow that needs a value (add a
# user, set a custom limit, broadcast) arms a prompt for that chat and the next
# plain message from that chat is consumed as the answer. The dangerous half is
# the consumption: a stale or misfiled entry would swallow a user's next real
# message. These tests pin both halves — that an armed prompt answers exactly
# once, and that it can never eat a command or outlive its TTL.
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

# ── Extract the shipped primitive ────────────────────────────────────────────
telegram_generate_service_script
DAEMON="$INSTALL_DIR/mtproxymax-telegram.sh"
FNS="$TEST_TMPDIR/daemon-fns.sh"
: > "$FNS"
for _fn in _tg_security_log _cb_label_ok _cb_enc _cb_dec; do
    awk "/^${_fn}\\(\\)/,/^}\$/" "$DAEMON" >> "$FNS"
done
# The block is delimited by markers so the test exercises exactly what ships,
# and so a function added to it later is picked up without editing this list.
awk '/^# >>> TG_PENDING_BEGIN$/,/^# <<< TG_PENDING_END$/' "$DAEMON" >> "$FNS"
assert_eq "pending-input extraction is valid bash" 0 \
    "$(bash -n "$FNS" 2>/dev/null; echo $?)"
assert_eq "the pending block was found in the daemon" 1 \
    "$(grep -c '^# >>> TG_PENDING_BEGIN$' "$FNS")"
# A missing function would silently make every later assertion vacuous.
assert_contains "the primitive ships in the daemon" "_tg_pending_set()" "$(cat "$FNS")"

# ── Stubs ────────────────────────────────────────────────────────────────────
SENDS="$TEST_TMPDIR/sends.log"
CALLS="$TEST_TMPDIR/calls.log"
ROLE_TO_RETURN="superadmin"
# Link building reads these; leaving them unset would make the assertion below
# pass against a malformed "host:" string.
PROXY_PORT=443
PROXY_DOMAIN="cloudflare.com"
MASKING_ENABLED="true"

_check_tg_role() { echo "$ROLE_TO_RETURN"; }
tg_send_to() { printf '%s|%s\n' "$1" "$2" >> "$SENDS"; }
tg_send() { printf 'admin|%s\n' "$*" >> "$SENDS"; }
tg_send_to_kb() { printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$SENDS"; }
load_tg_settings() { :; }
get_cached_ip() { echo "203.0.113.9"; }
domain_to_hex() { echo "0a0b0c0d"; }
_esc() { printf '%s' "$1"; }
format_bytes() { printf '%s' "$1"; }

# The stub records the call AND performs the one side effect the flow reads
# back — a created secret. Without that, the link-building half of the flow
# would silently take its "not found" branch and never be exercised.
cat > "$INSTALL_DIR/mtproxymax" <<'EOS'
#!/bin/bash
printf '%s\n' "$*" >> "$MTPX_CALLS"
if [ "$1" = "secret" ] && [ "$2" = "add" ]; then
    printf '%s|%s|1700000000|true|0|0|0|0||\n' "$3" "$(printf 'c%.0s' $(seq 1 32))" >> "$SECRETS_FILE"
fi
exit 0
EOS
chmod +x "$INSTALL_DIR/mtproxymax"
export MTPX_CALLS="$CALLS" SECRETS_FILE

source "$FNS"

PENDING="$INSTALL_DIR/relay_stats/.tg_pending"
reset_state() { : > "$SENDS"; : > "$CALLS"; rm -f "$PENDING"; }

# ── Round trip ───────────────────────────────────────────────────────────────
reset_state
_tg_pending_set "111" "add" "-"
assert_eq "an armed prompt reads back as verb|target" "add|-" "$(_tg_pending_take "111")"
assert_eq "taking clears it, so it answers only once" 1 "$(_tg_pending_take "111" >/dev/null 2>&1; echo $?)"

# ── Per-chat isolation ───────────────────────────────────────────────────────
reset_state
_tg_pending_set "111" "add" "-"
_tg_pending_set "222" "limit" "alice"
assert_eq "another chat's prompt is untouched" "add|-" "$(_tg_pending_take "111")"
assert_eq "and its own still answers" "limit|alice" "$(_tg_pending_take "222")"

# Re-arming must REPLACE, not append: a second set that left the first line in
# place would answer with the stale verb.
reset_state
_tg_pending_set "111" "add" "-"
_tg_pending_set "111" "limit" "alice"
assert_eq "re-arming replaces the previous prompt" "limit|alice" "$(_tg_pending_take "111")"
assert_eq "and leaves exactly one line on disk" 0 "$(grep -c . "$PENDING")"

# ── Expiry ───────────────────────────────────────────────────────────────────
reset_state
_TG_PENDING_TTL=0 _tg_pending_set "111" "add" "-"
assert_eq "an expired prompt does not answer" 1 "$(_tg_pending_take "111" >/dev/null 2>&1; echo $?)"
assert_eq "and is pruned off disk" 0 "$(grep -c . "$PENDING")"

# A prompt for another chat must not be swept by the prune above.
reset_state
_TG_PENDING_TTL=0 _tg_pending_set "111" "add" "-"
_tg_pending_set "222" "limit" "alice"
_tg_pending_take "111" >/dev/null 2>&1
assert_eq "pruning one chat leaves the other armed" "limit|alice" "$(_tg_pending_take "222")"

# ── Clear ────────────────────────────────────────────────────────────────────
reset_state
_tg_pending_set "111" "add" "-"
_tg_pending_clear "111"
assert_eq "clearing disarms the prompt" 1 "$(_tg_pending_take "111" >/dev/null 2>&1; echo $?)"

# ── The escape hatch ─────────────────────────────────────────────────────────
# This is the property that keeps a user from being trapped: any slash command
# cancels the prompt and is then dispatched normally.
reset_state
_tg_pending_set "111" "add" "-"
assert_eq "a command is not consumed as an answer" 1 "$(_tg_pending_try "111" "/mp_help"; echo $?)"
assert_eq "and the prompt is disarmed rather than left dangling" 1 "$(_tg_pending_take "111" >/dev/null 2>&1; echo $?)"
assert_eq "nothing was executed while escaping" "" "$(cat "$CALLS")"

reset_state
_tg_pending_set "111" "add" "-"
assert_eq "a plain message IS consumed as an answer" 0 "$(_tg_pending_try "111" "carol"; echo $?)"
assert_eq "and is not left armed afterwards" 1 "$(_tg_pending_take "111" >/dev/null 2>&1; echo $?)"

reset_state
assert_eq "with no prompt armed, a plain message passes through" 1 "$(_tg_pending_try "111" "hello"; echo $?)"

# ── The add flow actually runs ───────────────────────────────────────────────
# End-to-end for the one flow that exists at this layer: the typed value must
# reach the CLI verb, and the reply must go back to the chat that typed it.
reset_state
_tg_pending_set "111" "add" "-"
_tg_pending_try "111" "carol" >/dev/null
assert_contains "the typed label reaches the CLI" "secret add carol" "$(cat "$CALLS")"
assert_contains "and the chat is told about it" "111|" "$(cat "$SENDS")"
# The new user is useless without a way to connect, so the flow must hand back
# a link built from the freshly written secret — not just an acknowledgement.
assert_contains "a connect link comes back" "203.0.113.9:443" "$(cat "$SENDS")"

# A label that could never be a secret name is refused before reaching the CLI,
# so a pasted link cannot be turned into a directory-traversing label.
reset_state
_tg_pending_set "111" "add" "-"
_tg_pending_try "111" "../../etc/passwd" >/dev/null
assert_eq "an invalid label never reaches the CLI" "" "$(cat "$CALLS")"
assert_contains "and the user is told why" "❌" "$(cat "$SENDS")"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
