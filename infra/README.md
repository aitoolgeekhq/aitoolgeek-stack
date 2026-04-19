# infra

## Layout

```
docker/
  docker-compose.yml           # the stack
  .env.example                 # secrets template
  Caddyfile                    # reverse proxy (host-based routing + Plausible proxy)
  postgres-init.sql            # creates DBs for n8n + plausible
  plausible-clickhouse-user.xml # silences noisy ClickHouse logs
cloudflared/
  config.yml                   # tunnel ingress template
  cloudflared.service          # systemd unit template
incus/                         # optional, if you run on an Incus host
  create-stack-container.sh    # bootstrap an Incus system container with Docker inside
  start-stack.sh               # generate .env with random secrets + compose up
  setup-cloudflared.sh         # place tunnel config + enable systemd unit + add DNS
```

## Setup (any Docker host)

```bash
cd infra/docker
cp .env.example .env
# Edit .env: replace YOURDOMAIN.com, set SMTP credentials, generate secrets:
#   openssl rand -base64 32   # DB passwords
#   openssl rand -hex 32      # N8N_ENCRYPTION_KEY
#   openssl rand -base64 48   # PLAUSIBLE_SECRET_KEY_BASE
docker compose up -d
```

Check: `docker compose ps` — all should be `healthy` or `running`.

## Setup (Incus host, convenience scripts)

```bash
# On your Incus host:
cd infra/incus
./create-stack-container.sh     # creates `stack-web` container, Docker inside
./start-stack.sh <RESEND_KEY>   # fills .env with random secrets + compose up
```

## Public access (Cloudflare Tunnel)

1. `cloudflared tunnel create stack` → get UUID + credentials JSON
2. Edit `cloudflared/config.yml` — paste UUID, replace `YOURDOMAIN.com`, replace `${CONTAINER_IP}` with the host/container IP
3. Copy to `~/.cloudflared/config-stack.yml`
4. Install the systemd unit: `sudo cp cloudflared/cloudflared.service /etc/systemd/system/cloudflared-stack.service` (edit the User= line)
5. `sudo systemctl enable --now cloudflared-stack.service`
6. Add DNS: `cloudflared tunnel route dns stack yourdomain.com` (repeat for each subdomain)

Or run `incus/setup-cloudflared.sh` which does 2–6 automatically.

## First-boot checklist

- `https://YOURDOMAIN.com` → Ghost first-run wizard
- `https://n8n.YOURDOMAIN.com` → create n8n owner account
- `https://stats.YOURDOMAIN.com` → Plausible login; first user = admin
- `https://status.YOURDOMAIN.com` → Uptime Kuma setup

## Operations

```bash
# logs
docker compose logs -f

# restart one service
docker compose restart ghost

# update images
docker compose pull && docker compose up -d

# backup Ghost DB
docker compose exec -T ghost_db mysqldump -uroot -p"$GHOST_DB_ROOT_PASSWORD" ghost > ghost-$(date +%F).sql

# backup Ghost content volume
docker run --rm -v stack_ghost_content:/src:ro -v $(pwd):/dst alpine tar czf /dst/ghost-content-$(date +%F).tar.gz -C /src .
```

## Troubleshooting

**Ghost redirect-loops on /ghost** — Caddy isn't forwarding `X-Forwarded-Proto: https`. Confirm the `(upstream-https)` snippet in the Caddyfile is imported.

**Plausible blocked by ad-blockers** — use the first-party proxy (already set up in the Caddyfile: `/js/sc.js` and `/api/event`). Script tag on your site should be:

```html
<script defer data-domain="YOURDOMAIN.com" data-api="/api/event" src="/js/sc.js"></script>
<script>window.plausible=window.plausible||function(){(window.plausible.q=window.plausible.q||[]).push(arguments)}</script>
```

**Plausible crashes first boot** — it runs DB migrations on first start. Wait 30s and `docker compose restart plausible`.

**Ghost can't send email** — verify your sending domain in Resend (or your SMTP provider). Set `MAIL_FROM` only after verification succeeds.
