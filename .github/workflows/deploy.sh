#!/bin/bash
set -euo pipefail

IMAGE_TAG="$1"

AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="892013083652"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE="${ECR_REGISTRY}/lacrei-api:${IMAGE_TAG}"

echo "Deploying image: $IMAGE"

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

  if ! command -v aws >/dev/null 2>&1; then
    missing_packages+=("awscli")
  fi

  if ! command -v docker >/dev/null 2>&1; then
    missing_packages+=("docker.io")
  fi

  if ! command -v curl >/dev/null 2>&1; then
    missing_packages+=("curl")
  fi

  if [ "${#missing_packages[@]}" -gt 0 ]; then
    export DEBIAN_FRONTEND=noninteractive
    wait_for_apt
    apt-get update
    wait_for_apt
    apt-get install -y "${missing_packages[@]}"
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

curl --fail --retry 10 --retry-delay 2 \
  --retry-connrefused \
  http://localhost/status

echo "Deploy completed successfully!"
