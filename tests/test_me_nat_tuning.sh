#!/bin/bash
# Persistent ME NAT overrides must survive primary and instance regeneration.
set -eo pipefail
test_root=$(mktemp -d)
trap 'rm -rf "$test_root"' EXIT
export INSTALL_DIR="$test_root/install"
export CONFIG_DIR="$INSTALL_DIR/mtproxy"
export SETTINGS_FILE="$INSTALL_DIR/settings.conf"
export _TUNE_FILE="$INSTALL_DIR/tunings.conf"
mkdir -p "$CONFIG_DIR"
MTPROXYMAX_SOURCE_ONLY=true source "$(dirname "${BASH_SOURCE[0]}")/../mtproxymax.sh"
set -eo pipefail
check_root() { :; }
confirm_settings_restart() { return 0; }
is_proxy_running() { return 1; }
log_success() { :; }
log_error() { :; }

generate_telemt_config
! grep -q '^middle_proxy_nat_' "$CONFIG_DIR/config.toml"

tune_set middle_proxy_nat_ip 203.0.113.10
tune_set middle_proxy_nat_probe false
cp "$_TUNE_FILE" "$test_root/before"
for invalid in 256.1.1.1 1.2.3 01.2.3.4 hostname '1.2.3.4"' '1.2.3.4/24'; do
    if tune_set middle_proxy_nat_ip "$invalid"; then
        echo "FAIL: accepted invalid NAT IP: $invalid" >&2
        exit 1
    fi
done
if tune_set middle_proxy_nat_probe yes; then
    echo 'FAIL: accepted invalid probe boolean' >&2
    exit 1
fi
cmp "$test_root/before" "$_TUNE_FILE"

# Read persisted values during config generation, including an instance destination.
for destination in "$CONFIG_DIR/config.toml" "$CONFIG_DIR/instance.toml" "$CONFIG_DIR/config.toml"; do
    generate_telemt_config "$destination"
    test "$(grep -c '^middle_proxy_nat_ip = "203.0.113.10"$' "$destination")" -eq 1
    test "$(grep -c '^middle_proxy_nat_probe = false$' "$destination")" -eq 1
    awk '
        /^\[/ {section=$0}
        /^middle_proxy_nat_/ && section != "[general]" {exit 1}
    ' "$destination"
done

tune_clear middle_proxy_nat_ip
tune_clear middle_proxy_nat_probe
generate_telemt_config
! grep -q '^middle_proxy_nat_' "$CONFIG_DIR/config.toml"
echo 'PASS: ME NAT persistence, primary/instance regeneration, validation and clearing'
