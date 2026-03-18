# Deployment Guide - Automated 3-Tier Infrastructure

This guide explains how to use the automated deployment script to provision the complete 3-tier infrastructure.

## Quick Start

### Prerequisites

Before deploying, ensure you have:

```bash
# Check Ansible
ansible --version  # Should be 2.10 or higher

# Check AWS CLI
aws --version      # Should be v2

# Check Python
python3 --version  # Should be 3.8+

# Check boto3
python3 -c "import boto3; print(boto3.__version__)"

# Check SSH key
ls -la ~/.ssh/vprofile-key.pem  # Should exist with 600 permissions
chmod 600 ~/.ssh/vprofile-key.pem  # Fix permissions if needed

# Configure AWS credentials
aws configure      # Or set AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
```

### Installation

```bash
# Navigate to server-management directory
cd "Ansible-infrastructure/server-management"

# Make script executable
chmod +x deploy.sh

# Verify script
./deploy.sh help
```

---

## Deployment Options

### Option 1: Full Deployment (Recommended)

Deploy everything in one command:

```bash
./deploy.sh deploy
```

**What it does**:
1. ✅ Checks all prerequisites (Ansible, AWS CLI, boto3, SSH key)
2. ✅ Validates AWS configuration (VPC, Bastion SG, credentials)
3. ✅ Validates all configuration files
4. ✅ Creates 3 security groups
5. ✅ Provisions 30 servers (10 per tier)
6. ✅ Tests dynamic inventory
7. ✅ Tests connectivity to all tiers
8. ✅ Installs tier-specific packages
9. ✅ Applies OS patches and reboots if needed
10. ✅ Enables monitoring and cost tracking
11. ✅ Generates deployment summary

**Estimated time**: 45-60 minutes total
**User interaction**: Yes (confirmations at each major phase)

---

### Option 2: Phase-by-Phase Deployment

Deploy each phase separately for more control:

```bash
# Phase 1: Create security groups
./deploy.sh security-groups

# Phase 2: Provision servers
./deploy.sh servers

# Phase 3: Install packages
./deploy.sh packages

# Phase 4: Apply patches
./deploy.sh patches

# Phase 5: Setup monitoring
./deploy.sh monitor
```

**Advantages**:
- Fine-grained control over each phase
- Can stop and resume at any point
- Easier to diagnose issues
- Better for learning/testing

---

## Usage Examples

### Basic Full Deployment

```bash
./deploy.sh deploy
```

Follow the prompts at each phase. Answer "yes" to confirm:
- Security group creation
- Server provisioning
- Package installation
- OS patching
- Monitoring setup

### Deploy Only Security Groups

```bash
./deploy.sh security-groups
```

Useful when you want to:
- Create security groups separately
- Review security group configuration
- Test security rules before provisioning servers

### Deploy Only Servers

```bash
./deploy.sh servers
```

Useful when:
- Security groups already exist
- You want to add more servers to existing infrastructure
- You're scaling up the deployment

### Install Packages on Existing Servers

```bash
./deploy.sh packages
```

Useful for:
- Installing packages on manually created servers
- Updating package list
- Adding new tools to existing infrastructure

### Test Existing Infrastructure

```bash
./deploy.sh test
```

Tests:
- Dynamic inventory discovery
- Connectivity to all servers
- Network accessibility from Ansible controller

### Check Deployment Status

```bash
./deploy.sh status
```

Shows:
- Which phases have completed
- Timestamp of last deployment

### Cleanup / Rollback

```bash
./deploy.sh cleanup
```

⚠️ **WARNING**: This will:
- Terminate all 30 instances
- Delete all 3 security groups
- **This action cannot be undone**

---

## What the Script Does

### Prerequisites Check

Verifies:
- ✅ Ansible installed (2.10+)
- ✅ AWS CLI v2 installed
- ✅ Python 3.8+ installed
- ✅ SSH available
- ✅ boto3 Python package
- ✅ SSH key exists at `~/.ssh/vprofile-key.pem`
- ✅ SSH key permissions are 600

**If any prerequisites are missing**, the script will:
1. Print clear error messages
2. Log errors to file
3. Exit with error code

### AWS Validation

Verifies:
- ✅ AWS credentials are configured
- ✅ VPC exists: `vpc-00ea7a9f5d7626b30`
- ✅ Bastion security group exists
- ✅ AMI is accessible
- ✅ User account has required permissions

### Configuration Validation

Checks:
- ✅ All required files exist
- ✅ YAML files have valid syntax
- ✅ Playbooks can be parsed

### Deployment Phases

#### Phase 1: Security Groups
Creates 3 security groups with tightly scoped rules:
- `vprofile-web-tier-sg` - Allows 80, 443 from internet
- `vprofile-app-tier-sg` - Allows 8000-9000 from web tier
- `vprofile-db-tier-sg` - Allows DB ports from app tier only

**Time**: ~2 minutes

#### Phase 2: Provision Servers
Creates 30 EC2 instances:
- 10 web servers in public subnets
- 10 app servers in private subnets
- 10 database servers in private subnets

All distributed across 3 availability zones.

**Time**: ~8-10 minutes

#### Phase 3: Test Inventory
Verifies:
- AWS EC2 Dynamic inventory works
- Servers are tagged correctly
- Groups `web_tier`, `app_tier`, `db_tier` exist

**Time**: ~1 minute

#### Phase 4: Test Connectivity
Pings all servers to verify:
- SSH access from controller
- Network routing is working
- No security group issues blocking ping

**Time**: ~2 minutes

#### Phase 5: Install Packages
Installs tier-specific packages:
- Web: Nginx, certbot, fail2ban
- App: Java 17, Python 3, Node.js 20, Docker
- DB: MySQL, PostgreSQL, MongoDB, Redis clients

**Time**: ~15-20 minutes

#### Phase 6: Apply Patches
- Updates `apt` cache
- Upgrades all packages
- Reboots servers if kernel updated
- Waits for servers to come back online

**Time**: ~10-15 minutes (includes reboot)

#### Phase 7: Monitoring & Cost
- Collects metrics from all servers
- Queries AWS Cost Explorer
- Generates HTML cost report
- Saves metrics as JSON

**Time**: ~2-5 minutes

---

## Monitoring Deployment

### Real-Time Logs

Watch deployment logs in real-time:

```bash
# In another terminal
tail -f logs/deployment_*.log
```

### Check Progress

```bash
./deploy.sh status
```

### Review Errors

```bash
# Check error log
cat logs/deployment_errors_*.log
```

---

## Troubleshooting

### Script Won't Start

```bash
# Make it executable
chmod +x deploy.sh

# Run with bash explicitly
bash deploy.sh deploy
```

### Prerequisites Failed

```bash
# Install Ansible
pip install ansible

# Install boto3
pip3 install boto3

# Configure AWS
aws configure
```

### Security Groups Already Exist

If SGs already exist from a previous run:

**Option 1: Skip and use existing**
```bash
./deploy.sh servers
```

**Option 2: Delete and recreate**
```bash
aws ec2 delete-security-group --group-name vprofile-web-tier-sg --region us-east-2
aws ec2 delete-security-group --group-name vprofile-app-tier-sg --region us-east-2
aws ec2 delete-security-group --group-name vprofile-db-tier-sg --region us-east-2

./deploy.sh deploy
```

### Servers Won't Reach Running State

Check:
```bash
# Check instance status
aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:Project,Values=Vprofile" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],State:State.Name}'

# Check for errors
aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:Project,Values=Vprofile" \
  --query 'Reservations[].Instances[].StateReason'
```

### Connectivity Test Failed

```bash
# Check if Bastion can reach instances
ssh -i ~/.ssh/vprofile-key.pem ubuntu@bastion-public-ip

# From Bastion, check private network access
ping vprofile-app-01-private-ip

# Check security groups
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=vprofile-app-tier-sg" \
  --region us-east-2
```

### Packages Won't Install

```bash
# Check apt cache on a server
ansible -i inventory/aws_ec2.yml app_tier -m shell -a "apt update" --limit vprofile-app-01

# Check disk space
ansible -i inventory/aws_ec2.yml app_tier -m shell -a "df -h" --limit vprofile-app-01

# Check internet connectivity
ansible -i inventory/aws_ec2.yml app_tier -m shell -a "curl https://archive.ubuntu.com" --limit vprofile-app-01
```

---

## Post-Deployment

### Access Servers

```bash
# Connect via Bastion
ssh -J ubuntu@bastion-public-ip ubuntu@vprofile-app-01-private-ip

# Or configure SSH config
cat >> ~/.ssh/config << EOF
Host bastion
    HostName bastion-public-ip
    User ubuntu
    IdentityFile ~/.ssh/vprofile-key.pem

Host app
    HostName vprofile-app-01-private-ip
    User ubuntu
    IdentityFile ~/.ssh/vprofile-key.pem
    ProxyJump bastion
EOF

ssh app
```

### Verify Installation

```bash
# Check packages
ansible -i inventory/aws_ec2.yml app_tier -m shell -a "java -version && node --version && docker --version"

# Check services
ansible -i inventory/aws_ec2.yml web_tier -m shell -a "sudo systemctl status nginx"

# Check security
ansible -i inventory/aws_ec2.yml app_tier -m shell -a "sudo ufw status"
```

### Configure Load Balancer

Create an ALB for Web Tier (not included in script):

```bash
# Create ALB
aws elbv2 create-load-balancer \
  --name vprofile-alb \
  --subnets subnet-09bc2124ef62ca72b subnet-026f8265f7e6f8615 \
  --security-groups sg-xxx \
  --region us-east-2

# Create target group
aws elbv2 create-target-group \
  --name vprofile-web-targets \
  --protocol HTTP \
  --port 8080 \
  --vpc-id vpc-00ea7a9f5d7626b30

# Register targets (web tier instances)
aws elbv2 register-targets \
  --target-group-arn arn:aws:... \
  --targets Id=i-xxx Id=i-yyy ...
```

---

## Logs & Reports

### Deployment Logs

Located in `logs/` directory:

```bash
# View deployment log
cat logs/deployment_YYYYMMDD_HHMMSS.log

# View error log
cat logs/deployment_errors_YYYYMMDD_HHMMSS.log

# View summary
cat logs/deployment_summary_YYYYMMDD_HHMMSS.txt
```

### Cost Report

Located in `reports/` directory:

```bash
# View HTML cost report
open reports/cost_report_YYYY-MM-DD.html

# View JSON metrics
cat reports/metrics_*.json | jq
```

---

## Advanced Options

### Custom Variables

To customize deployment, edit before running:

```bash
# Edit server definitions
vim vars/servers.yml

# Edit packages
vim vars/packages.yml

# Edit security group rules
vim vars/security_groups.yml
```

### Run Specific Tier Only

```bash
# Install packages only on web tier
ansible-playbook playbooks/package_install.yml --limit web_tier

# Patch only app tier
ansible-playbook playbooks/patching.yml --limit app_tier

# Monitor only database tier
ansible-playbook playbooks/monitoring_and_cost.yml --limit db_tier
```

### Dry Run (Check Mode)

```bash
# Preview what would happen (no changes)
ansible-playbook playbooks/provision_servers.yml --check
```

---

## Cost Tracking

After deployment, check costs:

```bash
# View generated report
open reports/cost_report_*.html

# Query AWS Cost Explorer directly
aws ce get-cost-and-usage \
  --time-period Start=$(date +%Y-%m-01) End=$(date +%Y-%m-%d) \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE \
  --region us-east-2
```

---

## FAQ

### Q: Can I deploy to a different region?

**A**: Edit `vars/output_vars.yml` and `vars/servers.yml` to change region. Currently configured for us-east-2.

### Q: Can I change instance types?

**A**: Edit `vars/servers.yml`, change `instance_type: t3.medium` to desired type (e.g., t3.small, t3.large).

### Q: Can I deploy just a subset of servers?

**A**: Edit `vars/servers.yml` and reduce the number of servers in each tier.

### Q: How do I add a new security group rule?

**A**: Edit `vars/security_groups.yml` and add rule, then run:
```bash
./deploy.sh security-groups
```

### Q: Can I update servers after deployment?

**A**: Yes! Rerun playbooks:
```bash
./deploy.sh patches    # Update OS
./deploy.sh packages   # Install new packages
```

### Q: How do I access the database tier?

**A**: Via Bastion SSH or through app tier:
```bash
ssh -J ubuntu@bastion ubuntu@db-server
```

### Q: What if deployment fails mid-way?

**A**: Check logs, fix issues, and rerun:
```bash
./deploy.sh deploy     # Will continue from where it failed
```

---

## Support

For issues:

1. **Check logs**: `tail -f logs/deployment_*.log`
2. **Read documentation**: `docs/SECURITY_ARCHITECTURE.md`
3. **Test connectivity**: `./deploy.sh test`
4. **Check AWS Console**: Verify instances, SGs, networking
5. **Review error log**: `cat logs/deployment_errors_*.log`

---

## Additional Resources

- `README.md` - Full documentation
- `SECURITY_ARCHITECTURE.md` - Design overview
- `SECURITY_GROUPS.md` - Security rules
- `NETWORK_FLOWS.md` - Traffic testing
- `QUICK_REFERENCE.md` - Command cheatsheet
