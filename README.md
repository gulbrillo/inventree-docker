# inventree-docker

A small, opinionated deployment template for running
[InvenTree](https://inventree.org/) in Docker **behind an existing Apache
reverse proxy**.

It wraps InvenTree's official Docker image (`inventree/inventree`) — it does
**not** fork or build InvenTree from source. Updates therefore track upstream
releases and use InvenTree's own `invoke` task runner for migrations, so this
template stays thin and doesn't rot.

## What this gives you over the stock setup

InvenTree's official compose assumes its bundled **Caddy** container owns ports
80/443 and handles TLS itself. This template instead:

- Publishes Caddy on **`127.0.0.1:8087` (HTTP only)** — see
  [`docker-compose.override.yml`](docker-compose.override.yml) and
  [`Caddyfile`](Caddyfile).
- Lets **host Apache terminate TLS** and reverse-proxy to that loopback port.
- Ships [`install.sh`](install.sh) / [`update.sh`](update.sh) to handle the
  boring parts (generating `.env`, migrations, backups).

Caddy is still in the stack — it serves `/static` and `/media` (with auth on
media) and proxies the rest to gunicorn. Apache just sits in front of it.

```
client ──TLS──▶ Apache (:443) ──HTTP──▶ Caddy (127.0.0.1:8087) ──▶ gunicorn / static / media
```

## Files

| File | Purpose |
|------|---------|
| [`docker-compose.yml`](docker-compose.yml) | Vendored copy of the upstream compose. Don't edit. |
| [`docker-compose.override.yml`](docker-compose.override.yml) | Apache variant: Caddy on `127.0.0.1:8087`. |
| [`Caddyfile`](Caddyfile) | HTTP-only Caddy config (no TLS in the container). |
| [`.env.template`](.env.template) | Documented reference for every env var. |
| [`install.sh`](install.sh) | First-time setup: prompts, writes `.env`, starts the stack. |
| [`update.sh`](update.sh) | Pull repo + image, back up, migrate, restart. |
| [`apache/`](apache/) | **Example** Apache vhost — copied manually (see below). |

## Requirements

- Docker Engine + Docker Compose **v2.24+** (the override uses the `!override`
  YAML tag to drop the public port bindings).
- A host Apache with `proxy proxy_http proxy_wstunnel headers ssl rewrite`.
- `certbot` for TLS.

## Install

```bash
git clone <this-repo> inventree-docker
cd inventree-docker
./install.sh
```

`install.sh` asks for your domain and admin user / email / password, generates a
random PostgreSQL password, writes `.env`, then pulls the images, runs the
initial DB setup and starts the containers on `127.0.0.1:8087`.

### Configure Apache (manual)

The Apache vhost is **not** installed automatically — it's kept here as an
example for you to adapt. A working reference lives at
[`apache/inventree.darkcosmos.org.conf`](apache/inventree.darkcosmos.org.conf).

```bash
# 1. Copy and edit ServerName / log names for your domain
sudo cp apache/inventree.darkcosmos.org.conf \
        /etc/apache2/sites-available/inventree.example.org.conf
sudo $EDITOR /etc/apache2/sites-available/inventree.example.org.conf

# 2. Enable modules
sudo a2enmod proxy proxy_http proxy_wstunnel headers ssl rewrite

# 3. Get a cert (certonly so certbot doesn't rewrite the vhost)
sudo certbot certonly --apache -d inventree.example.org

# 4. Enable + reload
sudo a2ensite inventree.example.org
sudo apache2ctl configtest && sudo systemctl reload apache2
```

The vhost terminates TLS, forwards `X-Forwarded-Proto: https`, handles the
WebSocket upgrade, and proxies to `http://127.0.0.1:8087/`.

## Update

```bash
./update.sh
```

This pulls this repo, **backs up** the database + media (`invoke backup`), pulls
the latest InvenTree image, runs migrations and collects static files
(`invoke update`), then restarts. Apache is untouched.

## Pinning a version

`.env` defaults to `INVENTREE_TAG=stable`. For predictable upgrades, pin an
explicit release (e.g. `INVENTREE_TAG=0.17.0`) and bump it deliberately before
running `update.sh`.

## Notes

- `.env` and `inventree-data/` are gitignored — they hold your secrets and all
  persistent data. Back up `inventree-data/` (and the `invoke backup` output).
- The bundled Caddy never obtains a TLS certificate; if you ever expose it
  directly, revert to the upstream Caddyfile.
