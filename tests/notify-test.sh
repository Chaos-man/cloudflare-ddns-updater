#!/bin/bash
## Notification tests for cloudflare-ddns.sh and cloudflare-ddns-v6.sh.
## Runs each script in a small Alpine container with stand-ins for curl and logger: the IP
## services, the Cloudflare API and the Discord/Slack webhooks are faked, so nothing real is
## contacted. Checks that webhook results (sent / HTTP error / connection failure) are logged,
## that payloads are valid JSON, and that the scripts' exit codes are unchanged.
## Requires Docker. Usage: tests/notify-test.sh
set -u
export MSYS_NO_PATHCONV=1   # Git Bash on Windows: don't rewrite container paths

tests_dir="$(cd "$(dirname "$0")" && pwd)"
repo_dir="$(dirname "$tests_dir")"
# Docker on Windows needs a Windows-style path for bind mounts
if pwd -W >/dev/null 2>&1; then
  tests_dir="$(cd "$tests_dir" && pwd -W)"; repo_dir="$(cd "$repo_dir" && pwd -W)"
fi
image=ddns-notifytest

docker build -q -t "$image" - >/dev/null <<'DOCKERFILE' || { echo "Failed to build the test image." >&2; exit 1; }
FROM alpine:3.22
RUN apk add --no-cache bash jq
DOCKERFILE

# Runs inside the container: script under test, then a JSON check of each webhook payload
inner='
/repo/$SCRIPT.sh /tests/test.conf; echo "EXIT=$?"
echo "--- payloads"
while read -r u p; do
  printf "%s\n" "$p" > /tmp/p.json
  echo "$u json-valid=$(jq -e . /tmp/p.json >/dev/null 2>&1 && echo yes || echo no)"
done < /tmp/webhook-calls 2>/dev/null'

pass=0 fail=0
run_case() {  # script webhook_mode patch_mode expected_exit expect_regex...
  local script="$1" mode="$2" patch="$3" want_exit="$4"; shift 4
  local out ok=1
  out=$(docker run --rm -e SCRIPT="$script" -e WEBHOOK_MODE="$mode" -e PATCH_MODE="$patch" \
    -v "$repo_dir:/repo:ro" -v "$tests_dir:/tests:ro" \
    -v "$tests_dir/fake-curl:/usr/local/bin/curl:ro" -v "$tests_dir/fake-logger:/usr/local/bin/logger:ro" \
    "$image" bash -c "$inner" 2>&1)
  [[ "$out" == *"EXIT=$want_exit"* ]] || { ok=0; echo "    expected exit $want_exit"; }
  for re in "$@"; do
    grep -qE -- "$re" <<< "$out" || { ok=0; echo "    missing: $re"; }
  done
  if [[ $ok -eq 1 ]]; then
    pass=$((pass + 1)); echo "PASS $script webhook=$mode update=$patch"
  else
    fail=$((fail + 1)); echo "FAIL $script webhook=$mode update=$patch"; sed 's/^/      | /' <<< "$out" | tail -8
  fi
}

for s in cloudflare-ddns cloudflare-ddns-v6; do
  run_case $s 204  ok   0 "Discord notification sent" "Slack notification sent"
  run_case $s 401  ok   0 "Discord notification failed \(HTTP 401\)" "Slack notification failed \(HTTP 401\)"
  run_case $s 500  ok   0 "Discord notification failed \(HTTP 500\)" "Slack notification failed \(HTTP 500\)"
  run_case $s conn ok   0 "Discord notification failed \(curl exit 7\)" "Slack notification failed \(curl exit 7\)"
  run_case $s 401  fail 1 "DDNS failed" "Discord notification failed \(HTTP 401\)" "Slack notification failed \(HTTP 401\)"
  run_case $s 204  ok   0 "discord.test.* json-valid=yes" "slack.test.* json-valid=yes"
done

echo
echo "passed: $pass  failed: $fail"
[[ $fail -eq 0 ]]
