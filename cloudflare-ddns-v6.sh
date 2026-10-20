#!/bin/bash
## Updates a Cloudflare AAAA record with this host's IPv6 address.
## Usage: cloudflare-ddns-v6.sh [config file]
## Settings are read from the config file (see cloudflare-ddns-v6.conf.example). Lookup order:
##   1. First argument
##   2. $DDNS_CONFIG
##   3. cloudflare-ddns-v6.conf next to this script

################################################
## Load configuration
################################################
script_dir="$(cd "$(dirname "$0")" && pwd)"
config_file="${1:-${DDNS_CONFIG:-$script_dir/cloudflare-ddns-v6.conf}}"
log_header_name="DDNS Updater_v6"

if [[ ! -r "$config_file" ]]; then
    logger -s "$log_header_name: Config file $config_file not found or not readable."
    exit 1
fi
source "$config_file"

# Defaults for optional settings
auth_method="${auth_method:-token}"
ttl="${ttl:-3600}"
proxy="${proxy:-false}"
static_IPv6_mode="${static_IPv6_mode:-false}"
last_notable_hexes="${last_notable_hexes:-ffff:ffff}"
log_header_name="${log_header_name:-DDNS Updater_v6}"

# Exit if required settings are missing
for setting in auth_key zone_identifier record_name; do
    if [[ -z "${!setting}" ]]; then
        logger -s "$log_header_name: '$setting' is not set in $config_file."
        exit 1
    fi
done
if [[ "$auth_method" == "global" && -z "$auth_email" ]]; then
    logger -s "$log_header_name: 'auth_email' is required when auth_method is \"global\"."
    exit 1
fi

################################################
## Prevent overlapping runs
################################################
lock_file="/var/lock/cloudflare-ddns-v6.lock"
exec 9>"$lock_file" || { logger -s "$log_header_name: Unable to open lock file $lock_file."; exit 1; }
if ! flock -n 9; then
    logger -s "$log_header_name: Another instance is already running, exiting."
    exit 0
fi

# Timeouts and retries applied to every curl call
curl_opts=(--max-time 10 --retry 2)

################################################
## Make sure we have a valid IPv6 connection
################################################
if ! { curl "${curl_opts[@]}" -6 -s --head --fail https://ipv6.google.com >/dev/null; }; then
    logger -s "$log_header_name: Unable to establish a valid IPv6 connection to a known host."
    exit 1
fi

################################################
## Finding our IPv6 address
################################################
# Regex credits to https://stackoverflow.com/a/17871737
ipv6_regex="(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))"

if $static_IPv6_mode; then
    # Test whether 'ip' command is available
    if { command -v "ip" &>/dev/null; }; then
        ip=$(ip -6 -o addr show scope global primary -deprecated | grep -oE "$ipv6_regex" | grep -oE ".*($last_notable_hexes)$")
    else
        # Fall back to 'ifconfig' command
        ip=$(ifconfig | grep -oE "$ipv6_regex" | grep -oE ".*($last_notable_hexes)$")
    fi
else
    # Use external services to discover our system's preferred IPv6 address
    ip=$(curl "${curl_opts[@]}" -s -6 https://cloudflare.com/cdn-cgi/trace | grep -E '^ip')
    ret=$?
    if [[ ! $ret == 0 ]]; then # In the case that cloudflare failed to return an ip.
        # Attempt to get the ip from other websites.
        ip=$(curl "${curl_opts[@]}" -s -6 https://api64.ipify.org || curl "${curl_opts[@]}" -s -6 https://ipv6.icanhazip.com)
    else
        # Extract just the ip from the ip line from cloudflare.
        ip=$(echo $ip | sed -E "s/^ip=($ipv6_regex)$/\1/")
    fi
fi

# Check point: Make sure the collected IPv6 address is valid
if [[ ! $ip =~ ^$ipv6_regex$ ]]; then
    logger -s "$log_header_name: Failed to find a valid IPv6 address."
    exit 1
fi

################################################
## Check and set the proper auth header
################################################
if [[ "${auth_method}" == "global" ]]; then
    auth_header="X-Auth-Key:"
else
    auth_header="Authorization: Bearer"
fi

################################################
## Seek for the AAAA record
################################################
logger "$log_header_name: Check Initiated"
record=$(curl "${curl_opts[@]}" -s -X GET "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records?type=AAAA&name=$record_name" \
    -H "X-Auth-Email: $auth_email" \
    -H "$auth_header $auth_key" \
    -H "Content-Type: application/json")
lookup_status=$?

# Exit if the lookup failed or Cloudflare did not report success
if [[ $lookup_status -ne 0 || -z "$record" || $record != *"\"success\":true"* ]]; then
    logger -s "$log_header_name: Record lookup failed for ${record_name} (curl exit ${lookup_status}). Response: ${record}"
    exit 1
fi

################################################
## Check if the domain has an AAAA record
################################################
if [[ $record == *"\"count\":0"* ]]; then
    logger -s "$log_header_name: Record does not exist, perhaps create one first? (${ip} for ${record_name})"
    exit 1
fi

################################################
## Get existing IP
################################################
old_ip=$(echo "$record" | sed -E 's/.*"content":"'${ipv6_regex}'".*/\1/')

# Make sure the extracted IPv6 address is valid
if [[ ! $old_ip =~ ^$ipv6_regex$ ]]; then
    logger -s "$log_header_name: Unable to extract existing IPv6 address from DNS record."
    exit 1
fi

# Compare if they're the same
if [[ $ip == $old_ip ]]; then
    logger "$log_header_name: IP ($ip) for ${record_name} has not changed."
    exit 0
fi

################################################
## Set the record identifier from result
################################################
record_identifier=$(echo "$record" | sed -E 's/.*"id":"([A-Za-z0-9_]+)".*/\1/')

# Exit if either value is empty or sed found no match (returns the whole record)
if [[ -z "$old_ip" || -z "$record_identifier" || "$record_identifier" == "$record" ]]; then
    logger -s "$log_header_name: Unable to extract record ID for ${record_name}, not updating."
    exit 1
fi

################################################
## Change the IP@Cloudflare using the API
################################################
update=$(curl "${curl_opts[@]}" -s -X PATCH "https://api.cloudflare.com/client/v4/zones/$zone_identifier/dns_records/$record_identifier" \
    -H "X-Auth-Email: $auth_email" \
    -H "$auth_header $auth_key" \
    -H "Content-Type: application/json" \
    --data "{\"content\":\"$ip\",\"ttl\":$ttl,\"proxied\":$proxy}")
update_status=$?

################################################
## Report the status
################################################
# Only an explicit success counts; an empty or malformed response is a failure
case "$update" in
*"\"success\":true"*)
    logger "$log_header_name: $ip $record_name DDNS updated."
    if [[ $slackuri != "" ]]; then
        curl "${curl_opts[@]}" -L -X POST $slackuri \
            --data-raw "{
                \"channel\": \"$slackchannel\",
                \"text\": \"$sitename Updated: $record_name's new IPv6 Address is $ip\"
            }"
    fi
    if [[ $discorduri != "" ]]; then
        curl "${curl_opts[@]}" -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
            --data-raw "{
                \"content\": \"$sitename Updated: $record_name's new IPv6 Address is $ip\"
            }" $discorduri
    fi
    exit 0
    ;;
*)
    echo -e "$log_header_name: $ip $record_name DDNS failed for $record_identifier ($ip) (curl exit $update_status). DUMPING RESULTS:\n$update" | logger -s
    if [[ $slackuri != "" ]]; then
        curl "${curl_opts[@]}" -L -X POST $slackuri \
            --data-raw "{
                \"channel\": \"$slackchannel\",
                \"text\": \"$sitename DDNS Update Failed: $record_name: $record_identifier ($ip).\"
            }"
    fi
    if [[ $discorduri != "" ]]; then
        curl "${curl_opts[@]}" -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST \
            --data-raw "{
                \"content\": \"$sitename DDNS Update Failed: $record_name: $record_identifier ($ip).\"
            }" $discorduri
    fi
    exit 1
    ;;
esac
