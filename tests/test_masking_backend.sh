#!/bin/bash
# Regression tests for Mask Backend, Cover Shield synchronization, and domain secret rotation (#128)
set -o pipefail

if [ "${BASH_VERSINFO[0]:-0}" -lt 4 ]; then
    echo "SKIP: bash 4+ required (got ${BASH_VERSION:-unknown})" >&2
    exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT=$(mktemp -d) || { echo "SKIP: cannot create temp dir" >&2; exit 0; }
trap 'rm -rf "$TEST_ROOT"' EXIT

export INSTALL_DIR="$TEST_ROOT"
export CONFIG_DIR="$TEST_ROOT/mtproxy"
export SETTINGS_FILE="$TEST_ROOT/settings.conf"
export SECRETS_FILE="$TEST_ROOT/secrets.conf"
export STATS_DIR="$TEST_ROOT/relay_stats"
mkdir -p "$CONFIG_DIR" "$STATS_DIR"

MTPROXYMAX_SOURCE_ONLY=true source "${SCRIPT_DIR}/../mtproxymax.sh"
set +e

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

# ── Test Doubles & Setup ─────────────────────────────────────
is_proxy_running() { return 1; }
restart_proxy_container() { return 0; }
check_root() { return 0; }

LAST_WARN=""
log_warn() { LAST_WARN="$*"; }
log_info() { :; }
log_error() { :; }
log_success() { :; }
audit_log() { :; }

# Initialize baseline settings
PROXY_PORT=443
PROXY_DOMAIN="cloudflare.com"
MASKING_ENABLED="true"
MASKING_HOST=""
MASKING_PORT="443"
COVER_SHIELD_ENABLED="false"
COVER_FALLBACK_TARGET="https://cloudflare.com"
CUSTOM_IP="1.2.3.4"

echo "Masking backend & Cover Shield tests (#128)"

# ── 1. MASKING_HOST & MASKING_PORT honored when Cover Shield is OFF ─────────
MASKING_HOST="127.0.0.1"
MASKING_PORT="8443"
COVER_SHIELD_ENABLED="false"
generate_telemt_config 2>/dev/null

CFG="${CONFIG_DIR}/config.toml"
assert_contains "mask = true in telemt config" "mask = true" "$(cat "$CFG")"
assert_contains "mask_host matches MASKING_HOST" 'mask_host = "127.0.0.1"' "$(cat "$CFG")"
assert_contains "mask_port matches MASKING_PORT" 'mask_port = 8443' "$(cat "$CFG")"

# ── 2. MASKING_HOST & MASKING_PORT PRESERVED when Cover Shield is ON ────────
COVER_SHIELD_ENABLED="true"
COVER_FALLBACK_TARGET="https://fallback-override.com:443"
generate_telemt_config 2>/dev/null

assert_contains "mask_host preserved when Cover Shield is ON" 'mask_host = "127.0.0.1"' "$(cat "$CFG")"
assert_contains "mask_port preserved when Cover Shield is ON" 'mask_port = 8443' "$(cat "$CFG")"

# ── 3. Fallback to COVER_FALLBACK_TARGET when MASKING_HOST is empty ─────────
MASKING_HOST=""
MASKING_PORT="443"
COVER_SHIELD_ENABLED="true"
COVER_FALLBACK_TARGET="https://my-cover.org:9443"
generate_telemt_config 2>/dev/null

assert_contains "mask_host extracted from COVER_FALLBACK_TARGET" 'mask_host = "my-cover.org"' "$(cat "$CFG")"
assert_contains "mask_port extracted from COVER_FALLBACK_TARGET" 'mask_port = 9443' "$(cat "$CFG")"

# ── 4. Fallback target without explicit port defaults to 443 ─────────────────
COVER_FALLBACK_TARGET="https://no-port-cover.org"
generate_telemt_config 2>/dev/null

assert_contains "mask_host extracted from no-port target" 'mask_host = "no-port-cover.org"' "$(cat "$CFG")"
assert_contains "mask_port defaults to 443" 'mask_port = 443' "$(cat "$CFG")"

# ── 5. Default fallback to PROXY_DOMAIN when both are unset ──────────────────
COVER_SHIELD_ENABLED="false"
COVER_FALLBACK_TARGET=""
PROXY_DOMAIN="my-fake-sni.com"
generate_telemt_config 2>/dev/null

assert_contains "mask_host defaults to PROXY_DOMAIN" 'mask_host = "my-fake-sni.com"' "$(cat "$CFG")"
assert_contains "mask_port defaults to 443" 'mask_port = 443' "$(cat "$CFG")"

# ── 6. mask-backend command synchronizes COVER_FALLBACK_TARGET ───────────────
LAST_WARN=""
cli_main mask-backend 127.0.0.1:8443 >/dev/null 2>&1
assert_eq "mask-backend sets MASKING_HOST" "127.0.0.1" "$MASKING_HOST"
assert_eq "mask-backend sets MASKING_PORT" "8443" "$MASKING_PORT"
assert_eq "mask-backend syncs COVER_FALLBACK_TARGET" "https://127.0.0.1:8443" "$COVER_FALLBACK_TARGET"

# ── 7. cover-shield target synchronizes MASKING_HOST and MASKING_PORT ────────
run_cover_shield target https://decoy-server.com:7443 >/dev/null 2>&1
assert_eq "cover-shield target sets COVER_FALLBACK_TARGET" "https://decoy-server.com:7443" "$COVER_FALLBACK_TARGET"
assert_eq "cover-shield target syncs MASKING_HOST" "decoy-server.com" "$MASKING_HOST"
assert_eq "cover-shield target syncs MASKING_PORT" "7443" "$MASKING_PORT"

# ── 8. Loop detection warning fires when mask backend matches proxy port ─────
LAST_WARN=""
cli_main mask-backend 127.0.0.1:443 >/dev/null 2>&1
assert_contains "loop warning on localhost:PROXY_PORT in mask-backend" "Non-proxy TLS probes may loop" "$LAST_WARN"

LAST_WARN=""
generate_telemt_config 2>/dev/null
assert_contains "loop warning on config generation" "matches proxy listen port" "$LAST_WARN"

# ── 9. Domain change does NOT rotate secrets by default ──────────────────────
# Seed a secret
SECRETS_LABELS=("testuser")
SECRETS_KEYS=("0123456789abcdef0123456789abcdef")
SECRETS_CREATED=("1234567890")
SECRETS_ENABLED=("true")
SECRETS_MAX_CONNS=("0")
SECRETS_MAX_IPS=("0")
SECRETS_QUOTA=("0")
SECRETS_EXPIRES=("0")
SECRETS_NOTES=("")
SECRETS_ADTAG=("")
save_secrets

# Change domain non-interactively without --rotate
cli_main domain new-tls-domain.com </dev/null >/dev/null 2>&1
load_secrets
assert_eq "raw secret preserved on domain change without --rotate" \
    "0123456789abcdef0123456789abcdef" "${SECRETS_KEYS[0]}"
assert_eq "PROXY_DOMAIN updated" "new-tls-domain.com" "$PROXY_DOMAIN"

# Change domain non-interactively with --rotate
cli_main domain rotated-tls-domain.com --rotate </dev/null >/dev/null 2>&1
load_secrets
if [ "${SECRETS_KEYS[0]}" != "0123456789abcdef0123456789abcdef" ]; then
    assert_eq "secret was rotated when --rotate specified" "yes" "yes"
else
    assert_eq "secret was rotated when --rotate specified" "yes" "no"
fi

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
