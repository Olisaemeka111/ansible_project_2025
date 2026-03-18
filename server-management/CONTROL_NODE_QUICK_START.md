# Control Node Setup - Quick Start (SSM + S3 Approach)

## The Fastest Way to Deploy

This is the **recommended** approach: secure, scalable, and requires no SSH key management.

---

## Prerequisites (5 minutes)

### On Your Local Machine

```bash
# 1. Verify AWS CLI is installed
aws --version
# Expected: aws-cli/2.x.x

# 2. Verify AWS credentials
aws sts get-caller-identity
# Expected: Account, UserId, Arn output

# 3. Have your code ready
ls Ansible-infrastructure/server-management/deploy.sh
# Expected: deploy.sh exists
```

---

## Step 1: Upload Code to S3 (5 minutes)

```bash
# On your local machine

# Create unique S3 bucket
BUCKET_NAME="vprofile-ansible-$(date +%s)"
aws s3 mb s3://$BUCKET_NAME --region us-east-2

# Archive Ansible code
cd "Terraform repository/Ansible infrastructure"
tar -czf ansible-code.tar.gz Ansible-infrastructure/

# Upload to S3
aws s3 cp ansible-code.tar.gz s3://$BUCKET_NAME/ --region us-east-2

# Save bucket name for later
echo "S3 Bucket: $BUCKET_NAME" > ~/s3_bucket.txt
cat ~/s3_bucket.txt
```

---

## Step 2: Create IAM Role (5 minutes)

```bash
# On your local machine

# Create trust policy
cat > /tmp/trust-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Service": "ec2.amazonaws.com" },
    "Action": "sts:AssumeRole"
  }]
}
EOF

# Create role
aws iam create-role \
  --role-name ansible-control-node-role \
  --assume-role-policy-document file:///tmp/trust-policy.json

# Create and attach policy
cat > /tmp/policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:ListBucket"],
      "Resource": ["arn:aws:s3:::vprofile-ansible-*", "arn:aws:s3:::vprofile-ansible-*/*"]
    },
    { "Effect": "Allow", "Action": "ec2:*", "Resource": "*" },
    { "Effect": "Allow", "Action": ["ssm:*", "ssmmessages:*", "ec2messages:*"], "Resource": "*" }
  ]
}
EOF

aws iam put-role-policy \
  --role-name ansible-control-node-role \
  --policy-name AnsiblePolicy \
  --policy-document file:///tmp/policy.json

# Create instance profile
aws iam create-instance-profile \
  --instance-profile-name ansible-control-node-profile

aws iam add-role-to-instance-profile \
  --instance-profile-name ansible-control-node-profile \
  --role-name ansible-control-node-role

echo "✓ IAM role created"
```

---

## Step 3: Launch Control Node EC2 (5 minutes)

### Option A: AWS Console (Easiest)

1. Go to **EC2 Dashboard → Launch Instances**
2. **Name**: `ansible-control-node`
3. **AMI**: Ubuntu 22.04 LTS
4. **Instance Type**: `t3.medium`
5. **Key Pair**: Skip (using SSM)
6. **VPC**: `vpc-00ea7a9f5d7626b30`
7. **Subnet**: Any private subnet (e.g., `subnet-0b6b29c4dc3eeb9ab`)
8. **Auto-assign Public IP**: **No** ← Important
9. **IAM Instance Profile**: Select `ansible-control-node-profile`
10. **Security Group**: Create with outbound traffic allowed (no inbound needed)
11. **Tags**: Name=`ansible-control-node`, Project=`Vprofile`
12. **Launch**

### Option B: AWS CLI

```bash
# Get latest Ubuntu AMI
AMI=$(aws ec2 describe-images \
  --region us-east-2 \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text)

# Launch instance
INSTANCE=$(aws ec2 run-instances \
  --region us-east-2 \
  --image-id $AMI \
  --instance-type t3.medium \
  --subnet-id subnet-0b6b29c4dc3eeb9ab \
  --iam-instance-profile Name=ansible-control-node-profile \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ansible-control-node},{Key=Project,Value=Vprofile}]' \
  --no-associate-public-ip-address \
  --query 'Instances[0].InstanceId' \
  --output text)

echo "Instance ID: $INSTANCE"
```

---

## Step 4: Wait for SSM Access (2 minutes)

```bash
# On your local machine
# Wait for SSM agent to start

INSTANCE_ID="i-1234567890abcdef0"  # From previous step

# Check if available in SSM
aws ssm describe-instance-information \
  --region us-east-2 \
  --filters "Key=tag:Name,Values=ansible-control-node"

# Wait for output to show the instance
# (Takes 2-3 minutes after launch)
```

---

## Step 5: Connect & Run Bootstrap Script (15 minutes)

```bash
# On your local machine

# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:Name,Values=ansible-control-node" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

echo "Instance ID: $INSTANCE_ID"

# Start SSM session
aws ssm start-session --target $INSTANCE_ID --region us-east-2

# You're now inside the instance - follow commands below
```

### Inside SSM Session

```bash
# Get S3 bucket name (from local ~/s3_bucket.txt)
S3_BUCKET="vprofile-ansible-1234567890"

# Download bootstrap script
cat > ~/bootstrap.sh << 'EOF'
#!/bin/bash
# ... (paste the bootstrap-control-node.sh content here)
# OR download from GitHub/S3
EOF

# Run bootstrap
bash ~/bootstrap.sh $S3_BUCKET us-east-2

# Wait for completion (15 minutes)
```

---

## Step 6: Verify Setup (2 minutes)

```bash
# Inside SSM session

# Check Ansible
ansible --version

# Check AWS access
aws sts get-caller-identity

# Check inventory
cd ~/ansible-deploy/Ansible-infrastructure/server-management
ansible-inventory -i inventory/aws_ec2.yml --graph

# Exit SSM session when ready
exit
```

---

## Step 7: Deploy Infrastructure (45-60 minutes)

```bash
# Inside SSM session
cd ~/ansible-deploy/Ansible-infrastructure/server-management

# Full deployment
./deploy.sh deploy

# Answer "yes" to each prompt
# Total time: 45-60 minutes

# Monitor from another terminal:
# aws ssm start-session --target $INSTANCE_ID --region us-east-2
# tail -f ~/ansible-deploy/.../logs/deployment_*.log
```

---

## Complete Workflow (Copy-Paste Ready)

### Terminal 1: Setup (20 minutes)

```bash
# Step 1: Create S3 bucket
BUCKET="vprofile-ansible-$(date +%s)"
aws s3 mb s3://$BUCKET --region us-east-2

# Step 2: Upload code
cd "Terraform repository/Ansible infrastructure"
tar -czf ansible-code.tar.gz Ansible-infrastructure/
aws s3 cp ansible-code.tar.gz s3://$BUCKET/ --region us-east-2

# Step 3: Create IAM role (from previous section - copy all commands)
# ... (run IAM commands from Step 2)

# Step 4: Get instance ID and create SSM session
INSTANCE_ID=$(aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:Name,Values=ansible-control-node" \
  --query 'Reservations[0].Instances[0].InstanceId' \
  --output text)

aws ssm start-session --target $INSTANCE_ID --region us-east-2
```

### Terminal 2: Bootstrap Control Node (inside SSM, 15 minutes)

```bash
# Inside SSM session

# Set bucket name (from Terminal 1)
S3_BUCKET="vprofile-ansible-1234567890"

# Download and run bootstrap script
# Option A: From S3
aws s3 cp s3://$S3_BUCKET/bootstrap-control-node.sh .
bash bootstrap-control-node.sh $S3_BUCKET us-east-2

# Option B: Paste content directly
# cat > bootstrap.sh (paste full script content)
# bash bootstrap.sh $S3_BUCKET us-east-2

# Wait for completion
```

### Terminal 3: Deploy Infrastructure (inside SSM, 45-60 minutes)

```bash
# Inside new SSM session (Terminal 3)
cd ~/ansible-deploy/Ansible-infrastructure/server-management
./deploy.sh deploy

# Answer prompts with "yes"
# Wait for completion

# Monitor logs in Terminal 1:
# tail -f ~/ansible-deploy/Ansible-infrastructure/server-management/logs/deployment_*.log
```

---

## Troubleshooting

### Can't connect via SSM

```bash
# Check instance is running
aws ec2 describe-instances \
  --region us-east-2 \
  --instance-ids i-1234567890abcdef0 \
  --query 'Reservations[0].Instances[0].State'

# Check SSM agent is ready (wait 2-3 minutes after launch)
aws ssm describe-instance-information \
  --region us-east-2 \
  --filters "Key=instance-ids,Values=i-1234567890abcdef0"

# Check IAM role is attached
aws ec2 describe-instances \
  --region us-east-2 \
  --instance-ids i-1234567890abcdef0 \
  --query 'Reservations[0].Instances[0].IamInstanceProfile'
```

### Bootstrap fails

```bash
# Inside SSM session

# Check logs
ls -la ~/bootstrap.sh

# Try manual setup
sudo apt update && sudo apt upgrade -y
sudo apt install -y python3-pip curl git awscli
pip3 install --user ansible boto3

# Test AWS
aws sts get-caller-identity
aws s3 ls s3://$S3_BUCKET

# Download code
aws s3 cp s3://$S3_BUCKET/ansible-code.tar.gz ~
tar -xzf ~/ansible-code.tar.gz
cd ~/Ansible-infrastructure/server-management
chmod +x deploy.sh
```

### Deploy script won't run

```bash
# Inside SSM session, in deployment directory
cd ~/ansible-deploy/Ansible-infrastructure/server-management

# Check file exists
ls -la deploy.sh

# Make executable
chmod +x deploy.sh

# Test it
./deploy.sh help

# Run deployment
./deploy.sh deploy
```

---

## Time Estimates

| Phase | Time | Task |
|-------|------|------|
| Step 1 | 5 min | Upload to S3 |
| Step 2 | 5 min | Create IAM role |
| Step 3 | 5 min | Launch EC2 instance |
| Step 4 | 2 min | Wait for SSM |
| Step 5 | 15 min | Bootstrap control node |
| Step 6 | 2 min | Verify setup |
| Step 7 | 45-60 min | Deploy infrastructure |
| **Total** | **~90 min** | **End-to-end** |

---

## Cost Breakdown

| Resource | Cost/Month | Notes |
|----------|-----------|-------|
| Control Node (t3.medium) | ~$30 | Runs continuously |
| Managed Servers (30 × t3.medium) | ~$900 | Can stop when not needed |
| S3 Bucket (minimal) | <$1 | Small archive |
| Data Transfer | ~$50-100 | Between instances |
| **Total** | **~$980** | Can reduce to ~$610 with t3.small |

---

## Key Advantages of This Approach

✅ **Secure**: IAM-based access, no SSH keys needed
✅ **Scalable**: Control node in private subnet
✅ **Auditable**: All access logged in CloudTrail
✅ **Automatable**: Bootstrap script can be reused
✅ **Team-Friendly**: Easy to grant team access via IAM
✅ **Cost-Effective**: No public IP needed

---

## Next: Running Deployments

Once setup is complete:

```bash
# Connect anytime
INSTANCE_ID="i-..."
aws ssm start-session --target $INSTANCE_ID --region us-east-2

# Inside session
cd ~/ansible-deploy/Ansible-infrastructure/server-management

# Full deployment (first time)
./deploy.sh deploy

# Re-run specific phase
./deploy.sh packages     # Just packages
./deploy.sh patches      # Just patches
./deploy.sh monitor      # Just monitoring

# Add new servers
./deploy.sh servers      # Create more instances

# Cleanup (CAREFUL!)
./deploy.sh cleanup      # Delete all infrastructure
```

---

## Documentation

For more details, see:

| Document | Purpose |
|----------|---------|
| **SSM_S3_DEPLOYMENT.md** | Detailed SSM + S3 walkthrough |
| **DEPLOYMENT_GUIDE.md** | Full deployment instructions |
| **SECURITY_ARCHITECTURE.md** | Network design & security |
| **docs/SECURITY_GROUPS.md** | Security group rules |
| **docs/NETWORK_FLOWS.md** | Traffic flows & testing |

---

## Support

If something goes wrong:

1. **Check logs**: `ls ~/ansible-deploy/.../logs/`
2. **Read docs**: See Documentation section above
3. **Verify AWS**: `aws sts get-caller-identity`
4. **Test connectivity**: `ansible-inventory -i inventory/aws_ec2.yml --list`

---

**You're ready to deploy!** 🚀

Start with **Step 1** and follow through to **Step 7**. Each step is designed to take just a few minutes.
