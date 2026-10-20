# syntax=docker/dockerfile:1
# Cloudflare DDNS updater: runs cloudflare-ddns.sh / cloudflare-ddns-v6.sh on a schedule.
# Settings come from environment variables (see .env.example); nothing secret is baked in.
FROM alpine:3.24

ARG VERSION=dev
LABEL org.opencontainers.image.title="cloudflare-ddns" \
      org.opencontainers.image.description="Cloudflare dynamic DNS updater (A/AAAA records) on a schedule" \
      org.opencontainers.image.source="https://github.com/Chaos-man/cloudflare-ddns-updater" \
      org.opencontainers.image.url="https://hub.docker.com/r/chaosmanorg/cloudflare-ddns" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${VERSION}"

# apk upgrade: pick up Alpine security fixes released after the base image was built
RUN apk upgrade --no-cache \
 && apk add --no-cache bash curl ca-certificates tzdata iproute2 supercronic su-exec

# No syslog daemon in the container; this logger writes to LOG_FILE (or the console)
COPY docker/logger /usr/local/bin/logger
COPY cloudflare-ddns.sh cloudflare-ddns-v6.sh docker/entrypoint.sh /app/

# The scripts' flock lock files live in /run/lock (/var/lock)
RUN chmod 755 /usr/local/bin/logger /app/*.sh \
 && chmod 1777 /run/lock \
 && mkdir -p /logs

# Defaults; override in .env. The entrypoint starts as root only to chown the log
# directory to PUID:PGID, then runs everything as PUID:PGID.
ENV DDNS_SCHEDULE=5m \
    RUN_ON_START=true \
    TZ=UTC \
    LOG_FILE=/logs/ddns.log \
    LOG_MAX_SIZE=1048576

HEALTHCHECK --interval=1m --timeout=10s --start-period=2m \
  CMD ["/app/entrypoint.sh", "healthcheck"]

ENTRYPOINT ["/app/entrypoint.sh"]
