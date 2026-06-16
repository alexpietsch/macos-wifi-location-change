#!/bin/bash

SCRIPTPATH="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
LOGFILE="$SCRIPTPATH/changeLocation.log"
CONFIG_FILE="$SCRIPTPATH/config.json"

# Delete log file if it is larger than 1MB
find $LOGFILE -size +1M -delete

# Read config.json
ENABLE_LOGS=$(jq -r '.ENABLE_LOGFILE' "$CONFIG_FILE")
KNOWN_LOCATIONS=$(jq -c '.KNOWN_LOCATIONS[]' "$CONFIG_FILE")
DEFAULT_LOCATION=$(jq -r '.DEFAULT_LOCATION' "$CONFIG_FILE")

if [[ "$ENABLE_LOGS" == true ]]; then
    exec > >(while IFS= read -r line; do echo "[$(date '+%Y-%m-%d %H:%M:%S')] $line"; done >> "$LOGFILE") 2>&1
fi

echo "Script started at $(date)"

get_wifi_interface() {
    networksetup -listallhardwareports | awk '
        /^Hardware Port: (Wi-Fi|AirPort)$/ { found=1; next }
        found && /^Device: / { print $2; exit }
    '
}

get_current_ssid() {
    local wifi_iface="$1"
    local ssid

    if [[ -z "$wifi_iface" ]]; then
        return
    fi

    ssid=$(ipconfig getsummary "$wifi_iface" | awk -F ' SSID : ' '/ SSID : / {print $2}')
    ssid="${ssid%"${ssid##*[![:space:]]}"}"

    if [[ -z "$ssid" || "$ssid" == "<redacted>" ]]; then
        ssid=$(networksetup -getairportnetwork "$wifi_iface" 2>/dev/null | awk -F ': ' '/Current Wi-Fi Network:/{print $2}')
        ssid="${ssid%"${ssid##*[![:space:]]}"}"
    fi

    if [[ "$ssid" == "You are not associated with an AirPort network." ]]; then
        ssid=""
    fi

    echo "$ssid"
}

list_network_services() {
    networksetup -listallnetworkservices | tail -n +2 | grep -v '^\*'
}

get_location_dns_servers() {
    local config_dns_json="$1"
    local -a servers=()

    if [[ -n "$config_dns_json" && "$config_dns_json" != "null" ]]; then
        while IFS= read -r ip; do
            [[ -n "$ip" ]] && servers+=("$ip")
        done < <(echo "$config_dns_json" | jq -r '.[]')
    else
        while IFS= read -r service; do
            [[ -z "$service" ]] && continue
            local output
            output=$(networksetup -getdnsservers "$service" 2>/dev/null)
            if [[ "$output" != *"There aren't any"* && "$output" != *"Empty"* ]]; then
                while IFS= read -r ip; do
                    [[ -n "$ip" ]] && servers+=("$ip")
                done <<< "$output"
            fi
        done < <(list_network_services)
    fi

    if [[ ${#servers[@]} -eq 0 ]]; then
        return 0
    fi

    printf '%s\n' "${servers[@]}" | sort -u
}

read_service_dns_servers() {
    local service="$1"
    local output

    output=$(networksetup -getdnsservers "$service" 2>/dev/null)
    if [[ "$output" == *"There aren't any"* || "$output" == *"Empty"* ]]; then
        return 0
    fi

    printf '%s\n' "$output"
}

dns_server_sets_match() {
    local actual sorted_actual sorted_expected

    actual=$(printf '%s\n' "$@" | sort -u)
    sorted_actual=$(echo "$actual" | sort)
    sorted_expected=$(echo "$EXPECTED_DNS_SORTED" | sort)

    [[ "$sorted_actual" == "$sorted_expected" ]]
}

service_dns_is_correct() {
    local service="$1"
    local -a actual=()

    while IFS= read -r ip; do
        [[ -n "$ip" ]] && actual+=("$ip")
    done < <(read_service_dns_servers "$service")

    if [[ ${#actual[@]} -eq 0 ]]; then
        return 1
    fi

    dns_server_sets_match "${actual[@]}"
}

resolver_dns_is_correct() {
    local resolver_ips

    resolver_ips=$(scutil --dns 2>/dev/null | grep 'nameserver\[' | awk '{print $3}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' | sort -u)
    while IFS= read -r expected; do
        [[ -z "$expected" ]] && continue
        echo "$resolver_ips" | grep -qxF "$expected" || return 1
    done <<< "$EXPECTED_DNS_SORTED"
}

all_services_dns_correct() {
    local service

    while IFS= read -r service; do
        [[ -z "$service" ]] && continue
        service_dns_is_correct "$service" || return 1
    done < <(list_network_services)

    return 0
}

apply_dns_to_services() {
    local -a servers=()
    local service

    while IFS= read -r ip; do
        [[ -n "$ip" ]] && servers+=("$ip")
    done <<< "$EXPECTED_DNS_SORTED"

    if [[ ${#servers[@]} -eq 0 ]]; then
        echo "No DNS servers available to apply"
        return 1
    fi

    while IFS= read -r service; do
        [[ -z "$service" ]] && continue
        if service_dns_is_correct "$service"; then
            echo "DNS already configured on $service"
            continue
        fi
        echo "Applying DNS to $service: ${servers[*]}"
        networksetup -setdnsservers "$service" "${servers[@]}"
    done < <(list_network_services)
}

ensure_location() {
    local target_location="$1"
    local config_dns_json="$2"
    local active_location

    active_location=$(networksetup -getcurrentlocation)
    if [[ "$active_location" != "$target_location" ]]; then
        echo "Switching to location: $target_location"
        networksetup -switchtolocation "$target_location"
    else
        echo "Already on location: $target_location"
    fi

    EXPECTED_DNS_SORTED=$(get_location_dns_servers "$config_dns_json")
    if [[ -z "$EXPECTED_DNS_SORTED" ]]; then
        echo "No DNS servers configured for location $target_location"
        return 0
    fi

    echo "Expected DNS: $(echo "$EXPECTED_DNS_SORTED" | tr '\n' ' ')"

    if all_services_dns_correct && resolver_dns_is_correct; then
        echo "DNS already correct for location $target_location. Exiting."
        return 0
    fi

    apply_dns_to_services
}

wifi_iface=$(get_wifi_interface)
current_network=$(get_current_ssid "$wifi_iface")
current_gateway=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')
current_location=$(networksetup -getcurrentlocation)
echo "Current network: ${current_network:-<none>}. Gateway: ${current_gateway:-<none>}. Current location: $current_location"

while IFS= read -r location; do
    ssid=$(echo "$location" | jq -r '.ssid // empty')
    gateway=$(echo "$location" | jq -r '.gateway // empty')
    locationName=$(echo "$location" | jq -r '.location')
    config_dns=$(echo "$location" | jq -c '.dns // empty')
    echo "Checking location: $locationName for ssid: ${ssid:-<none>} gateway: ${gateway:-<none>}"

    matched=false
    match_reason=""

    if [[ -n "$ssid" && "$ssid" == "$current_network" ]]; then
        matched=true
        match_reason="ssid $ssid"
    elif [[ -n "$gateway" && "$gateway" == "$current_gateway" ]]; then
        matched=true
        match_reason="gateway $gateway"
    fi

    if [[ "$matched" == true ]]; then
        echo "Matched location: $locationName ($match_reason)"
        ensure_location "$locationName" "$config_dns"
        echo "Done. Exiting."
        exit 0
    fi
done <<< "$KNOWN_LOCATIONS"


if [[ "$current_location" == "$DEFAULT_LOCATION" ]]; then
    echo "Already on default location. Exiting."
    exit 0
else
    echo "No known location for current network. Switching to default location: $DEFAULT_LOCATION"
    networksetup -switchtolocation "$DEFAULT_LOCATION"
    exit 0
fi
