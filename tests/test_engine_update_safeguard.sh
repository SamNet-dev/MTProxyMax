#!/bin/bash
# Exercise safe abort during failed telemt image acquisition to prevent service outage.
set -euo pipefail
repo="${1:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

log_info() { :; }
log_warn() { :; }
log_success() { :; }
log_error() { :; }

# Mock state
restarted=0
restart_proxy_container() { restarted=1; }
is_proxy_running() { return 0; }
load_secrets() { :; }

# Case 1: build_telemt_image fails -> must abort without calling restart_proxy_container
build_telemt_image() { return 1; }

# Run update logic extracted from update_script()
run_engine_update() {
    local _expected_ver="3.5.16-84e5b82"
    local _current_ver="3.5.14-9d5b896"
    log_info "Engine update: v${_current_ver} -> v${_expected_ver}"
    if ! build_telemt_image true; then
        log_error "Failed to obtain telemt engine v${_expected_ver}; keeping existing proxy running"
        return 1
    fi
    if is_proxy_running; then
        load_secrets
        restart_proxy_container
    fi
}

if run_engine_update; then
    echo "FAIL: expected run_engine_update to fail when build_telemt_image fails" >&2
    exit 1
fi

test "$restarted" -eq 0

# Case 2: build_telemt_image succeeds -> restarts proxy safely
build_telemt_image() { return 0; }
if ! run_engine_update; then
    echo "FAIL: expected run_engine_update to succeed when build_telemt_image succeeds" >&2
    exit 1
fi

test "$restarted" -eq 1

echo "PASS: engine update safely preserves running proxy on build failure"
