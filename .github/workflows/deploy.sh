#!/bin/bash
set -euo pipefail

IMAGE_TAG="$1"

AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="892013083652"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE="${ECR_REGISTRY}/lacrei-api:${IMAGE_TAG}"

echo "Deploying image: $IMAGE"

dump_container_debug() {
  echo "Container status:"
  docker ps -a --filter "name=lacrei-api"

  echo "Container inspect:"
  docker inspect lacrei-api 2>/dev/null || true

  echo "Container logs:"
  docker logs --tail 100 lacrei-api 2>/dev/null || true
}

wait_for_apt() {
  if ! command -v fuser >/dev/null 2>&1; then
    return 0
  fi

  while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 ||
    fuser /var/lib/dpkg/lock >/dev/null 2>&1 ||
    fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
    echo "Waiting for apt/dpkg lock..."
    sleep 5
  done
}

ensure_packages() {
  local missing_packages=()

  if ! command -v docker >/dev/null 2>&1; then
    missing_packages+=("docker.io")
  fi

  if ! command -v curl >/dev/null 2>&1; then
    missing_packages+=("curl")
  fi

  if ! command -v unzip >/dev/null 2>&1; then
    missing_packages+=("unzip")
  fi

  if [ "${#missing_packages[@]}" -gt 0 ]; then
    export DEBIAN_FRONTEND=noninteractive
    wait_for_apt
    apt-get update
    wait_for_apt
    apt-get install -y ca-certificates "${missing_packages[@]}"
  fi

  if ! command -v aws >/dev/null 2>&1; then
    local tmp_dir
    tmp_dir=$(mktemp -d)

    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$tmp_dir/awscliv2.zip"
    unzip -q "$tmp_dir/awscliv2.zip" -d "$tmp_dir"
    "$tmp_dir/aws/install" --update
    rm -rf "$tmp_dir"
  fi

  systemctl enable --now docker
}

ensure_packages

aws ecr get-login-password --region "$AWS_REGION" |
  docker login --username AWS --password-stdin "$ECR_REGISTRY"

docker pull "$IMAGE"

docker rm -f lacrei-api 2>/dev/null || true

docker run -d \
  --name lacrei-api \
  --restart unless-stopped \
  -p 80:3000 \
  "$IMAGE"

for attempt in {1..30}; do
  health_status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' lacrei-api)

  if [ "$health_status" = "healthy" ] || [ "$health_status" = "running" ]; then
    break
  fi

  if [ "$health_status" = "unhealthy" ]; then
    dump_container_debug
    exit 1
  fi

  if [ "$health_status" = "exited" ] || [ "$health_status" = "dead" ]; then
    dump_container_debug
    exit 1
  fi

  echo "Waiting for container health ($health_status)..."
  sleep 2
done

health_status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' lacrei-api)

if [ "$health_status" != "healthy" ] && [ "$health_status" != "running" ]; then
  dump_container_debug
  exit 1
fi

if ! curl --fail --retry 30 --retry-delay 2 --retry-all-errors --max-time 5 \
  --retry-connrefused \
  http://localhost/status; then
  dump_container_debug
  exit 1
fi

echo "Deploy completed successfully!"
