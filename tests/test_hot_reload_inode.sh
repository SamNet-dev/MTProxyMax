#!/bin/bash
# Regression tests for the hot-reload path.
#
# The engine container reads its config through a bind mount. A single-file mount
# pins one inode, and `cp` onto a file that is itself a mount point replaces that
# inode rather than truncating it, so the engine is left reading an unlinked file
# — every reload silently becomes a no-op until the container is recreated.
# These tests lock in that we mount the directory, write the config in place,
# write instance configs straight to their own file instead of routing them
# through config.toml, and report a reload honestly when it cannot take effect.
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
export INSTANCES_FILE="$TEST_ROOT/instances.conf"
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

# ── Test doubles ─────────────────────────────────────────────
PROXY_RUNNING=true
KILL_FAILS=false
DOCKER_RUN_LOG="${TEST_ROOT}/docker_run.log"
INSTANCE_UP=false
LOG_INFO=""
LOG_WARN=""
RESTARTS=0
: > "$DOCKER_RUN_LOG"

docker() {
    case "$1" in
        # `docker run` is invoked inside $( ) — a subshell — so the argv has to be
        # recorded in a file for the assertions to see it.
        run)     echo "$*" >> "$DOCKER_RUN_LOG"; return 0 ;;
        kill)    [ "$KILL_FAILS" = "true" ] && return 1; return 0 ;;
        ps)      [ "$INSTANCE_UP" = "true" ] && echo "mtproxymax-8443"; return 0 ;;
        inspect) echo "0"; return 0 ;;
        exec)    return 1 ;;
        *)       return 0 ;;
    esac
}

is_proxy_running()    { [ "$PROXY_RUNNING" = "true" ]; }
flush_traffic_to_disk() { return 0; }
speed_limit_apply()   { return 0; }
restart_proxy_container() { RESTARTS=$((RESTARTS + 1)); return 0; }
log_info()  { LOG_INFO="$*"; }
log_warn()  { LOG_WARN="$*"; }
log_error() { LOG_WARN="$*"; }

# In-sync check is stubbed: it reads /proc/<pid>/root of a real container.
PRIMARY_IN_SYNC=true
INSTANCE_IN_SYNC=true
_engine_config_in_sync() {
    case "$2" in
        "$CONTAINER_NAME") [ "$PRIMARY_IN_SYNC" = "true" ] ;;
        *)                 [ "$INSTANCE_IN_SYNC" = "true" ] ;;
    esac
}

# Ignore the generation timestamp when comparing configs
_strip_ts() { grep -v '^# Generated:' "$1" 2>/dev/null; }

PRIMARY_PORT=443
PROXY_PORT="$PRIMARY_PORT"
PROXY_METRICS_PORT=9090

echo "Hot-reload bind-mount tests"

# ── 1. Source guards: the two things that made reloads a silent no-op ───────
SINGLE_FILE_MOUNTS=$(grep -c 'config\.toml:/etc/telemt' "${SCRIPT_DIR}/../mtproxymax.sh")
assert_eq "no single-file config bind mount remains" 0 "$SINGLE_FILE_MOUNTS"

# `cp` onto a mount point replaces the inode (busybox cp does this), which
# detaches the container. The config must be written through a redirect.
COPY_OVER=$(grep -c 'cp "$tmp" "$dest"' "${SCRIPT_DIR}/../mtproxymax.sh")
assert_eq "config is never copied over itself" 0 "$COPY_OVER"

# ── 2. Instance configs are written directly, and instances mount the dir ────
cat > "$INSTANCES_FILE" <<'EOF'
# MTProxyMax Instances — Format: PORT|METRICS_PORT|ENABLED|LABEL
8443|9091|true|inst1
EOF

: > "$DOCKER_RUN_LOG"
_start_all_instances 2>/dev/null

INST_CFG="${CONFIG_DIR}/config-8443.toml"
if [ -f "$INST_CFG" ]; then
    assert_eq "instance config written to its own file" "yes" "yes"
else
    assert_eq "instance config written to its own file" "yes" "no"
fi
assert_eq "instance config carries the instance port" 1 \
    "$(grep -c '^port = 8443' "$INST_CFG" 2>/dev/null)"
assert_eq "instance container mounts the config directory" 1 \
    "$(grep -c -- "-v ${CONFIG_DIR}:/etc/telemt:ro" "$DOCKER_RUN_LOG")"
assert_eq "instance container is pointed at its own config" 1 \
    "$(grep -c '/etc/telemt/config-8443.toml' "$DOCKER_RUN_LOG")"

# ── 3. Regenerating writes in place and produces a complete config ──────────
INSTANCE_UP=true
generate_telemt_config 2>/dev/null
GEN_INODE=$(stat -c %i "${CONFIG_DIR}/config.toml" 2>/dev/null)
generate_telemt_config 2>/dev/null
assert_eq "regeneration keeps the config inode" "$GEN_INODE" \
    "$(stat -c %i "${CONFIG_DIR}/config.toml" 2>/dev/null)"
assert_eq "in-place write produces a complete config" 1 \
    "$(grep -c '^\[access.users\]$' "${CONFIG_DIR}/config.toml" 2>/dev/null)"

# ── 4. Reloading never replaces the primary config file ─────────────────────
generate_telemt_config 2>/dev/null
BEFORE_INODE=$(stat -c %i "${CONFIG_DIR}/config.toml" 2>/dev/null)
cp "${CONFIG_DIR}/config.toml" "${TEST_ROOT}/before.toml" 2>/dev/null

reload_proxy_config 2>/dev/null

AFTER_INODE=$(stat -c %i "${CONFIG_DIR}/config.toml" 2>/dev/null)
assert_eq "primary config inode survives a reload with instances" "$BEFORE_INODE" "$AFTER_INODE"
if diff <(_strip_ts "${TEST_ROOT}/before.toml") <(_strip_ts "${CONFIG_DIR}/config.toml") >/dev/null 2>&1; then
    assert_eq "primary config is not overwritten by instance content" "yes" "yes"
else
    assert_eq "primary config is not overwritten by instance content" "yes" "no"
fi

# ── 5. Reload outcome is reported honestly ──────────────────────────────────
LOG_INFO=""
LOG_WARN=""
KILL_FAILS=true
reload_proxy_config 2>/dev/null
assert_eq "failed signal does not claim a reload" "" "$LOG_INFO"
if [ -n "$LOG_WARN" ]; then
    assert_eq "failed signal warns the user" "yes" "yes"
else
    assert_eq "failed signal warns the user" "yes" "no"
fi

LOG_INFO=""
LOG_WARN=""
KILL_FAILS=false
reload_proxy_config 2>/dev/null
assert_eq "successful signal reports the hot reload" \
    "Config reloaded (hot-reload, no restart)" "$LOG_INFO"

# ── 6. A detached config triggers a restart instead of a silent no-op ───────
LOG_INFO=""
LOG_WARN=""
RESTARTS=0
PRIMARY_IN_SYNC=false
reload_proxy_config 2>/dev/null
assert_eq "detached primary config falls back to a restart" 1 "$RESTARTS"
assert_eq "detached primary config does not claim a hot reload" "" "$LOG_INFO"

LOG_INFO=""
RESTARTS=0
PRIMARY_IN_SYNC=true
INSTANCE_IN_SYNC=false
reload_proxy_config 2>/dev/null
assert_eq "detached instance config falls back to a restart" 1 "$RESTARTS"
INSTANCE_IN_SYNC=true

# ── 7. A stopped container is never mistaken for an out-of-sync one ─────────
LOG_INFO=""
LOG_WARN=""
RESTARTS=0
PROXY_RUNNING=false
INSTANCE_UP=false
PRIMARY_IN_SYNC=false
INSTANCE_IN_SYNC=false
reload_proxy_config 2>/dev/null
assert_eq "stopped proxy is not reported as reloaded" "" "$LOG_INFO"
assert_eq "stopped proxy is not restarted" 0 "$RESTARTS"

# A stopped instance must not drag the whole proxy into a restart either
PROXY_RUNNING=true
PRIMARY_IN_SYNC=true
RESTARTS=0
reload_proxy_config 2>/dev/null
assert_eq "stopped instance does not trigger a restart" 0 "$RESTARTS"

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[ "$TESTS_FAILED" -eq 0 ]
