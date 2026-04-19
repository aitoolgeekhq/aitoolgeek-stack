#!/usr/bin/env bash
# Generate .env with random secrets inside the container and bring the stack up.
#
# Usage:
#   ./start-stack.sh <RESEND_API_KEY> <DOMAIN>
#
# Example:
#   ./start-stack.sh re_xxxxxx example.com

set -euo pipefail

RESEND_KEY="${1:-}"
DOMAIN="${2:-}"
if [ -z "${RESEND_KEY}" ] || [ -z "${DOMAIN}" ]; then
  echo "Usage: $0 <RESEND_API_KEY> <DOMAIN>" >&2
  exit 1
fi

CONTAINER="${CONTAINER_NAME:-stack-web}"
TMP=$(mktemp)
trap 'rm -f "${TMP}" "${TMP}.sql"' EXIT

gen()     { openssl rand -base64 32 | tr -d '=+/' | head -c 32; }
genhex()  { openssl rand -hex 32; }
genlong() { openssl rand -base64 48 | tr -d '\n'; }

cat > "${TMP}" <<EOF
# Generated $(date -Iseconds)
GHOST_DOMAIN=${DOMAIN}
N8N_DOMAIN=n8n.${DOMAIN}
PLAUSIBLE_DOMAIN=stats.${DOMAIN}
UPTIME_DOMAIN=status.${DOMAIN}

TZ=UTC

GHOST_DB_PASSWORD=$(gen)
GHOST_DB_ROOT_PASSWORD=$(gen)

POSTGRES_ROOT_PASSWORD=$(gen)
POSTGRES_N8N_PASSWORD=$(gen)
POSTGRES_PLAUSIBLE_PASSWORD=$(gen)

N8N_ENCRYPTION_KEY=$(genhex)
PLAUSIBLE_SECRET_KEY_BASE=$(genlong)

MAIL_HOST=smtp.resend.com
MAIL_PORT=587
MAIL_USER=resend
MAIL_PASSWORD=${RESEND_KEY}
MAIL_FROM=onboarding@resend.dev
EOF

echo "▶ Pushing .env to ${CONTAINER}:/opt/stack/docker/.env"
incus file push "${TMP}" "${CONTAINER}/opt/stack/docker/.env"

# Build postgres-init.sql with resolved passwords.
N8N_PW=$(grep '^POSTGRES_N8N_PASSWORD=' "${TMP}" | cut -d= -f2-)
PLAUSIBLE_PW=$(grep '^POSTGRES_PLAUSIBLE_PASSWORD=' "${TMP}" | cut -d= -f2-)
cat > "${TMP}.sql" <<SQL
CREATE USER n8n WITH PASSWORD '${N8N_PW}';
CREATE DATABASE n8n OWNER n8n;
CREATE USER plausible WITH PASSWORD '${PLAUSIBLE_PW}';
CREATE DATABASE plausible OWNER plausible;
SQL
incus file push "${TMP}.sql" "${CONTAINER}/opt/stack/docker/postgres-init.sql"

echo "▶ docker compose up -d"
incus exec "${CONTAINER}" -- bash -c "cd /opt/stack/docker && docker compose up -d"

echo
incus exec "${CONTAINER}" -- bash -c "cd /opt/stack/docker && docker compose ps"

echo
echo "✅ Stack started. Note: MAIL_FROM is onboarding@resend.dev until you verify ${DOMAIN} in Resend."
