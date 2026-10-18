
#!/bin/bash
set -euo pipefail

CADDYFILE="/etc/caddy/Caddyfile"

ENVIRONMENT="${1:-staging}"

if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "production" ]]; then
  echo "Invalid environment: $ENVIRONMENT"
  exit 1
fi

DOMAIN="pedro-lacrei-$ENVIRONMENT.duckdns.org"

exec 9>/var/lock/lacrei-deploy.lock
flock -n 9 || {
  echo "Another deploy or rollback is running"
  exit 1
}

ACTIVE_PORT=$(
  awk '/^[[:space:]]*reverse_proxy 127\.0\.0\.1:300[12][[:space:]]*$/ {
    split($2, address, ":")
    print address[2]
  }' "$CADDYFILE"
)

case "$ACTIVE_PORT" in
  3001)
    TARGET_PORT=3002
    TARGET_CONTAINER="lacrei-api-green"
    ;;
  3002)
    TARGET_PORT=3001
    TARGET_CONTAINER="lacrei-api-blue"
    ;;
  *)
    echo "Invalid active port: $ACTIVE_PORT"
    exit 1
    ;;
esac

HEALTH=$(docker inspect \
  --format '{{.State.Health.Status}}' \
  "$TARGET_CONTAINER")

if [[ "$HEALTH" != "healthy" ]]; then
  echo "Rollback target is not healthy: $HEALTH"
  exit 1
fi

curl -fsS "http://127.0.0.1:$TARGET_PORT/status" >/dev/null

BACKUP=$(mktemp)
cp "$CADDYFILE" "$BACKUP"

restore_config() {
  echo "Restoring previous Caddy configuration..."
  cp "$BACKUP" "$CADDYFILE"
  systemctl reload caddy
}

CANDIDATE=$(mktemp /etc/caddy/Caddyfile.XXXXXX)

sed \
  "s|reverse_proxy 127\.0\.0\.1:$ACTIVE_PORT|reverse_proxy 127.0.0.1:$TARGET_PORT|" \
  "$CADDYFILE" > "$CANDIDATE"

caddy validate --config "$CANDIDATE" --adapter caddyfile

cp "$CANDIDATE" "$CADDYFILE"

if ! systemctl reload caddy ||
   ! curl -fsS https://$DOMAIN/status >/dev/null; then
  echo "Rollback switch failed"
  restore_config
  rm -f "$BACKUP" "$CANDIDATE"
  exit 1
fi

rm -f "$BACKUP" "$CANDIDATE"

echo "Rollback completed!"
echo "Active port: $TARGET_PORT"
echo "Active container: $TARGET_CONTAINER"
