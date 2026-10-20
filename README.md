# Cloudflare Dynamic DNS IP Updater
<img alt="GitHub" src="https://img.shields.io/github/license/K0p1-Git/cloudflare-ddns-updater?color=black"> <img alt="GitHub last commit (branch)" src="https://img.shields.io/github/last-commit/K0p1-Git/cloudflare-ddns-updater/main"> <img alt="GitHub contributors" src="https://img.shields.io/github/contributors/K0p1-Git/cloudflare-ddns-updater">

This script is used to update Dynamic DNS (DDNS) service based on Cloudflare! Access your home network remotely via a custom domain name without a static IP! Written in pure BASH.

## Support Me
[![Donate Via Paypal](https://www.paypalobjects.com/en_US/i/btn/btn_donateCC_LG.gif)](https://www.paypal.me/Jasonkkf)

## Scripts

| Script | Record | Config file |
|---|---|---|
| `cloudflare-ddns.sh` | A (IPv4) | `cloudflare-ddns.conf` |
| `cloudflare-ddns-v6.sh` | AAAA (IPv6) | `cloudflare-ddns-v6.conf` |

The record must already exist in Cloudflare; the scripts update it, they don't create it.

## Installation

```bash
git clone https://github.com/Chaos-man/cloudflare-ddns-updater.git
cd cloudflare-ddns-updater
```

Requires `bash`, `curl`, `flock` (util-linux) and `logger`.

## Configuration

Settings live in a config file, not in the scripts. Copy the example and fill it in:

```bash
cp cloudflare-ddns.conf.example cloudflare-ddns.conf
chmod 600 cloudflare-ddns.conf   # it holds your API token
nano cloudflare-ddns.conf
```

Do the same with `cloudflare-ddns-v6.conf.example` for IPv6. Required settings are `auth_key`, `zone_identifier` and `record_name` (plus `auth_email` when `auth_method="global"`). The example files document every setting.

Real `*.conf` files are in `.gitignore`, so `git pull` never overwrites them and they can't be committed by accident.

The script looks for its config in this order:
1. The first argument: `./cloudflare-ddns.sh /path/to/my.conf`
2. The `DDNS_CONFIG` environment variable
3. `cloudflare-ddns.conf` (or `cloudflare-ddns-v6.conf`) in the same directory as the script

The config file is sourced by bash, so it uses shell syntax and runs as code; keep it owned by the user running the script.

## Usage
Run it once by hand to check the config:

```bash
/bin/bash /path/to/cloudflare-ddns.sh
```

Then schedule it with crontab (`crontab -e`). Every 5 minutes is a good default:

```bash
MAILTO=""
*/5 * * * * /bin/bash /path/to/cloudflare-ddns-updater/cloudflare-ddns.sh
```

Each script holds a lock (`/var/lock/cloudflare-ddns.lock` or `/var/lock/cloudflare-ddns-v6.lock`) so overlapping runs exit instead of piling up. The user running the script needs write access to `/var/lock`.

Crontab field reference:

```bash
# ┌───────────── minute (0 - 59)
# │ ┌───────────── hour (0 - 23)
# │ │ ┌───────────── day of the month (1 - 31)
# │ │ │ ┌───────────── month (1 - 12)
# │ │ │ │ ┌───────────── day of the week (0 - 6) (Sunday to Saturday 7 is also Sunday on some systems)
# │ │ │ │ │ ┌───────────── command to issue                               
# │ │ │ │ │ │
# │ │ │ │ │ │
# * * * * * /bin/bash {Location of the script}
```

Logs go to syslog and stderr via `logger -s` (view with `journalctl -t root` or `grep "DDNS Updater" /var/log/syslog`, depending on the system).

## Migrating from `cloudflare.sh`
Older versions kept settings inside a copy of `cloudflare-template.sh` (usually `cloudflare.sh`). To migrate:
1. `git pull`
2. Create `cloudflare-ddns.conf` from the example and copy your values over from `cloudflare.sh`.
3. Point crontab at `cloudflare-ddns.sh` instead of `cloudflare.sh`.
4. Run it once by hand, then delete `cloudflare.sh`.

## Tested Environments:
macOS Mojave version 10.14.6 (x86_64) <br />
AlmaLinux 9.3 (Linux kernel: 5.14.0 | x86_64) <br />
Debian Bullseye 11 (Linux kernel: 6.1.28 | aarch64) <br />

## Contributing
Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

## Reference
This script was made with reference from [Keld Norman](https://www.youtube.com/watch?v=vSIBkH7sxos) video.

## License
[MIT](https://github.com/K0p1-Git/cloudflare-ddns-updater/blob/main/LICENSE)
