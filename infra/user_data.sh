#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates curl docker.io snapd unzip caddy

if ! command -v aws >/dev/null 2>&1; then
  tmp_dir=$(mktemp -d)
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "$tmp_dir/awscliv2.zip"
  unzip -q "$tmp_dir/awscliv2.zip" -d "$tmp_dir"
  "$tmp_dir/aws/install" --update
  rm -rf "$tmp_dir"
fi

systemctl enable --now docker
systemctl enable --now snapd.socket

if ! snap list amazon-ssm-agent >/dev/null 2>&1; then
  snap install amazon-ssm-agent --classic
fi

systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent.service

cat > /etc/caddy/Caddyfile <<'EOF'
:80 {
    reverse_proxy 127.0.0.1:3001
}
EOF

caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
systemctl enable --now caddy
systemctl restart caddy
