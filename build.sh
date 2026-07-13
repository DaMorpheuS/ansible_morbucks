#!/usr/bin/env bash
# Build an Elixir release. Run this ON morbucks (as root / with sudo).
set -euo pipefail

usage() {
    echo "Usage: $0 <app> <tag> [extra ansible args...]"
    echo "  app   Application name (must match app_vars/<app>.yml)"
    echo "  tag   Git tag / release version to build (e.g. 0.1.0)"
    echo ""
    echo "Example: $0 koopmans_orderportal 0.1.0"
    exit 1
}

[[ $# -ge 2 ]] || usage
APP="$1"; TAG="$2"; shift 2
[[ -n "$APP" && -n "$TAG" ]] || usage

cd "$(dirname "$0")"
echo "Building Elixir release: app=$APP tag=$TAG"
ansible-playbook playbooks/build-elixir-release.yml \
    --extra-vars "app=$APP" \
    --extra-vars "tag=$TAG" "$@"
