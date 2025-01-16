#!/bin/bash

# WebTriggers - Monitor web pages for changes and trigger actions
# Dependencies: chromium-browser, pup, spd-say

CONFIG_FILE="$HOME/.webtriggers"
CACHE_DIR="$HOME/.webtriggers_cache"
LOG_FILE="$HOME/webtriggers.log"
mkdir -p "$CACHE_DIR"

trim() {
    local str="$1"
    str="${str#"${str%%[![:space:]]*}"}"
    str="${str%"${str##*[![:space:]]}"}"
    echo "$str"
}

send_notification() {
    local message="$1"
    notify-send "WebTrigger Alert" "$message"
}

say_message() {
    local message="$1"
    spd-say "$message"
}

log_message() {
    local message="$1"
    echo "$message" >&2
    echo "$(date): $message" >> "$LOG_FILE"
}

fetch_element_value() {
    local url="$1"
    local selector="$2"

    local html
    html=$(chromium-browser --headless --disable-gpu --dump-dom "$url" 2>/dev/null)
    [[ $? -ne 0 ]] && echo "Error: Failed to fetch HTML from $url" >&2 && return 1

    local value
    value=$(echo "$html" | pup "$selector" text{})
    [[ $? -ne 0 ]] && echo "Error: Failed to extract element value using selector '$selector'" >&2 && return 1

    echo "$value"
}

evaluate_condition() {
    local value="$1"
    local condition="$2"

    local operator operand
    operator=$(echo "$condition" | grep -o '^[<>=!]*')
    operand=${condition#"$operator"}

    case "$operator" in
        "=") [[ "$value" == "$operand" ]] ;;
        "!=") [[ "$value" != "$operand" ]] ;;
        ">") (( $(echo "$value > $operand" | bc -l) )) ;;
        "<") (( $(echo "$value < $operand" | bc -l) )) ;;
        ">=") (( $(echo "$value >= $operand" | bc -l) )) ;;
        "<=") (( $(echo "$value <= $operand" | bc -l) )) ;;
        "") return 0 ;; # if no condition is specified always trigger the action
        *) return 1 ;;
    esac
}

process_entry() {
    local url="$1" selector="$2" condition="$3" message="$4" handler="$5"
    local cache_file="$CACHE_DIR/$(echo "$url|$selector" | md5sum | awk '{print $1}')"

    local value
    value=$(fetch_element_value "$url" "$selector")
    [[ $? -ne 0 || -z "$value" ]] && log_message "Error fetching value for $url" && return

    if [[ -f "$cache_file" ]]; then
        local old_value
        old_value=$(<"$cache_file")
        [[ "$value" == "$old_value" ]] && return
    fi

    if evaluate_condition "$value" "$condition"; then
        local formatted_message="${message//\{\{value\}\}/$value}"
        IFS=',' read -ra handlers <<< "$handler"
        for h in "${handlers[@]}"; do
            h=$(trim "$h")
            case "$h" in
                "notify") send_notification "$formatted_message" ;;
                "say") say_message "$formatted_message" & ;;
                *) log_message "Unknown handler '$h' for $url" ;;
            esac
        done
    fi

    echo "$value" > "$cache_file"
}

convert_to_seconds() {
    local interval="$1"
    local time_value
    local time_unit

    # Extract the numeric value and unit (s, m, h, etc.)
    time_value="${interval//[!0-9]/}"
    time_unit="${interval//[0-9]/}"

    # Default to seconds if no unit is specified
    case "$time_unit" in
        s) echo "$time_value" ;;             # Seconds
        m) echo "$((time_value * 60))" ;;     # Minutes to seconds
        h) echo "$((time_value * 3600))" ;;   # Hours to seconds
        *) echo "$time_value" ;;             # Default to seconds
    esac
}

run_checks() {
    local url selector condition interval message handler

    while read -r line; do
        line="${line%%#*}" # Remove comments
        case "$line" in
            "- url:"*) url="${line#- url: }" ;;
            "querySelector:"*) selector=$(trim "${line#querySelector: }");;
            "condition:"*) condition=$(trim "${line#condition: }") ;;
            "interval:"*) interval=$(trim "${line#interval: }") ;;
            "message:"*) message=$(trim "${line#message: }") ;;
            "handler:"*) handler="${line#handler: }" ;;
            "") # Execute the entry
                if [[ -n "$url" && -n "$selector" && -n "$condition" && -n "$interval" && -n "$message" ]]; then
                    while true; do
                        process_entry "$url" "$selector" "$condition" "$message" "$handler"
                        sleep $(convert_to_seconds "$interval")
                    done &
                    bg_pids+=($!) # Add the process ID to the list
                fi
                url="" selector="" condition="" interval="" message="" handler=""
                ;;
        esac
    done < "$CONFIG_FILE"
}

webtriggers() {
    log_message "Starting WebTriggers..."
    run_checks
    wait
}

cleanup() {
    log_message "$(date): Stopping WebTriggers and cleaning up..."
    for pid in "${bg_pids[@]}"; do
        kill "$pid" 2>/dev/null
    done
    ps aux | grep $0
    exit
}

webtriggers() {
    echo "$(date): Starting WebTriggers..." >> "$LOG_FILE"
    bg_pids=() # Array to store background process IDs
    trap cleanup SIGINT SIGTERM # Catch signals and clean up
    run_checks
    wait
}
trap cleanup SIGINT SIGTERM
webtriggers

