#!/bin/bash
# Tests for the per-secret management surface: the manage card, the limit
# pickers behind it, and the commits those buttons make.
#
# The behaviour that matters most here is the WRITE PATH. The obvious way to set
# one limit is `secret setlimits <label> <conns> <ips> <quota> <expires>`, but
# secret_set_limits reads "0" as UNLIMITED, not as "leave alone" — so tapping
# "quota: 10G" through that verb would silently wipe the connection and IP caps
# too. Every commit below therefore has to reach the per-field
# `secret setlimit <label> <field> <value>` form, and the assertions pin that.
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

printf 'alice|%s|1700000000|true|7|3|10737418240|2027-01-01|the note|%s\n' \
    "$(printf 'a%.0s' $(seq 1 32))" "$(printf 'f%.0s' $(seq 1 32))" > "$SECRETS_FILE"
printf 'bob|%s|1700000000|false|0|0|0|0||\n' "$(printf 'b%.0s' $(seq 1 32))" >> "$SECRETS_FILE"

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

# ── Extract the shipped menu block ───────────────────────────────────────────
telegram_generate_service_script
DAEMON="$INSTALL_DIR/mtproxymax-telegram.sh"
FNS="$TEST_TMPDIR/daemon-fns.sh"
: > "$FNS"
for _fn in _tg_security_log _esc _cb_label_ok _cb_enc _cb_dec _iso_to_epoch; do
    awk "/^${_fn}\\(\\)/,/^}\$/" "$DAEMON" >> "$FNS"
done
awk '/^# >>> TG_MENU_BEGIN$/,/^# <<< TG_MENU_END$/' "$DAEMON" >> "$FNS"
assert_eq "extraction is valid bash" 0 "$(bash -n "$FNS" 2>/dev/null; echo $?)"

# ── Stubs ────────────────────────────────────────────────────────────────────
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
is_running() { return 1; }
log_warn() { :; }
get_cached_ip() { echo "203.0.113.9"; }
_tg_metrics_raw() { printf ''; }
_tg_have_python() { return 1; }

cat > "$INSTALL_DIR/mtproxymax" <<'EOS'
#!/bin/bash
printf '%s\n' "$*" >> "$MTPX_CALLS"
exit 0
EOS
chmod +x "$INSTALL_DIR/mtproxymax"
export MTPX_CALLS="$CALLS"

source "$FNS"

_UI_ROLE="superadmin"
_CB_CHAT="111"; _CB_MID="77"

render() {   # render <ns> <act> <tgt> <page>
    : > "$EDITS"
    _cb_dispatch_prepare "$1" "$2" "$3" "$4"
    _cb_dispatch >/dev/null 2>&1
    cat "$EDITS"
}
# Drive the dispatcher the way a real tap does: through the codec, so the
# payload is validated exactly as it would be in production.
_cb_dispatch_prepare() {
    local p
    p=$(_cb_enc "$1" "$2" "$3" "$4") || { _CB_DATA=""; return 1; }
    _CB_DATA="$p"
    _CB_NS="$1"; _CB_ACT="$2"; _CB_TGT="$3"; _CB_PAGE="$4"
    _CB_CHAT="111"; _CB_MID="77"; _CB_TOAST=""; _CB_ALERT="false"
}
commit() {   # commit <act> <label> <value> -> manager calls
    : > "$CALLS"
    _cb_dispatch_prepare "c" "$1" "$2" "$3"
    _cb_dispatch >/dev/null 2>&1
    cat "$CALLS"
}

# ── The manage card is reachable from the user card ──────────────────────────
_out=$(render "u" "s" "alice" "0")
assert_contains "user card offers a manage entry" "u:m:alice:0" "$_out"

_out=$(render "u" "m" "alice" "0")
assert_contains "manage card offers the quota picker"  "e:q:alice:0" "$_out"
assert_contains "manage card offers the conns picker"  "e:c:alice:0" "$_out"
assert_contains "manage card offers the IPs picker"    "e:i:alice:0" "$_out"
assert_contains "manage card offers the expiry picker" "e:x:alice:0" "$_out"
assert_contains "manage card offers the note prompt"   "e:n:alice:0" "$_out"
assert_contains "manage card offers the adtag prompt"  "e:a:alice:0" "$_out"
assert_contains "manage card offers the template picker" "e:t:alice:0" "$_out"
assert_contains "manage card goes back to the user card" "u:s:alice:0" "$_out"
# The card is where the current values are read, so they have to be on it.
assert_contains "manage card shows the current quota" "10.00 GB" "$_out"
assert_contains "manage card shows the current conn cap" "7" "$_out"
assert_contains "manage card shows the note" "the note" "$_out"

# ── Pickers offer presets, and every payload is one Telegram will accept ─────
for _f in q c i x r; do
    _out=$(render "e" "$_f" "alice" "0")
    _bad=""
    while IFS= read -r _p; do
        [ -z "$_p" ] && continue
        case "$_p" in
            c:*) ;;
            *) continue ;;
        esac
        [ "${#_p}" -le 64 ] || _bad="${_bad} len:${_p}"
        _cb_dec "$_p" || _bad="${_bad} unparseable:${_p}"
    done < <(printf '%s' "$_out" | grep -oE 'c:[A-Za-z0-9_:.-]+')
    assert_eq "every $_f preset is a payload Telegram will accept" "" "$_bad"
    assert_not_contains "$_f picker draws no code box" '```' "$_out"
done

_out=$(render "e" "q" "alice" "0")
assert_contains "quota picker offers 10G"   "c:setq:alice:10G" "$_out"
assert_contains "quota picker offers unlimited" "c:setq:alice:0" "$_out"
assert_contains "quota picker goes back to the manage card" "u:m:alice:0" "$_out"

_out=$(render "e" "x" "alice" "0")
assert_contains "expiry picker offers 30 days" "c:setx:alice:30" "$_out"
assert_contains "expiry picker offers never"   "c:setx:alice:0" "$_out"

_out=$(render "e" "r" "alice" "0")
assert_contains "reset picker offers day 15" "c:setr:alice:15" "$_out"
assert_contains "reset picker offers off"    "c:setr:alice:off" "$_out"

# ── Commits hit the per-field verb, and only that field ──────────────────────
assert_eq "quota commit uses the per-field verb" \
    "secret setlimit alice quota 10G" "$(commit "setq" "alice" "10G")"
assert_eq "conns commit uses the per-field verb" \
    "secret setlimit alice conns 50" "$(commit "setc" "alice" "50")"
assert_eq "IPs commit uses the per-field verb" \
    "secret setlimit alice ips 5" "$(commit "seti" "alice" "5")"
assert_eq "unlimited quota commits as 0" \
    "secret setlimit alice quota 0" "$(commit "setq" "alice" "0")"

# The whole reason for the per-field verb: setlimits with a 0 would read as
# "unlimited" for the fields the tap never mentioned.
assert_not_contains "a quota change never calls setlimits" \
    "setlimits" "$(commit "setq" "alice" "10G")"

# Expiry is relative ("+30d") for a real date and absolute ("never") for 0, and
# the CLI already has a verb for the relative case.
assert_eq "a relative expiry extends rather than rewriting limits" \
    "secret extend alice 30" "$(commit "setx" "alice" "30")"
assert_eq "never expiry clears the date" \
    "secret setlimit alice expires 0" "$(commit "setx" "alice" "0")"

assert_eq "reset-day commit reaches the CLI" \
    "secret quota-reset alice 15" "$(commit "setr" "alice" "15")"
assert_eq "reset-day off reaches the CLI" \
    "secret quota-reset alice off" "$(commit "setr" "alice" "off")"

# ── Bad input cannot reach the CLI ───────────────────────────────────────────
assert_eq "an unknown commit verb is refused" "" "$(commit "setz" "alice" "10G")"
assert_eq "a non-numeric conns value is refused" "" "$(commit "setc" "alice" "lots")"
assert_eq "a non-numeric quota value is refused" "" "$(commit "setq" "alice" "abc")"
assert_eq "a nonsense reset day is refused" "" "$(commit "setr" "alice" "99")"
assert_eq "a missing label is refused" "" "$(commit "setq" "" "10G")"

# ── A label off disk is re-validated before it is used as a pattern ──────────
# The label comes back out of callback_data, which is attacker-controlled, and
# out of secrets.conf, which is hand-editable. Neither is trusted.
assert_eq "a label that is not a label never reaches the CLI" "" "$(commit "setq" "../../etc" "10G")"

# ── RBAC: every action above is known to the capability table ────────────────
_missing=""
# Note and ad-tag are pending-input flows rather than c: commits (their text
# cannot ride in callback_data), so they are entered through e: and not listed
# here — _tg_pending_run owns their write path.
for _k in u:m e:q e:c e:i e:x e:r e:n e:a e:t e:z c:setq c:setc c:seti c:setx c:setr c:tpl p:x; do
    _ns="${_k%%:*}"; _act="${_k#*:}"
    [ -n "$(_tg_cap_for "$_ns" "$_act")" ] || _missing="${_missing} ${_k}"
done
assert_eq "every new action has a capability" "" "$_missing"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
