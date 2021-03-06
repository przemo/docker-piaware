#!/usr/bin/with-contenv bash
# shellcheck shell=bash

# Exit abnormally for any error
set -eo pipefail

# Set default exit code
EXITCODE=0

# Get list of flightaware server IPs
FA_SERVER_IPS=$(piaware-config -show adept-serverhosts | cut -d '{' -f 2 | cut -d '}' -f 1)

# Get flightaware server port
FA_SERVER_PORT=$(piaware-config -show adept-serverport)

# Get netstat output
NETSTAT_AN=$(netstat -an)

# Define function to return number msgs sent to FA from a process for a given time
function check_logs_for_msgs_sent_to_fa () {
    # $1 = sending process (eg: dump1090, socat, dump978-fa)
    # $2 = number of output lines to consider (every line represents 5 minutes, so 12 would be an hour)
    # ------
    REGEX_FA_MSGS_SENT_PAST_5MIN="^(?'date'\d{4}-\d{1,2}-\d{1,2})\s+(?'time'\d{1,2}:\d{1,2}:[\d\.]+)\s+\[piaware\]\s+(?'date2'\d{4}\/\d{1,2}\/\d{1,2})\s+(?'time2'\d{1,2}:\d{1,2}:[\d\.]+)\s+\d+ msgs recv'd from $1 \(\K(?'msgslast5m'\d+) in last 5m\);\s+\d+ msgs sent to FlightAware\s*$"
    NUM_MSGS_RECEIVED=$(tail -$(($2 * 10)) /var/log/piaware/current | grep -oP "$REGEX_FA_MSGS_SENT_PAST_5MIN" | tail "-$2" | tr -s " " | cut -d " " -f 1)
    TOTAL_MSGS_RECEIVED=0
    for NUM_MSGS in $NUM_MSGS_RECEIVED; do
        TOTAL_MSGS_RECEIVED=$((TOTAL_MSGS_RECEIVED + NUM_MSGS))
    done
    echo "$TOTAL_MSGS_RECEIVED"
}

# Make sure there is an established connection to flightaware
CONNECTED_TO_FA=""
for FA_SERVER_IP in $FA_SERVER_IPS; do
    IP_ESCAPED_DOTS=${FA_SERVER_IP//./\\.}
    REGEX_FA_CONNECTION_FROM_NETSTAT="^\s*tcp\s+\d+\s+\d+\s+(?>\d{1,3}\.{0,1}){4}:\d{1,5}\s+(?>${IP_ESCAPED_DOTS}):(?>${FA_SERVER_PORT})\s+ESTABLISHED\s*$"
    if echo "$NETSTAT_AN" | grep -P "$REGEX_FA_CONNECTION_FROM_NETSTAT" > /dev/null 2>&1; then
        CONNECTED_TO_FA="true"
        break 2
    fi
done
if [[ -z "$CONNECTED_TO_FA" ]]; then
    echo "No connection to Flightaware, NOT OK."
    EXITCODE=1
else
    echo "Connected to Flightaware, OK."
fi

# Make sure 1090MHz data is being sent to flightaware
if [[ -n "$BEASTHOST" || "$RECEIVER_TYPE" == "rtlsdr" ]]; then
    # look for log messages from dump1090
    FA_DUMP1090_MSGS_SENT_PAST_HOUR=$(check_logs_for_msgs_sent_to_fa dump1090 12)
    if [[ "$FA_DUMP1090_MSGS_SENT_PAST_HOUR" -gt 0 ]]; then
        echo "$FA_DUMP1090_MSGS_SENT_PAST_HOUR dump1090 messages sent in past hour, OK."
    else
        echo "$FA_DUMP1090_MSGS_SENT_PAST_HOUR dump1090 messages sent in past hour, NOT OK."
        EXITCODE=1
    fi
fi

# Make sure 978MHz data is being sent to flightaware
if [[ -n "$UAT_RECEIVER_HOST" ]]; then
    # look for log messages from socat
    FA_DUMP978_MSGS_SENT_PAST_HOUR=$(check_logs_for_msgs_sent_to_fa socat 24)
    if [[ "$FA_DUMP978_MSGS_SENT_PAST_HOUR" -gt 0 ]]; then
        echo "$FA_DUMP978_MSGS_SENT_PAST_HOUR dump978 messages sent in past 2 hours, OK."
    else
        echo "$FA_DUMP978_MSGS_SENT_PAST_HOUR dump978 messages sent in past 2 hours, NOT OK."
        EXITCODE=1
    fi
elif [[ "$UAT_RECEIVER_TYPE" == "rtlsdr" ]]; then
    # look for log messages from dump978-fa
    FA_DUMP1090_MSGS_SENT_PAST_HOUR=$(check_logs_for_msgs_sent_to_fa dump978-fa 24)
    if [[ "$FA_DUMP978_MSGS_SENT_PAST_HOUR" -gt 0 ]]; then
        echo "$FA_DUMP978_MSGS_SENT_PAST_HOUR dump978 messages sent in past 2 hours, OK."
    else
        echo "$FA_DUMP978_MSGS_SENT_PAST_HOUR dump978 messages sent in past 2 hours, NOT OK."
        EXITCODE=1
    fi
fi

# Make sure web server listening on port 80
WEBSERVER_LISTENING_PORT_80=""
REGEX_WEBSERVER_LISTENING_PORT_80="^\s*tcp\s+\d+\s+\d+\s+(?>0\.0\.0\.0):80\s+(?>0\.0\.0\.0):(?>\*)\s+LISTEN\s*$"
if echo "$NETSTAT_AN" | grep -P "$REGEX_WEBSERVER_LISTENING_PORT_80" > /dev/null 2>&1; then
        WEBSERVER_LISTENING_PORT_80="true"
fi
if [[ -z "$WEBSERVER_LISTENING_PORT_80" ]]; then
    echo "Webserver not listening on port 80, NOT OK."
    EXITCODE=1
else
    echo "Webserver listening on port 80, OK."
fi

# Make sure web server listening on port 8080
WEBSERVER_LISTENING_PORT_80=""
REGEX_WEBSERVER_LISTENING_PORT_80="^\s*tcp\s+\d+\s+\d+\s+(?>0\.0\.0\.0):8080\s+(?>0\.0\.0\.0):(?>\*)\s+LISTEN\s*$"
if echo "$NETSTAT_AN" | grep -P "$REGEX_WEBSERVER_LISTENING_PORT_80" > /dev/null 2>&1; then
        WEBSERVER_LISTENING_PORT_80="true"
fi
if [[ -z "$WEBSERVER_LISTENING_PORT_80" ]]; then
    echo "Webserver not listening on port 8080, NOT OK."
    EXITCODE=1
else
    echo "Webserver listening on port 8080, OK."
fi

# Exit with determined exit status
exit "$EXITCODE"
