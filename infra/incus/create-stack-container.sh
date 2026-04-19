#!/usr/bin/env bash
# Create an Incus system container and install Docker inside it.
# The stack then runs as docker-compose inside this container.
#
# Usage:  ./create-stack-container.sh
# Idempotent — safe to re-run.

set -euo pipefail

CONTAINER="${CONTAINER_NAME:-stack-web}"
IMAGE="${BASE_IMAGE:-images:ubuntu/24.04/cloud}"
STORAGE_GB="${STORAGE_GB:-50}"
MEMORY="${MEMORY:-6GiB}"
CPUS="${CPUS:-4}"

echo "▶ Incus container: ${CONTAINER}"

if incus info "${CONTAINER}" >/dev/null 2>&1; then
  echo "  ✓ already exists — skipping creation"
else
  incus launch "${IMAGE}" "${CONTAINER}" \
    -c limits.cpu="${CPUS}" \
    -c limits.memory="${MEMORY}" \
    -c security.nesting=true \
    -c security.syscalls.intercept.mknod=true \
    -c security.syscalls.intercept.setxattr=true
  echo "  ✓ created"
fi

echo "▶ Root disk: ${STORAGE_GB}GB"
incus config device override "${CONTAINER}" root size="${STORAGE_GB}GiB" 2>/dev/null || true

echo "▶ Waiting for container to finish boot…"
until incus exec "${CONTAINER}" -- bash -c "command -v apt >/dev/null"; do
  sleep 2
done

echo "▶ Installing Docker + compose plugin"
incus exec "${CONTAINER}" -- bash -s <<'INNER'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
if command -v docker >/dev/null 2>&1; then
  echo "  ✓ docker already installed"; exit 0
fi
apt-get update -qq
apt-get install -y -qq ca-certificates curl gnupg >/dev/null
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu noble stable" \
  > /etc/apt/sources.list.d/docker.list
apt-get update -qq
apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin >/dev/null
systemctl enable --now docker >/dev/null
mkdir -p /opt/stack
echo "  ✓ docker installed"
INNER

echo "▶ Pushing docker/ files into the container at /opt/stack/"
incus file push --recursive --quiet \
  "$(dirname "$0")/../docker/" \
  "${CONTAINER}/opt/stack/"

echo
echo "✅ Container ready. Next:"
echo "   incus exec ${CONTAINER} -- bash"
echo "   cd /opt/stack/docker && cp .env.example .env && vim .env"
echo "   docker compose up -d"
echo
echo "   Container IP (for Cloudflare Tunnel):"
echo "     incus list ${CONTAINER} -c4"
