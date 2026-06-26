#!/bin/bash
set -euo pipefail

# Only run in Claude Code remote environments; local dev uses mise + a native setup.
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

# Start the Docker daemon if it isn't running. The init script trips on a ulimit
# call in this sandbox, so launch dockerd directly and wait for the socket.
if ! docker info >/dev/null 2>&1; then
  nohup dockerd >/tmp/dockerd.log 2>&1 &
  for _ in $(seq 1 30); do
    docker info >/dev/null 2>&1 && break
    sleep 1
  done
fi

if ! docker info >/dev/null 2>&1; then
  echo "warning: Docker daemon did not start; see /tmp/dockerd.log" >&2
  exit 0
fi

# Bring up the dev stack (app + postgres). The image is prebuilt and cached by the
# environment setup script (see docs/claude-remote-env.md); without it, this pulls
# the image on first use.
docker compose up -d

# Prepare the databases inside the app container so `bin/rails test` and
# `bin/rails server` work without a manual step. With DATABASE_URL unset,
# db:prepare runs against both development and test, so one call creates,
# migrates, and seeds the dev DB and also creates and loads the test DB.
# Idempotent on later sessions since pg_data persists across runs.
docker compose exec -T app bin/rails db:prepare ||
  echo "warning: db:prepare failed; run it manually once the stack is up" >&2
