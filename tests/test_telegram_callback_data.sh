#!/bin/bash
# Tests for the inline-keyboard callback_data codec.
#
# callback_data is capped at 64 bytes by the Bot API, and a single over-long
# payload makes Telegram reject the ENTIRE reply_markup with a 400 — the whole
# message is lost, not just the one button. Equally, a target containing ':'
# would shift the positional fields and silently decode to a different target.
# These tests pin both properties.
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

assert_ok() {
    local name="$1"; shift
    TESTS_RUN=$((TESTS_RUN + 1))
    if "$@" >/dev/null 2>&1; then
        printf '  PASS  %s\n' "$name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s (expected success)\n' "$name"
    fi
}

assert_rejects() {
    local name="$1"; shift
    TESTS_RUN=$((TESTS_RUN + 1))
    if "$@" >/dev/null 2>&1; then
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s (expected rejection)\n' "$name"
    else
        printf '  PASS  %s\n' "$name"
    fi
}

# ── Extract the codec from the daemon that actually ships ────────────────────
telegram_generate_service_script
DAEMON="$INSTALL_DIR/mtproxymax-telegram.sh"
CODEC="$TEST_TMPDIR/codec.sh"
# _CB_MAX is a top-level assignment in the daemon, so the function extractor
# below would not pick it up — pull it explicitly, and assert it so that a
# future move fails loudly here instead of as an obscure arithmetic error.
grep -m1 '^_CB_MAX=' "$DAEMON" > "$CODEC"
for _fn in _cb_label_ok _cb_enc _cb_dec; do
    awk "/^${_fn}\\(\\)/,/^}\$/" "$DAEMON" >> "$CODEC"
done
assert_eq "codec extraction is valid bash" 0 \
    "$(bash -n "$CODEC" 2>/dev/null; echo $?)"
source "$CODEC"
assert_eq "callback_data cap is 64 bytes" 64 "${_CB_MAX:-}"

echo "Telegram callback_data codec tests"

# ── _cb_label_ok ─────────────────────────────────────────────────────────────
assert_ok       "label 'alice' is valid"            _cb_label_ok "alice"
assert_ok       "label 'a-b_c9' is valid"           _cb_label_ok "a-b_c9"
assert_ok       "32-char label is valid"            _cb_label_ok "0123456789012345678901234567890a"
assert_rejects  "33-char label is rejected"         _cb_label_ok "0123456789012345678901234567890ab"
assert_rejects  "empty label is rejected"           _cb_label_ok ""
assert_rejects  "label with ':' is rejected"        _cb_label_ok "alice:bob"
assert_rejects  "label with space is rejected"      _cb_label_ok "al ice"
assert_rejects  "label with '\$(' is rejected"      _cb_label_ok 'a$(id)'
assert_rejects  "label with ';' is rejected"        _cb_label_ok "alice;rm"
assert_rejects  "label with '*' is rejected"        _cb_label_ok "alice*"
assert_rejects  "label with '/' is rejected"        _cb_label_ok "a/b"

# ── _cb_enc ──────────────────────────────────────────────────────────────────
assert_eq "encodes a bare no-op"        "n"                 "$(_cb_enc n "" "" "")"
assert_eq "encodes hub:help"            "m:h"               "$(_cb_enc m h "" "")"
assert_eq "encodes a list page"         "u:l:2"             "$(_cb_enc u l 2 "")"
assert_eq "encodes a detail card"       "u:s:alice:0"       "$(_cb_enc u s alice 0)"
assert_eq "encodes an action request"   "a:disable:alice"   "$(_cb_enc a disable alice "")"
assert_eq "encodes a confirmed action"  "c:remove:alice"    "$(_cb_enc c remove alice "")"
assert_eq "encodes a traffic window"    "t:w:24h"           "$(_cb_enc t w 24h "")"

assert_rejects "enc refuses a ':' in the target"  _cb_enc a disable "ali:ce" ""
assert_rejects "enc refuses a 33-char target"     _cb_enc a disable "0123456789012345678901234567890ab" ""
assert_rejects "enc refuses an injected target"   _cb_enc a disable 'a$(id)' ""
assert_rejects "enc refuses an empty target"      _cb_enc a disable "" ""

# Every verb against a maximal label must stay inside the 64-byte cap.
for _verb in enable disable rotate remove; do
    _p=$(_cb_enc a "$_verb" "0123456789012345678901234567890a" "")
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ -n "$_p" ] && [ "${#_p}" -le 64 ]; then
        printf '  PASS  maximal %s payload is within 64 bytes (%d)\n' "$_verb" "${#_p}"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  maximal %s payload is within 64 bytes (got %d)\n' "$_verb" "${#_p}"
    fi
    _rt=$(_cb_enc a "$_verb" "0123456789012345678901234567890a" "")
    assert_eq "maximal ${_verb} payload round-trips" \
        "a:${_verb}:0123456789012345678901234567890a" "$_rt"
done

# ── _cb_dec ──────────────────────────────────────────────────────────────────
decode() {
    _CB_NS=""; _CB_ACT=""; _CB_TGT=""; _CB_PAGE=""
    _cb_dec "$1" || return 1
    printf '%s|%s|%s|%s' "$_CB_NS" "$_CB_ACT" "$_CB_TGT" "$_CB_PAGE"
}

assert_eq "decodes a bare no-op"       "n|||"              "$(decode n)"
assert_eq "decodes hub:help"           "m|h||"             "$(decode m:h)"
assert_eq "decodes a list page"        "u|l|2|"            "$(decode u:l:2)"
assert_eq "decodes a detail card"      "u|s|alice|0"       "$(decode u:s:alice:0)"
assert_eq "decodes an action request"  "a|disable|alice|"  "$(decode a:disable:alice)"
assert_eq "decodes a traffic window"   "t|w|24h|"          "$(decode t:w:24h)"

assert_rejects "dec rejects an empty payload"        _cb_dec ""
assert_rejects "dec rejects an empty field"          _cb_dec "a:disable:"
assert_rejects "dec rejects an uppercase namespace"  _cb_dec "A:disable:alice"
assert_rejects "dec rejects a 3-char namespace"      _cb_dec "tool:l"
assert_rejects "dec rejects too many fields"         _cb_dec "u:l:2:3:4"
assert_rejects "dec rejects an over-long field"      _cb_dec "u:s:0123456789012345678901234567890ab"
assert_rejects "dec rejects an over-long payload"    _cb_dec "u:s:alice:0:extra:more:junk:padding:aaaaaaaaaaaaaaaaaaaaaaaaa"

# An over-long payload must be refused, never truncated: truncation would
# decode into a different, still-valid target.
_pad=$(printf 'a%.0s' $(seq 1 80))
assert_rejects "dec rejects an 80-byte payload"      _cb_dec "$_pad"

# A forged payload is inert data — never evaluated, never decoded into a target
# that could reach a shell.
assert_rejects "dec rejects a forged \$( ) payload"  _cb_dec 'a:disable:$(id)'

# ── Round-trip ───────────────────────────────────────────────────────────────
# Field is 3rd-positional, so these specs carry no trailing ':' (read would
# absorb it into the last variable).
for _spec in "n" "m:h" "u:l:2" "u:s:alice:0" "a:disable:alice" "c:remove:alice" \
             "t" "t:w:7d" "t:u:30d" "y" "y:e"; do
    IFS=':' read -r _ns _act _tgt _pg <<< "$_spec"
    _enc=$(_cb_enc "$_ns" "$_act" "$_tgt" "$_pg")
    _dec=$(decode "$_enc")
    assert_eq "round-trip $_spec" "$_ns|$_act|$_tgt|$_pg" "$_dec"
done

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
