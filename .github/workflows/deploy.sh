#!/bin/bash
set -euo pipefail

exec 9>/var/lock/lacrei-deploy.lock

if ! flock -n 9; then
  echo "Another deployment is already running"
  exit 1
fi

IMAGE_TAG="${1}"
ENVIRONMENT="${2}"

AWS_REGION="us-east-1"
ECR_REGISTRY="892013083652.dkr.ecr.us-east-1.amazonaws.com"
IMAGE="$ECR_REGISTRY/lacrei-api:$IMAGE_TAG"
LOG_GROUP="/lacrei/$ENVIRONMENT"
CADDYFILE="/etc/caddy/Caddyfile"

if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "production" ]]; then
  echo "Ambiente inválido: $ENVIRONMENT"
  exit 1
fi

aws ecr get-login-password --region "$AWS_REGION" |
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

docker pull "$IMAGE"

start_container() {
  local name="$1"
  local ports="$2"

  docker rm -f "$name" 2>/dev/null || true

  docker run -d \
    --name "$name" \
    --restart unless-stopped \
    -p "$ports" \
    -e APP_ENV="$ENVIRONMENT" \
    --log-driver=awslogs \
    --log-opt awslogs-region="$AWS_REGION" \
    --log-opt awslogs-group="$LOG_GROUP" \
    --log-opt awslogs-stream="lacrei-api" \
    "$IMAGE"
}

check_health() {
  local name="$1"
  local port="$2"

  for attempt in {1..30}; do
    status=$(docker inspect \
      --format '{{.State.Health.Status}}' "$name")

    if [[ "$status" == "healthy" ]] &&
       curl -fsS "http://127.0.0.1:$port/status" >/dev/null; then
      return 0
    fi

    if [[ "$status" == "unhealthy" ]]; then
      break
    fi

    sleep 2
  done

  docker ps -a --filter "name=$name"
  docker logs --tail 50 "$name" || true
  return 1
}

if [[ "$ENVIRONMENT" == "production" ]]; then
  start_container "lacrei-api" "80:3000"
  check_health "lacrei-api" 80
  echo "Production deployed!"
  exit 0
fi

ACTIVE_PORT=$(
  awk '/^[[:space:]]*reverse_proxy 127\.0\.0\.1:300[12][[:space:]]*$/ {
    split($2, address, ":")
    print address[2]
  }' "$CADDYFILE"
)

case "$ACTIVE_PORT" in
  3001)
    NEXT_PORT=3002
    NEXT_CONTAINER="lacrei-api-green"
    ;;
  3002)
    NEXT_PORT=3001
    NEXT_CONTAINER="lacrei-api-blue"
    ;;
  *)
    echo "Porta ativa inválida: $ACTIVE_PORT"
    exit 1
    ;;
esac

echo "Active: $ACTIVE_PORT"
echo "Deploying $NEXT_CONTAINER on $NEXT_PORT"

curl -fsS "http://127.0.0.1:$ACTIVE_PORT/status" >/dev/null

start_container "$NEXT_CONTAINER" "127.0.0.1:$NEXT_PORT:3000"

check_health "$NEXT_CONTAINER" "$NEXT_PORT"

BACKUP=$(mktemp)
cp "$CADDYFILE" "$BACKUP"

rollback() {
  echo "Restoring previous Caddy configuration..."
  cp "$BACKUP" "$CADDYFILE"
  caddy validate --config "$CADDYFILE" --adapter caddyfile
  systemctl reload caddy
}

trap 'echo "Deploy failed"; rollback || echo "CRITICAL: rollback failed"' ERR

sed -i \
  "s|reverse_proxy 127.0.0.1:$ACTIVE_PORT|reverse_proxy 127.0.0.1:$NEXT_PORT|" \
  "$CADDYFILE"

caddy validate --config "$CADDYFILE" --adapter caddyfile
systemctl reload caddy

curl -fsS "http://127.0.0.1/status" >/dev/null

trap - ERR
rm -f "$BACKUP"

echo "Staging deployed successfully!"
echo "Active port: $NEXT_PORT"
