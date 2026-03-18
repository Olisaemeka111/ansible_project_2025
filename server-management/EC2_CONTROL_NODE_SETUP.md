# EC2 Control Node Setup Guide

## Overview

Instead of running Ansible from your local machine, you'll use an EC2 instance as the **Ansible Control Node**. This instance will:
- Run the `deploy.sh` script
- Execute all Ansible playbooks
- Manage the 30 infrastructure servers
- Access AWS APIs for dynamic inventory

**Architecture**:
```
Your Local Machine
        ↓ (SSH)
Control Node EC2 (runs Ansible)
        ↓ (SSH via Bastion or direct)
Web Tier (10 servers)
App Tier (10 servers)
Database Tier (10 servers)
```

---

## Step 1: Launch Control Node EC2 Instance

### 1.1 Create Instance in AWS Console

1. **Go to EC2 Dashboard** → Instances → Launch Instances
2. **Name**: `ansible-control-node`
3. **AMI**: Ubuntu 22.04 LTS (same as managed servers)
4. **Instance Type**: `t3.medium` (or `t3.small` if budget-conscious)
5. **Key Pair**: Use existing `vprofile-key` or create new
6. **VPC**: `vpc-00ea7a9f5d7626b30`
7. **Subnet**: **PUBLIC subnet** (pubsub1, pubsub2, or pubsub3) - needs internet access
8. **Auto-assign public IP**: **Yes** - you'll SSH to this from your machine
9. **Security Group**: Create new or use existing with:
   - Inbound: SSH (port 22) from your IP or 0.0.0.0/0
   - Outbound: All traffic (needs to reach AWS APIs, Git, package repos)
10. **Storage**: 30 GB (default is fine)
11. **Tags**:
    - Name: `ansible-control-node`
    - Project: `Vprofile`
    - Owner: `DevOps Team`
    - Role: `control-node`

### 1.2 Launch and Wait

Click **Launch Instance** and wait for it to reach **Running** state.
Get the **Public IP** from the instance details (e.g., `54.123.45.67`).

---

## Step 2: Connect to Control Node

### 2.1 SSH from Local Machine

```bash
# Replace with your instance's public IP
ssh -i ~/.ssh/vprofile-key.pem ubuntu@54.123.45.67

# You should now be logged in as ubuntu user
ubuntu@ip-10-0-1-xx:~$
```

### 2.2 Verify Basic System

```bash
# Check OS
uname -a
# Expected: Linux ... #1 SMP ... x86_64 GNU/Linux

# Check Python
python3 --version
# Expected: Python 3.10 or higher

# Check available disk
df -h
# Should show ~30 GB available
```

---

## Step 3: Install Ansible & Dependencies

### 3.1 Update System

```bash
sudo apt update
sudo apt upgrade -y
sudo apt install -y python3-pip python3-venv git curl wget
```

### 3.2 Install Ansible

```bash
# Install via pip (recommended for latest version)
pip3 install --user ansible boto3 botocore

# Verify installation
ansible --version
# Expected: ansible [core 2.15.x] or higher

# Verify boto3
python3 -c "import boto3; print(boto3.__version__)"
# Expected: 1.26.x or higher
```

### 3.3 Add Ansible to PATH

```bash
# Add to ~/.bashrc if not already there
echo 'export PATH=$PATH:~/.local/bin' >> ~/.bashrc
source ~/.bashrc

# Test
ansible --version
```

---

## Step 4: Setup AWS Credentials

### 4.1 Option A: AWS CLI Configuration (Recommended)

```bash
# Install AWS CLI v2
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

# Verify
aws --version
# Expected: aws-cli/2.x.x
```

### 4.2 Option B: Environment Variables

If you prefer environment variables instead of `aws configure`:

```bash
# Add to ~/.bashrc
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export AWS_DEFAULT_REGION="us-east-2"

source ~/.bashrc
```

### 4.3 Configure AWS Credentials

```bash
# Interactive configuration
aws configure

# When prompted, enter:
# AWS Access Key ID: [your-key]
# AWS Secret Access Key: [your-secret]
# Default region name: us-east-2
# Default output format: json

# Verify credentials
aws sts get-caller-identity
# Expected: Account, UserId, Arn output
```

---

## Step 5: Clone Project & Setup SSH Keys

### 5.1 Clone Repository

```bash
# If using GitHub
git clone <your-repo-url>
cd Ansible-infrastructure/server-management

# Or if using local copy, download files via SCP
# From your local machine:
# scp -i ~/.ssh/vprofile-key.pem -r Ansible-infrastructure/server-management ubuntu@54.123.45.67:~/
```

### 5.2 Copy SSH Key

The control node needs the SSH key to connect to managed servers:

```bash
# From your local machine:
scp -i ~/.ssh/vprofile-key.pem ~/.ssh/vprofile-key.pem ubuntu@54.123.45.67:~/.ssh/

# SSH to control node and fix permissions
ssh -i ~/.ssh/vprofile-key.pem ubuntu@54.123.45.67

# On control node:
chmod 600 ~/.ssh/vprofile-key.pem
ls -la ~/.ssh/vprofile-key.pem
# Expected: -rw------- 1 ubuntu ubuntu ... vprofile-key.pem
```

---

## Step 6: Setup Ansible Configuration

### 6.1 Create ansible.cfg (if not already present)

```bash
cd ~/Ansible-infrastructure/server-management

# Create ansible.cfg
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

cat ansible.cfg
```

### 6.2 Install AWS Collection

```bash
# Install amazon.aws collection
ansible-galaxy collection install amazon.aws

# Verify
ansible-galaxy collection list | grep amazon.aws
# Expected: amazon.aws 6.x.x or higher
```

### 6.3 Test Dynamic Inventory

```bash
# List all discovered instances
ansible-inventory -i inventory/aws_ec2.yml --list | head -50

# List grouped hosts
ansible-inventory -i inventory/aws_ec2.yml --graph
# Expected output showing web_tier, app_tier, db_tier groups
```

---

## Step 7: Verify Connectivity to Bastion

The control node must be able to reach your Bastion host (and through it, the managed servers):

```bash
# Test SSH to Bastion
ssh -i ~/.ssh/vprofile-key.pem ubuntu@<bastion-public-ip> echo "Connected"
# Expected: "Connected" output

# If Bastion is in private subnet (uncommon), this won't work directly
# In that case, use jump host or Systems Manager Session Manager
```

---

## Step 8: Test Ansible Connectivity

### 8.1 Ping All Tiers

```bash
# Ping web tier (public subnet servers)
ansible -i inventory/aws_ec2.yml web_tier -m ping

# Ping app tier (private subnet servers - via Bastion)
ansible -i inventory/aws_ec2.yml app_tier -m ping

# Ping db tier (private subnet servers - via Bastion)
ansible -i inventory/aws_ec2.yml db_tier -m ping
```

**Note**: If app_tier and db_tier fail to ping, you may need to configure SSH jump through Bastion. See **Step 9**.

---

## Step 9: Configure SSH Jump Through Bastion (If Needed)

If your control node can't directly reach app/db tier servers (they're in private subnets):

### 9.1 Create SSH Config

```bash
# On control node
cat > ~/.ssh/config << 'EOF'
Host bastion
    HostName <bastion-public-ip>
    User ubuntu
    IdentityFile ~/.ssh/vprofile-key.pem
    StrictHostKeyChecking no

Host 10.0.* 172.16.* 192.168.*
    ProxyJump bastion
    User ubuntu
    IdentityFile ~/.ssh/vprofile-key.pem
    StrictHostKeyChecking no
EOF

chmod 600 ~/.ssh/config
```

### 9.2 Update ansible.cfg

```bash
# Add to ansible.cfg [defaults] section
cat >> ansible.cfg << 'EOF'

# SSH settings for bastion jump
ssh_args = -o ProxyCommand="ssh -W %h:%p -i ~/.ssh/vprofile-key.pem ubuntu@<bastion-public-ip>"
EOF
```

### 9.3 Test Connectivity Again

```bash
# Test web tier
ansible -i inventory/aws_ec2.yml web_tier -m ping

# Test app tier (should now work via Bastion)
ansible -i inventory/aws_ec2.yml app_tier -m ping

# Test db tier (should now work via Bastion)
ansible -i inventory/aws_ec2.yml db_tier -m ping
```

---

## Step 10: Make deploy.sh Executable

```bash
cd ~/Ansible-infrastructure/server-management
chmod +x deploy.sh
./deploy.sh help
# Expected: Help message displayed
```

---

## Step 11: Run Pre-Deployment Checks

```bash
# Verify all prerequisites on control node
ansible --version
aws --version
python3 --version
python3 -c "import boto3; print('boto3 OK')"

# Verify AWS credentials
aws sts get-caller-identity

# Test Ansible connectivity
ansible -i inventory/aws_ec2.yml all -m ping --limit 1
```

---

## Step 12: Ready for Deployment!

You're now ready to run the deployment:

```bash
cd ~/Ansible-infrastructure/server-management

# Full deployment
./deploy.sh deploy

# Or deploy phase-by-phase
./deploy.sh security-groups
./deploy.sh servers
./deploy.sh packages
./deploy.sh patches
./deploy.sh monitor
```

---

## Troubleshooting

### Issue: SSH key permissions error

```bash
# Fix on control node
chmod 600 ~/.ssh/vprofile-key.pem
chmod 700 ~/.ssh
```

### Issue: Can't reach app/db tier servers

```bash
# Verify Bastion access first
ssh -i ~/.ssh/vprofile-key.pem ubuntu@<bastion-ip> echo "Bastion OK"

# If that fails, check Bastion security group allows SSH from control node's IP
# If that works, check app/db tier security groups allow SSH from Bastion

# Test with explicit jump
ssh -i ~/.ssh/vprofile-key.pem -J ubuntu@<bastion-ip> ubuntu@<app-server-private-ip> echo "App tier OK"
```

### Issue: Dynamic inventory shows no hosts

```bash
# Check AWS credentials
aws ec2 describe-instances --region us-east-2 --query 'Reservations[].Instances[]' | head -20

# If empty, check:
# 1. VPC ID is correct in vars/servers.yml
# 2. Servers are tagged with Project: Vprofile
# 3. Servers are in running state
# 4. Region is us-east-2
```

### Issue: Ansible says "host unreachable"

```bash
# Check if you can SSH directly
ssh -i ~/.ssh/vprofile-key.pem ubuntu@<instance-private-ip> echo "Direct SSH OK"

# If direct fails, try via Bastion
ssh -i ~/.ssh/vprofile-key.pem -J ubuntu@<bastion-ip> ubuntu@<instance-private-ip> echo "Jump SSH OK"

# If both fail, check:
# 1. Security group allows SSH (port 22) from Bastion
# 2. Network ACLs allow traffic
# 3. VPC routing is correct
```

### Issue: "Permission denied (publickey)"

```bash
# Verify SSH key is readable
ls -la ~/.ssh/vprofile-key.pem
# Should be: -rw------- (600)

# Verify SSH key is correct
ssh-keygen -l -f ~/.ssh/vprofile-key.pem
# Should match the key in AWS EC2 key pairs
```

---

## Monitoring Logs from Local Machine

While deployment runs on control node, you can watch logs from your local machine:

```bash
# SSH into control node and tail logs
ssh -i ~/.ssh/vprofile-key.pem ubuntu@54.123.45.67 tail -f ~/Ansible-infrastructure/server-management/logs/deployment_*.log

# Or download logs after deployment
scp -i ~/.ssh/vprofile-key.pem -r ubuntu@54.123.45.67:~/Ansible-infrastructure/server-management/logs ./
scp -i ~/.ssh/vprofile-key.pem -r ubuntu@54.123.45.67:~/Ansible-infrastructure/server-management/reports ./
```

---

## Control Node vs Local Machine

### Advantages of EC2 Control Node
✅ Ansible control node is within AWS (faster network)
✅ Access to AWS APIs without SSH tunneling
✅ Can run long deployments without laptop being on
✅ All Ansible state in one place
✅ Easy to automate/repeat deployments
✅ Better for team collaboration

### Disadvantages
❌ Extra EC2 cost (~$30-50/month for t3.medium)
❌ One more instance to manage
❌ Must SSH to control node to run playbooks

---

## Network Topology with EC2 Control Node

```
Your Local Machine (your-ip)
        ↓ SSH (22)
EC2 Control Node (public subnet)
        ↓ SSH (22) direct or via Bastion
Web Tier (10 servers - public subnets)
        ↓ custom ports (8000-9000)
App Tier (10 servers - private subnets)
        ↓ custom ports (3306, 5432, 27017, 6379)
Database Tier (10 servers - private subnets)

All within VPC: vpc-00ea7a9f5d7626b30
Region: us-east-2
```

---

## Next Steps

1. Launch EC2 control node (follow Step 1-2)
2. Install Ansible & dependencies (Step 3-4)
3. Copy project files & SSH keys (Step 5)
4. Configure Ansible (Step 6)
5. Test connectivity (Step 8-9)
6. Run deployment (Step 12)

---

## Quick Reference

```bash
# SSH to control node
ssh -i ~/.ssh/vprofile-key.pem ubuntu@<control-node-public-ip>

# Check deployment status
./deploy.sh status

# View logs
tail -f logs/deployment_*.log

# View cost report
cat reports/cost_report_*.html | head -50

# Clean up everything (IRREVERSIBLE)
./deploy.sh cleanup
```

---

**Control Node is now ready for deployment!** 🚀
