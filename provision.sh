#!/usr/bin/env bash
# Provision the morbucks server. Run this FROM your workstation.
# Any extra args are passed through to ansible-playbook (e.g. --ask-vault-pass).
set -euo pipefail
cd "$(dirname "$0")"

echo "Provisioning morbucks (common + build-toolchain + postgres + caddy)..."
ansible-playbook playbooks/provision.yml "$@"
