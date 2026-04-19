# AI Tool Geek — Infrastructure (Pass 1: Core web stack)

**Target:** your UAE server (Ubuntu 24.04 + Incus + existing cloudflared).
**Delivers:** Ghost blog + newsletter, n8n, Plausible analytics, Uptime Kuma, shared Postgres + Redis, Caddy reverse proxy — all in ONE Incus system container.

GPU services (Ollama, XTTS, Whisper, ComfyUI) come in **Pass 2** — they need GPU device passthrough and are separately deployable.

---

## What lives where

```
infra/
├── incus/
│   └── create-stack-container.sh       # one script to bootstrap the Incus container
├── docker/
│   ├── docker-compose.yml              # the stack
│   ├── .env.example                    # secrets template
│   ├── Caddyfile                       # internal routing
│   ├── postgres-init.sql               # creates DBs for n8n + plausible
│   └── plausible-clickhouse-user.xml   # silences noisy ClickHouse logs
└── cloudflared/
    ├── config-aitoolgeek.yml           # per-tunnel config (matches your existing pattern)
    └── cloudflared-aitoolgeek.service  # systemd unit (matches cloudflared-pratibedan pattern)
```

---

## Quickstart — 10 minutes end to end

### 1. Copy this `infra/` folder to your UAE server

From your local machine:

```bash
# one option: scp
scp -r infra/ your-uae-server:~/

# or rsync
rsync -avz infra/ your-uae-server:~/infra/
```

### 2. Create the container

SSH in, then:

```bash
cd ~/infra/incus
chmod +x create-stack-container.sh
./create-stack-container.sh
```

This:
- Launches an Incus container called `aitoolgeek-web` (Ubuntu 24.04, 4 CPU, 6 GiB RAM, 50 GiB disk)
- Enables nesting so Docker works inside
- Installs Docker + compose plugin
- Pushes your `infra/docker/` files into `/opt/aitoolgeek/` inside the container

Re-run any time — it's idempotent.

### 3. Configure secrets

Enter the container and copy the env file:

```bash
incus exec aitoolgeek-web -- bash
cd /opt/aitoolgeek/docker
cp .env.example .env
```

Open `.env` and generate real values. Quick helpers:

```bash
# Inside the container:
openssl rand -base64 32   # for DB passwords
openssl rand -hex 32      # for N8N_ENCRYPTION_KEY
openssl rand -base64 48   # for PLAUSIBLE_SECRET_KEY_BASE
```

For mail (Ghost newsletter): sign up at [resend.com](https://resend.com) — free 3k emails/month — get an SMTP password, paste into `MAIL_PASSWORD`.

### 4. Boot the stack

Still inside the container:

```bash
cd /opt/aitoolgeek/docker
docker compose up -d
```

First boot pulls ~3 GB of images; expect 3–5 minutes.

Check it's up:

```bash
docker compose ps
```

All services should show `running` or `healthy`.

### 5. Wire up Cloudflare Tunnel

Matches your existing per-tunnel-per-systemd-unit pattern (like `cloudflared-pratibedan`).

The `aitoolgeek` tunnel **already exists** (ID `8e5cefbe-90b3-431d-b2f4-9c7d97cd4125`, created 2026-01-28 but never activated). We reuse it.

Exit back to the host and get the container IP:

```bash
exit
incus list aitoolgeek-web -c4   # shows something like 192.168.108.X
```

Copy the IPv4 address. Then place the config + systemd unit:

```bash
# 1. Copy the tunnel config
cp infra/cloudflared/config-aitoolgeek.yml $HOME/.cloudflared/config-aitoolgeek.yml
# Edit it — replace ${CONTAINER_IP} with the IP from the previous step:
sed -i "s|\${CONTAINER_IP}|192.168.108.X|g" $HOME/.cloudflared/config-aitoolgeek.yml

# 2. Install the systemd unit
sudo cp infra/cloudflared/cloudflared-aitoolgeek.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now cloudflared-aitoolgeek.service

# 3. Verify
sudo systemctl status cloudflared-aitoolgeek.service
```

Add DNS records for each hostname:

```bash
cloudflared tunnel route dns aitoolgeek aitoolgeek.ai
cloudflared tunnel route dns aitoolgeek www.aitoolgeek.ai
cloudflared tunnel route dns aitoolgeek n8n.aitoolgeek.ai
cloudflared tunnel route dns aitoolgeek stats.aitoolgeek.ai
cloudflared tunnel route dns aitoolgeek status.aitoolgeek.ai
```

### 6. Complete Ghost setup

Open [https://aitoolgeek.ai/ghost](https://aitoolgeek.ai/ghost) in your browser.

Ghost walks you through admin setup on first visit. Pick a theme (the default Source is fine — we'll ship a custom one later), create the admin account, and enable Members (Settings → Newsletter).

### 7. Verify everything

- `https://aitoolgeek.ai` → Ghost homepage
- `https://n8n.aitoolgeek.ai` → n8n login
- `https://stats.aitoolgeek.ai` → Plausible login (first user becomes admin)
- `https://status.aitoolgeek.ai` → Uptime Kuma setup screen

---

## Day-to-day operations

### Tail logs

```bash
incus exec aitoolgeek-web -- docker compose -f /opt/aitoolgeek/docker/docker-compose.yml logs -f
```

### Restart one service

```bash
incus exec aitoolgeek-web -- docker compose -f /opt/aitoolgeek/docker/docker-compose.yml restart ghost
```

### Update all images

```bash
incus exec aitoolgeek-web -- docker compose -f /opt/aitoolgeek/docker/docker-compose.yml pull
incus exec aitoolgeek-web -- docker compose -f /opt/aitoolgeek/docker/docker-compose.yml up -d
```

### Snapshot the whole container (before big changes)

```bash
incus snapshot create aitoolgeek-web before-upgrade
incus snapshot list aitoolgeek-web
# to restore:
incus snapshot restore aitoolgeek-web before-upgrade
```

### Backup Ghost content + databases

```bash
# From the host:
incus exec aitoolgeek-web -- bash -c \
  'cd /opt/aitoolgeek/docker && docker compose exec -T ghost_db mysqldump -uroot -p"$GHOST_DB_ROOT_PASSWORD" ghost' \
  > ~/backups/ghost-$(date +%Y%m%d).sql

# Content volume:
incus exec aitoolgeek-web -- tar czf - -C /var/lib/docker/volumes/aitoolgeek_ghost_content/_data . \
  > ~/backups/ghost-content-$(date +%Y%m%d).tar.gz
```

Automate these with a nightly cron + push to Backblaze B2 for off-site — I'll ship that in Pass 2.

---

## Troubleshooting

**`Cannot connect to the Docker daemon` inside the container**
→ Nesting didn't take. Run `incus config set aitoolgeek-web security.nesting=true` and `incus restart aitoolgeek-web`.

**Plausible crashes on first boot**
→ Normal once — it needs the DB migration. Run `docker compose restart plausible` after 30 seconds.

**Ghost admin says "email sending failed"**
→ Check `MAIL_*` values in `.env`. Resend requires verifying your domain first at resend.com/domains.

**Caddy returns "unknown host"**
→ Your `Host:` header doesn't match any domain in the Caddyfile. Check your Cloudflare Tunnel is passing the correct Host header (it does by default).

**Cloudflare says "1033 Argo Tunnel error"**
→ The tunnel is running but the container isn't reachable. `curl http://CONTAINER_IP:80 -H "Host: aitoolgeek.ai"` from the host — if that fails, restart Caddy.

---

## What's NOT here yet (Pass 2)

- Ollama (language models on GPU)
- XTTS-v2 (voice generation on GPU)
- Whisper (transcription on GPU)
- ComfyUI + Flux (image gen on GPU)
- Postiz (social scheduling)
- MinIO (S3-compatible storage)
- Restic off-site backups

These need GPU passthrough to the Incus container (or a separate GPU container). I'll ship Pass 2 next — but this Pass 1 stack is what Week 1 Day 3 of the plan needs, so you can start using it now.
