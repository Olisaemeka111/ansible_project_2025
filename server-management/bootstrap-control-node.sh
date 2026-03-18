#!/bin/bash

################################################################################
# Control Node Bootstrap Script
# Purpose: Automate Ansible control node setup on EC2
# Usage: bash bootstrap-control-node.sh <s3-bucket-name> [aws-region]
################################################################################

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
S3_BUCKET="${1}"
AWS_REGION="${2:-us-east-2}"
DEPLOY_DIR="$HOME/ansible-deploy"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

################################################################################
# Logging Functions
################################################################################

log_info() {
    echo -e "${BLUE}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

################################################################################
# Validation Functions
################################################################################

validate_inputs() {
    if [ -z "$S3_BUCKET" ]; then
        log_error "S3 bucket name is required"
        echo "Usage: bash bootstrap-control-node.sh <s3-bucket-name> [aws-region]"
        echo "Example: bash bootstrap-control-node.sh vprofile-ansible-deployment-1234567890 us-east-2"
        exit 1
    fi

    log_info "S3 Bucket: $S3_BUCKET"
    log_info "AWS Region: $AWS_REGION"
    log_info "Deploy Directory: $DEPLOY_DIR"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check internet connectivity
    if ! ping -c 1 8.8.8.8 &> /dev/null; then
        log_warning "No internet connectivity detected"
    fi

    # Check AWS CLI
    if ! command -v aws &> /dev/null; then
        log_warning "AWS CLI not found, will install"
    else
        log_success "AWS CLI installed: $(aws --version)"
    fi

    # Check Python
    if ! command -v python3 &> /dev/null; then
        log_error "Python 3 not found"
        exit 1
    fi
    log_success "Python 3 found: $(python3 --version)"
}

################################################################################
# Installation Functions
################################################################################

install_dependencies() {
    log_info "Installing system dependencies..."

    sudo apt-get update -qq
    sudo apt-get install -y \
        python3-pip \
        python3-venv \
        git \
        curl \
        wget \
        unzip \
        jq \
        &> /dev/null

    log_success "System dependencies installed"
}

install_aws_cli() {
    log_info "Installing AWS CLI v2..."

    if command -v aws &> /dev/null; then
        log_success "AWS CLI already installed: $(aws --version)"
        return
    fi

    cd /tmp
    curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q awscliv2.zip
    sudo ./aws/install > /dev/null 2>&1
    rm -rf aws awscliv2.zip
    cd - > /dev/null

    log_success "AWS CLI v2 installed: $(aws --version)"
}

install_ansible() {
    log_info "Installing Ansible and Python packages..."

    pip3 install --user --quiet \
        ansible \
        boto3 \
        botocore \
        jinja2 &> /dev/null

    # Add to PATH if not already there
    if ! grep -q "\.local/bin" ~/.bashrc 2>/dev/null; then
        echo 'export PATH=$PATH:~/.local/bin' >> ~/.bashrc
    fi

    # Source bashrc
    source ~/.bashrc

    log_success "Ansible installed: $(ansible --version | head -1)"
    log_success "boto3 installed: $(python3 -c "import boto3; print(f'v{boto3.__version__}')" 2>/dev/null)"
}

################################################################################
# AWS Configuration Functions
################################################################################

verify_aws_credentials() {
    log_info "Verifying AWS credentials..."

    # Set region
    aws configure set region $AWS_REGION --profile default
    export AWS_DEFAULT_REGION=$AWS_REGION

    # Test credentials
    if ! aws sts get-caller-identity --region $AWS_REGION &> /dev/null; then
        log_error "AWS credentials not configured or invalid"
        log_info "Please configure AWS credentials:"
        log_info "  aws configure"
        exit 1
    fi

    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    USER_ID=$(aws sts get-caller-identity --query UserId --output text)

    log_success "AWS credentials verified"
    log_success "Account ID: $ACCOUNT_ID"
    log_success "User ID: $USER_ID"
}

verify_s3_bucket() {
    log_info "Verifying S3 bucket access..."

    if ! aws s3api head-bucket --bucket "$S3_BUCKET" --region $AWS_REGION &> /dev/null; then
        log_error "Cannot access S3 bucket: $S3_BUCKET"
        log_info "Verify:"
        log_info "  1. Bucket exists in region: $AWS_REGION"
        log_info "  2. IAM role has S3 permissions"
        log_info "  3. Bucket name is correct"
        exit 1
    fi

    log_success "S3 bucket accessible: $S3_BUCKET"
}

################################################################################
# Code Deployment Functions
################################################################################

download_from_s3() {
    log_info "Downloading code from S3..."

    # Create deploy directory
    mkdir -p "$DEPLOY_DIR"
    cd "$DEPLOY_DIR"

    # Download archive
    if ! aws s3 cp s3://$S3_BUCKET/ansible-code.tar.gz . --region $AWS_REGION &> /dev/null; then
        log_error "Failed to download ansible-code.tar.gz from S3"
        log_info "Verify file exists:"
        log_info "  aws s3 ls s3://$S3_BUCKET/ --region $AWS_REGION"
        exit 1
    fi

    if [ ! -f "ansible-code.tar.gz" ]; then
        log_error "Download failed - file not found"
        exit 1
    fi

    log_success "Downloaded: ansible-code.tar.gz ($(du -h ansible-code.tar.gz | cut -f1))"
}

extract_archive() {
    log_info "Extracting archive..."

    cd "$DEPLOY_DIR"

    if ! tar -xzf ansible-code.tar.gz; then
        log_error "Failed to extract archive"
        exit 1
    fi

    # Verify structure
    if [ ! -d "Ansible-infrastructure/server-management" ]; then
        log_error "Invalid archive structure"
        exit 1
    fi

    log_success "Archive extracted"
    log_info "Directory structure:"
    log_info "  $(ls -d Ansible-infrastructure/server-management/* 2>/dev/null | sed 's/^/    /')"
}

setup_ansible() {
    log_info "Setting up Ansible configuration..."

    cd "$DEPLOY_DIR/Ansible-infrastructure/server-management"

    # Make deploy script executable
    chmod +x deploy.sh

    # Set AWS region for dynamic inventory
    export AWS_DEFAULT_REGION=$AWS_REGION

    # Verify ansible.cfg
    if [ ! -f "ansible.cfg" ]; then
        log_warning "ansible.cfg not found, creating default..."
        cat > ansible.cfg << 'EOF'
[defaults]
inventory = inventory/aws_ec2.yml
host_key_checking = False
remote_user = ubuntu
private_key_file = ~/.ssh/vprofile-key.pem
ansible_python_interpreter = /usr/bin/python3
deprecation_warnings = False
gather_timeout = 60
timeout = 300

[inventory]
enable_plugins = amazon.aws.aws_ec2

[privilege_escalation]
become = True
become_method = sudo
become_user = root
become_ask_pass = False
EOF
    fi

    log_success "Ansible configuration ready"
}

install_aws_collection() {
    log_info "Installing AWS Ansible collection..."

    if ! ansible-galaxy collection install amazon.aws --force-with-deps -q &> /dev/null; then
        log_warning "Failed to install AWS collection, attempting retry..."
        ansible-galaxy collection install amazon.aws --force-with-deps -q
    fi

    log_success "AWS collection installed"
}

################################################################################
# Testing Functions
################################################################################

test_aws_connectivity() {
    log_info "Testing AWS connectivity..."

    cd "$DEPLOY_DIR/Ansible-infrastructure/server-management"

    # Test AWS credentials
    if ! aws sts get-caller-identity --region $AWS_REGION &> /dev/null; then
        log_error "AWS credentials test failed"
        return 1
    fi
    log_success "AWS credentials verified"

    # Test S3 access
    if ! aws s3 ls s3://$S3_BUCKET --region $AWS_REGION &> /dev/null; then
        log_error "S3 bucket access test failed"
        return 1
    fi
    log_success "S3 bucket accessible"

    return 0
}

test_ansible_inventory() {
    log_info "Testing Ansible dynamic inventory..."

    cd "$DEPLOY_DIR/Ansible-infrastructure/server-management"

    # Count discovered hosts
    HOST_COUNT=$(ansible-inventory -i inventory/aws_ec2.yml --list 2>/dev/null | jq '.all.hosts | length' 2>/dev/null || echo 0)

    if [ "$HOST_COUNT" -eq 0 ]; then
        log_warning "No hosts discovered in inventory"
        log_info "This is normal if servers haven't been deployed yet"
        log_info "Servers will be discovered once deploy.sh runs"
    else
        log_success "Discovered $HOST_COUNT host(s) in inventory"

        # Show groups
        GROUPS=$(ansible-inventory -i inventory/aws_ec2.yml --graph 2>/dev/null | grep "@" | wc -l)
        log_info "Found $GROUPS tier groups (web_tier, app_tier, db_tier)"
    fi

    return 0
}

test_deploy_script() {
    log_info "Testing deploy script..."

    cd "$DEPLOY_DIR/Ansible-infrastructure/server-management"

    if ! ./deploy.sh help &> /dev/null; then
        log_error "Deploy script test failed"
        return 1
    fi

    log_success "Deploy script is functional"
    return 0
}

################################################################################
# Summary & Instructions
################################################################################

print_summary() {
    cat << EOF

${GREEN}═══════════════════════════════════════════════════════════════${NC}
${GREEN}  CONTROL NODE BOOTSTRAP COMPLETE! ✓${NC}
${GREEN}═══════════════════════════════════════════════════════════════${NC}

${BLUE}Setup Details:${NC}
  • Location: $DEPLOY_DIR
  • S3 Bucket: $S3_BUCKET
  • AWS Region: $AWS_REGION
  • Timestamp: $TIMESTAMP

${BLUE}Installed Components:${NC}
  ✓ Ansible $(ansible --version | head -1 | awk '{print $2}')
  ✓ AWS CLI $(aws --version | awk '{print $1}')
  ✓ Python 3 $(python3 --version | awk '{print $2}')
  ✓ boto3 $(python3 -c "import boto3; print(boto3.__version__)" 2>/dev/null)
  ✓ aws_ec2 inventory plugin

${BLUE}Next Steps:${NC}

  1. Verify SSH key is available for managed servers:
     ls -la ~/.ssh/vprofile-key.pem
     chmod 600 ~/.ssh/vprofile-key.pem

  2. Navigate to deployment directory:
     cd $DEPLOY_DIR/Ansible-infrastructure/server-management

  3. Test Ansible connectivity (after servers are created):
     ansible -i inventory/aws_ec2.yml all -m ping --limit 1

  4. Run full deployment:
     ./deploy.sh deploy

  5. Monitor deployment:
     tail -f logs/deployment_*.log

${BLUE}Available Commands:${NC}

  Full deployment:
    ./deploy.sh deploy

  Phase-by-phase:
    ./deploy.sh security-groups    # Create security groups
    ./deploy.sh servers             # Provision servers
    ./deploy.sh packages            # Install packages
    ./deploy.sh patches             # Apply patches
    ./deploy.sh monitor             # Setup monitoring

  Utilities:
    ./deploy.sh test                # Test connectivity
    ./deploy.sh status              # Check deployment status
    ./deploy.sh help                # Show help message
    ./deploy.sh cleanup             # Destroy infrastructure (IRREVERSIBLE!)

${BLUE}Documentation:${NC}
  • docs/SECURITY_ARCHITECTURE.md - Network design
  • docs/SECURITY_GROUPS.md - Security rules
  • docs/NETWORK_FLOWS.md - Traffic flows & testing
  • DEPLOYMENT_GUIDE.md - Full walkthrough
  • PRE_DEPLOYMENT_CHECKLIST.md - Verification steps

${BLUE}Troubleshooting:${NC}
  Check logs:
    ls -la logs/
    tail -f logs/deployment_*.log

  Debug inventory:
    ansible-inventory -i inventory/aws_ec2.yml --list | jq

  Test AWS access:
    aws sts get-caller-identity
    aws s3 ls

${GREEN}═══════════════════════════════════════════════════════════════${NC}

Ready to deploy! Happy automating! 🚀

EOF
}

################################################################################
# Main Execution
################################################################################

main() {
    log_info "Starting Control Node Bootstrap..."
    log_info "============================================"

    validate_inputs

    log_info "Phase 1: Prerequisites Check"
    check_prerequisites

    log_info "Phase 2: System Dependencies"
    install_dependencies
    install_aws_cli
    install_ansible

    log_info "Phase 3: AWS Configuration"
    verify_aws_credentials
    verify_s3_bucket

    log_info "Phase 4: Code Deployment"
    download_from_s3
    extract_archive
    setup_ansible
    install_aws_collection

    log_info "Phase 5: Testing"
    test_aws_connectivity
    test_ansible_inventory
    test_deploy_script

    log_success "All tests passed!"

    log_info "============================================"
    print_summary
}

# Run main function
main "$@"
