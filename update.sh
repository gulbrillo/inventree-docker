#!/usr/bin/env bash
#
# update.sh — update an existing InvenTree deployment.
#
# Pulls this repo (compose/Caddy/script changes), pulls the latest InvenTree
# image, backs up the database + media, runs migrations & collects static, and
# restarts the stack. Apache is left untouched (its config does not change).

set -euo pipefail

cd "$(dirname "$0")"

err()  { printf '\033[31m%s\033[0m\n' "$*" >&2; }
info() { printf '\033[36m%s\033[0m\n' "$*"; }
ok()   { printf '\033[32m%s\033[0m\n' "$*"; }

if docker compose version >/dev/null 2>&1; then
    DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    DC="docker-compose"
else
    err "Docker Compose not found."
    exit 1
fi

[ -f .env ] || { err "No .env found — run ./install.sh first."; exit 1; }

# 1. Update this repo (docker-compose.yml, override, Caddyfile, scripts).
if [ -d .git ]; then
    info "Updating inventree-docker repo ..."
    git pull --ff-only
else
    info "Not a git checkout — skipping repo update."
fi

# 2. Safety backup before touching the database.
info "Backing up database + media (invoke backup) ..."
$DC run --rm inventree-server invoke backup

# 3. Pull the latest InvenTree image (this is the new InvenTree 'code').
info "Pulling latest images ..."
$DC pull

# 4. Run migrations and collect static files.
info "Applying migrations & collecting static (invoke update) ..."
$DC run --rm inventree-server invoke update

# 5. Restart with the new image.
info "Restarting containers ..."
$DC up -d

ok ""
ok "Update complete. Apache config unchanged — no reload required."
ok "If you bumped INVENTREE_TAG to a new major version, check the release notes."
