#!/bin/sh

# OTSA SSH User Access Management — Reconfigure Script
# Called by configd action: sshmanagement configure
#
# Authorized keys, shell, and group memberships are written by
# auth.inc::local_user_set() (triggered via "auth sync user" / "auth sync all").
# This script only renders the sshd drop-in and bounces the SSH service.

set -eu

TEMPLATE="OPNsense/Auth/SshManagement"
SSHD_DROPIN="/usr/local/etc/ssh/sshd_config.d/otsa-sshmanagement.conf"

echo "==> Rendering SSH management template..."
/usr/local/sbin/configctl template reload "${TEMPLATE}"

echo "==> Validating sshd configuration..."
if ! /usr/sbin/sshd -t; then
    echo "!!! sshd configuration validation failed. NOT restarting sshd." >&2
    echo "!!! Check ${SSHD_DROPIN} for errors." >&2
    exit 1
fi

echo "==> Restarting OpenSSH via pluginctl..."
/usr/local/sbin/pluginctl -s openssh restart

echo "==> SSH reconfiguration complete."
