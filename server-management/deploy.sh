#!/bin/bash

################################################################################
# 3-Tier Infrastructure Deployment Script
# Purpose: Automated deployment of Web, App, and Database tier servers with
#          tight security groups and network isolation
# Author: DevOps Team
# Last Updated: 2026-03-17
################################################################################

set -e  # Exit on error

# Auto-confirm flag (set via --yes or -y)
AUTO_YES=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAYBOOKS_DIR="$SCRIPT_DIR/playbooks"
VARS_DIR="$SCRIPT_DIR/vars"
LOGS_DIR="$SCRIPT_DIR/logs"
INVENTORY_DIR="$SCRIPT_DIR/inventory"

# Log files
LOG_FILE="$LOGS_DIR/deployment_$(date +%Y%m%d_%H%M%S).log"
ERROR_LOG="$LOGS_DIR/deployment_errors_$(date +%Y%m%d_%H%M%S).log"

# Deployment state tracking
DEPLOYMENT_STATE_FILE="$LOGS_DIR/.deployment_state"

################################################################################
# UTILITY FUNCTIONS
################################################################################

# Print colored output
print_header() {
    echo -e "\n${BLUE}+============================================================+${NC}"
    echo -e "${BLUE}|${NC} $1"
    echo -e "${BLUE}+============================================================+${NC}\n"
}

print_step() {
    echo -e "${CYAN}->${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_info() {
    echo -e "${MAGENTA}[INFO]${NC} $1"
}

# Log to file
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Log errors
log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1" >> "$ERROR_LOG"
    print_error "$1"
}

# Create logs directory
setup_logging() {
    mkdir -p "$LOGS_DIR"
    touch "$LOG_FILE" "$ERROR_LOG"
    log "Deployment started"
}

# Check prerequisites
check_prerequisites() {
    print_header "Checking Prerequisites"

    local missing_tools=()

    # Check Ansible
    if ! command -v ansible &> /dev/null; then
        missing_tools+=("ansible")
    else
        local ansible_version=$(ansible --version | head -1)
        print_success "Ansible: $ansible_version"
        log "Ansible: $ansible_version"
    fi

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws-cli")
    else
        local aws_version=$(aws --version | head -1)
        print_success "AWS CLI: $aws_version"
        log "AWS CLI: $aws_version"
    fi

    # Check Python 3
    if ! command -v python3 &> /dev/null; then
        missing_tools+=("python3")
    else
        local python_version=$(python3 --version)
        print_success "Python 3: $python_version"
        log "Python 3: $python_version"
    fi

    # Check SSH
    if ! command -v ssh &> /dev/null; then
        missing_tools+=("ssh")
    else
        print_success "SSH: Installed"
        log "SSH: Installed"
    fi

    # Check boto3
    if ! python3 -c "import boto3" &> /dev/null; then
        missing_tools+=("boto3")
    else
        print_success "boto3: Installed"
        log "boto3: Installed"
    fi

    # Check SSH key
    if [ -f ~/.ssh/vprofile-key.pem ]; then
        local key_perms=$(ls -l ~/.ssh/vprofile-key.pem | awk '{print $1}')
        print_success "SSH Key: ~/.ssh/vprofile-key.pem ($key_perms)"
        log "SSH Key: ~/.ssh/vprofile-key.pem ($key_perms)"

        if [ "$key_perms" != "-rw-------" ]; then
            print_warning "SSH key permissions may be incorrect (should be 600)"
            chmod 600 ~/.ssh/vprofile-key.pem
            print_success "Fixed SSH key permissions to 600"
            log "Fixed SSH key permissions to 600"
        fi
    else
        log_error "SSH key not found: ~/.ssh/vprofile-key.pem"
        missing_tools+=("vprofile-key.pem")
    fi

    # Report missing tools
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo -e "\n${RED}Missing required tools:${NC}"
        for tool in "${missing_tools[@]}"; do
            echo "  - $tool"
            log_error "Missing tool: $tool"
        done
        return 1
    fi

    print_success "All prerequisites satisfied"
    return 0
}

# Validate AWS configuration
validate_aws() {
    print_header "Validating AWS Configuration"

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        return 1
    fi

    local account_id=$(aws sts get-caller-identity --query Account --output text)
    local user_arn=$(aws sts get-caller-identity --query Arn --output text)
    print_success "AWS Account: $account_id"
    print_success "AWS User: $user_arn"
    log "AWS Account: $account_id"
    log "AWS User: $user_arn"

    # Check VPC exists (read from output_vars.yml)
    local vpc_id=$(grep '^vpc_id:' "$VARS_DIR/output_vars.yml" | awk '{print $2}' | tr -d '"')
    if [ -z "$vpc_id" ]; then
        log_error "vpc_id not found in vars/output_vars.yml"
        return 1
    fi
    if aws ec2 describe-vpcs --vpc-ids "$vpc_id" --region us-east-2 &> /dev/null; then
        print_success "VPC exists: $vpc_id"
        log "VPC exists: $vpc_id"
    else
        log_error "VPC not found: $vpc_id"
        return 1
    fi

    # Check Bastion SG exists (optional - deployment works without it)
    local bastion_sg=$(aws ec2 describe-security-groups \
        --filters "Name=group-name,Values=Bastion-host-sg" "Name=vpc-id,Values=$vpc_id" \
        --region us-east-2 \
        --query 'SecurityGroups[0].GroupId' \
        --output text 2>/dev/null)
    if [ -n "$bastion_sg" ] && [ "$bastion_sg" != "None" ]; then
        print_success "Bastion Security Group: $bastion_sg"
        log "Bastion Security Group: $bastion_sg"
    else
        print_warning "No Bastion SG in VPC - SSH will use VPC CIDR (172.20.0.0/16)"
        log "No Bastion SG found - using VPC CIDR fallback"
    fi

    return 0
}

# Validate configuration files
validate_config() {
    print_header "Validating Configuration Files"

    local config_files=(
        "$VARS_DIR/servers.yml"
        "$VARS_DIR/packages.yml"
        "$VARS_DIR/security_groups.yml"
        "$VARS_DIR/output_vars.yml"
        "$PLAYBOOKS_DIR/security_groups.yml"
        "$PLAYBOOKS_DIR/provision_servers.yml"
        "$PLAYBOOKS_DIR/package_install.yml"
        "$INVENTORY_DIR/aws_ec2.yml"
    )

    for file in "${config_files[@]}"; do
        if [ -f "$file" ]; then
            print_success "Found: $file"
            log "Found: $file"
        else
            log_error "Missing: $file"
            return 1
        fi
    done

    # Validate YAML syntax
    print_step "Validating YAML syntax..."
    if ! ansible-playbook --syntax-check "$PLAYBOOKS_DIR/security_groups.yml" &> /dev/null; then
        log_error "Invalid YAML in security_groups.yml"
        return 1
    fi

    if ! ansible-playbook --syntax-check "$PLAYBOOKS_DIR/provision_servers.yml" &> /dev/null; then
        log_error "Invalid YAML in provision_servers.yml"
        return 1
    fi

    print_success "All YAML files valid"
    return 0
}

# Check AMI ID
validate_ami() {
    print_header "Validating Ubuntu 22.04 AMI"

    local current_ami=$(grep "ubuntu_22_04_ami:" "$VARS_DIR/servers.yml" | awk '{print $2}' | tr -d '"')
    print_info "Current AMI: $current_ami"

    if [[ ! "$current_ami" =~ ^ami-[0-9a-f]{8,}$ ]]; then
        print_warning "AMI ID format may be incorrect: $current_ami"
    fi

    # Check if AMI is accessible
    if aws ec2 describe-images --image-ids "$current_ami" --region us-east-2 &> /dev/null; then
        print_success "AMI is accessible: $current_ami"
        log "AMI is accessible: $current_ami"
    else
        print_warning "Cannot verify AMI: $current_ami"
        print_info "Using: $current_ami (please verify manually if needed)"
        log "AMI verification skipped: $current_ami"
    fi
}

# Get user confirmation
confirm() {
    local prompt="$1"
    local default="${2:-n}"
    local response

    if [ "$AUTO_YES" = true ]; then
        echo -e "${YELLOW}$prompt${NC} [Y] y (auto-confirmed)"
        return 0
    fi

    read -p "$(echo -e ${YELLOW}$prompt${NC}) [${default^^}] " -r response
    response=${response:-$default}

    if [[ "$response" =~ ^[Yy]$ ]]; then
        return 0
    else
        return 1
    fi
}

# Run Ansible playbook with error handling
run_playbook() {
    local playbook_name="$1"
    local limit="${2:-}"
    local playbook_path="$PLAYBOOKS_DIR/${playbook_name}.yml"

    if [ ! -f "$playbook_path" ]; then
        log_error "Playbook not found: $playbook_path"
        return 1
    fi

    print_step "Running playbook: $playbook_name"
    log "Running playbook: $playbook_name"

    local cmd="ansible-playbook $playbook_path"

    if [ -n "$limit" ]; then
        cmd="$cmd --limit $limit"
    fi

    if $cmd 2>> "$ERROR_LOG"; then
        print_success "Playbook completed: $playbook_name"
        log "Playbook completed: $playbook_name"
        return 0
    else
        log_error "Playbook failed: $playbook_name"
        return 1
    fi
}

# Deploy phase: Security Groups
deploy_security_groups() {
    print_header "PHASE 1: Creating Security Groups"

    echo -e "${YELLOW}This will create 3 security groups:${NC}"
    echo "  * vprofile-web-tier-sg"
    echo "  * vprofile-app-tier-sg"
    echo "  * vprofile-db-tier-sg"
    echo ""

    if confirm "Continue with security group creation?"; then
        if run_playbook "security_groups"; then
            # Save state
            echo "security_groups_created=1" >> "$DEPLOYMENT_STATE_FILE"
            print_success "Security groups created successfully"
            return 0
        else
            log_error "Failed to create security groups"
            return 1
        fi
    else
        print_warning "Security groups creation skipped"
        return 1
    fi
}

# Deploy phase: Provision Servers
deploy_provision_servers() {
    print_header "PHASE 2: Provisioning 30 Servers (3 Tiers)"

    echo -e "${YELLOW}This will create:${NC}"
    echo "  * 10 Web Servers (vprofile-web-01 to -10) in public subnets"
    echo "  * 10 App Servers (vprofile-app-01 to -10) in private subnets"
    echo "  * 10 Database Servers (vprofile-db-01 to -10) in private subnets"
    echo ""
    echo -e "${CYAN}Estimated time: 5-10 minutes${NC}"
    echo -e "${CYAN}Estimated cost: ~$1.25/hour (~$900/month for compute)${NC}"
    echo ""

    if confirm "Continue with server provisioning?"; then
        if run_playbook "provision_servers"; then
            echo "servers_provisioned=1" >> "$DEPLOYMENT_STATE_FILE"
            print_success "Servers provisioned successfully"
            return 0
        else
            log_error "Failed to provision servers"
            return 1
        fi
    else
        print_warning "Server provisioning skipped"
        return 1
    fi
}

# Deploy phase: Test Inventory
test_inventory() {
    print_header "PHASE 3: Testing Dynamic Inventory"

    print_step "Discovering instances via AWS tags..."

    local inv_output
    inv_output=$(ansible-inventory -i "$INVENTORY_DIR/aws_ec2.yml" --list 2>/dev/null)

    if [ $? -ne 0 ]; then
        log_error "Inventory test failed"
        return 1
    fi

    # Count hosts per group using JSON output
    local web_count=$(echo "$inv_output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
group = data.get('web_tier', data.get('_web', data.get('web', {})))
print(len(group.get('hosts', [])))
" 2>/dev/null || echo "0")

    local app_count=$(echo "$inv_output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
group = data.get('app_tier', data.get('_app', data.get('app', {})))
print(len(group.get('hosts', [])))
" 2>/dev/null || echo "0")

    local db_count=$(echo "$inv_output" | python3 -c "
import sys, json
data = json.load(sys.stdin)
group = data.get('db_tier', data.get('_db', data.get('db', {})))
print(len(group.get('hosts', [])))
" 2>/dev/null || echo "0")

    print_success "Web Tier: $web_count instances discovered"
    print_success "App Tier: $app_count instances discovered"
    print_success "Database Tier: $db_count instances discovered"

    log "Inventory test passed - Web: $web_count, App: $app_count, DB: $db_count"
    return 0
}

# Deploy phase: Test Connectivity
test_connectivity() {
    print_header "PHASE 4: Testing Connectivity"

    echo -e "${YELLOW}Testing ping to all servers (via Bastion)...${NC}"
    echo ""

    # Test one host per tier with a short timeout
    for tier in web_tier app_tier db_tier; do
        local tier_label=$(echo "$tier" | tr '_' ' ' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1')
        if ansible -i "$INVENTORY_DIR/aws_ec2.yml" "$tier" -m ping --one-line -o 2>&1 | grep -q "pong"; then
            print_success "$tier_label: Reachable"
            log "$tier_label: Reachable"
        else
            print_warning "$tier_label: Not reachable (check SSH key and SG rules)"
            log "$tier_label: Not reachable"
        fi
    done

    return 0
}

# Deploy phase: Install Packages
deploy_packages() {
    print_header "PHASE 5: Installing Packages (Tier-Specific)"

    echo -e "${YELLOW}This will install:${NC}"
    echo "  Web Tier:   Nginx, certbot, fail2ban"
    echo "  App Tier:   Java 17, Python 3, Node.js 20, Docker"
    echo "  DB Tier:    MySQL, PostgreSQL, MongoDB, Redis clients"
    echo ""
    echo -e "${CYAN}Estimated time: 15-20 minutes per tier (sequential)${NC}"
    echo ""

    if confirm "Continue with package installation?"; then
        if run_playbook "package_install"; then
            echo "packages_installed=1" >> "$DEPLOYMENT_STATE_FILE"
            print_success "Packages installed successfully"
            return 0
        else
            log_error "Failed to install packages"
            return 1
        fi
    else
        print_warning "Package installation skipped"
        return 0  # Don't fail, packages can be installed later
    fi
}

# Deploy phase: Apply Patches
deploy_patches() {
    print_header "PHASE 6: Applying OS Patches"

    echo -e "${YELLOW}This will:${NC}"
    echo "  * Update apt cache"
    echo "  * Upgrade all packages"
    echo "  * Reboot servers if kernel updated"
    echo ""
    echo -e "${CYAN}Estimated time: 10-15 minutes per tier${NC}"
    echo -e "${RED}Servers will be rebooted if kernel is updated${NC}"
    echo ""

    if confirm "Continue with patching?"; then
        if run_playbook "patching"; then
            echo "patching_completed=1" >> "$DEPLOYMENT_STATE_FILE"
            print_success "Patching completed successfully"
            return 0
        else
            log_error "Failed to apply patches"
            return 1
        fi
    else
        print_warning "Patching skipped"
        return 0  # Don't fail, can patch later
    fi
}

# Deploy phase: Monitoring & Cost
deploy_monitoring() {
    print_header "PHASE 7: Enabling Monitoring & Cost Tracking"

    echo -e "${YELLOW}This will:${NC}"
    echo "  * Collect system metrics from all servers"
    echo "  * Query AWS Cost Explorer for current month"
    echo "  * Generate HTML cost report"
    echo ""
    echo -e "${CYAN}Estimated time: 2-5 minutes${NC}"
    echo ""

    if confirm "Continue with monitoring setup?"; then
        if run_playbook "monitoring_and_cost"; then
            echo "monitoring_enabled=1" >> "$DEPLOYMENT_STATE_FILE"
            print_success "Monitoring enabled successfully"

            # Display report location
            local latest_report=$(ls -t "$SCRIPT_DIR/reports"/cost_report_*.html 2>/dev/null | head -1)
            if [ -f "$latest_report" ]; then
                print_info "Cost report: $latest_report"
            fi

            return 0
        else
            log_error "Failed to enable monitoring"
            return 1
        fi
    else
        print_warning "Monitoring setup skipped"
        return 0
    fi
}

# Display EC2 instance inventory list
display_inventory() {
    print_header "EC2 INSTANCE INVENTORY"

    local vpc_id=$(grep '^vpc_id:' "$VARS_DIR/output_vars.yml" | awk '{print $2}' | tr -d '"')

    echo -e "${CYAN}Querying AWS for all instances in VPC ${vpc_id}...${NC}"
    echo ""

    # Get all running instances in the VPC grouped by tier
    for tier in web app db; do
        local tier_upper=$(echo "$tier" | tr '[:lower:]' '[:upper:]')
        echo -e "${GREEN}[${tier_upper}] ${tier_upper} TIER INSTANCES${NC}"
        echo "--------------------------------------------------------------"
        printf "  %-25s %-20s %-18s %-15s\n" "NAME" "INSTANCE ID" "PRIVATE IP" "AZ"
        echo "  ---------------------------------------------------------------"

        aws ec2 describe-instances \
            --region us-east-2 \
            --filters \
                "Name=vpc-id,Values=${vpc_id}" \
                "Name=tag:Tier,Values=${tier}" \
                "Name=tag:Project,Values=Vprofile" \
                "Name=instance-state-name,Values=running" \
            --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],ID:InstanceId,IP:PrivateIpAddress,AZ:Placement.AvailabilityZone}' \
            --output text | sort | while read -r az id ip name; do
                printf "  %-25s %-20s %-18s %-15s\n" "$name" "$id" "$ip" "$az"
        done
        echo ""
    done

    # Also get public IPs for web tier
    echo -e "${GREEN}[WEB] WEB TIER PUBLIC IPs (Internet-Facing)${NC}"
    echo "--------------------------------------------------------------"
    printf "  %-25s %-18s %-18s\n" "NAME" "PRIVATE IP" "PUBLIC IP"
    echo "  ---------------------------------------------------------------"

    aws ec2 describe-instances \
        --region us-east-2 \
        --filters \
            "Name=vpc-id,Values=${vpc_id}" \
            "Name=tag:Tier,Values=web" \
            "Name=tag:Project,Values=Vprofile" \
            "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],PrivIP:PrivateIpAddress,PubIP:PublicIpAddress}' \
        --output text | sort | while read -r name privip pubip; do
            pubip=${pubip:-"N/A"}
            printf "  %-25s %-18s %-18s\n" "$name" "$privip" "$pubip"
    done
    echo ""

    # Total count
    local total=$(aws ec2 describe-instances \
        --region us-east-2 \
        --filters \
            "Name=vpc-id,Values=${vpc_id}" \
            "Name=tag:Project,Values=Vprofile" \
            "Name=instance-state-name,Values=running" \
        --query 'Reservations[].Instances[].InstanceId' \
        --output text | wc -w)

    echo -e "${GREEN}[STATS] Total Running Instances: ${total}${NC}"
    echo "=============================================================="
    echo ""

    log "Inventory displayed: $total instances"
}

# Generate deployment summary
generate_summary() {
    local summary_file="$LOGS_DIR/deployment_summary_$(date +%Y%m%d_%H%M%S).txt"

    cat > "$summary_file" << EOF
+================================================================+
|           3-TIER INFRASTRUCTURE DEPLOYMENT SUMMARY             |
+================================================================+

Deployment Date: $(date)
Region: us-east-2
VPC ID: $(grep '^vpc_id:' "$VARS_DIR/output_vars.yml" 2>/dev/null | awk '{print $2}' | tr -d '"')

--------------------------------------------------------------

SECURITY GROUPS CREATED:
  [OK] vprofile-web-tier-sg    (Internet-facing, ports 80/443)
  [OK] vprofile-app-tier-sg    (Restricted to web tier)
  [OK] vprofile-db-tier-sg     (Restricted to app tier, no outbound)

--------------------------------------------------------------

SERVERS PROVISIONED:
  Web Tier (Public Subnets):
    * vprofile-web-01 through vprofile-web-10
    * Instance Type: t3.medium
    * Security Group: vprofile-web-tier-sg
    * Availability Zones: us-east-2a, us-east-2b, us-east-2c

  App Tier (Private Subnets):
    * vprofile-app-01 through vprofile-app-10
    * Instance Type: t3.medium
    * Security Group: vprofile-app-tier-sg
    * Availability Zones: us-east-2a, us-east-2b, us-east-2c

  Database Tier (Private Subnets):
    * vprofile-db-01 through vprofile-db-10
    * Instance Type: t3.medium
    * Security Group: vprofile-db-tier-sg
    * Availability Zones: us-east-2a, us-east-2b, us-east-2c

--------------------------------------------------------------

PACKAGES INSTALLED:
  Web Tier:
    * Nginx (web server)
    * Certbot (SSL certificates)
    * Fail2ban (DDoS protection)

  App Tier:
    * Java 17 JDK
    * Python 3 + pip + boto3
    * Node.js 20 + npm
    * Docker CE + docker-compose

  Database Tier:
    * MySQL client
    * PostgreSQL client
    * MongoDB tools
    * Redis CLI

--------------------------------------------------------------

NETWORK FLOWS:
  [OK] Internet -> Web Tier (80, 443)
  [OK] Web Tier -> App Tier (8000-9000)
  [OK] App Tier -> Database Tier (3306, 5432, 27017, 6379)
  [OK] Bastion -> All Tiers (SSH 22)
  [FAIL] Web Tier -X-> Database Tier (BLOCKED)
  [FAIL] Database Tier -> Internet (BLOCKED - DENY ALL)

--------------------------------------------------------------

ESTIMATED MONTHLY COSTS:
  * 30 × t3.medium instances: ~$900
  * Data transfer: ~$50-100
  * CloudWatch: ~$10
  * ---------------------
  * Total: ~$960-1010/month

--------------------------------------------------------------

NEXT STEPS:
  1. Test connectivity: ansible -i inventory/aws_ec2.yml web_tier -m ping
  2. SSH via Bastion: ssh -J ubuntu@bastion-ip ubuntu@app-server-ip
  3. Review cost report: open reports/cost_report_*.html
  4. Configure ALB for web tier (setup separately)
  5. Deploy your application

--------------------------------------------------------------

DOCUMENTATION:
  * docs/SECURITY_ARCHITECTURE.md - Complete design
  * docs/SECURITY_GROUPS.md - Security group rules
  * docs/NETWORK_FLOWS.md - Traffic flows & testing
  * README.md - Operations guide
  * GETTING_STARTED.md - Step-by-step setup

--------------------------------------------------------------

LOGS:
  Deployment Log: $LOG_FILE
  Error Log: $ERROR_LOG

===================================================================
EOF

    cat "$summary_file"
    print_success "Summary saved to: $summary_file"
}

# Cleanup function (for rollback)
cleanup() {
    print_header "CLEANUP / ROLLBACK"

    echo -e "${RED}WARNING: This will delete all provisioned infrastructure${NC}"
    echo ""

    if confirm "Are you sure you want to delete all servers and security groups?"; then
        if confirm "Last chance - type 'yes' to confirm deletion"; then
            print_step "Terminating all instances..."

            local instance_ids=$(aws ec2 describe-instances \
                --region us-east-2 \
                --filters "Name=tag:Project,Values=Vprofile" "Name=instance-state-name,Values=running,stopped" \
                --query 'Reservations[].Instances[].InstanceId' \
                --output text)

            if [ -n "$instance_ids" ]; then
                aws ec2 terminate-instances --region us-east-2 --instance-ids $instance_ids
                print_success "Termination request sent"
                log "Instances terminated: $instance_ids"
            fi

            print_step "Waiting for instances to terminate (5 minutes)..."
            sleep 300

            print_step "Deleting security groups..."
            local sg_names=("vprofile-web-tier-sg" "vprofile-app-tier-sg" "vprofile-db-tier-sg")
            for sg_name in "${sg_names[@]}"; do
                if aws ec2 describe-security-groups --filters "Name=group-name,Values=$sg_name" --region us-east-2 &> /dev/null; then
                    local sg_id=$(aws ec2 describe-security-groups \
                        --filters "Name=group-name,Values=$sg_name" \
                        --region us-east-2 \
                        --query 'SecurityGroups[0].GroupId' \
                        --output text)
                    aws ec2 delete-security-group --group-id "$sg_id" --region us-east-2
                    print_success "Deleted: $sg_name ($sg_id)"
                    log "Deleted security group: $sg_name ($sg_id)"
                fi
            done

            print_success "Cleanup completed"
            log "Cleanup completed"
        fi
    fi
}

# Main deployment flow
main() {
    clear

    print_header "3-TIER INFRASTRUCTURE DEPLOYMENT"

    echo -e "${CYAN}Region:${NC} us-east-2"
    local display_vpc=$(grep '^vpc_id:' "$VARS_DIR/output_vars.yml" 2>/dev/null | awk '{print $2}' | tr -d '"')
    echo -e "${CYAN}VPC:${NC} ${display_vpc:-unknown}"
    echo -e "${CYAN}Deployment Started:${NC} $(date)"
    echo ""

    # Check for --yes flag
    for arg in "$@"; do
        if [ "$arg" = "--yes" ] || [ "$arg" = "-y" ]; then
            AUTO_YES=true
        fi
    done

    # Parse command line arguments
    case "${1:-deploy}" in
        deploy)
            # Full deployment flow
            setup_logging

            # Phase 0: Validation
            if ! check_prerequisites; then
                log_error "Prerequisites check failed"
                exit 1
            fi

            if ! validate_aws; then
                log_error "AWS validation failed"
                exit 1
            fi

            if ! validate_config; then
                log_error "Configuration validation failed"
                exit 1
            fi

            validate_ami

            # Initialize deployment state
            > "$DEPLOYMENT_STATE_FILE"  # Clear state file

            # Phase 1: Security Groups
            if ! deploy_security_groups; then
                log_error "Deployment failed at Phase 1"
                exit 1
            fi

            # Phase 2: Provision Servers
            if ! deploy_provision_servers; then
                log_error "Deployment failed at Phase 2"
                exit 1
            fi

            # Phase 3: Test Inventory
            if ! test_inventory; then
                print_warning "Inventory test encountered issues"
                # Don't fail, continue
            fi

            # Phase 4: Test Connectivity
            if ! test_connectivity; then
                print_warning "Connectivity test encountered issues"
                # Don't fail, continue
            fi

            # Phase 5: Install Packages
            deploy_packages

            # Phase 6: Apply Patches
            deploy_patches

            # Phase 7: Monitoring
            deploy_monitoring

            # Phase 8: Display EC2 Instance Inventory
            display_inventory

            # Generate summary
            generate_summary

            print_header "DEPLOYMENT COMPLETED"
            print_success "All phases completed successfully"
            log "Deployment completed successfully"
            echo -e "\n${CYAN}Log files:${NC}"
            echo "  * $LOG_FILE"
            echo "  * $ERROR_LOG"
            ;;

        security-groups)
            # Deploy only security groups
            setup_logging
            check_prerequisites || exit 1
            validate_aws || exit 1
            > "$DEPLOYMENT_STATE_FILE"
            deploy_security_groups || exit 1
            ;;

        servers)
            # Deploy only servers
            setup_logging
            check_prerequisites || exit 1
            validate_aws || exit 1
            deploy_provision_servers || exit 1
            ;;

        packages)
            # Install packages
            setup_logging
            deploy_packages || exit 1
            ;;

        patches)
            # Apply patches
            setup_logging
            deploy_patches || exit 1
            ;;

        monitor)
            # Setup monitoring
            setup_logging
            deploy_monitoring || exit 1
            ;;

        test)
            # Run tests only
            setup_logging
            test_inventory || exit 1
            test_connectivity || exit 1
            ;;

        cleanup)
            # Cleanup/rollback
            cleanup
            ;;

        status)
            # Show deployment status
            setup_logging
            if [ -f "$DEPLOYMENT_STATE_FILE" ]; then
                echo "Deployment Status:"
                cat "$DEPLOYMENT_STATE_FILE"
            else
                echo "No deployment state found"
            fi
            ;;

        help|--help|-h)
            print_usage
            ;;

        *)
            print_error "Unknown command: $1"
            print_usage
            exit 1
            ;;
    esac
}

# Print usage
print_usage() {
    cat << EOF
${BLUE}3-TIER INFRASTRUCTURE DEPLOYMENT SCRIPT${NC}

Usage: $0 [command]

${GREEN}Commands:${NC}
  deploy           Full deployment (all phases) - DEFAULT
  security-groups  Deploy only security groups
  servers          Deploy only servers
  packages         Install packages only
  patches          Apply OS patches only
  monitor          Setup monitoring and cost tracking
  test             Run connectivity and inventory tests
  status           Show current deployment status
  cleanup          Destroy all infrastructure (irreversible)
  help             Show this help message

${YELLOW}Examples:${NC}
  $0 deploy           # Full deployment
  $0 security-groups  # Create security groups only
  $0 servers          # Provision servers only
  $0 cleanup          # Delete all resources

${CYAN}Prerequisites:${NC}
  * Ansible 2.10+
  * AWS CLI v2
  * Python 3.8+
  * boto3
  * SSH key at ~/.ssh/vprofile-key.pem

${CYAN}Documentation:${NC}
  * docs/SECURITY_ARCHITECTURE.md
  * docs/SECURITY_GROUPS.md
  * docs/NETWORK_FLOWS.md
  * README.md
  * GETTING_STARTED.md

EOF
}

# Execute main function
main "$@"
