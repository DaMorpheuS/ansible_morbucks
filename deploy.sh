#!/usr/bin/env bash
# Deploy an Elixir release. Run this ON morbucks (as root / with sudo).
set -euo pipefail

usage() {
    echo "Usage: $0 <app> <tag> <env> [extra ansible args...]"
    echo "  app   Application name (must match app_vars/<app>.yml)"
    echo "  tag   Release version to deploy (must have been built first)"
    echo "  env   Deployment environment (e.g. prod, acc)"
    echo ""
    echo "Note: env is the DEPLOYMENT environment, not MIX_ENV."
    echo "      Releases are always built with MIX_ENV=prod."
    echo ""
    echo "Example: $0 koopmans_orderportal 0.1.0 prod"
    exit 1
}

[[ $# -ge 3 ]] || usage
APP="$1"; TAG="$2"; ENV="$3"; shift 3
[[ -n "$APP" && -n "$TAG" && -n "$ENV" ]] || usage

cd "$(dirname "$0")"
echo "Deploying Elixir release: app=$APP tag=$TAG env=$ENV"
ansible-playbook playbooks/deploy-elixir-release.yml \
    --extra-vars "app=$APP" \
    --extra-vars "tag=$TAG" \
    --extra-vars "env=$ENV" "$@"
