#!/bin/bash

# ==============================================================================
# Script Name : connect_wifi_profile.sh
# Description : Connect to a Wi-Fi SSID using NetworkManager.
#               If the NetworkManager profile is missing, recreate it from
#               wifi_profiles.ini located in the same directory.
#
# Version     : 1.6
# Author      : Pascal
# Date        : 2026-09-16
#
# Environment : Raspberry Pi
#               Debian Trixie (arm64 / armhf)
#               NetworkManager + nmcli
#
# Usage:
#   sudo ./connect_wifi_profile.sh --ssid "Livebox-D330"
#   sudo ./connect_wifi_profile.sh --ssid "iPhone P"
#
# wifi_profiles.ini:
#
#   [Livebox-D330]
#   password=your_password
#
#   [iPhone P]
#   password=your_password|with|pipes
# ==============================================================================

set -euo pipefail


# ------------------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------------------

timeout=15

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
profiles_file="${script_dir}/wifi_profiles.ini"


# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage:
  sudo $0 --ssid "SSID"

Options:
  --ssid "SSID"    Wi-Fi SSID to connect to
  -h, --help       Show this help

Examples:
  sudo $0 --ssid "Livebox-D330"
  sudo $0 --ssid "iPhone P"
EOF
}


# ------------------------------------------------------------------------------
# Parse arguments
# ------------------------------------------------------------------------------

ssid=""

while [[ $# -gt 0 ]]; do
    case "$1" in

        --ssid)
            if [[ $# -lt 2 ]]; then
                echo "❌ Missing value for --ssid."
                usage
                exit 2
            fi

            ssid="$2"
            shift 2
            ;;

        -h|--help)
            usage
            exit 0
            ;;

        *)
            echo "❌ Unknown argument: $1"
            usage
            exit 2
            ;;

    esac
done


# ------------------------------------------------------------------------------
# Validate SSID
# ------------------------------------------------------------------------------

if [[ -z "$ssid" ]]; then
    echo "❌ No SSID specified."
    echo
    usage
    exit 2
fi


echo "📡 Checking Wi-Fi: $ssid ..."


# ------------------------------------------------------------------------------
# Helper: Check NetworkManager
# ------------------------------------------------------------------------------

nm_running() {
    systemctl is-active --quiet NetworkManager
}


# ------------------------------------------------------------------------------
# Ensure NetworkManager is running
# ------------------------------------------------------------------------------

if ! nm_running; then
    echo "⚠️  NetworkManager is not running. Trying to start it..."

    if sudo systemctl start NetworkManager; then

        for i in {1..12}; do
            if nm_running; then
                break
            fi
            sleep 1
        done
    fi
fi


if ! nm_running; then
    echo "❌ NetworkManager failed to start. Exiting."
    exit 1
fi

echo "✅ NetworkManager is running."


# ------------------------------------------------------------------------------
# 1) Check current NetworkManager connection
# ------------------------------------------------------------------------------

active_connection="$(
    nmcli -t -f DEVICE,TYPE,STATE,CONNECTION device 2>/dev/null \
    | awk -F: '$2 == "wifi" && $3 == "connected" {print $4; exit}'
)"

if [[ "$active_connection" == "$ssid" ]]; then
    echo "✅ Already connected to $ssid"
    echo "🏁 Done!"
    exit 0
fi


# ------------------------------------------------------------------------------
# 2) Check the actual wireless interface using iwconfig
#
#    This is important because nmcli wifi list may not show the currently
#    associated network, while iwconfig reports the actual ESSID.
# ------------------------------------------------------------------------------

if command -v iwconfig >/dev/null 2>&1; then

    current_essid="$(
        iwconfig wlan0 2>/dev/null \
        | sed -n 's/.*ESSID:"\([^"]*\)".*/\1/p'
    )"

    if [[ "$current_essid" == "$ssid" ]]; then
        echo "✅ wlan0 is already associated with $ssid"
        echo "🏁 Done!"
        exit 0
    fi

fi


# ------------------------------------------------------------------------------
# 3) Check whether the SSID is currently visible
# ------------------------------------------------------------------------------

echo "🔍 Checking for broadcasted SSID: $ssid ..."

found_broadcast=false

if nmcli -t -f SSID device wifi list 2>/dev/null \
    | grep -Fqx "$ssid"; then

    found_broadcast=true
fi


# ------------------------------------------------------------------------------
# 4) If not found, request a rescan
# ------------------------------------------------------------------------------

if ! $found_broadcast; then

    echo "🔄 SSID not currently visible. Requesting Wi-Fi rescan..."

    if ! sudo nmcli device wifi rescan 2>/dev/null; then
        echo "⚠️  Wi-Fi rescan failed or is not supported."
    fi

    sleep 3

    for i in $(seq 1 "$timeout"); do

        if nmcli -t -f SSID device wifi list 2>/dev/null \
            | grep -Fqx "$ssid"; then

            found_broadcast=true
            break
        fi

        sleep 1
    done
fi


# ------------------------------------------------------------------------------
# 5) Check again using iwconfig after the scan
# ------------------------------------------------------------------------------

if ! $found_broadcast && command -v iwconfig >/dev/null 2>&1; then

    current_essid="$(
        iwconfig wlan0 2>/dev/null \
        | sed -n 's/.*ESSID:"\([^"]*\)".*/\1/p'
    )"

    if [[ "$current_essid" == "$ssid" ]]; then
        echo "✅ wlan0 is associated with $ssid"
        echo "🏁 Done!"
        exit 0
    fi
fi


# ------------------------------------------------------------------------------
# 6) SSID still unavailable
# ------------------------------------------------------------------------------

if ! $found_broadcast; then
    echo "❌ SSID not broadcasted: $ssid – cancelling."
    exit 1
fi

echo "✅ SSID is broadcasted: $ssid"


# ------------------------------------------------------------------------------
# 7) Check whether a saved NetworkManager profile exists
# ------------------------------------------------------------------------------

profile_exists=false

if nmcli -t -f NAME connection show \
    | grep -Fqx "$ssid"; then

    profile_exists=true
    echo "✅ Profile exists: $ssid"

else
    echo "⚠️  No saved NetworkManager profile for $ssid."
fi


# ------------------------------------------------------------------------------
# 8) Create missing profile from wifi_profiles.ini
# ------------------------------------------------------------------------------

if ! $profile_exists; then

    if [[ ! -f "$profiles_file" ]]; then
        echo "❌ Profile file not found: $profiles_file"
        exit 1
    fi

    echo "🔍 Looking for credentials for $ssid ..."

    password=""
    in_section=false

    while IFS= read -r line || [[ -n "$line" ]]; do

        line="${line%$'\r'}"

        # Ignore empty lines
        [[ -z "${line//[[:space:]]/}" ]] && continue

        # Ignore comments
        [[ "$line" =~ ^[[:space:]]*[#\;] ]] && continue

        # Section
        if [[ "$line" =~ ^[[:space:]]*\[(.*)\][[:space:]]*$ ]]; then

            section="${BASH_REMATCH[1]}"

            if [[ "$section" == "$ssid" ]]; then
                in_section=true
            else
                in_section=false
            fi

            continue
        fi

        # Password
        if $in_section &&
           [[ "$line" =~ ^[[:space:]]*password[[:space:]]*=(.*)$ ]]; then

            password="${BASH_REMATCH[1]}"
            break
        fi

    done < "$profiles_file"


    password="${password# }"


    if [[ -z "$password" ]]; then
        echo "❌ No password found for $ssid in $profiles_file"
        exit 1
    fi

    echo "🔐 Credentials found for $ssid."
    echo "➕ Creating NetworkManager profile..."

    if sudo nmcli connection add \
        type wifi \
        ifname "*" \
        con-name "$ssid" \
        ssid "$ssid" \
        wifi-sec.key-mgmt wpa-psk \
        wifi-sec.psk "$password"; then

        echo "✅ NetworkManager profile created: $ssid"

    else
        echo "❌ Failed to create NetworkManager profile: $ssid"
        exit 1
    fi
fi


# ------------------------------------------------------------------------------
# 9) Connect
# ------------------------------------------------------------------------------

echo "🔌 Connecting to $ssid ..."

if sudo nmcli connection up "$ssid"; then
    echo "✅ Connected to $ssid"
else
    echo "❌ Connection failed: $ssid"
    exit 1
fi


# ------------------------------------------------------------------------------
# Finished
# ------------------------------------------------------------------------------

echo "🏁 Done!"

exit 0
