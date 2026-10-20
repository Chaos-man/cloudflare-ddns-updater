#!/bin/bash
## Container entrypoint.
##   entrypoint.sh              Check settings, run once on start, then schedule with supercronic
##   entrypoint.sh run NAME     Run one DDNS script (used by the crontab) and record its exit status
##   entrypoint.sh healthcheck  Exit 1 if the last run of any configured script failed
##
## Settings come from environment variables (see .env.example and README.Docker.md).
## The container starts as root only to give PUID:PGID ownership of the log directory,
## then re-runs this script as PUID:PGID.

set -u

app_dir=/app
state_dir=/tmp
schedule="${DDNS_SCHEDULE:-5m}"
run_on_start="${RUN_ON_START:-true}"

# Console output (docker logs): startup summary and problems only
console() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >&2; }

# Records to update, based on which record names are set
names=()
[[ -n "${CF_RECORD_NAME:-}" ]] && names+=(cloudflare-ddns)
[[ -n "${CF_RECORD_NAME_V6:-}" ]] && names+=(cloudflare-ddns-v6)

# Run one script and record its exit status for the healthcheck
run_job() {
  local name="$1"
  "$app_dir/$name.sh" "$state_dir/$name.conf"
  local status=$?
  echo "$status" > "$state_dir/ddns-status-$name"
  return $status
}

###########################################
## Subcommands
###########################################
case "${1:-}" in
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
  run)
    case "${2:-}" in
      cloudflare-ddns|cloudflare-ddns-v6) ;;
      *) console "Usage: entrypoint.sh run cloudflare-ddns|cloudflare-ddns-v6"; exit 1 ;;
    esac
    # `docker exec` runs as root; switch to PUID:PGID so file ownership stays consistent
    if [[ "$(id -u)" == "0" ]]; then
      exec su-exec "${PUID}:${PGID}" "$0" "$@"
    fi
    run_job "$2"
    exit $? ;;
  "") ;;
  *) console "Unknown command: $1"; exit 1 ;;
esac

###########################################
## As root: give PUID:PGID the log directory, then drop privileges
###########################################
if [[ "$(id -u)" == "0" ]]; then
  if [[ ! "${PUID:-}" =~ ^[0-9]+$ || ! "${PGID:-}" =~ ^[0-9]+$ ]]; then
    console "ERROR: PUID and PGID must be set to numeric IDs (e.g. the output of 'id docker')."
    exit 1
  fi
  if [[ -n "${LOG_FILE:-}" ]]; then
    log_dir="$(dirname "$LOG_FILE")"
    mkdir -p "$log_dir" 2>/dev/null
    chown "$PUID:$PGID" "$log_dir" 2>/dev/null
    for f in "$LOG_FILE" "$LOG_FILE.1"; do
      [[ -e "$f" ]] && chown "$PUID:$PGID" "$f" 2>/dev/null
    done
  fi
  exec su-exec "$PUID:$PGID" "$0" "$@"
fi

###########################################
## Logging: fall back to the console if LOG_FILE can't be written
###########################################
if [[ -n "${LOG_FILE:-}" ]] && ! touch "$LOG_FILE" 2>/dev/null; then
  console "WARNING: Cannot write $LOG_FILE as UID $(id -u). Logging to the console instead."
  export LOG_FILE=""
fi

###########################################
## Check settings
###########################################
errors=()
[[ ${#names[@]} -eq 0 ]] && errors+=("Set CF_RECORD_NAME (IPv4) and/or CF_RECORD_NAME_V6 (IPv6).")
[[ -z "${CF_API_TOKEN:-}" ]] && errors+=("CF_API_TOKEN is not set.")
[[ -z "${CF_ZONE_ID:-}" ]] && errors+=("CF_ZONE_ID is not set.")
case "${CF_AUTH_METHOD:-token}" in
  token) ;;
  global) [[ -z "${CF_AUTH_EMAIL:-}" ]] && errors+=("CF_AUTH_EMAIL is required when CF_AUTH_METHOD=global.") ;;
  *) errors+=("CF_AUTH_METHOD must be 'token' or 'global'.") ;;
esac
# These values are used unquoted by the scripts, so only allow safe values
[[ "${CF_PROXY:-false}" =~ ^(true|false)$ ]] || errors+=("CF_PROXY must be 'true' or 'false'.")
[[ "${STATIC_IPV6_MODE:-false}" =~ ^(true|false)$ ]] || errors+=("STATIC_IPV6_MODE must be 'true' or 'false'.")
[[ "${CF_TTL:-3600}" =~ ^[0-9]+$ ]] || errors+=("CF_TTL must be a number of seconds (1 = automatic).")

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
if [[ ${#names[@]} -gt 0 ]] && ! supercronic -test "$crontab_file" >/dev/null 2>&1; then
  errors+=("Invalid DDNS_SCHEDULE '$schedule' (use 5m, 1h, 1d, or a cron expression).")
fi

if [[ ${#errors[@]} -gt 0 ]]; then
  for e in "${errors[@]}"; do
    console "CONFIG ERROR: $e"
  done
  console "Fix the settings in .env / compose.yaml, then run 'docker compose up -d'."
  exit 1
fi

###########################################
## Generate the config files the scripts read
###########################################
write_conf() {
  local file="$1" record_name="$2"
  {
    printf 'auth_email=%q\n' "${CF_AUTH_EMAIL:-}"
    printf 'auth_method=%q\n' "${CF_AUTH_METHOD:-token}"
    printf 'auth_key=%q\n' "$CF_API_TOKEN"
    printf 'zone_identifier=%q\n' "$CF_ZONE_ID"
    printf 'record_name=%q\n' "$record_name"
    printf 'ttl=%q\n' "${CF_TTL:-3600}"
    printf 'proxy=%q\n' "${CF_PROXY:-false}"
    printf 'sitename=%q\n' "${SITENAME:-}"
    printf 'slackchannel=%q\n' "${SLACK_CHANNEL:-}"
    printf 'slackuri=%q\n' "${SLACK_URI:-}"
    printf 'discorduri=%q\n' "${DISCORD_URI:-}"
  } > "$file"
}

umask 077
if [[ -n "${CF_RECORD_NAME:-}" ]]; then
  write_conf "$state_dir/cloudflare-ddns.conf" "$CF_RECORD_NAME"
fi
if [[ -n "${CF_RECORD_NAME_V6:-}" ]]; then
  write_conf "$state_dir/cloudflare-ddns-v6.conf" "$CF_RECORD_NAME_V6"
  {
    printf 'static_IPv6_mode=%q\n' "${STATIC_IPV6_MODE:-false}"
    printf 'last_notable_hexes=%q\n' "${LAST_NOTABLE_HEXES:-ffff:ffff}"
  } >> "$state_dir/cloudflare-ddns-v6.conf"
fi
umask 022

###########################################
## Run once, then hand over to the scheduler
###########################################
summary="Starting as UID $(id -u):$(id -g)"
[[ -n "${CF_RECORD_NAME:-}" ]] && summary+=", IPv4: $CF_RECORD_NAME"
[[ -n "${CF_RECORD_NAME_V6:-}" ]] && summary+=", IPv6: $CF_RECORD_NAME_V6"
summary+=", schedule '$cron_expr', logs: ${LOG_FILE:-console}"
console "$summary"
[[ -n "${LOG_FILE:-}" ]] && logger "entrypoint: $summary"

if [[ "$run_on_start" == "true" ]]; then
  for name in "${names[@]}"; do
    if run_job "$name"; then
      console "Initial run of $name.sh succeeded."
    else
      console "Initial run of $name.sh failed (exit $(cat "$state_dir/ddns-status-$name")). See ${LOG_FILE:-the output above}. It will run again on schedule."
    fi
  done
fi

# Full path: as PID 1, supercronic re-executes itself to reap child processes
exec /usr/bin/supercronic -quiet -passthrough-logs "$crontab_file"
