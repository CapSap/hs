#!/usr/bin/env bash
# sync-secrets.sh — mirror per-service secret files to the server.
#
# secrets live in server/<service>/secrets/ locally (gitignored) and are copied
# to the same path inside the server's checkout. run from the repo root.
#
#   ./server/sync-secrets.sh            # sync every server/<service>/secrets/ dir
#   SERVER=other ./server/sync-secrets.sh
#
# no --delete: this only adds/updates files on the server, never removes them.
set -euo pipefail

SERVER="${SERVER:-debian-box}"     # ssh host alias (see ~/.ssh/config)
REMOTE_REPO="${REMOTE_REPO:-box}"  # checkout path, relative to the remote home dir

shopt -s nullglob
found=0
for dir in server/*/secrets/; do
  found=1
  svc="${dir%/secrets/}"
  echo ">> $svc/secrets -> $SERVER:$REMOTE_REPO/$svc/secrets"
  ssh "$SERVER" "mkdir -p '$REMOTE_REPO/$svc/secrets' && chmod 700 '$REMOTE_REPO/$svc/secrets'"
  rsync -a --chmod=F600 "$dir" "$SERVER:$REMOTE_REPO/$svc/secrets/"
done

if [ "$found" != 1 ]; then
  echo "no server/*/secrets/ dirs found — are you in the repo root?" >&2
  exit 1
fi
echo "done."
