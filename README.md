# aitoolgeek-stack

The complete self-hosted creator + AI dev stack I run for [AI Tool Geek](https://aitoolgeek.ai).
One Incus system container, one Docker Compose, behind a Cloudflare Tunnel.

**What you get:**
- [Ghost](https://ghost.org) — blog + newsletter + memberships
- [n8n](https://n8n.io) — self-hosted automations
- [Plausible](https://plausible.io) — privacy-friendly analytics (with first-party proxy so ad-blockers don't strip it)
- [Uptime Kuma](https://uptime.kuma.pet) — status page + alerts
- Postgres 16, Redis 7, Caddy 2 reverse proxy, all wired
- MySQL 8 for Ghost's dedicated DB

**Runs on:** Ubuntu 24.04 + Incus 6 + Docker 29. (Incus is optional — the Docker Compose also works on any Docker host.)

**Cost:** ~$5/month (domain + off-site backups). The AI bill replaces ~$50/mo of SaaS once you add the GPU half.

The GPU half (Ollama + XTTS + Whisper + ComfyUI) lives in the [Pass-2 branch](https://github.com/aitoolgeekhq/aitoolgeek-stack/tree/pass-2-gpu) and ships shortly.

---

## Quickstart (10 min)

```bash
git clone https://github.com/aitoolgeekhq/aitoolgeek-stack.git
cd aitoolgeek-stack/infra/incus
./create-stack-container.sh                    # creates Incus container + installs Docker inside
./start-stack.sh 're_YOUR_RESEND_API_KEY'      # generates .env + docker compose up -d
```

Then wire the Cloudflare Tunnel:

```bash
cloudflared tunnel create aitoolgeek
# copy the UUID into infra/cloudflared/config-aitoolgeek.yml
./setup-cloudflared.sh                         # installs systemd unit + adds DNS routes
```

Full walkthrough: **[infra/README.md](./infra/README.md)**.

---

## Architecture

```
Cloudflare Tunnel (HTTPS termination)
          ↓
Incus container: aitoolgeek-web (192.168.108.X)
          ↓
Caddy :80 (Host-header routing, forces X-Forwarded-Proto: https)
     ├─ aitoolgeek.ai       → ghost:2368
     ├─ n8n.aitoolgeek.ai   → n8n:5678
     ├─ stats.aitoolgeek.ai → plausible:8000
     ├─ status.aitoolgeek.ai → uptime:3001
     ├─ /js/sc.js           → plausible (first-party proxy)
     └─ /api/event          → plausible (first-party proxy)
```

Caddy's first-party Plausible proxy means the analytics script loads from your own domain — ad-blockers don't match and you don't lose pageviews to filter lists.

---

## Repo layout

```
infra/
├── README.md                          # full setup walkthrough
├── cloudflared/
│   ├── config-aitoolgeek.yml          # tunnel ingress config (template)
│   └── cloudflared-aitoolgeek.service # systemd unit
├── docker/
│   ├── docker-compose.yml             # the stack
│   ├── .env.example                   # fill in your values → .env
│   ├── Caddyfile                      # internal routing + Plausible proxy
│   ├── postgres-init.sql              # creates n8n + plausible DBs
│   └── plausible-clickhouse-user.xml  # silences noisy ClickHouse logs
├── incus/
│   ├── create-stack-container.sh      # bootstrap Incus container
│   ├── start-stack.sh                 # generate .env + compose up
│   └── setup-cloudflared.sh           # deploy tunnel config + enable systemd
└── scripts/
    └── ghost-setup.mjs                # Ghost Admin API: bulk-create pages, settings, posts
```

---

## Watch the video

Full walkthrough of this exact stack (including honest hidden costs):
**[I replaced $200/month of AI SaaS with a home server](https://youtube.com/@aitoolgeekhq)** — dropping soon.

New videos every Friday at [@aitoolgeekhq](https://youtube.com/@aitoolgeekhq).
Weekly newsletter at [aitoolgeek.ai](https://aitoolgeek.ai).

---

## Why self-host this?

- Own your audience — no platform can shadow-ban you, kill your reach, or change terms overnight.
- Predictable cost — one VPS bill or one home server, instead of N creeping SaaS subscriptions.
- Privacy — Plausible, self-hosted, no tracking pixels leaking user data.
- Hackable — you can script anything against n8n, add MCP servers to Ollama, fine-tune a local model on your own codebase.

## Why NOT self-host?

- If you don't enjoy ops, use a managed Ghost + Beehiiv + Umami stack. The money you save is your time, not dollars.
- This is opinionated for one creator running on one box. Not a production multi-tenant system.

---

## License

[MIT](./LICENSE) — do whatever you want with it. Attribution welcome but not required.

---

## Credits

Built by **[@aitoolgeekhq](https://github.com/aitoolgeekhq)** — a remote software engineer from the Himalayas.

Questions / issues: [open one](https://github.com/aitoolgeekhq/aitoolgeek-stack/issues) or reach out at `hello@aitoolgeek.ai`.
