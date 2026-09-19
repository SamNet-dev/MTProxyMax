#!/bin/bash
# Tests for the getUpdates parser.
#
# Two production bugs motivate this file:
#
#   1. The no-python3 fallback extracted text and chat id in two INDEPENDENT
#      `grep | tail -1` passes and paired them by position. A batch of two
#      updates therefore lost all but the last, and could pair update A's text
#      with update B's chat id.
#   2. callback_query updates were never parsed at all, so the offset advanced
#      and Telegram never redelivered them.
#
# Both extractors must emit byte-identical records, because the awk path is the
# only one available on a host without python3 (e.g. Alpine, which this project
# supports via OpenRC).
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
        printf '  FAIL  %s\n         got=%q\n        want=%q\n' "$name" "$got" "$want"
    fi
}

assert_contains() {
    local name="$1" needle="$2" haystack="$3"
    TESTS_RUN=$((TESTS_RUN + 1))
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '  PASS  %s\n' "$name"
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        printf '  FAIL  %s (missing %q)\n' "$name" "$needle"
    fi
}

# ── Extract both extractors from the daemon that actually ships ──────────────
telegram_generate_service_script
DAEMON="$INSTALL_DIR/mtproxymax-telegram.sh"
PARSER="$TEST_TMPDIR/parser.sh"
: > "$PARSER"
for _fn in _tg_have_python _tg_parse_updates_py _tg_parse_updates_awk; do
    awk "/^${_fn}\\(\\)/,/^}\$/" "$DAEMON" >> "$PARSER"
done
assert_eq "parser extraction is valid bash" 0 \
    "$(bash -n "$PARSER" 2>/dev/null; echo $?)"
source "$PARSER"

echo "Telegram update parser tests"

# ── Fixtures ─────────────────────────────────────────────────────────────────
# Three updates in one batch. The second message's text deliberately embeds
# escaped quotes, braces and a backslash so that a scanner which does not track
# JSON string state will mis-slice the batch.
F_MAIN="$TEST_TMPDIR/main.json"
cat > "$F_MAIN" <<'JSON'
{"ok":true,"result":[{"update_id":1001,"message":{"message_id":11,"chat":{"id":111,"type":"private"},"text":"/mp_status"}},{"update_id":1002,"message":{"message_id":12,"chat":{"id":222,"type":"private"},"text":"tricky \"chat\":{\"id\":999} and } and \\ backslash"}},{"update_id":1003,"callback_query":{"id":"cb-abc","data":"u:s:alice:0","message":{"message_id":13,"chat":{"id":111,"type":"private"}}}}]}
JSON

# The text decodes to: tricky "chat":{"id":999} and } and \ backslash
EXPECT_MAIN=$(printf '1001\tmsg\t111\t11\t-\t/mp_status\n1002\tmsg\t222\t12\t-\ttricky "chat":{"id":999} and } and \\ backslash\n1003\tcb\t111\t13\tcb-abc\tu:s:alice:0')

# An update with no message/callback at all must still yield a record, so the
# consumer advances past it. Otherwise Telegram redelivers it forever.
F_BARE="$TEST_TMPDIR/bare.json"
cat > "$F_BARE" <<'JSON'
{"ok":true,"result":[{"update_id":2000},{"update_id":2001,"message":{"message_id":21,"chat":{"id":333,"type":"private"},"text":"/start"}}]}
JSON
EXPECT_BARE=$(printf '2000\tmsg\t\t\t-\t\n2001\tmsg\t333\t21\t-\t/start')

# A truncated response must yield nothing at all — never a partial record.
F_TRUNC="$TEST_TMPDIR/truncated.json"
printf '{"ok":true,"result":[{"update_id":9,"message":{"message_id":1,' > "$F_TRUNC"

# text containing a real newline escape: only the first line is the command.
F_MULTILINE="$TEST_TMPDIR/multiline.json"
cat > "$F_MULTILINE" <<'JSON'
{"ok":true,"result":[{"update_id":3000,"message":{"message_id":31,"chat":{"id":444,"type":"private"},"text":"/mp_add alice\nsecond line ignored"}}]}
JSON
EXPECT_MULTILINE=$(printf '3000\tmsg\t444\t31\t-\t/mp_add alice')

# ── The awk extractor (always available) ─────────────────────────────────────
assert_eq "awk parses a 3-update batch in order" "$EXPECT_MAIN" "$(_tg_parse_updates_awk "$(cat "$F_MAIN")")"
assert_eq "awk advances past updates with no message" "$EXPECT_BARE" "$(_tg_parse_updates_awk "$(cat "$F_BARE")")"
assert_eq "awk emits nothing for truncated JSON" "" "$(_tg_parse_updates_awk "$(cat "$F_TRUNC")")"
assert_eq "awk keeps only the first line of text" "$EXPECT_MULTILINE" "$(_tg_parse_updates_awk "$(cat "$F_MULTILINE")")"
assert_eq "awk emits nothing for empty input" "" "$(_tg_parse_updates_awk "")"
assert_eq "awk emits nothing for non-JSON input" "" "$(_tg_parse_updates_awk "not json at all")"

# The mis-pairing regression: update 1002's chat must be 222, not 111 or 999.
_awk_main=$(_tg_parse_updates_awk "$(cat "$F_MAIN")")
assert_contains "awk pairs text with its own chat id" "$(printf '1002\tmsg\t222\t12')" "$_awk_main"
assert_eq "awk does not leak a chat id embedded in text" 3 "$(printf '%s\n' "$_awk_main" | wc -l | tr -d ' ')"
assert_eq "awk does not mistake embedded text for the chat id" 0 \
    "$(printf '%s\n' "$_awk_main" | grep -c $'^1002\tmsg\t999\t')"

# ── 5000-char text is truncated to 512 ───────────────────────────────────────
F_LONG="$TEST_TMPDIR/long.json"
_LONG=$(printf 'A%.0s' $(seq 1 5000))
printf '{"ok":true,"result":[{"update_id":9,"message":{"message_id":1,"chat":{"id":5,"type":"private"},"text":"%s"}}]}' \
    "$_LONG" > "$F_LONG"
_LONG_OUT=$(_tg_parse_updates_awk "$(cat "$F_LONG")")
_LONG_PAY=$(printf '%s' "$_LONG_OUT" | cut -f6)
assert_eq "awk truncates a 5000-char text to 512" 512 "${#_LONG_PAY}"

# ── The python extractor, when a working python3 exists ──────────────────────
# `command -v python3` is not enough: the Windows Store ships a python3.exe
# alias that is on PATH but fails the moment it runs, so probe by executing it.
# Where only `python` exists, stand up a shim so the parity contract below is
# still exercised instead of quietly skipping the assertions that matter most.
if ! _tg_have_python && command -v python >/dev/null 2>&1 && python -c '' >/dev/null 2>&1; then
    _PY_REAL=$(command -v python)
    mkdir -p "$TEST_TMPDIR/bin"
    printf '#!/bin/bash\nexec "%s" "$@"\n' "$_PY_REAL" > "$TEST_TMPDIR/bin/python3"
    chmod +x "$TEST_TMPDIR/bin/python3"
    PATH="$TEST_TMPDIR/bin:$PATH"
    printf '  NOTE  python3 shimmed to %s for parity checks\n' "$_PY_REAL"
fi

if _tg_have_python; then
    assert_eq "python parses a 3-update batch in order" "$EXPECT_MAIN" "$(_tg_parse_updates_py "$(cat "$F_MAIN")")"
    assert_eq "python advances past updates with no message" "$EXPECT_BARE" "$(_tg_parse_updates_py "$(cat "$F_BARE")")"
    assert_eq "python emits nothing for truncated JSON" "" "$(_tg_parse_updates_py "$(cat "$F_TRUNC")")"
    assert_eq "python keeps only the first line of text" "$EXPECT_MULTILINE" "$(_tg_parse_updates_py "$(cat "$F_MULTILINE")")"

    # The contract that keeps the fallback honest.
    for _f in "$F_MAIN" "$F_BARE" "$F_TRUNC" "$F_MULTILINE" "$F_LONG"; do
        assert_eq "extractors agree byte-for-byte on $(basename "$_f")" \
            "$(_tg_parse_updates_awk "$(cat "$_f")")" "$(_tg_parse_updates_py "$(cat "$_f")")"
    done
else
    printf '  SKIP  python extractor assertions (no working python3)\n'
fi

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
