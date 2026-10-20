# Running in Docker

The container runs `cloudflare-ddns.sh` (IPv4) and/or `cloudflare-ddns-v6.sh` (IPv6) on a schedule using [supercronic](https://github.com/aptible/supercronic). All settings come from environment variables, normally kept in a `.env` file next to `compose.yaml`. Nothing secret is baked into the image.

## Quick start

```bash
git clone -b docker https://github.com/Chaos-man/cloudflare-ddns-updater.git
cd cloudflare-ddns-updater

cp .env.example .env
chmod 600 .env                 # it holds your API token
nano .env                      # set PUID, PGID, CF_API_TOKEN, CF_ZONE_ID, CF_RECORD_NAME

docker compose up -d --build
docker compose logs            # startup summary and first-run result
tail -f logs/ddns.log          # everything else
```

`PUID`/`PGID` are the user and group the container runs as. Use the IDs of the user that owns your Docker files, for example `id docker`. The `./logs` folder is created on first start (if needed) and owned by `PUID:PGID`.

### Without a .env file

`compose.yaml` only needs five values. Instead of using `.env`, you can replace each `${...}` reference with your value directly (or set them as environment variables, e.g. in a Portainer stack). Optional settings can then be added under `environment:`.

## Settings

### Required (in `compose.yaml`)

| Variable | Description |
|---|---|
| `PUID`, `PGID` | Numeric user and group IDs the container runs as |
| `CF_API_TOKEN` | Cloudflare API token with Zone.DNS edit permission (or the Global API Key, see `CF_AUTH_METHOD`) |
| `CF_ZONE_ID` | Zone ID, from the "Overview" tab of your domain in the Cloudflare dashboard |
| `CF_RECORD_NAME` | A record to update, e.g. `home.example.com`. Leave empty for IPv6 only |

At least one of `CF_RECORD_NAME` and `CF_RECORD_NAME_V6` must be set.

### Optional (add to `.env`)

All of these are listed, commented out, in `.env.example`.

| Variable | Default | Description |
|---|---|---|
| `CF_RECORD_NAME_V6` | | AAAA record to update. Needs `network_mode: host` (see IPv6) |
| `STATIC_IPV6_MODE` | `false` | `true` reads the address from the host's interfaces instead of an external service |
| `LAST_NOTABLE_HEXES` | `ffff:ffff` | With `STATIC_IPV6_MODE`: the address suffix to pick, e.g. `ab12:34cd` |
| `CF_TTL` | `3600` | Record TTL in seconds (60-86400), or `1` for automatic |
| `CF_PROXY` | `false` | `true` to proxy the record through Cloudflare |
| `CF_AUTH_METHOD` | `token` | `global` to use a Global API Key in `CF_API_TOKEN` |
| `CF_AUTH_EMAIL` | | Cloudflare login email; required with `CF_AUTH_METHOD=global` |
| `SITENAME` | | Site name used in notifications |
| `DISCORD_URI` | | Discord webhook URL |
| `SLACK_URI`, `SLACK_CHANNEL` | | Slack webhook URL and channel |
| `DDNS_SCHEDULE` | `5m` | `5m`, `1h`, `1d`, or a cron expression such as `*/15 * * * *` |
| `RUN_ON_START` | `true` | Run an update as soon as the container starts |
| `TZ` | `UTC` | Timezone for log timestamps and the schedule, e.g. `America/Chicago` |
| `LOG_FILE` | `/logs/ddns.log` | Log file inside the container (`./logs/ddns.log` on the host). Set it empty to log to `docker logs` instead |
| `LOG_MAX_SIZE` | `1048576` | Rotate the log to `ddns.log.1` past this many bytes |

Values with spaces need quotes in `.env`, e.g. `SITENAME="My Home"`.

After changing `.env` or `compose.yaml`, run `docker compose up -d` to recreate the container.

## IPv6

Docker's default bridge network has no IPv6, so the container can't see the host's IPv6 address. To update an AAAA record:

1. Set `CF_RECORD_NAME_V6` in `.env` (and leave `CF_RECORD_NAME` empty for IPv6 only).
2. Uncomment `network_mode: host` in `compose.yaml`.

`STATIC_IPV6_MODE=true` reads the host's network interfaces, so it also needs `network_mode: host`.

## Logs

| Where | What |
|---|---|
| `docker compose logs` | Startup summary, config errors, and whether the first run succeeded |
| `./logs/ddns.log` | Every run: fetched IP, unchanged/updated, and errors |

The log file rotates to `ddns.log.1` when it reaches `LOG_MAX_SIZE`, keeping one old copy. If the container can't write to `/logs`, it prints a warning and logs to `docker logs` instead.

## Startup and failures

- **Config errors** (missing token, zone or record name, invalid values): printed to `docker compose logs`, then the container exits. Because of `restart: unless-stopped`, Docker keeps restarting it, with increasing delays, until the settings are fixed. `docker ps` shows `Restarting`.
- **First run fails** (bad token, record doesn't exist, network down): one line in `docker compose logs` points to the log file. The container keeps running and tries again on the next scheduled run; there are no extra retries.
- **Scheduled run fails**: logged to `./logs/ddns.log`. The container keeps running.

## Health

`docker ps` shows the container as `healthy` while the last run of each configured record succeeded, and `unhealthy` a few minutes after a failed run. It goes back to `healthy` after the next successful run. See the reason with:

```bash
docker inspect --format '{{json .State.Health}}' cloudflare-ddns
```

## Running an update by hand

```bash
docker exec cloudflare-ddns /app/entrypoint.sh run cloudflare-ddns      # IPv4
docker exec cloudflare-ddns /app/entrypoint.sh run cloudflare-ddns-v6   # IPv6
```

## Updating

```bash
git pull
docker compose up -d --build
```

`.env` and `logs/` are git-ignored, so `git pull` leaves them alone.

## Troubleshooting

| Message | Fix |
|---|---|
| `required variable ... is missing a value` (from `docker compose`) | Set that variable in `.env` |
| `PUID and PGID must be set to numeric IDs` | Set `PUID`/`PGID` to numbers, e.g. from `id docker` |
| `CONFIG ERROR: ...` | Fix the named setting in `.env`, then `docker compose up -d` |
| `Cannot write /logs/ddns.log` | Check that `./logs` is mounted and not read-only |
| `Unable to establish a valid IPv6 connection` (in the log) | Use `network_mode: host` (see IPv6) |
| `Record does not exist` (in the log) | Create the A/AAAA record in Cloudflare first |
