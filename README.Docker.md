# Running in Docker

The image runs `cloudflare-ddns.sh` and/or `cloudflare-ddns-v6.sh` on a schedule using [supercronic](https://github.com/aptible/supercronic). Your config files are mounted at runtime; nothing secret is baked into the image.

## Quick start

On the Docker host, from a clone of this repo:

```bash
# 1. Create and edit the config (same format as the non-Docker setup)
cp cloudflare-ddns.conf.example cloudflare-ddns.conf
nano cloudflare-ddns.conf

# 2. Let the container user (UID 10001) read it, and nobody else
sudo chown 10001 cloudflare-ddns.conf
sudo chmod 600 cloudflare-ddns.conf

# 3. Build and start
docker compose up -d --build

# 4. Check it
docker compose logs -f
```

The first update runs as soon as the container starts, then on the schedule.

> **Create the config file before the first `docker compose up`.** If a mounted file doesn't exist on the host, Docker creates an empty *directory* in its place. The container detects this and exits with a message; delete the directory, create the file, and start again.

## Settings

Set these under `environment:` in `compose.yaml`.

| Variable | Default | Values |
|---|---|---|
| `DDNS_RECORD` | `v4` | `v4`, `v6` or `both` |
| `DDNS_SCHEDULE` | `5m` | `5m`, `1h`, `1d`, or a cron expression such as `*/15 * * * *` |
| `RUN_ON_START` | `true` | `true` runs an update when the container starts |
| `TZ` | `UTC` | Timezone for log timestamps and the schedule, e.g. `America/Chicago` |
| `LOG_FILE` | (unset) | Also append logs to this file, e.g. `/logs/ddns.log` |
| `LOG_MAX_SIZE` | `1048576` | Rotate `LOG_FILE` to `LOG_FILE.1` past this many bytes |

Config files are read from `/config/cloudflare-ddns.conf` and `/config/cloudflare-ddns-v6.conf`. Only the ones for `DDNS_RECORD` need to exist.

After changing `compose.yaml` or a config file, run `docker compose up -d` to recreate the container.

## IPv6

Docker's default bridge network usually has no IPv6, so the container can't see the host's IPv6 address. For `DDNS_RECORD=v6` or `both`:

1. Create `cloudflare-ddns-v6.conf` from its example and `chown 10001` it, as above.
2. In `compose.yaml`, uncomment the v6 volume line and `network_mode: host`.

`static_IPv6_mode` reads the host's interfaces, so it also needs `network_mode: host`.

## Logs

Logs always go to `docker logs` (rotated by the `logging:` section in `compose.yaml`):

```bash
docker compose logs -f
```

To also keep them in a file on the host:

```bash
mkdir -p logs && sudo chown 10001 logs
```

Then uncomment `LOG_FILE` and the `./logs:/logs` volume in `compose.yaml`, and run `docker compose up -d`. Logs are written to `./logs/ddns.log` and rotated to `ddns.log.1` at `LOG_MAX_SIZE`.

The log directory is mounted separately from the config on purpose: the config mounts are read-only, so the container can't modify the files that hold your API token.

## Health

`docker ps` shows the container as `healthy` while the last run of each configured script succeeded, and `unhealthy` a few minutes after a failed run (bad token, Cloudflare unreachable, and so on). It goes back to `healthy` after the next successful run. See the reason with:

```bash
docker inspect --format '{{json .State.Health}}' cloudflare-ddns
```

## Updating

```bash
git pull
docker compose up -d --build
```

Your `.conf` files and `logs/` are git-ignored, so `git pull` leaves them alone.

## Troubleshooting

| Message | Fix |
|---|---|
| `Cannot read /config/cloudflare-ddns.conf` | The file isn't mounted, or UID 10001 can't read it: `sudo chown 10001 cloudflare-ddns.conf` |
| `/config/... is a directory` | The host file didn't exist when the container started. Remove the directory, create the file, `docker compose up -d` |
| `Cannot write LOG_FILE` | Mount `./logs:/logs` and `sudo chown 10001 logs` |
| `Invalid DDNS_SCHEDULE` | Use `5m`, `1h`, `1d`, or a valid 5-field cron expression |
| `Unable to establish a valid IPv6 connection` | Use `network_mode: host` (see IPv6 above) |

To run a one-off update by hand inside the running container:

```bash
docker exec cloudflare-ddns /app/entrypoint.sh run cloudflare-ddns
```
