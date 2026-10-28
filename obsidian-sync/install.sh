#!/usr/bin/env bash
# Установка Self-hosted LiveSync (CouchDB) на Ubuntu VPS.
# Запускать на сервере: sudo bash install.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}==>${NC} $*"; }
warn()  { echo -e "${YELLOW}!!${NC} $*"; }
die()   { echo -e "${RED}ERROR:${NC} $*" >&2; exit 1; }

if [[ "$(id -u)" -ne 0 ]]; then
  die "Запустите от root: sudo bash install.sh"
fi

PROFILE="${1:-tailscale}"
case "$PROFILE" in
  tailscale|caddy|cloudflare|local) ;;
  *)
    die "Профиль: tailscale | caddy | cloudflare | local
Пример: sudo bash install.sh tailscale"
    ;;
esac

info "Профиль: $PROFILE"
info "Каталог: $SCRIPT_DIR"

# --- Docker ---
if ! command -v docker >/dev/null 2>&1; then
  info "Устанавливаю Docker..."
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg
  install -m 0755 -d /etc/apt/keyrings
  if [[ ! -f /etc/apt/keyrings/docker.asc ]]; then
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
  fi
  . /etc/os-release
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
  systemctl enable --now docker
else
  info "Docker уже установлен: $(docker --version)"
fi

docker compose version >/dev/null 2>&1 || die "Нужен Docker Compose v2 (plugin)"

# --- .env ---
if [[ ! -f .env ]]; then
  info "Создаю .env из .env.example..."
  cp .env.example .env
  GEN_PASS="$(openssl rand -base64 24 | tr -d '=+/' | cut -c1-24)"
  sed -i "s|^COUCHDB_PASSWORD=.*|COUCHDB_PASSWORD=${GEN_PASS}|" .env
  info "Сгенерирован пароль CouchDB (сохранён в .env)"
else
  info ".env уже есть — не перезаписываю"
fi

chmod 600 .env

# shellcheck disable=SC1091
set -a
# shellcheck source=/dev/null
source .env
set +a

need_env() {
  local key="$1"
  local val="${!key:-}"
  if [[ -z "$val" || "$val" == change_me* || "$val" == *xxxxxxxx* || "$val" == eyJhIjoixxx* || "$val" == sync.example.com ]]; then
    return 1
  fi
  return 0
}

case "$PROFILE" in
  tailscale)
    if ! need_env TS_AUTHKEY; then
      cat <<EOF

${YELLOW}Нужен Tailscale auth key${NC}
1. Откройте https://login.tailscale.com/admin/settings/keys
2. Generate auth key → Reusable + Ephemeral
3. Вставьте в .env:
     nano $SCRIPT_DIR/.env
   строка TS_AUTHKEY=tskey-auth-...
4. Снова: sudo bash install.sh tailscale

EOF
      exit 1
    fi
    COMPOSE_ARGS=(--profile tailscale)
    # Для Tailscale CouchDB должен слушать все интерфейсы внутри netns
    # (sidecar шарит network_mode с couchdb). Порт на хосте оставляем localhost.
    ;;
  caddy)
    need_env COUCHDB_DOMAIN || die "Заполните COUCHDB_DOMAIN в .env (A-запись → IP VPS)"
    need_env ACME_EMAIL || die "Заполните ACME_EMAIL в .env"
    COMPOSE_ARGS=(--profile caddy)
    ;;
  cloudflare)
    need_env CF_TUNNEL_TOKEN || die "Заполните CF_TUNNEL_TOKEN в .env"
    COMPOSE_ARGS=(--profile cloudflare)
    ;;
  local)
    COMPOSE_ARGS=()
    # Локальный HTTP — открываем порт для тестов
    sed -i 's|^COUCHDB_PORT=.*|COUCHDB_PORT=5984|' .env
    warn "Профиль local: HTTP без TLS. Android не подключится без HTTPS."
    ;;
esac

info "Запускаю стек..."
docker compose "${COMPOSE_ARGS[@]}" up -d

info "Жду инициализацию CouchDB..."
for i in $(seq 1 60); do
  if docker compose logs couchdb-init 2>/dev/null | grep -q "initialization complete"; then
    break
  fi
  # init мог уже завершиться и контейнер удалён/exited
  status="$(docker inspect -f '{{.State.Status}}:{{.State.ExitCode}}' livesync-init 2>/dev/null || true)"
  if [[ "$status" == "exited:0" ]]; then
    break
  fi
  sleep 2
done

echo ""
info "Проверка локально..."
if docker exec livesync-couchdb curl -sf -u "${COUCHDB_USER}:${COUCHDB_PASSWORD}" http://127.0.0.1:5984/_up | grep -q ok; then
  echo -e "${GREEN}CouchDB OK${NC}"
else
  warn "CouchDB ещё не ответил. Смотрите: docker compose logs -f"
fi

SYNC_URL=""
case "$PROFILE" in
  tailscale)
    sleep 3
    TS_DNS="$(docker exec livesync-tailscale tailscale status --json 2>/dev/null | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("Self",{}).get("DNSName","").rstrip("."))' 2>/dev/null || true)"
    if [[ -n "$TS_DNS" ]]; then
      SYNC_URL="https://${TS_DNS}"
    else
      SYNC_URL="https://${TS_HOSTNAME}.<ваш-tailnet>.ts.net"
      warn "DNS Tailscale ещё не готов. Через минуту: docker exec livesync-tailscale tailscale status"
    fi
    ;;
  caddy)
    SYNC_URL="https://${COUCHDB_DOMAIN}"
    ;;
  cloudflare)
    SYNC_URL="https://${COUCHDB_DOMAIN}"
    ;;
  local)
    SYNC_URL="http://127.0.0.1:5984"
    ;;
esac

cat <<EOF

${GREEN}========================================${NC}
  Obsidian LiveSync готов на VPS
${GREEN}========================================${NC}

  URI плагина : ${SYNC_URL}
  Username    : ${COUCHDB_USER}
  Password    : (смотрите .env — COUCHDB_PASSWORD)
  Database    : ${COUCHDB_DATABASE}

  E2E passphrase придумайте сами и запомните —
  без неё заметки на сервере не расшифровать.

Дальше:
  1) На ноутбуке и Android установите плагин
     «Self-hosted LiveSync»
  2) Вставьте URI / логин / пароль / БД / passphrase
  3) На Android поставьте приложение Tailscale
     и войдите в тот же аккаунт (для профиля tailscale)

Полезные команды:
  cd $SCRIPT_DIR
  docker compose ${COMPOSE_ARGS[*]} logs -f
  docker compose ${COMPOSE_ARGS[*]} ps

EOF
