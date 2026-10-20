# Cloudflare Dynamic DNS IP Updater
<img alt="GitHub" src="https://img.shields.io/github/license/Chaos-man/cloudflare-ddns-updater?color=black"> <img alt="GitHub last commit (branch)" src="https://img.shields.io/github/last-commit/Chaos-man/cloudflare-ddns-updater/docker"> <img alt="GitHub contributors" src="https://img.shields.io/github/contributors/Chaos-man/cloudflare-ddns-updater">

This script is used to update Dynamic DNS (DDNS) service based on Cloudflare! Access your home network remotely via a custom domain name without a static IP! Written in pure BASH.

This is a fork of [K0p1-Git/cloudflare-ddns-updater](https://github.com/K0p1-Git/cloudflare-ddns-updater), packaged as a Docker container configured with environment variables, with hardening against overlapping runs and failed API calls.

## Support the Original Creator
[![Donate Via Paypal](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.me/Jasonkkf)

## How it works

The container runs `cloudflare-ddns.sh` (A record, IPv4) and/or `cloudflare-ddns-v6.sh` (AAAA record, IPv6) on a schedule, every 5 minutes by default. Each run looks up your public IP and updates the Cloudflare record when it has changed, optionally notifying Discord or Slack.

The record must already exist in Cloudflare; the scripts update it, they don't create it.

## Quick start

The image is on Docker Hub as [`chaosmanorg/cloudflare-ddns`](https://hub.docker.com/r/chaosmanorg/cloudflare-ddns) (amd64 and arm64).

```bash
mkdir cloudflare-ddns && cd cloudflare-ddns
curl -fsSLO https://raw.githubusercontent.com/Chaos-man/cloudflare-ddns-updater/docker/compose.yaml
curl -fsSL https://raw.githubusercontent.com/Chaos-man/cloudflare-ddns-updater/docker/.env.example -o .env
chmod 600 .env
nano .env                      # PUID/PGID, CF_API_TOKEN, CF_ZONE_ID, CF_RECORD_NAME
docker compose up -d
tail -f logs/ddns.log
```

See [README.Docker.md](README.Docker.md) for all settings, IPv6, logs, health and troubleshooting.

## Tests

`tests/notify-test.sh` checks the scripts' Discord/Slack notification handling (sent, HTTP errors, connection failures, valid JSON, exit codes). It runs the scripts in a throwaway Alpine container with stand-ins for `curl` and `logger`, so nothing real is contacted. Requires Docker:

```bash
tests/notify-test.sh
```

## Tested Environments (original scripts, without Docker):
macOS Mojave version 10.14.6 (x86_64) <br />
AlmaLinux 9.3 (Linux kernel: 5.14.0 | x86_64) <br />
Debian Bullseye 11 (Linux kernel: 6.1.28 | aarch64) <br />

## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## Reference
This script was made with reference from [Keld Norman](https://www.youtube.com/watch?v=vSIBkH7sxos) video.

## License
[MIT](https://github.com/Chaos-man/cloudflare-ddns-updater/blob/main/LICENSE)
