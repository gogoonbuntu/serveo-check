#!/bin/bash

# Configuration
LOG_DIR="/var/log/serveo-monitor"
LOG_FILE="${LOG_DIR}/serveo_$(date +%Y%m%d).log"
AUTOSSH_PIDFILE="/var/run/serveo_autossh.pid"
CHECK_INTERVAL=6  # 60초/10회 = 6초 간격

# Initialize
mkdir -p ${LOG_DIR}

log_message() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] $1" | tee -a ${LOG_FILE}
}

get_open_ports() {
    log_message "Scanning for open ports..."
    netstat -tuln | grep "0.0.0.0" | grep "LISTEN" | awk '{print $4}' | awk -F: '{print $2}' | sort -n
}

check_serveo_process() {
    local port=$1
    local serveo_domain="sy${port}"
    
    # Check if autossh process is running for this port
    if pgrep -f "autossh.*serveo.net.*:${port}.*${serveo_domain}" > /dev/null; then
        log_message "Serveo process for port ${port} (${serveo_domain}.serveo.net) is running"
        return 0
    fi
    
    log_message "Serveo process for port ${port} is not running. Starting..."
    
    # Start serveo with autossh for reliability
    autossh -M 0 -o "ServerAliveInterval 30" -o "ServerAliveCountMax 3" \
        -R "${serveo_domain}:80:localhost:${port}" serveo.net \
        -f > /dev/null 2>&1
    
    # Check if started successfully
    if [ $? -eq 0 ] && pgrep -f "autossh.*serveo.net.*:${port}" > /dev/null; then
        log_message "Successfully started serveo for port ${port} (${serveo_domain}.serveo.net)"
        return 0
    else
        log_message "Failed to start serveo for port ${port}"
        return 1
    fi
}

cleanup_old_processes() {
    log_message "Cleaning up stale serveo processes..."
    pkill -f "autossh.*serveo.net"
    pkill -f "ssh.*serveo.net"
}

monitor_serveo() {
    # Get list of open ports
    local open_ports=$(get_open_ports)
    
    if [ -z "${open_ports}" ]; then
        log_message "No open ports found"
        return 1
    fi
    
    # Monitor each port
    local failed=false
    for port in ${open_ports}; do
        check_serveo_process "${port}"
        if [ $? -ne 0 ]; then
            failed=true
        fi
    done
    
    if [ "$failed" = true ]; then
        return 1
    fi
    return 0
}

# Main execution
for (( i=1; i<=10; i++ )); do
    log_message "Check iteration ${i}/10"
    monitor_serveo
    
    if [ $i -lt 10 ]; then
        sleep ${CHECK_INTERVAL}
    fi
done
