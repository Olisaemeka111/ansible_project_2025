#!/bin/bash
# Resource Monitoring Script for Cost Tracking System
# Collects CPU, memory, disk, and network metrics from EC2 instances

set -e

HOSTNAME=$(hostname -s)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
REGION=${AWS_REGION:-us-east-2}
INSTANCE_ID=$(ec2-metadata --instance-id 2>/dev/null | cut -d ' ' -f 2 || echo "unknown")
PRIVATE_IP=$(ec2-metadata --local-ipv4 2>/dev/null | cut -d ' ' -f 2 || hostname -I | awk '{print $1}')

# Function to get CPU metrics
get_cpu_metrics() {
    local cores=$(nproc)
    local load=$(cat /proc/loadavg | awk '{printf "%.2f", $1}')
    echo "{\"cores\": $cores, \"load_average\": $load}"
}

# Function to get memory metrics (in bytes)
get_memory_metrics() {
    free -b | awk '/^Mem/ {
        printf "{\"total\": %d, \"used\": %d, \"free\": %d, \"percent_used\": %.2f}",
        $2, $3, $4, ($3/$2)*100
    }'
}

# Function to get disk metrics (in bytes)
get_disk_metrics() {
    df -B1 / | awk 'NR==2 {
        printf "{\"total\": %d, \"used\": %d, \"available\": %d, \"percent_used\": %.2f}",
        $2, $3, $4, ($3/$2)*100
    }'
}

# Function to get network metrics
get_network_metrics() {
    if [ -f /proc/net/dev ]; then
        # Try eth0 first, then fall back to other interfaces
        local interface=$(ip route get 8.8.8.8 2>/dev/null | grep -oP '(?<=dev\s)\w+' | head -1 || echo "eth0")
        cat /proc/net/dev | grep "$interface" | awk '{
            printf "{\"interface\": \"%s\", \"bytes_in\": %d, \"bytes_out\": %d, \"packets_in\": %d, \"packets_out\": %d}",
            $1, $2, $10, $3, $11
        }' | sed 's/:/:/'
    else
        echo "{\"interface\": \"unknown\", \"bytes_in\": 0, \"bytes_out\": 0, \"packets_in\": 0, \"packets_out\": 0}"
    fi
}

# Function to get process count
get_process_metrics() {
    local total_procs=$(ps aux | wc -l)
    local running_procs=$(ps aux | grep -c -E '^\S+\s+[0-9]+\s+' || echo "0")
    echo "{\"total_processes\": $total_procs, \"running_processes\": $running_procs}"
}

# Build the JSON report
generate_report() {
    cat <<EOF
{
  "timestamp": "$TIMESTAMP",
  "hostname": "$HOSTNAME",
  "instance_id": "$INSTANCE_ID",
  "private_ip": "$PRIVATE_IP",
  "region": "$REGION",
  "cpu": $(get_cpu_metrics),
  "memory": $(get_memory_metrics),
  "disk": $(get_disk_metrics),
  "network": $(get_network_metrics),
  "processes": $(get_process_metrics),
  "uptime": $(awk '{printf "%.0f", $1}' /proc/uptime),
  "docker_info": {
    "installed": $(command -v docker >/dev/null 2>&1 && echo "true" || echo "false"),
    "running_containers": $(docker ps -q 2>/dev/null | wc -l || echo "0")
  }
}
EOF
}

# Output the report
generate_report

# Also save to a local file for reference
REPORT_FILE="/tmp/resource_report_${HOSTNAME}_$(date +%s).json"
generate_report > "$REPORT_FILE" 2>/dev/null || true
