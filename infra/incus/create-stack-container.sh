#!/usr/bin/env bash
# Create an Incus system container for the AI Tool Geek web stack.
# Runs Ghost, n8n, Plausible, Postgres, Redis behind Caddy.
# GPU services (Ollama, XTTS, Whisper, ComfyUI) are in Pass 2.
#
# Usage:   ./create-stack-container.sh
# Re-run:  it's idempotent — safe to run multiple times.

set -euo pipefail

CONTAINER="aitoolgeek-web"
IMAGE="images:ubuntu/24.04/cloud"
STORAGE_GB=50
MEMORY="6GiB"
CPUS="4"

echo "▶ Creating Incus container: ${CONTAINER}"

if incus info "${CONTAINER}" >/dev/null 2>&1; then
  echo "  ✓ Container ${CONTAINER} already exists — skipping creation."
else
  incus launch "${IMAGE}" "${CONTAINER}" \
    -c limits.cpu="${CPUS}" \
    -c limits.memory="${MEMORY}" \
    -c security.nesting=true \
    -c security.syscalls.intercept.mknod=true \
    -c security.syscalls.intercept.setxattr=true
  echo "  ✓ Container created."
fi

echo "▶ Setting root disk size to ${STORAGE_GB}GB"
incus config device override "${CONTAINER}" root size="${STORAGE_GB}GiB" 2>/dev/null || true

echo "▶ Waiting for container to be ready..."
until incus exec "${CONTAINER}" -- bash -c "systemctl is-system-running --wait >/dev/null 2>&1 || true; command -v apt >/dev/null"; do
  sleep 2
done
echo "  ✓ Ready."

echo "▶ Installing Docker + docker compose inside the container"
incus exec "${CONTAINER}" -- bash -s <<'INNER'
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

if command -v docker >/dev/null 2>&1; then
  echo "  ✓ Docker already installed"
else
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
  echo "  ✓ Docker installed"
fi

mkdir -p /opt/aitoolgeek
INNER

echo "▶ Pushing stack files into the container"
incus file push --recursive --quiet \
  "$(dirname "$0")/../docker/" \
  "${CONTAINER}/opt/aitoolgeek/"

echo
echo "✅ Done. Next steps:"
echo "   1. SSH into the container:"
echo "        incus exec ${CONTAINER} -- bash"
echo "   2. cd /opt/aitoolgeek/docker"
echo "   3. cp .env.example .env   # then edit secrets"
echo "   4. docker compose up -d"
echo
echo "   To get the container's IP (for Cloudflare Tunnel config):"
echo "        incus list ${CONTAINER} -c4"
