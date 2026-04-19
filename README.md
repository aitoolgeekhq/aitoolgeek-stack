# aitoolgeek-stack

Self-hosted creator web stack — one Docker Compose, behind a Cloudflare Tunnel.

- **Ghost** — blog + newsletter + memberships
- **n8n** — self-hosted automations
- **Plausible** — privacy-friendly analytics (first-party proxied to bypass ad-blockers)
- **Uptime Kuma** — status page + alerts
- **Postgres 16**, **Redis 7**, **Caddy 2**, **MySQL 8** — glue

Runs on any Ubuntu 22/24 host with Docker. Optional scripts provided for Incus system containers.

## Repo layout

```
infra/
├── docker/            # compose, Caddyfile, env template, init SQL
├── cloudflared/       # tunnel config + systemd unit templates
└── incus/             # optional: bootstrap scripts for Incus hosts
```

## Quickstart

```bash
git clone https://github.com/aitoolgeekhq/aitoolgeek-stack.git
cd aitoolgeek-stack/infra/docker
cp .env.example .env    # edit: domains, passwords, SMTP
docker compose up -d
```

Point your domains at the host (Cloudflare Tunnel recommended). See `infra/README.md`.

## License

[MIT](./LICENSE).
