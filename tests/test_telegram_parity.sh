#!/bin/bash
# Tests that every administrative command has a button route.
#
# The point of the button surface is that an operator never has to remember a
# command, so a command that is reachable ONLY by typing is a gap, not a
# nicety. The parity map is asserted directly: for each command there is a
# payload somewhere in the menu graph that reaches the same CLI verb.
#
# The global verbs (rotate-all, restart, update, lockdown) are the dangerous
# ones: they are targetless, so they carry a "_" placeholder where a secret
# label would go, and they must stay behind a confirmation.
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
TEMPLATES_FILE="$INSTALL_DIR/templates.conf"

printf 'alice|%s|1700000000|true|7|3|10737418240|2027-01-01||\n' "$(printf 'a%.0s' $(seq 1 32))" > "$SECRETS_FILE"
# A secret genuinely called "_" — the global verbs use "_" as a placeholder for
# "no label", and that must not take this secret's verbs away from it.
printf '_|%s|1700000000|true|0|0|0|0||\n' "$(printf '9%.0s' $(seq 1 32))" >> "$SECRETS_FILE"
printf 'vip|100|5|50G|2027-01-01|top tier\n' > "$TEMPLATES_FILE"

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
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then printf '  PASS  %s\n' "$name"
    else TESTS_FAILED=$((TESTS_FAILED + 1)); printf '  FAIL  %s (missing %q in %q)\n' "$name" "$needle" "$haystack"; fi
}
assert_not_contains() {
    local name="$1" needle="$2" haystack="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
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
assert_eq "extraction is valid bash" 0 "$(bash -n "$FNS" 2>/dev/null; echo $?)"

SENDS="$TEST_TMPDIR/sends.log"
CALLS="$TEST_TMPDIR/calls.log"
EDITS="$TEST_TMPDIR/edits.log"
ROLE_TO_RETURN="superadmin"

_check_tg_role() { echo "$ROLE_TO_RETURN"; }
tg_send() { printf 'admin|%s\n' "$*" >> "$SENDS"; }
tg_send_to() { printf '%s|%s\n' "$1" "$2" >> "$SENDS"; }
tg_send_kb() { printf 'admin|%s|%s\n' "$1" "$2" >> "$SENDS"; }
tg_send_to_kb() { printf '%s|%s|%s\n' "$1" "$2" "$3" >> "$SENDS"; }
tg_answer_cb() { :; }
tg_edit() { printf '%s\n---\n%s\n' "$3" "$4" > "$EDITS"; }
tg_edit_markup() { printf 'markup\n---\n%s\n' "$3" > "$EDITS"; }
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
_tg_metrics_raw() { printf ''; }
_tg_have_python() { return 1; }

cat > "$INSTALL_DIR/mtproxymax" <<'EOS'
#!/bin/bash
printf '%s\n' "$*" >> "$MTPX_CALLS"
case "$1" in
    telegram)
        # The /help view renders from the same list Telegram is told about,
        # rather than a hand-maintained copy that can drift from it.
        case "$2" in
            commands)
                printf 'mp_status|Proxy status\nmp_add|Add a new secret (usage: /mp_add <label>)\n'
                ;;
        esac
        ;;
esac
exit 0
EOS
chmod +x "$INSTALL_DIR/mtproxymax"
export MTPX_CALLS="$CALLS"

source "$FNS"

_UI_ROLE="superadmin"
_CB_CHAT="111"; _CB_MID="77"

prepare() {
    local p
    p=$(_cb_enc "$1" "$2" "$3" "$4") || { _CB_DATA=""; return 1; }
    _CB_DATA="$p"; _CB_NS="$1"; _CB_ACT="$2"; _CB_TGT="$3"; _CB_PAGE="$4"
    _CB_CHAT="111"; _CB_MID="77"; _CB_TOAST=""; _CB_ALERT="false"
    : > "$EDITS"; : > "$CALLS"; : > "$SENDS"
}
render() { prepare "$1" "$2" "$3" "$4" && _cb_dispatch >/dev/null 2>&1; cat "$EDITS"; }
commit() { prepare "$1" "$2" "$3" "$4" && _cb_dispatch >/dev/null 2>&1; cat "$CALLS"; }
toast()  { prepare "$1" "$2" "$3" "$4" && _cb_dispatch >/dev/null 2>&1; printf '%s' "$_CB_TOAST"; }

# ── The hub reaches every section ────────────────────────────────────────────
_out=$(render "m" "" "" "")
assert_contains "hub offers users"     "u:l:0" "$_out"
assert_contains "hub offers traffic"   "t"     "$_out"
assert_contains "hub offers the server console" "y" "$_out"
assert_contains "hub offers templates" "k"     "$_out"
assert_contains "hub offers tools"     "g"     "$_out"
assert_contains "hub offers settings"  "s"     "$_out"
assert_contains "hub offers help"      "m:h"   "$_out"
assert_not_contains "hub draws no code box" '```' "$_out"

# ── The server console reaches everything /mp_status, /mp_digest,
#    /mp_upstreams and /mp_fleet used to be the only route to ────────────────
_out=$(render "y" "" "" "")
assert_contains "server console reaches the digest"    "y:d" "$_out"
assert_contains "server console reaches upstreams"     "y:p" "$_out"
assert_contains "server console reaches fleet"         "y:f" "$_out"
assert_contains "server console reaches vouchers"      "y:v" "$_out"
assert_contains "server console reaches the update check" "y:u" "$_out"

for _v in d p f v u; do
    _out=$(render "y" "$_v" "" "")
    assert_not_contains "server sub-view $_v draws no code box" '```' "$_out"
done

# ── Tools reach the commands that need typed input ───────────────────────────
_out=$(render "g" "" "" "")
assert_contains "tools offer adding a user"   "g:a"   "$_out"
assert_contains "tools offer rotate-all"      "a:rotall:_" "$_out"
assert_contains "tools offer a broadcast"     "g:b"   "$_out"
assert_contains "tools offer quarantine"      "a:lockdown:on" "$_out"
assert_not_contains "tools do not execute lockdown on a single tap" "c:lockdown:on" "$_out"
assert_contains "tools offer restart"         "a:restart:_" "$_out"
assert_contains "tools offer update"          "a:update:_" "$_out"

# ── Global verbs: confirmed first, and reaching the right CLI verb ───────────
assert_contains "rotate-all asks first" "Rotate all" "$(render "a" "rotall" "_" "")"
assert_eq "rotate-all does not run on the confirm tap" "" "$(cat "$CALLS")"
assert_contains "restart asks first" "Restart" "$(render "a" "restart" "_" "")"
assert_eq "restart does not run on the confirm tap" "" "$(cat "$CALLS")"

assert_eq "rotate-all runs the bulk verb" "secret rotate --all" "$(commit "c" "rotall" "_" "")"
assert_eq "restart runs the service verb" "restart"             "$(commit "c" "restart" "_" "")"
assert_eq "update runs the self-update verb" "update"           "$(commit "c" "update" "_" "")"
assert_eq "lockdown on reaches the CLI"  "lockdown on"          "$(commit "c" "lockdown" "on" "")"
assert_eq "lockdown off reaches the CLI" "lockdown off"         "$(commit "c" "lockdown" "off" "")"
assert_eq "a nonsense lockdown mode is refused" "" "$(commit "c" "lockdown" "maybe" "")"

# The "_" placeholder must not leak into the secret verbs: a secret genuinely
# named "_" is legal, and "disable _" must still mean that secret.
assert_eq "a secret named _ is still a secret" \
    "secret disable _" "$(commit "c" "disable" "_" "0")"

# ── Typed-input flows arm a prompt and then land on the right verb ───────────
arm() {   # arm <ns> <act> <tgt> <page> -> pending store line
    prepare "$1" "$2" "$3" "$4" && _cb_dispatch >/dev/null 2>&1
    cat "$INSTALL_DIR/relay_stats/.tg_pending" 2>/dev/null
}

assert_contains "add-user arms a prompt"   "|add|-|"    "$(arm "g" "a" "" "")"
assert_contains "broadcast arms a prompt"  "|broadcast|-|" "$(arm "g" "b" "" "")"
assert_contains "note arms a prompt"       "|note|alice|" "$(arm "e" "n" "alice" "0")"
assert_contains "ad-tag arms a prompt"     "|adtag|alice|" "$(arm "e" "a" "alice" "0")"

# And the typed answer reaches the matching CLI verb.
answer() {   # answer <text>
    : > "$CALLS"; : > "$SENDS"
    _tg_pending_try "111" "$1" >/dev/null 2>&1
    cat "$CALLS"
}
arm "e" "n" "alice" "0" >/dev/null
assert_eq "a typed note reaches the note verb" "secret note alice hello there" "$(answer "hello there")"

arm "e" "a" "alice" "0" >/dev/null
assert_eq "a typed ad-tag reaches the adtag verb" \
    "secret adtag alice 0123456789abcdef0123456789abcdef" "$(answer "0123456789abcdef0123456789abcdef")"

arm "e" "a" "alice" "0" >/dev/null
assert_eq "an ad-tag that is not 32 hex is refused" "" "$(answer "not-a-tag")"

arm "g" "b" "" "" >/dev/null
assert_eq "a typed broadcast reaches the broadcast verb" "broadcast hello all" "$(answer "hello all")"

# A prompt for a secret that has since been removed must not write to it.
arm "e" "n" "ghost" "0" >/dev/null
assert_eq "a note for a removed secret is refused" "" "$(answer "hi")"

# ── The escape hatch still works with these flows armed ──────────────────────
arm "e" "n" "alice" "0" >/dev/null
: > "$CALLS"
_tg_pending_try "111" "/mp_status" >/dev/null 2>&1
assert_eq "a command escapes the note prompt" "" "$(cat "$CALLS")"

# ── The help view is the real command list, not a hand-kept copy ─────────────
_out=$(render "m" "h" "" "")
assert_contains "help lists the registered commands" "mp\\_status" "$_out"
assert_contains "help lists the usage text too" "Add a new secret" "$_out"
assert_not_contains "help escapes the underscores Telegram would italicise" "/mp_status" "$_out"
assert_not_contains "help draws no code box" '```' "$_out"

# ── Every action the new views can emit is known to the capability table ─────
_missing=""
for _k in m y:d y:p y:f y:v y:u g g:a g:b a:rotall c:rotall a:restart c:restart \
          a:update c:update a:lockdown c:lockdown; do
    _ns="${_k%%:*}"; _act="${_k#*:}"
    [ "$_act" = "$_ns" ] && _act=""
    [ -n "$(_tg_cap_for "$_ns" "$_act")" ] || _missing="${_missing} ${_k}"
done
assert_eq "every new global action has a capability" "" "$_missing"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
