# Cloudflare DDNS Updater

Keeps a Cloudflare **A** (IPv4) and/or **AAAA** (IPv6) record pointed at your current public IP, so a home server stays reachable at your own domain without a static IP. It runs on a schedule (every 5 minutes by default), only updates the record when the IP changes, and can notify **Discord** or **Slack**.

- Small Alpine image for `linux/amd64` and `linux/arm64`
- Configured entirely with environment variables; nothing secret is baked into the image
- Runs as your own user (`PUID`/`PGID`); logs to a file on the host
- Built-in healthcheck: `unhealthy` after a failed update
- Hardened: no overlapping runs, timeouts on every request, and no update with an incomplete record lookup

Source, full documentation and issues: **[github.com/Chaos-man/cloudflare-ddns-updater](https://github.com/Chaos-man/cloudflare-ddns-updater)**

## Quick start

The DNS record must already exist in Cloudflare; this updates it, it doesn't create it.

**`compose.yaml`**

```yaml
services:
  cloudflare-ddns:
    image: chaosmanorg/cloudflare-ddns:latest
    container_name: cloudflare-ddns
    restart: unless-stopped
    environment:
      PUID: ${PUID:?Set PUID in .env}
      PGID: ${PGID:?Set PGID in .env}
      CF_API_TOKEN: ${CF_API_TOKEN:?Set CF_API_TOKEN in .env}
      CF_ZONE_ID: ${CF_ZONE_ID:?Set CF_ZONE_ID in .env}
      CF_RECORD_NAME: ${CF_RECORD_NAME:-}
      # Optional, e.g.:
      # DISCORD_URI: ${DISCORD_URI}
    volumes:
      - ./logs:/logs
```

**`.env`** (next to `compose.yaml`; `chmod 600 .env`)

```bash
PUID=1000                       # user/group the container runs as, e.g. from `id`
PGID=1000
CF_API_TOKEN=your-api-token     # scoped API token with Zone.DNS edit permission
CF_ZONE_ID=your-zone-id         # Cloudflare dashboard > your domain > Overview
CF_RECORD_NAME=home.example.com
```

```bash
docker compose up -d
docker compose logs            # startup summary and first-run result
tail -f logs/ddns.log          # every run
```

## Settings

### Required

| Variable | Description |
|---|---|
| `PUID`, `PGID` | Numeric user and group IDs the container runs as; `./logs` is owned by them |
| `CF_API_TOKEN` | Cloudflare API token with Zone.DNS edit permission (or a Global API Key, see `CF_AUTH_METHOD`) |
| `CF_ZONE_ID` | Zone ID from the domain's Overview page in the Cloudflare dashboard |
| `CF_RECORD_NAME` | A record to update. Leave empty for IPv6 only |

### Optional

Add a line under `environment:` for each one you use (e.g. `DISCORD_URI: ${DISCORD_URI}`) and set its value in `.env`.

| Variable | Default | Description |
|---|---|---|
| `CF_RECORD_NAME_V6` | | AAAA record to update (needs `network_mode: host`, see below) |
| `STATIC_IPV6_MODE` | `false` | `true` reads the address from the host's interfaces instead of an external service |
| `LAST_NOTABLE_HEXES` | `ffff:ffff` | With `STATIC_IPV6_MODE`: the address suffix to pick |
| `CF_TTL` | `3600` | Record TTL in seconds (60-86400), or `1` for automatic |
| `CF_PROXY` | `false` | `true` to proxy the record through Cloudflare |
| `CF_AUTH_METHOD` | `token` | `global` to use a Global API Key in `CF_API_TOKEN` |
| `CF_AUTH_EMAIL` | | Cloudflare login email; **required** with `CF_AUTH_METHOD=global` |
| `DISCORD_URI` | | Discord webhook URL |
| `SLACK_URI`, `SLACK_CHANNEL` | | Slack webhook URL and channel |
| `SITENAME` | record name | Name used in notifications |
| `DDNS_SCHEDULE` | `5m` | `5m`, `1h`, `1d`, or a cron expression such as `*/15 * * * *` |
| `RUN_ON_START` | `true` | Run an update when the container starts |
| `TZ` | `UTC` | Timezone for logs and the schedule, e.g. `America/Chicago` |
| `LOG_FILE` | `/logs/ddns.log` | Log file; set empty to log to `docker logs` instead |
| `LOG_MAX_SIZE` | `1048576` | Rotate the log to `ddns.log.1` past this many bytes |

## IPv6

Docker's default network has no IPv6, so for an AAAA record add `CF_RECORD_NAME_V6` and run on the host network:

```yaml
services:
  cloudflare-ddns:
    network_mode: host
    environment:
      CF_RECORD_NAME_V6: ${CF_RECORD_NAME_V6}
```

## Logs and health

- `docker compose logs`: startup summary, configuration errors, and whether the first run succeeded.
- `./logs/ddns.log`: every run (fetched IP, unchanged/updated, notification results, errors). Rotated at `LOG_MAX_SIZE`.
- A configuration error stops the container with a message (Docker restarts it until it's fixed). A failed update doesn't stop it; it retries on the next scheduled run and the container shows as `unhealthy` until an update succeeds.

Run an update by hand:

```bash
docker exec cloudflare-ddns /app/entrypoint.sh run cloudflare-ddns      # IPv4
docker exec cloudflare-ddns /app/entrypoint.sh run cloudflare-ddns-v6   # IPv6
```

## Tags

- `latest`: the newest release
- `1.0.0`, …: fixed versions; pin one in `compose.yaml` for predictable upgrades

## Credits

Based on [K0p1-Git/cloudflare-ddns-updater](https://github.com/K0p1-Git/cloudflare-ddns-updater). MIT licensed.
