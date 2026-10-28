#!/usr/bin/env bash
# Быстрая проверка CouchDB на VPS (запускать из каталога obsidian-sync)
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "Нет файла .env — сначала install.sh"
  exit 1
fi

# shellcheck disable=SC1091
set -a
# shellcheck source=/dev/null
source .env
set +a

echo "→ Контейнеры:"
docker compose ps || true

echo ""
echo "→ CouchDB _up:"
docker exec livesync-couchdb curl -sf -u "${COUCHDB_USER}:${COUCHDB_PASSWORD}" http://127.0.0.1:5984/_up
echo ""

echo "→ Базы:"
docker exec livesync-couchdb curl -sf -u "${COUCHDB_USER}:${COUCHDB_PASSWORD}" http://127.0.0.1:5984/_all_dbs
echo ""

if docker ps --format '{{.Names}}' | grep -q '^livesync-tailscale$'; then
  echo "→ Tailscale:"
  docker exec livesync-tailscale tailscale status || true
  DNS="$(docker exec livesync-tailscale tailscale status --json 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("Self",{}).get("DNSName","").rstrip("."))' 2>/dev/null || true)"
  if [[ -n "$DNS" ]]; then
    echo ""
    echo "URI для Obsidian: https://${DNS}"
  fi
fi
