# SSM + S3 Deployment Guide

## Overview

Instead of SSH, use **AWS Systems Manager Session Manager** to access the control node securely, and **S3** to distribute the Ansible code. This approach:
- ✅ No SSH keys needed
- ✅ No public IP required
- ✅ All access logged in CloudTrail
- ✅ IAM-based access control
- ✅ More secure & auditable

**Architecture**:
```
Your Local Machine
        ↓ (AWS CLI + IAM)
Control Node EC2 (private subnet)
        ↓ (S3 bucket pull)
S3 Bucket (ansible code + vars)
        ↓ (Ansible playbooks)
Web Tier (10 servers)
App Tier (10 servers)
Database Tier (10 servers)
```

---

## Step 1: Prepare S3 Bucket

### 1.1 Create S3 Bucket

```bash
# From your local machine
aws s3 mb s3://vprofile-ansible-deployment-$(date +%s) --region us-east-2

# Note the bucket name (example: vprofile-ansible-deployment-1234567890)
export S3_BUCKET="vprofile-ansible-deployment-1234567890"
echo $S3_BUCKET
```

### 1.2 Compress Ansible Code

```bash
# From your local machine, navigate to parent directory
cd "Terraform repository/Ansible infrastructure"

# Create tar archive
tar -czf ansible-code.tar.gz Ansible-infrastructure/

# Verify archive
tar -tzf ansible-code.tar.gz | head -20
```

### 1.3 Upload to S3

```bash
# Upload archive to S3
aws s3 cp ansible-code.tar.gz s3://$S3_BUCKET/ansible-code.tar.gz --region us-east-2

# Verify upload
aws s3 ls s3://$S3_BUCKET/ --region us-east-2
# Expected: ansible-code.tar.gz listed
```

---

## Step 2: Create IAM Role for Control Node

### 2.1 Create Trust Policy

```bash
# Create trust policy file
cat > trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

# Create the role
aws iam create-role \
  --role-name ansible-control-node-role \
  --assume-role-policy-document file://trust-policy.json \
  --region us-east-2
```

### 2.2 Create Policy for S3 & EC2 Access

```bash
# Create inline policy
cat > s3-ec2-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::vprofile-ansible-deployment-*",
        "arn:aws:s3:::vprofile-ansible-deployment-*/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "ec2:*",
        "ec2-instance-connect:*"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "ssm:*",
        "ssmmessages:*",
        "ec2messages:*"
      ],
      "Resource": "*"
    }
  ]
}
EOF

# Attach policy to role
aws iam put-role-policy \
  --role-name ansible-control-node-role \
  --policy-name AnsibleControlNodePolicy \
  --policy-document file://s3-ec2-policy.json
```

### 2.3 Create Instance Profile

```bash
# Create instance profile
aws iam create-instance-profile \
  --instance-profile-name ansible-control-node-profile

# Add role to instance profile
aws iam add-role-to-instance-profile \
  --instance-profile-name ansible-control-node-profile \
  --role-name ansible-control-node-role
```

---

## Step 3: Launch Control Node with IAM Role

### 3.1 Launch via AWS Console

1. **EC2 Dashboard** → **Launch Instances**
2. **Name**: `ansible-control-node`
3. **AMI**: Ubuntu 22.04 LTS
4. **Instance Type**: `t3.medium`
5. **Key Pair**: (can skip since we're using SSM)
6. **VPC**: `vpc-00ea7a9f5d7626b30`
7. **Subnet**: Can be **PRIVATE** subnet (no need for public IP!)
8. **Auto-assign public IP**: **No**
9. **IAM Instance Profile**: Select `ansible-control-node-profile`
10. **Security Group**: Create with:
    - Inbound: None needed (using SSM)
    - Outbound: All traffic (needs AWS APIs, internet)
11. **Tags**:
    - Name: `ansible-control-node`
    - Project: `Vprofile`
    - Role: `control-node`

### 3.2 Alternative: Launch via AWS CLI

```bash
# Get latest Ubuntu 22.04 LTS AMI
AMI_ID=$(aws ec2 describe-images \
  --region us-east-2 \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)

# Get subnet ID
SUBNET_ID="subnet-0b6b29c4dc3eeb9ab"  # Private subnet ID

# Get security group ID
SG_ID=$(aws ec2 describe-security-groups \
  --region us-east-2 \
  --filters "Name=group-name,Values=your-sg-name" \
  --query 'SecurityGroups[0].GroupId' \
  --output text)

# Launch instance
aws ec2 run-instances \
  --region us-east-2 \
  --image-id $AMI_ID \
  --instance-type t3.medium \
  --subnet-id $SUBNET_ID \
  --security-group-ids $SG_ID \
  --iam-instance-profile Name=ansible-control-node-profile \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ansible-control-node},{Key=Project,Value=Vprofile},{Key=Role,Value=control-node}]' \
  --no-associate-public-ip-address

# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:Name,Values=ansible-control-node" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

echo $INSTANCE_ID
```

---

## Step 4: Connect via Systems Manager Session Manager

### 4.1 Verify SSM Agent Running

```bash
# Check if instance can be accessed via Session Manager
# (wait 2-3 minutes after launch for agent to start)

aws ssm describe-instance-information \
  --region us-east-2 \
  --filters "Key=tag:Name,Values=ansible-control-node"

# Expected: Instance listed in output
```

### 4.2 Start Session

```bash
# Get instance ID
INSTANCE_ID="i-1234567890abcdef0"  # Replace with your instance ID

# Start session
aws ssm start-session --target $INSTANCE_ID --region us-east-2

# You should now be in the instance's shell
ubuntu@ip-10-0-7-xxx:~$
```

### 4.3 Exit Session

```bash
# From within the session
exit

# Or press Ctrl+D
```

---

## Step 5: Install Dependencies on Control Node

### 5.1 Connect via SSM

```bash
aws ssm start-session --target i-1234567890abcdef0 --region us-east-2
```

### 5.2 Update System & Install Tools

```bash
# Update package manager
sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y \
  python3-pip \
  python3-venv \
  git \
  curl \
  wget \
  awscli

# Install Ansible
pip3 install --user ansible boto3 botocore

# Add to PATH
echo 'export PATH=$PATH:~/.local/bin' >> ~/.bashrc
source ~/.bashrc

# Verify
ansible --version
aws --version
python3 -c "import boto3; print('boto3 OK')"
```

---

## Step 6: Pull Code from S3

### 6.1 Download Archive

```bash
# From control node (via SSM session)

# Set S3 bucket name (update this!)
export S3_BUCKET="vprofile-ansible-deployment-1234567890"

# Create directory
mkdir -p ~/ansible-deploy
cd ~/ansible-deploy

# Download archive from S3
aws s3 cp s3://$S3_BUCKET/ansible-code.tar.gz . --region us-east-2

# Verify download
ls -lah ansible-code.tar.gz
```

### 6.2 Extract Archive

```bash
# Extract archive
tar -xzf ansible-code.tar.gz

# Verify structure
ls -la Ansible-infrastructure/server-management/
# Should show: deploy.sh, playbooks/, vars/, inventory/, docs/, etc.
```

### 6.3 Setup Ansible Configuration

```bash
cd Ansible-infrastructure/server-management

# Make deploy.sh executable
chmod +x deploy.sh

# Configure AWS region for dynamic inventory
export AWS_DEFAULT_REGION=us-east-2

# Test dynamic inventory
ansible-inventory -i inventory/aws_ec2.yml --graph
# Expected: web_tier, app_tier, db_tier groups
```

---

## Step 7: Configure AWS Credentials

### 7.1 Verify IAM Role is Active

```bash
# Check if running with IAM role (no credentials needed!)
aws sts get-caller-identity
# Expected: Shows Account, Arn, UserId (from IAM role)

# If fails, reconfigure AWS region:
aws configure set region us-east-2
aws sts get-caller-identity
```

### 7.2 Alternative: If IAM Role Isn't Working

```bash
# Option A: Add AWS credentials to control node
aws configure
# Enter: Access Key, Secret Key, Region (us-east-2), Output (json)

# Option B: Add credentials via environment
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export AWS_DEFAULT_REGION="us-east-2"
```

---

## Step 8: Test Connectivity to Managed Servers

### 8.1 Test Dynamic Inventory

```bash
# List all discovered servers
ansible-inventory -i inventory/aws_ec2.yml --list | jq '.all.hosts | keys' | head -20

# Expected: List of server names (vprofile-web-01, etc.)
```

### 8.2 Test Ping All Tiers

```bash
# Ping web tier
ansible -i inventory/aws_ec2.yml web_tier -m ping --limit 1

# Ping app tier
ansible -i inventory/aws_ec2.yml app_tier -m ping --limit 1

# Ping db tier
ansible -i inventory/aws_ec2.yml db_tier -m ping --limit 1
```

**Note**: If ping fails, check:
- Security groups allow SSH (22) from control node SG
- Control node has outbound access
- Bastion connectivity (if needed)

---

## Step 9: Deploy Infrastructure

### 9.1 Full Deployment

```bash
cd ~/ansible-deploy/Ansible-infrastructure/server-management

# Run full deployment
./deploy.sh deploy

# Follow prompts, answer "yes" to each phase
```

### 9.2 Phase-by-Phase Deployment

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

---

## Step 10: Monitor Deployment from Local Machine

### 10.1 Watch Logs in Real-Time

```bash
# From your local machine (new terminal)

# Start session
aws ssm start-session --target i-1234567890abcdef0 --region us-east-2

# Inside session:
tail -f ~/ansible-deploy/Ansible-infrastructure/server-management/logs/deployment_*.log
```

### 10.2 Download Logs & Reports

```bash
# After deployment, download logs and reports
aws ssm start-session --target i-1234567890abcdef0 --region us-east-2

# Inside session:
tar -czf deployment-artifacts.tar.gz \
  ~/ansible-deploy/Ansible-infrastructure/server-management/logs \
  ~/ansible-deploy/Ansible-infrastructure/server-management/reports

# Upload to S3 for easy download
aws s3 cp deployment-artifacts.tar.gz s3://$S3_BUCKET/deployment-artifacts.tar.gz

# Exit session
exit

# Download from S3 to local
aws s3 cp s3://$S3_BUCKET/deployment-artifacts.tar.gz ./
tar -xzf deployment-artifacts.tar.gz
```

---

## Step 11: Connect to Managed Servers

### 11.1 From Control Node to App Servers

```bash
# Via SSM session on control node:
ssh ubuntu@vprofile-app-01  # If in same VPC with proper SGs
```

### 11.2 From Local Machine to Managed Servers (Multi-Hop SSM)

```bash
# Use SSM through control node as jump host
aws ssm start-session \
  --target i-1234567890abcdef0 \
  --document-name AWS-StartPortForwardingSession \
  --parameters "localPortNumber=22,portNumber=22,host=vprofile-app-01-private-ip" \
  --region us-east-2
```

---

## Complete Workflow Summary

### From Your Local Machine

```bash
# Step 1: Create S3 bucket and upload code
aws s3 mb s3://vprofile-ansible-deployment-$(date +%s) --region us-east-2
export S3_BUCKET="vprofile-ansible-deployment-1234567890"
tar -czf ansible-code.tar.gz Ansible-infrastructure/
aws s3 cp ansible-code.tar.gz s3://$S3_BUCKET/ --region us-east-2

# Step 2: Create IAM role (use scripts from Step 2)
# ... (run IAM setup scripts)

# Step 3: Launch EC2 instance with IAM role
# ... (use AWS Console or CLI from Step 3)

# Step 4: Connect via SSM
aws ssm start-session --target i-1234567890abcdef0 --region us-east-2
```

### On Control Node (via SSM)

```bash
# Step 5: Install dependencies
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3-pip git curl awscli
pip3 install --user ansible boto3 botocore
echo 'export PATH=$PATH:~/.local/bin' >> ~/.bashrc
source ~/.bashrc

# Step 6: Pull code from S3
export S3_BUCKET="vprofile-ansible-deployment-1234567890"
mkdir -p ~/ansible-deploy && cd ~/ansible-deploy
aws s3 cp s3://$S3_BUCKET/ansible-code.tar.gz . --region us-east-2
tar -xzf ansible-code.tar.gz
cd Ansible-infrastructure/server-management
chmod +x deploy.sh

# Step 7: Verify AWS access
aws sts get-caller-identity

# Step 8: Test connectivity
ansible-inventory -i inventory/aws_ec2.yml --graph
ansible -i inventory/aws_ec2.yml web_tier -m ping --limit 1

# Step 9: Deploy!
./deploy.sh deploy
```

---

## Advantages of SSM + S3 Approach

| Aspect | SSH | SSM + S3 |
|--------|-----|----------|
| **Public IP** | Required | Not needed |
| **Security** | Key-based | IAM-based |
| **Port 22 Open** | Yes | No |
| **Code Distribution** | SCP/Git | S3 |
| **Audit Trail** | SSH logs | CloudTrail |
| **Cost** | Slightly less | Slightly more (S3) |
| **Team Access** | Key sharing | IAM policies |
| **Security Group Rules** | More rules | Less rules |

---

## Troubleshooting

### SSM Session Won't Start

```bash
# Check instance has SSM agent
aws ssm describe-instance-information \
  --region us-east-2 \
  --filters "Key=tag:Name,Values=ansible-control-node"

# Verify IAM role is attached
aws ec2 describe-instances \
  --region us-east-2 \
  --instance-ids i-1234567890abcdef0 \
  --query 'Reservations[0].Instances[0].IamInstanceProfile'

# Check security group allows VPC endpoints (for SSM communication)
# Should NOT block HTTPS (443) outbound
```

### Can't Download from S3

```bash
# Verify bucket name
aws s3 ls vprofile-ansible-deployment-*

# Verify bucket exists in correct region
aws s3api head-bucket --bucket vprofile-ansible-deployment-1234567890 --region us-east-2

# Verify file is in bucket
aws s3 ls s3://vprofile-ansible-deployment-1234567890/ --region us-east-2

# Test S3 access directly
aws s3 cp s3://vprofile-ansible-deployment-1234567890/ansible-code.tar.gz . \
  --region us-east-2 --debug
```

### Dynamic Inventory Shows No Hosts

```bash
# Check credentials
aws sts get-caller-identity

# Check region
export AWS_DEFAULT_REGION=us-east-2

# Check tags on servers
aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:Project,Values=Vprofile" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],State:State.Name}'
```

---

## Next Steps

1. ✅ Create S3 bucket & upload code
2. ✅ Create IAM role with S3 & EC2 access
3. ✅ Launch control node in private subnet with IAM role
4. ✅ Connect via SSM Session Manager
5. ✅ Install Ansible & dependencies
6. ✅ Pull code from S3
7. ✅ Test connectivity to managed servers
8. ✅ Run `./deploy.sh deploy`

**You're now ready for secure, auditable deployment!** 🚀
