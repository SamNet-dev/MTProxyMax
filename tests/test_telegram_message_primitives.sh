#!/bin/bash
# Tests for the Bot API send primitives: chunking and the 400 fallback.
#
# Two behaviours matter here and neither existed before:
#
#   * Telegram caps a message at 4096 UTF-16 units and the bot builds messages
#     by appending one line per secret, so a fleet with enough users silently
#     produced a message that failed to send at all. There was no chunking.
#   * A single malformed legacy-Markdown entity made Telegram reject the whole
#     message with a 400. Retrying without parse_mode costs the formatting
#     instead of the content.
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
    local name="$1" cond="$2"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [ "$cond" -eq 0 ] 2>/dev/null; then
        printf '  PASS  %s\n' "$name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s\n' "$name"
    fi
}

telegram_generate_service_script
DAEMON="$INSTALL_DIR/mtproxymax-telegram.sh"
PRIMS="$TEST_TMPDIR/prims.sh"
: > "$PRIMS"
for _fn in _tg_chunk_text _tg_send_pieces _tg_msg_id; do
    awk "/^${_fn}\\(\\)/,/^}\$/" "$DAEMON" >> "$PRIMS"
done
assert_eq "primitive extraction is valid bash" 0 \
    "$(bash -n "$PRIMS" 2>/dev/null; echo $?)"
source "$PRIMS"

echo "Telegram message primitive tests"

# The chunker separates records with 0x1f. NOTE: `tr '\x1f' ...` does not work
# — GNU tr has no \xHH escape — and chunk bodies legitimately contain newlines,
# so neither line-counting nor splitting on newlines is valid here.
SEP=$'\x1f'
n_chunks() {
    local c n=0
    while IFS= read -r -d "$SEP" c; do n=$((n + 1)); done < <(_tg_chunk_text "$2" "$1")
    printf '%s' "$n"
}
# Reassemble every chunk, joining with the newline the split removed.
joined() {
    local c out=""
    while IFS= read -r -d "$SEP" c; do
        if [ -z "$out" ]; then out="$c"; else out="${out}"$'\n'"${c}"; fi
    done < <(_tg_chunk_text "$2" "$1")
    printf '%s' "$out"
}

# ── A body that fits stays a single chunk, unmodified ────────────────────────
assert_eq "short body yields one chunk" 1 "$(n_chunks "hello world" 3800)"
assert_eq "short body is passed through verbatim" "hello world" "$(joined "hello world" 3800)"

# ── A long body is split, and nothing is lost ────────────────────────────────
_long=$(seq 1 40 | awk '{printf "line %02d %s\n", $1, "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"}')
assert_ok "long body splits into more than one chunk" \
    "$([ "$(n_chunks "$_long" 300)" -gt 1 ] && echo 0 || echo 1)"

_over=1
while IFS= read -r -d "$SEP" _c; do
    [ "${#_c}" -gt 300 ] && _over=0
done < <(_tg_chunk_text 300 "$_long")
assert_ok "no chunk exceeds the budget" "$([ "$_over" -eq 1 ] && echo 0 || echo 1)"

# Reassembly must be lossless for unfenced content.
assert_eq "splitting then rejoining is lossless" "$_long" "$(joined "$_long" 300)"

# ── Fences are closed and reopened across a split ────────────────────────────
# A sparkline is alignment-sensitive: a chunk that opens a fence without
# closing it renders the remainder of that message as code.
_fenced=$( { printf 'header\n```\n'; seq 1 30 | awk '{printf "bar %02d %s\n", $1, "yyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyyy"}'; printf '```\ntail\n'; } )
_bad=0
while IFS= read -r -d "$SEP" _c; do
    _n=$(printf '%s\n' "$_c" | grep -c '^```')
    [ $(( _n % 2 )) -ne 0 ] && _bad=1
done < <(_tg_chunk_text 250 "$_fenced")
assert_ok "every chunk has balanced fences" "$([ "$_bad" -eq 0 ] && echo 0 || echo 1)"

assert_ok "fenced body actually splits" \
    "$([ "$(n_chunks "$_fenced" 250)" -gt 1 ] && echo 0 || echo 1)"

# No fenced row may be dropped, whatever the split point.
_rows=$(printf '%s' "$(joined "$_fenced" 250)" | grep -c '^bar ')
assert_eq "all fenced rows survive the split" 30 "$_rows"

# ── The 400 fallback drops parse_mode instead of the message ─────────────────
POST_LOG="$TEST_TMPDIR/posts.log"
POST_N=0
_tg_post_method() {
    printf '%s\n' "$*" >> "$POST_LOG"
    POST_N=$((POST_N + 1))
    if [ "$POST_N" -eq 1 ]; then
        printf '{"ok":false,"error_code":400,"description":"Bad Request: can not parse entities"}'
    else
        printf '{"ok":true,"result":{"message_id":42,"chat":{"id":1}}}'
    fi
}
: > "$POST_LOG"
_tg_send_pieces "111" "" "bad *markdown" "" >/dev/null
assert_eq "a 400 is retried exactly once" 2 "$(wc -l < "$POST_LOG" | tr -d ' ')"
assert_ok "the first attempt uses Markdown" \
    "$(grep -q 'parse_mode=Markdown' "$POST_LOG" && echo 0 || echo 1)"
assert_ok "the retry omits parse_mode" \
    "$(sed -n '2p' "$POST_LOG" | grep -qv 'parse_mode' && echo 0 || echo 1)"

# A successful send must NOT be retried.
: > "$POST_LOG"
POST_N=99
_tg_send_pieces "111" "" "fine" "" >/dev/null
assert_eq "a successful send is not retried" 1 "$(wc -l < "$POST_LOG" | tr -d ' ')"

# ── The keyboard rides on the final chunk only ───────────────────────────────
: > "$POST_LOG"
POST_N=99
_tg_send_pieces "111" "" "$_long" '{"inline_keyboard":[[{"text":"x","callback_data":"n"}]]}' >/dev/null
assert_eq "only the last chunk carries reply_markup" 1 "$(grep -c 'reply_markup' "$POST_LOG")"

# ── message_id extraction ────────────────────────────────────────────────────
assert_eq "extracts message_id from a send response" 42 \
    "$(_tg_msg_id '{"ok":true,"result":{"message_id":42,"chat":{"id":1}}}')"
assert_eq "returns empty when there is no message_id" "" \
    "$(_tg_msg_id '{"ok":false}')"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
