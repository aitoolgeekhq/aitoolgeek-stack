#!/usr/bin/env bash
# Deploy the aitoolgeek cloudflared tunnel config and systemd unit.
# Matches your existing pattern (cloudflared-pratibedan.service).
#
# Usage: ./setup-cloudflared.sh
# Assumes: infra/ rsync'd to ~/infra/ and the aitoolgeek-web container is running.

set -euo pipefail

INFRA_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONTAINER_IP=$(incus list aitoolgeek-web -f json \
  | python3 -c 'import json,sys;d=json.load(sys.stdin);print([a["address"] for a in d[0]["state"]["network"]["eth0"]["addresses"] if a["family"]=="inet"][0])' 2>/dev/null)
if [ -z "${CONTAINER_IP}" ]; then
  echo "ERROR: could not determine container IP" >&2
  exit 1
fi
echo "▶ Container IP: ${CONTAINER_IP}"

# 1. Place the per-tunnel config file
CONFIG_DEST=""$HOME"/.cloudflared/config-aitoolgeek.yml"
echo "▶ Writing ${CONFIG_DEST}"
sed "s|\${CONTAINER_IP}|${CONTAINER_IP}|g" "${INFRA_DIR}/cloudflared/config-aitoolgeek.yml" > "${CONFIG_DEST}"

# 2. Install the systemd unit (needs sudo)
echo "▶ Installing cloudflared-aitoolgeek.service (sudo)"
sudo cp "${INFRA_DIR}/cloudflared/cloudflared-aitoolgeek.service" /etc/systemd/system/
sudo systemctl daemon-reload

# 3. Add DNS records for each hostname
echo "▶ Adding DNS records"
for host in aitoolgeek.ai www.aitoolgeek.ai n8n.aitoolgeek.ai stats.aitoolgeek.ai status.aitoolgeek.ai; do
  echo "   ↪ ${host}"
  cloudflared tunnel route dns aitoolgeek "${host}" 2>&1 | head -3 || true
done

# 4. Enable + start the service
echo "▶ Enabling + starting cloudflared-aitoolgeek.service"
sudo systemctl enable --now cloudflared-aitoolgeek.service

sleep 2
echo
echo "▶ Service status:"
sudo systemctl status --no-pager cloudflared-aitoolgeek.service | head -15
