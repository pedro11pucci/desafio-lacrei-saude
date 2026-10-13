set -euo pipefail

IMAGE_TAG="$1"

AWS_REGION="us-east-1"
AWS_ACCOUNT_ID="892013083652"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE="${ECR_REGISTRY}/lacrei-api:${IMAGE_TAG}"

echo "Deploying image: $IMAGE"

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
