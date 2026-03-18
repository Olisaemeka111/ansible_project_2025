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

# Helper functions
print_usage() {
    cat <<EOF
${BLUE}Server Management Tool${NC}

Usage: ./manage-servers.sh [command] [options]

${GREEN}Commands:${NC}
  provision          Provision 30 new app servers
  install PKG        Install packages (all/batch_1/batch_2/batch_3)
  patch PKG          Apply patches (all/batch_1/batch_2/batch_3)
  monitor            Collect metrics and generate cost report
  ping PKG           Test connectivity (all/batch_1/batch_2/batch_3)
  list               List all instances and their details
  status             Check running instances and their status
  info PKG           Show info about instances (all/batch_1/batch_2/batch_3)
  shell CMD PKG      Run shell command on instances (PKG: all/batch_1/etc)
  ssh INSTANCE       SSH into specific instance (e.g., vprofile-app-01)
  stop PKG           Stop instances (all/batch_1/batch_2/batch_3)
  start PKG          Start instances (all/batch_1/batch_2/batch_3)
  terminate PKG      Terminate instances (all/batch_1/batch_2/batch_3)
  help               Show this help message

${GREEN}Examples:${NC}
  ./manage-servers.sh provision
  ./manage-servers.sh install all
  ./manage-servers.sh patch batch_1
  ./manage-servers.sh ping all
  ./manage-servers.sh shell 'df -h' batch_1
  ./manage-servers.sh list
  ./manage-servers.sh status

${YELLOW}Note:${NC} Run from the server-management directory
EOF
}

# Check if Ansible is installed
check_ansible() {
    if ! command -v ansible &> /dev/null; then
        echo -e "${RED}✗ Ansible not found. Please install Ansible first.${NC}"
        exit 1
    fi
}

# Provision servers
cmd_provision() {
    echo -e "${BLUE}Provisioning 30 app servers...${NC}"
    echo -e "${YELLOW}This will take 5-10 minutes${NC}"
    ansible-playbook "${PLAYBOOKS_DIR}/provision_servers.yml"
    echo -e "${GREEN}✓ Provisioning complete${NC}"
}

# Install packages
cmd_install() {
    local batch="${1:-all}"
    if [[ "$batch" != "all" && ! "$batch" =~ ^batch_[123]$ ]]; then
        echo -e "${RED}✗ Invalid batch. Use: all, batch_1, batch_2, or batch_3${NC}"
        exit 1
    fi

    local limit=""
    if [[ "$batch" != "all" ]]; then
        limit="--limit $batch"
    fi

    echo -e "${BLUE}Installing packages on $batch servers...${NC}"
    echo -e "${YELLOW}This will take 15-20 minutes per batch${NC}"
    ansible-playbook "${PLAYBOOKS_DIR}/package_install.yml" $limit
    echo -e "${GREEN}✓ Package installation complete${NC}"
}

# Apply patches
cmd_patch() {
    local batch="${1:-all}"
    if [[ "$batch" != "all" && ! "$batch" =~ ^batch_[123]$ ]]; then
        echo -e "${RED}✗ Invalid batch. Use: all, batch_1, batch_2, or batch_3${NC}"
        exit 1
    fi

    local limit=""
    if [[ "$batch" != "all" ]]; then
        limit="--limit $batch"
    fi

    echo -e "${BLUE}Applying patches on $batch servers...${NC}"
    echo -e "${YELLOW}This will take 10-15 minutes per batch. Servers may reboot.${NC}"
    ansible-playbook "${PLAYBOOKS_DIR}/patching.yml" $limit
    echo -e "${GREEN}✓ Patching complete${NC}"
}

# Monitor and generate report
cmd_monitor() {
    echo -e "${BLUE}Collecting metrics and generating cost report...${NC}"
    ansible-playbook "${PLAYBOOKS_DIR}/monitoring_and_cost.yml"

    # Find and display the latest report
    LATEST_REPORT=$(ls -t reports/cost_report_*.html 2>/dev/null | head -1)
    if [[ -n "$LATEST_REPORT" ]]; then
        echo -e "${GREEN}✓ Report saved to: $LATEST_REPORT${NC}"
    fi
}

# Test connectivity
cmd_ping() {
    local batch="${1:-all}"
    if [[ "$batch" != "all" && ! "$batch" =~ ^batch_[123]$ ]]; then
        echo -e "${RED}✗ Invalid batch. Use: all, batch_1, batch_2, or batch_3${NC}"
        exit 1
    fi

    local limit=""
    if [[ "$batch" != "all" ]]; then
        limit="--limit $batch"
    fi

    echo -e "${BLUE}Testing connectivity on $batch servers...${NC}"
    ansible -i "$INVENTORY" app_servers $limit -m ping
}

# List instances
cmd_list() {
    echo -e "${BLUE}App Server Instances:${NC}"
    aws ec2 describe-instances \
        --region us-east-2 \
        --filters "Name=tag:Project,Values=Vprofile" "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],PrivateIpAddress,Tags[?Key==`Batch`].Value|[0],InstanceType,State.Name]' \
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

# Show instance info
cmd_info() {
    local batch="${1:-all}"
    if [[ "$batch" != "all" && ! "$batch" =~ ^batch_[123]$ ]]; then
        echo -e "${RED}✗ Invalid batch. Use: all, batch_1, batch_2, or batch_3${NC}"
        exit 1
    fi

    local filter="Name=tag:Project,Values=Vprofile"
    if [[ "$batch" != "all" ]]; then
        filter="$filter Name=tag:Batch,Values=$batch"
    fi

    echo -e "${BLUE}Instance Information ($batch):${NC}"
    ansible -i "$INVENTORY" app_servers $([ "$batch" != "all" ] && echo "--limit $batch") --list-hosts
}

# Run shell command
cmd_shell() {
    local cmd="$1"
    local batch="${2:-all}"

    if [[ -z "$cmd" ]]; then
        echo -e "${RED}✗ Command required. Usage: ./manage-servers.sh shell 'command' [batch]${NC}"
        exit 1
    fi

    if [[ "$batch" != "all" && ! "$batch" =~ ^batch_[123]$ ]]; then
        echo -e "${RED}✗ Invalid batch. Use: all, batch_1, batch_2, or batch_3${NC}"
        exit 1
    fi

    local limit=""
    if [[ "$batch" != "all" ]]; then
        limit="--limit $batch"
    fi

    echo -e "${BLUE}Running: $cmd${NC}"
    echo -e "${BLUE}Target: $batch servers${NC}"
    ansible -i "$INVENTORY" app_servers $limit -m shell -a "$cmd"
}

# SSH into instance
cmd_ssh() {
    local instance="$1"
    if [[ -z "$instance" ]]; then
        echo -e "${RED}✗ Instance name required. E.g., vprofile-app-01${NC}"
        exit 1
    fi

    echo -e "${BLUE}Connecting to $instance...${NC}"

    # Get the private IP of the instance
    local ip=$(aws ec2 describe-instances \
        --region us-east-2 \
        --filters "Name=tag:Name,Values=$instance" \
        --query 'Reservations[0].Instances[0].PrivateIpAddress' \
        --output text 2>/dev/null)

    if [[ -z "$ip" || "$ip" == "None" ]]; then
        echo -e "${RED}✗ Instance not found: $instance${NC}"
        exit 1
    fi

    echo -e "${YELLOW}Note: You may need to SSH through a bastion host:${NC}"
    echo "ssh -J ubuntu@bastion-host ubuntu@$ip"
    echo ""
    echo -e "${BLUE}Or configure SSH ProxyJump in ~/.ssh/config${NC}"
}

# Stop instances
cmd_stop() {
    local batch="${1:-all}"
    if [[ "$batch" != "all" && ! "$batch" =~ ^batch_[123]$ ]]; then
        echo -e "${RED}✗ Invalid batch. Use: all, batch_1, batch_2, or batch_3${NC}"
        exit 1
    fi

    local filter="Name=tag:Project,Values=Vprofile"
    if [[ "$batch" != "all" ]]; then
        filter="$filter Name=tag:Batch,Values=$batch"
    fi

    local instances=$(aws ec2 describe-instances \
        --region us-east-2 \
        --filters "$filter" "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)

    if [[ -z "$instances" ]]; then
        echo -e "${YELLOW}No running instances found in $batch${NC}"
        return
    fi

    echo -e "${YELLOW}Stopping $batch instances...${NC}"
    aws ec2 stop-instances --region us-east-2 --instance-ids $instances
    echo -e "${GREEN}✓ Stop request sent${NC}"
}

# Start instances
cmd_start() {
    local batch="${1:-all}"
    if [[ "$batch" != "all" && ! "$batch" =~ ^batch_[123]$ ]]; then
        echo -e "${RED}✗ Invalid batch. Use: all, batch_1, batch_2, or batch_3${NC}"
        exit 1
    fi

    local filter="Name=tag:Project,Values=Vprofile"
    if [[ "$batch" != "all" ]]; then
        filter="$filter Name=tag:Batch,Values=$batch"
    fi

    local instances=$(aws ec2 describe-instances \
        --region us-east-2 \
        --filters "$filter" "Name=instance-state-name,Values=stopped" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)

    if [[ -z "$instances" ]]; then
        echo -e "${YELLOW}No stopped instances found in $batch${NC}"
        return
    fi

    echo -e "${YELLOW}Starting $batch instances...${NC}"
    aws ec2 start-instances --region us-east-2 --instance-ids $instances
    echo -e "${GREEN}✓ Start request sent${NC}"
}

# Terminate instances
cmd_terminate() {
    local batch="${1:-all}"
    if [[ "$batch" != "all" && ! "$batch" =~ ^batch_[123]$ ]]; then
        echo -e "${RED}✗ Invalid batch. Use: all, batch_1, batch_2, or batch_3${NC}"
        exit 1
    fi

    local filter="Name=tag:Project,Values=Vprofile"
    if [[ "$batch" != "all" ]]; then
        filter="$filter Name=tag:Batch,Values=$batch"
    fi

    local instances=$(aws ec2 describe-instances \
        --region us-east-2 \
        --filters "$filter" "Name=instance-state-name,Values=running,stopped" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text)

    if [[ -z "$instances" ]]; then
        echo -e "${YELLOW}No instances found in $batch${NC}"
        return
    fi

    echo -e "${RED}⚠ WARNING: You are about to terminate instances in $batch${NC}"
    read -p "Type 'confirm' to proceed: " confirm

    if [[ "$confirm" != "confirm" ]]; then
        echo -e "${YELLOW}✓ Cancelled${NC}"
        return
    fi

    echo -e "${RED}Terminating $batch instances...${NC}"
    aws ec2 terminate-instances --region us-east-2 --instance-ids $instances
    echo -e "${RED}✓ Termination requested${NC}"
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
    info)
        cmd_info "$2"
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
        echo -e "${RED}✗ Unknown command: $1${NC}"
        echo ""
        print_usage
        exit 1
        ;;
esac
