# syntax=docker/dockerfile:1
# Cloudflare DDNS updater: runs cloudflare-ddns.sh / cloudflare-ddns-v6.sh on a schedule.
# Config files are mounted at runtime (see README.Docker.md); none are baked into the image.
FROM alpine:3.22

RUN apk add --no-cache bash curl ca-certificates tzdata iproute2 supercronic

# No syslog daemon in the container; this logger prints to stderr and optionally a file
COPY docker/logger /usr/local/bin/logger
COPY cloudflare-ddns.sh cloudflare-ddns-v6.sh docker/entrypoint.sh /app/

# Non-root user; the scripts' flock lock files live in /run/lock (/var/lock)
ARG UID=10001
RUN adduser -D -H -u "${UID}" -s /sbin/nologin ddns \
 && chmod 755 /usr/local/bin/logger /app/*.sh \
 && chmod 1777 /run/lock \
 && mkdir -p /config

USER ddns

ENV DDNS_RECORD=v4 \
    DDNS_SCHEDULE=5m \
    RUN_ON_START=true

HEALTHCHECK --interval=1m --timeout=10s --start-period=2m \
  CMD ["/app/entrypoint.sh", "healthcheck"]

ENTRYPOINT ["/app/entrypoint.sh"]
