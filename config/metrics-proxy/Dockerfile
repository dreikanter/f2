# Thin wrapper so Kamal can tag and push a Caddy image (with our Caddyfile baked
# in) to the registry and deploy it as a standalone app. Bump the tag to upgrade.
FROM caddy:2.10-alpine
COPY Caddyfile /etc/caddy/Caddyfile
