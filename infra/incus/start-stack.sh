#!/usr/bin/env bash
# Generate .env with random secrets and bring the stack up.
# Usage: ./start-stack.sh <RESEND_API_KEY>
#
# Secrets are generated inside the container and immediately pushed;
# they never land on the host filesystem permanently.

set -euo pipefail

RESEND_KEY="${1:-}"
if [ -z "${RESEND_KEY}" ]; then
  echo "ERROR: Pass your Resend API key as the first arg." >&2
  echo "Usage: $0 re_..." >&2
  exit 1
fi

CONTAINER="aitoolgeek-web"
TMP=$(mktemp)
trap 'rm -f "${TMP}"' EXIT

gen() { openssl rand -base64 32 | tr -d '=+/' | head -c 32; }
genhex() { openssl rand -hex 32; }
genlong() { openssl rand -base64 48 | tr -d '\n'; }

cat > "${TMP}" <<EOF
# Generated on $(date -Iseconds). Random secrets; safe to re-generate anytime.
# MAIL_FROM = onboarding@resend.dev until you verify aitoolgeek.ai in Resend.
# Verify at: https://resend.com/domains  → add DNS records shown → change MAIL_FROM to hello@aitoolgeek.ai

GHOST_DOMAIN=aitoolgeek.ai
N8N_DOMAIN=n8n.aitoolgeek.ai
PLAUSIBLE_DOMAIN=stats.aitoolgeek.ai
UPTIME_DOMAIN=status.aitoolgeek.ai

TZ=Asia/Dubai

GHOST_DB_PASSWORD=$(gen)
GHOST_DB_ROOT_PASSWORD=$(gen)

POSTGRES_ROOT_PASSWORD=$(gen)
POSTGRES_N8N_PASSWORD=$(gen)
POSTGRES_PLAUSIBLE_PASSWORD=$(gen)

N8N_ENCRYPTION_KEY=$(genhex)

PLAUSIBLE_SECRET_KEY_BASE=$(genlong)

MAIL_SERVICE=
MAIL_HOST=smtp.resend.com
MAIL_PORT=587
MAIL_USER=resend
MAIL_PASSWORD=${RESEND_KEY}
MAIL_FROM=onboarding@resend.dev
EOF

echo "▶ Pushing .env into container (${CONTAINER}:/opt/aitoolgeek/docker/.env)"
incus file push "${TMP}" "${CONTAINER}/opt/aitoolgeek/docker/.env"

# Also write the postgres init with resolved passwords (it uses :'n8n_password' syntax
# which needs to be replaced by actual values).
N8N_PW=$(grep '^POSTGRES_N8N_PASSWORD=' "${TMP}" | cut -d= -f2-)
PLAUSIBLE_PW=$(grep '^POSTGRES_PLAUSIBLE_PASSWORD=' "${TMP}" | cut -d= -f2-)

cat > "${TMP}.sql" <<SQL
-- Generated at boot. Creates DBs for n8n + plausible with the resolved passwords.
CREATE USER n8n WITH PASSWORD '${N8N_PW}';
CREATE DATABASE n8n OWNER n8n;

CREATE USER plausible WITH PASSWORD '${PLAUSIBLE_PW}';
CREATE DATABASE plausible OWNER plausible;
SQL
incus file push "${TMP}.sql" "${CONTAINER}/opt/aitoolgeek/docker/postgres-init.sql"
rm -f "${TMP}.sql"

echo "▶ Bringing the stack up (docker compose up -d)"
incus exec "${CONTAINER}" -- bash -c "cd /opt/aitoolgeek/docker && docker compose up -d"

echo
echo "▶ Service status:"
incus exec "${CONTAINER}" -- bash -c "cd /opt/aitoolgeek/docker && docker compose ps"

echo
echo "✅ Stack boot initiated. First pull can take a few minutes. Wait for 'healthy' on ghost_db and postgres."
