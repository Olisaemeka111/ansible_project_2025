#!/bin/bash
# Server Management Wrapper Script
# Usage: ./manage-servers.sh [command] [options]

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="${SCRIPT_DIR}/inventory/aws_ec2.yml"
PLAYBOOKS_DIR="${SCRIPT_DIR}/playbooks"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

VALID_TIERS="all, web_tier, app_tier, db_tier"

# Helper functions
print_usage() {
    cat <<EOF
${BLUE}Server Management Tool - 3-Tier Architecture${NC}

Usage: ./manage-servers.sh [command] [options]

${GREEN}Commands:${NC}
  provision          Provision 30 servers (10 web + 10 app + 10 db)
  install TIER       Install packages (all/web_tier/app_tier/db_tier)
  patch TIER         Apply patches (all/web_tier/app_tier/db_tier)
  monitor            Collect metrics and generate cost report
  ping TIER          Test connectivity (all/web_tier/app_tier/db_tier)
  list               List all instances and their details
  status             Check running instances and their status
  shell CMD TIER     Run shell command on instances
  ssh INSTANCE       SSH into specific instance (e.g., vprofile-web-01)
  stop TIER          Stop instances (all/web_tier/app_tier/db_tier)
  start TIER         Start instances (all/web_tier/app_tier/db_tier)
  terminate TIER     Terminate instances (all/web_tier/app_tier/db_tier)
  help               Show this help message

${GREEN}Examples:${NC}
  ./manage-servers.sh provision
  ./manage-servers.sh install all
  ./manage-servers.sh patch web_tier
  ./manage-servers.sh ping app_tier
  ./manage-servers.sh shell 'df -h' db_tier
  ./manage-servers.sh list
  ./manage-servers.sh status

${YELLOW}Note:${NC} Run from the server-management directory
EOF
}

validate_tier() {
    local tier="$1"
    if [[ "$tier" != "all" && "$tier" != "web_tier" && "$tier" != "app_tier" && "$tier" != "db_tier" ]]; then
        echo -e "${RED}Invalid tier. Use: ${VALID_TIERS}${NC}"
        exit 1
    fi
}

# Check if Ansible is installed
check_ansible() {
    if ! command -v ansible &> /dev/null; then
        echo -e "${RED}Ansible not found. Please install Ansible first.${NC}"
        exit 1
    fi
}

get_ansible_target() {
    local tier="$1"
    if [[ "$tier" == "all" ]]; then
        echo "web_tier:app_tier:db_tier"
    else
        echo "$tier"
    fi
}

# Provision servers
cmd_provision() {
    echo -e "${BLUE}Provisioning 30 servers (3-tier architecture)...${NC}"
    ansible-playbook "${PLAYBOOKS_DIR}/security_groups.yml"
    ansible-playbook "${PLAYBOOKS_DIR}/provision_servers.yml"
    echo -e "${GREEN}Provisioning complete${NC}"
}

# Install packages
cmd_install() {
    local tier="${1:-all}"
    validate_tier "$tier"

    local limit=""
    if [[ "$tier" != "all" ]]; then
        limit="--limit $tier"
    fi

    echo -e "${BLUE}Installing packages on $tier servers...${NC}"
    ansible-playbook "${PLAYBOOKS_DIR}/package_install.yml" $limit
    echo -e "${GREEN}Package installation complete${NC}"
}

# Apply patches
cmd_patch() {
    local tier="${1:-all}"
    validate_tier "$tier"

    local limit=""
    if [[ "$tier" != "all" ]]; then
        limit="--limit $tier"
    fi

    echo -e "${BLUE}Applying patches on $tier servers...${NC}"
    ansible-playbook "${PLAYBOOKS_DIR}/patching.yml" $limit
    echo -e "${GREEN}Patching complete${NC}"
}

# Monitor and generate report
cmd_monitor() {
    echo -e "${BLUE}Collecting metrics and generating cost report...${NC}"
    ansible-playbook "${PLAYBOOKS_DIR}/monitoring_and_cost.yml"

    LATEST_REPORT=$(ls -t reports/cost_report_*.html 2>/dev/null | head -1)
    if [[ -n "$LATEST_REPORT" ]]; then
        echo -e "${GREEN}Report saved to: $LATEST_REPORT${NC}"
    fi
}

# Test connectivity
cmd_ping() {
    local tier="${1:-all}"
    validate_tier "$tier"

    local target
    target=$(get_ansible_target "$tier")

    echo -e "${BLUE}Testing connectivity on $tier servers...${NC}"
    ansible -i "$INVENTORY" "$target" -m ping
}

# List instances
cmd_list() {
    echo -e "${BLUE}Server Instances (3-Tier):${NC}"
    aws ec2 describe-instances \
        --region us-east-2 \
        --filters "Name=tag:Project,Values=Vprofile" "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],PrivateIpAddress,Tags[?Key==`Tier`].Value|[0],InstanceType,State.Name]' \
        --output table || echo -e "${RED}No instances found or AWS CLI error${NC}"
}

# Check status
cmd_status() {
    echo -e "${BLUE}Instance Status:${NC}"
    aws ec2 describe-instance-status \
        --region us-east-2 \
        --filters "Name=instance-state-name,Values=running" \
        --query 'InstanceStatuses[].[InstanceId,InstanceStatus.Status,SystemStatus.Status]' \
        --output table 2>/dev/null || echo -e "${YELLOW}No running instances or AWS CLI not configured${NC}"
}

# Run shell command
cmd_shell() {
    local cmd="$1"
    local tier="${2:-all}"

    if [[ -z "$cmd" ]]; then
        echo -e "${RED}Command required. Usage: ./manage-servers.sh shell 'command' [tier]${NC}"
        exit 1
    fi

    validate_tier "$tier"

    local target
    target=$(get_ansible_target "$tier")

    local limit=""
    if [[ "$tier" != "all" ]]; then
        limit="--limit $tier"
    fi

    echo -e "${BLUE}Running: $cmd${NC}"
    echo -e "${BLUE}Target: $tier servers${NC}"
    ansible -i "$INVENTORY" "$target" -m shell -a "$cmd"
}

# SSH into instance
cmd_ssh() {
    local instance="$1"
    if [[ -z "$instance" ]]; then
        echo -e "${RED}Instance name required. E.g., vprofile-web-01${NC}"
        exit 1
    fi

    local ip=$(aws ec2 describe-instances \
        --region us-east-2 \
        --filters "Name=tag:Name,Values=$instance" \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text 2>/dev/null)

    if [[ -z "$ip" || "$ip" == "None" ]]; then
        echo -e "${RED}Instance not found: $instance${NC}"
        exit 1
    fi

    echo -e "${BLUE}Instance $instance has IP: $ip${NC}"
    echo -e "${YELLOW}Connect via SSM to control node, then:${NC}"
    echo "ssh ubuntu@$ip"
}

# Stop instances
cmd_stop() {
    local tier="${1:-all}"
    validate_tier "$tier"

    local filter="Name=tag:Project,Values=Vprofile"
    if [[ "$tier" != "all" ]]; then
        filter="$filter Name=tag:Tier,Values=${tier%_tier}"
    fi

    local instances=$(aws ec2 describe-instances \
        --region us-east-2 \
        --filters $filter "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)

    if [[ -z "$instances" ]]; then
        echo -e "${YELLOW}No running instances found in $tier${NC}"
        return
    fi

    echo -e "${YELLOW}Stopping $tier instances...${NC}"
    aws ec2 stop-instances --region us-east-2 --instance-ids $instances
    echo -e "${GREEN}Stop request sent${NC}"
}

# Start instances
cmd_start() {
    local tier="${1:-all}"
    validate_tier "$tier"

    local filter="Name=tag:Project,Values=Vprofile"
    if [[ "$tier" != "all" ]]; then
        filter="$filter Name=tag:Tier,Values=${tier%_tier}"
    fi

    local instances=$(aws ec2 describe-instances \
        --region us-east-2 \
        --filters $filter "Name=instance-state-name,Values=stopped" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)

    if [[ -z "$instances" ]]; then
        echo -e "${YELLOW}No stopped instances found in $tier${NC}"
        return
    fi

    echo -e "${YELLOW}Starting $tier instances...${NC}"
    aws ec2 start-instances --region us-east-2 --instance-ids $instances
    echo -e "${GREEN}Start request sent${NC}"
}

# Terminate instances
cmd_terminate() {
    local tier="${1:-all}"
    validate_tier "$tier"

    local filter="Name=tag:Project,Values=Vprofile"
    if [[ "$tier" != "all" ]]; then
        filter="$filter Name=tag:Tier,Values=${tier%_tier}"
    fi

    local instances=$(aws ec2 describe-instances \
        --region us-east-2 \
        --filters $filter "Name=instance-state-name,Values=running,stopped" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)

    if [[ -z "$instances" ]]; then
        echo -e "${YELLOW}No instances found in $tier${NC}"
        return
    fi

    echo -e "${RED}WARNING: You are about to terminate instances in $tier${NC}"
    read -p "Type 'confirm' to proceed: " confirm

    if [[ "$confirm" != "confirm" ]]; then
        echo -e "${YELLOW}Cancelled${NC}"
        return
    fi

    echo -e "${RED}Terminating $tier instances...${NC}"
    aws ec2 terminate-instances --region us-east-2 --instance-ids $instances
    echo -e "${RED}Termination requested${NC}"
}

# Main
check_ansible

case "${1:-help}" in
    provision)
        cmd_provision
        ;;
    install)
        cmd_install "$2"
        ;;
    patch)
        cmd_patch "$2"
        ;;
    monitor)
        cmd_monitor
        ;;
    ping)
        cmd_ping "$2"
        ;;
    list)
        cmd_list
        ;;
    status)
        cmd_status
        ;;
    shell)
        cmd_shell "$2" "$3"
        ;;
    ssh)
        cmd_ssh "$2"
        ;;
    stop)
        cmd_stop "$2"
        ;;
    start)
        cmd_start "$2"
        ;;
    terminate)
        cmd_terminate "$2"
        ;;
    help|--help|-h)
        print_usage
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        echo ""
        print_usage
        exit 1
        ;;
esac
