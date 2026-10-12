#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y docker.io

systemctl enable --now docker