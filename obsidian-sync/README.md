# Синхронизация Obsidian через VPS `basya`

Бесплатная замена Obsidian Sync: ноутбук ↔ Android через ваш сервер  
**IP:** `82.22.187.58` · Ubuntu · 1 GB RAM.

Стек: **CouchDB** + плагин [Self-hosted LiveSync](https://github.com/vrtmrz/obsidian-livesync).  
На Android нужен **HTTPS с доверенным сертификатом** — поэтому по умолчанию используем **Tailscale** (бесплатно, без своего домена).

```
Ноутбук Obsidian  ──HTTPS──┐
                           ├── Tailscale ──▶ CouchDB на VPS
Android Obsidian  ──HTTPS──┘
```

---

## Что нужно заранее

| Что | Зачем |
|-----|--------|
| SSH-доступ к VPS `basya` | Установка Docker и CouchDB |
| Аккаунт [Tailscale](https://login.tailscale.com/) | HTTPS для телефона без домена |
| Obsidian на ноутбуке и телефоне | Клиенты синхронизации |

Альтернативы Tailscale (если есть домен): профиль `caddy` или `cloudflare` — см. ниже.

---

## 1. Установка на VPS

С ноутбука скопируйте папку и зайдите по SSH:

```bash
# с вашего компьютера (подставьте пользователя SSH)
scp -r obsidian-sync USER@82.22.187.58:~/
ssh USER@82.22.187.58
```

На сервере:

```bash
cd ~/obsidian-sync

# 1) Создайте auth key: https://login.tailscale.com/admin/settings/keys
#    галочки: Reusable + Ephemeral
nano .env.example   # можно сразу скопировать в .env после install,
                    # но удобнее сначала узнать ключ

# 2) Запуск установщика (поставит Docker, сгенерирует пароль)
sudo bash install.sh tailscale
```

Если ключа ещё нет — скрипт остановится и подскажет, куда вписать `TS_AUTHKEY` в `.env`, затем снова:

```bash
sudo nano /root/obsidian-sync/.env   # или путь, куда вы положили папку
# TS_AUTHKEY=tskey-auth-...
sudo bash install.sh tailscale
```

В конце скрипт покажет **URI** вида:

```text
https://basya-livesync.TAILNET.ts.net
```

Сохраните из `.env`: `COUCHDB_USER`, `COUCHDB_PASSWORD`, `COUCHDB_DATABASE`.

---

## 2. Ноутбук

1. Установите [Tailscale](https://tailscale.com/download) и войдите в тот же аккаунт.
2. В Obsidian → Community plugins → **Self-hosted LiveSync**.
3. Setup / Wizard:
   - **URI** — URL из вывода `install.sh`
   - **Username / Password** — из `.env`
   - **Database** — `obsidiannotes` (или как в `.env`)
   - **End-to-end encryption passphrase** — своя фраза (обязательно запомните)
4. Test connection → Apply → включите синхронизацию.
5. Первый устройство: отправьте vault на сервер (Send / Rebuild / как предложит мастер).

---

## 3. Android

1. Установите [Tailscale для Android](https://play.google.com/store/apps/details?id=com.tailscale.ipn), войдите, VPN включён.
2. В браузере телефона откройте ваш URI (`https://….ts.net`) — должна открыться JSON-страница CouchDB **без** предупреждения о сертификате.
3. Obsidian → тот же плагин **Self-hosted LiveSync** → те же URI, логин, пароль, БД, **та же E2E-фраза**.
4. Если «Failed to fetch»: в настройках плагина включите **Use Request API**.
5. Получите данные с сервера (Fetch / Pull), не перезаписывайте сервер пустым vault.

Готово: правки на ноутбуке появляются на телефоне и наоборот.

---

## Другие профили (вместо Tailscale)

### Домен + Let's Encrypt

```bash
# A-запись sync.ваш-домен.ru → 82.22.187.58
# В панели VPS откройте порты 80 и 443
sudo nano .env   # COUCHDB_DOMAIN=...  ACME_EMAIL=...
sudo bash install.sh caddy
```

URI в плагине: `https://sync.ваш-домен.ru`

### Cloudflare Tunnel

Нужен домен в Cloudflare и tunnel token — см. комментарии в `.env.example`, затем:

```bash
sudo bash install.sh cloudflare
```

---

## Полезные команды на VPS

```bash
cd ~/obsidian-sync   # ваш путь

docker compose --profile tailscale ps
docker compose --profile tailscale logs -f couchdb
docker exec livesync-tailscale tailscale status
docker exec livesync-couchdb curl -sf -u USER:PASS http://127.0.0.1:5984/_up
```

Бэкап тома данных:

```bash
docker compose --profile tailscale stop couchdb
docker run --rm -v obsidian-livesync_couchdb-data:/data:ro -v "$PWD/backup:/backup" alpine \
  tar czf "/backup/couchdb-$(date +%Y%m%d).tar.gz" -C /data .
docker compose --profile tailscale start couchdb
```

---

## Безопасность

- CouchDB слушает только `127.0.0.1` на хосте; снаружи — через Tailscale HTTPS.
- Funnel (публичный интернет) **выключен** в `config/ts-serve.json`.
- Включите E2E passphrase в плагине — на сервере лежат только шифрованные данные.
- Не публикуйте `.env` и не коммитьте его.

---

## Источники

Конфиг основан на официальном Docker-стеке  
https://github.com/vrtmrz/obsidian-livesync/tree/main/docker
