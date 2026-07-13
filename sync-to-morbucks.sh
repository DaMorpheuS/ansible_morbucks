#!/usr/bin/env bash
# Copy this project onto morbucks so build/deploy can run there.
# Run FROM your workstation. Requires rsync on both ends.
#
#   ./sync-to-morbucks.sh                 # -> root@morbucks:/opt/ansible_morbucks
#   ./sync-to-morbucks.sh user@host /path # custom target
set -euo pipefail
cd "$(dirname "$0")"

DEST_HOST="${1:-root@morbucks}"
DEST_PATH="${2:-/opt/ansible_morbucks}"

echo "Syncing project to ${DEST_HOST}:${DEST_PATH} ..."
rsync -avz --delete \
    --exclude '.git/' \
    --exclude '*.retry' \
    --exclude '__pycache__/' \
    --exclude 'group_vars/all/vault.yml' \
    ./ "${DEST_HOST}:${DEST_PATH}/"

echo "Done. Now: ssh ${DEST_HOST%%:*}  then  cd ${DEST_PATH} && ./deploy.sh <app> <tag> <env>"
