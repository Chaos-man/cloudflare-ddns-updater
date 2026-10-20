#!/bin/bash
## Container entrypoint.
##   entrypoint.sh              Check config, run once on start, then schedule with supercronic
##   entrypoint.sh run NAME     Run one DDNS script (used by the crontab) and record its exit status
##   entrypoint.sh healthcheck  Exit 1 if the last run of any configured script failed
##
## Environment:
##   DDNS_RECORD     v4, v6 or both (default v4)
##   DDNS_SCHEDULE   5m, 1h, 1d, or a cron expression (default 5m)
##   RUN_ON_START    true to run once at startup (default true)
##   LOG_FILE        Also append logs to this file, e.g. /logs/ddns.log (optional)
##   LOG_MAX_SIZE    Rotate LOG_FILE past this many bytes (default 1048576)

set -u

app_dir=/app
config_dir=/config
state_dir=/tmp
record="${DDNS_RECORD:-v4}"
schedule="${DDNS_SCHEDULE:-5m}"
run_on_start="${RUN_ON_START:-true}"

log() { logger -s "entrypoint: $*"; }

case "$record" in
  v4)   names=(cloudflare-ddns) ;;
  v6)   names=(cloudflare-ddns-v6) ;;
  both) names=(cloudflare-ddns cloudflare-ddns-v6) ;;
  *)    log "Invalid DDNS_RECORD '$record' (use v4, v6 or both)."; exit 1 ;;
esac

# Run one script and record its exit status for the healthcheck
run_job() {
  local name="$1"
  "$app_dir/$name.sh" "$config_dir/$name.conf"
  local status=$?
  echo "$status" > "$state_dir/ddns-status-$name"
  return $status
}

###########################################
## Subcommands
###########################################
case "${1:-}" in
  run)
    case "${2:-}" in
      cloudflare-ddns|cloudflare-ddns-v6) run_job "$2"; exit $? ;;
      *) log "Usage: entrypoint.sh run cloudflare-ddns|cloudflare-ddns-v6"; exit 1 ;;
    esac ;;
  healthcheck)
    for name in "${names[@]}"; do
      status_file="$state_dir/ddns-status-$name"
      [[ -f "$status_file" ]] || continue   # Not run yet
      status="$(cat "$status_file")"
      if [[ "$status" != "0" ]]; then
        echo "$name: last run failed (exit $status)"
        exit 1
      fi
    done
    exit 0 ;;
  "") ;;
  *) log "Unknown command: $1"; exit 1 ;;
esac

###########################################
## Startup checks
###########################################
log "Starting as UID $(id -u): DDNS_RECORD=$record DDNS_SCHEDULE=$schedule"

if [[ -n "${LOG_FILE:-}" ]] && ! touch "$LOG_FILE" 2>/dev/null; then
  log "Cannot write LOG_FILE $LOG_FILE. Mount its directory read-write and make it writable by UID $(id -u) (chown $(id -u) <dir>)."
  exit 1
fi

for name in "${names[@]}"; do
  conf="$config_dir/$name.conf"
  if [[ -d "$conf" ]]; then
    log "$conf is a directory. Docker creates one when the host file is missing; create $name.conf on the host and recreate the container."
    exit 1
  elif [[ ! -r "$conf" ]]; then
    log "Cannot read $conf. Mount it (see README.Docker.md) and make it readable by UID $(id -u) (chown $(id -u) $name.conf)."
    exit 1
  fi
done

###########################################
## Build and check the crontab
###########################################
case "$schedule" in
  5m) cron_expr="*/5 * * * *" ;;
  1h) cron_expr="0 * * * *" ;;
  1d) cron_expr="0 0 * * *" ;;
  *)  cron_expr="$schedule" ;;
esac

crontab_file="$state_dir/crontab"
: > "$crontab_file"
for name in "${names[@]}"; do
  echo "$cron_expr $app_dir/entrypoint.sh run $name" >> "$crontab_file"
done

if ! supercronic -test "$crontab_file" >/dev/null 2>&1; then
  log "Invalid DDNS_SCHEDULE '$schedule' (use 5m, 1h, 1d, or a cron expression)."
  exit 1
fi

###########################################
## Run once, then hand over to the scheduler
###########################################
if [[ "$run_on_start" == "true" ]]; then
  for name in "${names[@]}"; do
    log "Initial run of $name.sh"
    run_job "$name" || log "Initial run of $name.sh failed; it will retry on schedule."
  done
fi

log "Scheduling with '$cron_expr'"
# Full path: as PID 1, supercronic re-executes itself to reap child processes
exec /usr/bin/supercronic -quiet -passthrough-logs "$crontab_file"
