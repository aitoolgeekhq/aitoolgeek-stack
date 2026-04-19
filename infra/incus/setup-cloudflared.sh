#!/usr/bin/env bash
# Install the Cloudflare Tunnel config + systemd unit, add DNS routes,
# and enable the service. Run as a user with sudo + cloudflared login.
#
# Usage:
#   ./setup-cloudflared.sh <TUNNEL_NAME> <DOMAIN>
#
# Example:
#   ./setup-cloudflared.sh stack example.com

set -euo pipefail

TUNNEL="${1:-}"
DOMAIN="${2:-}"
if [ -z "${TUNNEL}" ] || [ -z "${DOMAIN}" ]; then
  echo "Usage: $0 <TUNNEL_NAME> <DOMAIN>" >&2
  exit 1
fi

CONTAINER="${CONTAINER_NAME:-stack-web}"
INFRA_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Container IP
CONTAINER_IP=$(incus list "${CONTAINER}" -f json \
  | python3 -c 'import json,sys;d=json.load(sys.stdin);print([a["address"] for a in d[0]["state"]["network"]["eth0"]["addresses"] if a["family"]=="inet"][0])' 2>/dev/null)
if [ -z "${CONTAINER_IP}" ]; then
  echo "ERROR: could not determine IP for container ${CONTAINER}" >&2
  exit 1
fi
echo "▶ Container IP: ${CONTAINER_IP}"

# Tunnel UUID
UUID=$(cloudflared tunnel list -o json 2>/dev/null | python3 -c "
import json,sys
for t in json.load(sys.stdin):
  if t.get('name') == '${TUNNEL}':
    print(t['id']); break
")
if [ -z "${UUID}" ]; then
  echo "ERROR: tunnel '${TUNNEL}' not found. Create it with: cloudflared tunnel create ${TUNNEL}" >&2
  exit 1
fi
echo "▶ Tunnel: ${TUNNEL} (${UUID})"

# Config
CONFIG_DEST="${HOME}/.cloudflared/config-${TUNNEL}.yml"
echo "▶ Writing ${CONFIG_DEST}"
sed \
  -e "s|YOUR-TUNNEL-UUID|${UUID}|g" \
  -e "s|YOUR-USER|$(whoami)|g" \
  -e "s|YOURDOMAIN.com|${DOMAIN}|g" \
  -e "s|\${CONTAINER_IP}|${CONTAINER_IP}|g" \
  "${INFRA_DIR}/cloudflared/config.yml" > "${CONFIG_DEST}"

# Systemd unit
UNIT="/etc/systemd/system/cloudflared-${TUNNEL}.service"
echo "▶ Installing ${UNIT} (sudo)"
sudo bash -c "sed -e 's|YOUR-USER|$(whoami)|g' -e 's|config-stack|config-${TUNNEL}|g' -e 's|run stack|run ${TUNNEL}|g' '${INFRA_DIR}/cloudflared/cloudflared.service' > '${UNIT}'"
sudo systemctl daemon-reload

# DNS routes
echo "▶ Adding DNS routes"
for host in "${DOMAIN}" "www.${DOMAIN}" "n8n.${DOMAIN}" "stats.${DOMAIN}" "status.${DOMAIN}"; do
  echo "   ↪ ${host}"
  cloudflared tunnel route dns "${TUNNEL}" "${host}" 2>&1 | head -3 || true
done

# Enable + start
echo "▶ Enabling cloudflared-${TUNNEL}.service"
sudo systemctl enable --now "cloudflared-${TUNNEL}.service"
sleep 2

echo
sudo systemctl status --no-pager "cloudflared-${TUNNEL}.service" | head -15
