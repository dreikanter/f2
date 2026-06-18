# Thin wrapper so Kamal can tag and push a Caddy image (with our Caddyfile baked
# in) to the registry and deploy it as a standalone app. Bump the tag to upgrade.
FROM caddy:2.10-alpine
COPY Caddyfile /etc/caddy/Caddyfile

# The basic-auth password is bcrypt-hashed, and bcrypt hashes contain '$'. Kamal
# feeds secrets through a dotenv layer that interpolates '$...' sequences, which
# silently empties the hash before it reaches the container. So it's transported
# base64-encoded (base64 has no '$') and decoded here into the env var Caddy
# reads via the {$METRICS_PASSWORD_HASH} placeholder. Reset the upstream
# ENTRYPOINT (["caddy"]) so the shell command runs directly.
ENTRYPOINT []
CMD ["sh", "-c", "export METRICS_PASSWORD_HASH=\"$(printf %s \"$METRICS_PASSWORD_HASH_B64\" | base64 -d)\"; exec caddy run --config /etc/caddy/Caddyfile --adapter caddyfile"]
