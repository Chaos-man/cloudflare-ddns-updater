#!/bin/bash
## Sets up cloudflare-ddns: creates config files from the examples, checks they have been
## filled in, test-runs the script(s), and installs a cron job for the current user.
## Run once to create the config, edit it, then run again to finish.

set -u

usage() {
  cat <<'EOF'
Usage: setup.sh [options]

First run creates the config file(s) from the examples (existing files are never
overwritten). Edit them, then run again to test the script(s) and install cron.

Options:
  -r, --record v4|v6|both   Which script(s) to set up (default: ask)
  -s, --schedule SCHEDULE   5m, 1h, 1d, none, or a quoted cron expression such as
                            "*/15 * * * *" (default: ask)
  -n, --no-test             Install the cron job without a test run
  -q, --quiet               No prompts and no output on success; requires
                            --record and --schedule. Errors go to stderr.
  -h, --help                Show this help

Exit codes: 0 done, 1 error, 2 config file(s) created and need editing.

Examples:
  ./setup.sh
  ./setup.sh --record v4 --schedule 5m --quiet
  ./setup.sh -r both -s "*/10 * * * *" --no-test
EOF
}

say() { $quiet || echo "$*"; }
err() { echo "setup.sh: $*" >&2; }

script_dir="$(cd "$(dirname "$0")" && pwd)"
record=""
schedule=""
run_test=true
quiet=false

###########################################
## Parse options
###########################################
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--record)   record="${2:-}"; shift 2 || { err "$1 needs a value."; exit 1; } ;;
    -s|--schedule) schedule="${2:-}"; shift 2 || { err "$1 needs a value."; exit 1; } ;;
    -n|--no-test)  run_test=false; shift ;;
    -q|--quiet)    quiet=true; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             err "Unknown option: $1"; usage >&2; exit 1 ;;
  esac
done

if $quiet && [[ -z "$record" || -z "$schedule" ]]; then
  err "--quiet requires --record and --schedule."
  exit 1
fi

###########################################
## Choose which script(s) to set up
###########################################
if [[ -z "$record" ]]; then
  echo "Which record(s) do you want to keep updated?"
  echo "  1) IPv4 (A record)"
  echo "  2) IPv6 (AAAA record)"
  echo "  3) Both"
  read -r -p "Choice [1]: " choice
  case "${choice:-1}" in
    1) record="v4" ;;
    2) record="v6" ;;
    3) record="both" ;;
    *) err "Invalid choice: $choice"; exit 1 ;;
  esac
fi

case "$record" in
  v4)   names=(cloudflare-ddns) ;;
  v6)   names=(cloudflare-ddns-v6) ;;
  both) names=(cloudflare-ddns cloudflare-ddns-v6) ;;
  *)    err "Invalid --record '$record' (use v4, v6 or both)."; exit 1 ;;
esac

###########################################
## Resolve the cron schedule (validated before any changes are made)
###########################################
resolve_schedule() {
  case "$1" in
    5m)   cron_expr="*/5 * * * *" ;;
    1h)   cron_expr="0 * * * *" ;;
    1d)   cron_expr="0 0 * * *" ;;
    none) cron_expr="" ;;
    @*)   cron_expr="$1" ;;
    *)
      local fields
      read -ra fields <<< "$1"
      if [[ ${#fields[@]} -ne 5 ]]; then
        err "Invalid schedule '$1' (use 5m, 1h, 1d, none, or a 5-field cron expression)."
        return 1
      fi
      cron_expr="$1" ;;
  esac
}

if [[ -n "$schedule" ]]; then
  resolve_schedule "$schedule" || exit 1
fi

###########################################
## Step 1: Create config files (never overwrite)
###########################################
created=()
for name in "${names[@]}"; do
  conf="$script_dir/$name.conf"
  example="$conf.example"
  if [[ -e "$conf" ]]; then
    say "Found $name.conf, leaving it unchanged."
  else
    if ! cp "$example" "$conf" || ! chmod 600 "$conf"; then
      err "Could not create $conf from $example."
      exit 1
    fi
    created+=("$conf")
  fi
done

if [[ ${#created[@]} -gt 0 ]]; then
  # Always shown, even with --quiet: setup can't finish until these are edited
  for conf in "${created[@]}"; do
    echo "Created $conf from the example (permissions 600)." >&2
  done
  echo "Edit the new config file(s), then run setup.sh again to test and install the cron job." >&2
  exit 2
fi

###########################################
## Step 2: Check the config files were filled in
###########################################
config_ok=true
for name in "${names[@]}"; do
  conf="$script_dir/$name.conf"
  if cmp -s "$conf" "$conf.example"; then
    err "$name.conf is unchanged from the example. Edit it first."
    config_ok=false
    continue
  fi
  missing=$(
    source "$conf" >/dev/null 2>&1
    for setting in auth_key zone_identifier record_name; do
      [[ -z "${!setting:-}" ]] && printf '%s ' "$setting"
    done
    [[ "${auth_method:-token}" == "global" && -z "${auth_email:-}" ]] && printf '%s ' "auth_email"
  )
  if [[ -n "$missing" ]]; then
    err "$name.conf is missing: ${missing% }"
    config_ok=false
  else
    say "$name.conf looks complete."
  fi
done
$config_ok || exit 1

###########################################
## Step 3: Test run
###########################################
if $run_test; then
  for name in "${names[@]}"; do
    say "Test run: $name.sh"
    if $quiet; then
      output=$(/bin/bash "$script_dir/$name.sh" "$script_dir/$name.conf" 2>&1)
      status=$?
    else
      /bin/bash "$script_dir/$name.sh" "$script_dir/$name.conf"
      status=$?
    fi
    if [[ $status -ne 0 ]]; then
      $quiet && echo "$output" >&2
      err "Test run of $name.sh failed (exit $status). Cron job not installed. Fix the problem, or use --no-test to install anyway."
      exit 1
    fi
    say "Test run of $name.sh succeeded."
  done
else
  say "Skipping test run (--no-test)."
fi

###########################################
## Step 4: Install the cron job (no duplicates)
###########################################
if [[ -z "$schedule" ]]; then
  echo "How often should the update run?"
  echo "  1) Every 5 minutes (recommended)"
  echo "  2) Every hour"
  echo "  3) Every day (midnight)"
  echo "  4) Custom cron expression"
  echo "  5) Don't install a cron job"
  read -r -p "Choice [1]: " choice
  case "${choice:-1}" in
    1) schedule="5m" ;;
    2) schedule="1h" ;;
    3) schedule="1d" ;;
    4) read -r -p "Cron expression (e.g. */15 * * * *): " schedule ;;
    5) schedule="none" ;;
    *) err "Invalid choice: $choice"; exit 1 ;;
  esac
  resolve_schedule "$schedule" || exit 1
fi

if [[ -z "$cron_expr" ]]; then
  say "No cron job installed. Setup complete."
  exit 0
fi

if ! command -v crontab >/dev/null 2>&1; then
  err "crontab not found. Install cron, or rerun with --schedule none."
  exit 1
fi

current_tab="$(crontab -l 2>/dev/null)"
new_tab="$current_tab"
changed=false

for name in "${names[@]}"; do
  script="$script_dir/$name.sh"
  line="$cron_expr /bin/bash \"$script\" \"$script_dir/$name.conf\" >/dev/null 2>&1"
  if grep -qxF -- "$line" <<< "$new_tab"; then
    say "Cron job for $name.sh is already installed."
    continue
  fi
  if grep -qF -- "$script" <<< "$new_tab"; then
    say "Replacing the existing cron job for $name.sh."
    new_tab="$(grep -vF -- "$script" <<< "$new_tab")"
  fi
  new_tab="${new_tab:+$new_tab$'\n'}$line"
  changed=true
  say "Added cron job: $line"
done

if $changed; then
  if ! printf '%s\n' "$new_tab" | crontab -; then
    err "Failed to write the crontab."
    exit 1
  fi
fi

# The pre-config-split script would run alongside the new one
if grep -qE '/cloudflare\.sh([[:space:]]|$)' <<< "$new_tab"; then
  err "Warning: your crontab still runs the old cloudflare.sh. Remove that line with 'crontab -e'."
fi

say "Setup complete."
