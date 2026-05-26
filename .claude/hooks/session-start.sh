#!/bin/bash
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

RUBY_BIN="/opt/rbenv/versions/3.3.6/bin"
export PATH="$RUBY_BIN:$PATH"
echo "export PATH=\"$RUBY_BIN:\$PATH\"" >> "$CLAUDE_ENV_FILE"

# Start PostgreSQL
service postgresql start

# Ensure root pg role exists
su -c "createuser -s root" postgres 2>/dev/null || true

# Install gems (idempotent)
bundle install

# Prepare test database
bin/rails db:test:prepare
