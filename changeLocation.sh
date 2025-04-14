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
    exec >> "$LOGFILE" 2>&1
fi

echo "Script started at $(date)"

current_network=$(ipconfig getsummary en0 | awk -F ' SSID : '  '/ SSID : / {print $2}')
current_location=$(networksetup -getcurrentlocation)
echo "Current network: $current_network. Current location: $current_location"

while IFS= read -r location; do
    ssid=$(echo "$location" | jq -r '.ssid')
    locationName=$(echo "$location" | jq -r '.location')
    echo "Checking location: $locationName for ssid: $ssid" 
    if [[ "$ssid" == "$current_network" ]]; then
        if [[ "$current_location" == "$locationName" ]]; then
            echo "Matching location already set for ssid $ssid. Exiting."
            exit 0
        fi
        echo "Switching to location: $locationName for ssid $ssid"
        networksetup -switchtolocation "$locationName"
        echo "Location switched. Exiting."
        exit 0
    fi
done <<< "$KNOWN_LOCATIONS"


if [[ "$current_location" == "$DEFAULT_LOCATION" ]]; then
    echo "Already on default location. Exiting."
    exit 0
else
    echo "No known location for current ssid. Switching to default location: $DEFAULT_LOCATION"
    networksetup -switchtolocation "$DEFAULT_LOCATION"
    exit 0
fi