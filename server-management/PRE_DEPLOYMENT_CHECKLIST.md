# Pre-Deployment Checklist

Before running the deployment script, verify everything is in place. This checklist ensures a smooth, successful deployment.

---

## 1. System Prerequisites

### Ansible
- [ ] Ansible 2.10+ installed
  ```bash
  ansible --version
  ```
  Expected: Ansible 2.10 or higher

- [ ] AWS collection installed
  ```bash
  ansible-galaxy collection list | grep amazon.aws
  ```
  Expected: amazon.aws collection should be listed

### AWS Tools
- [ ] AWS CLI v2 installed
  ```bash
  aws --version
  ```
  Expected: aws-cli/2.x.x

- [ ] AWS credentials configured
  ```bash
  aws sts get-caller-identity
  ```
  Expected: Output with Account, UserId, Arn

### Python
- [ ] Python 3.8+ installed
  ```bash
  python3 --version
  ```
  Expected: Python 3.8 or higher

- [ ] boto3 installed
  ```bash
  python3 -m pip list | grep boto3
  ```
  Expected: boto3 should be listed

### SSH
- [ ] SSH installed
  ```bash
  ssh -V
  ```
  Expected: OpenSSH version

- [ ] SSH key exists and has correct permissions
  ```bash
  ls -la ~/.ssh/vprofile-key.pem
  ```
  Expected: `-rw-------  1 user group  size date vprofile-key.pem`

  If permissions are wrong, fix them:
  ```bash
  chmod 600 ~/.ssh/vprofile-key.pem
  ```

---

## 2. AWS Account & Network Setup

### AWS Account Access
- [ ] AWS Account ID noted
  ```bash
  aws sts get-caller-identity --query Account --output text
  ```

- [ ] User/Role has required permissions:
  - EC2: Create instances, security groups
  - VPC: Describe VPC, subnets, route tables
  - CloudWatch: Put metrics
  - Cost Explorer: Read cost data

### VPC & Network
- [ ] VPC exists: `vpc-00ea7a9f5d7626b30`
  ```bash
  aws ec2 describe-vpcs --vpc-ids vpc-00ea7a9f5d7626b30 --region us-east-2
  ```
  Expected: VPC details returned

- [ ] Public subnets exist:
  - [ ] pubsub1: subnet-09bc2124ef62ca72b (us-east-2a)
  - [ ] pubsub2: subnet-026f8265f7e6f8615 (us-east-2b)
  - [ ] pubsub3: subnet-0ed50fb1814384df7 (us-east-2c)
  ```bash
  aws ec2 describe-subnets --subnet-ids subnet-09bc2124ef62ca72b --region us-east-2
  ```

- [ ] Private subnets exist:
  - [ ] privsub1: subnet-0b6b29c4dc3eeb9ab (us-east-2a)
  - [ ] privsub2: subnet-04bd899a975a06512 (us-east-2b)
  - [ ] privsub3: subnet-0555d912faa6f5670 (us-east-2c)

- [ ] Route tables configured (should be from existing Terraform/Ansible)
  - [ ] Public route table routes to IGW
  - [ ] Private route table routes to NAT gateway

### Bastion Host
- [ ] Bastion host exists in VPC
  ```bash
  aws ec2 describe-instances --region us-east-2 --filters "Name=tag:Name,Values=Bastion*" --query 'Reservations[].Instances[].InstanceId'
  ```

- [ ] Bastion security group exists: `Bastion-host-sg`
  ```bash
  aws ec2 describe-security-groups --filters "Name=group-name,Values=Bastion-host-sg" --region us-east-2
  ```
  Expected: Security group details returned

- [ ] Bastion is running and accessible
  ```bash
  ssh -i ~/.ssh/vprofile-key.pem ubuntu@bastion-public-ip uptime
  ```
  Expected: Uptime output (no errors)

---

## 3. Deployment Files

### Directory Structure
- [ ] `server-management/` directory exists
- [ ] All required files present:
  ```bash
  ls -la server-management/
  ```
  Should show:
  - [ ] `deploy.sh` (executable)
  - [ ] `ansible.cfg`
  - [ ] `playbooks/` directory
  - [ ] `vars/` directory
  - [ ] `inventory/` directory
  - [ ] `scripts/` directory
  - [ ] `docs/` directory

### Playbooks
- [ ] `playbooks/security_groups.yml` exists
- [ ] `playbooks/provision_servers.yml` exists
- [ ] `playbooks/package_install.yml` exists
- [ ] `playbooks/patching.yml` exists
- [ ] `playbooks/monitoring_and_cost.yml` exists

### Variables
- [ ] `vars/servers.yml` exists
  - [ ] Contains web_servers, app_servers, db_servers definitions
  - [ ] Ubuntu AMI ID is set: search for latest:
    ```bash
    aws ec2 describe-images --region us-east-2 --owners 099720109477 \
      --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64*" \
      --query 'sort_by(Images, &CreationDate)[-1].[ImageId,Name]' --output text
    ```

- [ ] `vars/packages.yml` exists with package definitions
- [ ] `vars/security_groups.yml` exists with SG rules
- [ ] `vars/output_vars.yml` exists with VPC/subnet IDs

### Inventory
- [ ] `inventory/aws_ec2.yml` exists (dynamic inventory config)
- [ ] `inventory/group_vars/all.yml` exists
- [ ] `inventory/group_vars/web_tier.yml` exists
- [ ] `inventory/group_vars/app_tier.yml` exists
- [ ] `inventory/group_vars/db_tier.yml` exists

### Documentation
- [ ] `README.md` exists
- [ ] `SECURITY_ARCHITECTURE.md` exists
- [ ] `SECURITY_GROUPS.md` exists
- [ ] `NETWORK_FLOWS.md` exists
- [ ] `GETTING_STARTED.md` exists
- [ ] `QUICK_REFERENCE.md` exists
- [ ] `DEPLOYMENT_GUIDE.md` exists (this file)

---

## 4. Script Readiness

### Permissions
- [ ] deploy.sh is executable
  ```bash
  ls -la server-management/deploy.sh
  ```
  Expected: `-rwxr-xr-x` (has execute permission)

  If not, make it executable:
  ```bash
  chmod +x server-management/deploy.sh
  ```

### Script Verification
- [ ] Script can be read
  ```bash
  head -20 server-management/deploy.sh
  ```

- [ ] Script can display help
  ```bash
  cd server-management
  ./deploy.sh help
  ```
  Expected: Help message displayed

---

## 5. AWS Permissions Verification

Run this script to check required IAM permissions:

```bash
# Create temporary policy check (optional, but recommended)
aws ec2 describe-security-groups --region us-east-2 &> /dev/null && echo "✓ EC2 SecurityGroup read" || echo "✗ EC2 SecurityGroup"
aws ec2 describe-instances --region us-east-2 &> /dev/null && echo "✓ EC2 Instance read" || echo "✗ EC2 Instance"
aws ec2 describe-vpcs --region us-east-2 &> /dev/null && echo "✓ VPC read" || echo "✗ VPC"
aws ce get-cost-and-usage --time-period Start=2026-03-01,End=2026-03-17 --granularity MONTHLY --metrics UnblendedCost --region us-east-2 &> /dev/null && echo "✓ Cost Explorer" || echo "✗ Cost Explorer"
```

Expected: All checks pass with ✓

---

## 6. Configuration Values

### Key Values to Verify

Before deployment, confirm these critical values:

#### Region
- [ ] Region: `us-east-2` (Ohio)
  ```bash
  grep "region:" server-management/vars/*.yml
  ```

#### VPC ID
- [ ] VPC ID: `vpc-00ea7a9f5d7626b30`
  ```bash
  grep "vpc_id:" server-management/vars/servers.yml
  ```

#### Key Pair
- [ ] Key pair name: `vprofile-key`
  ```bash
  grep "key_name:" server-management/vars/servers.yml
  ```

#### Instance Type
- [ ] Instance type: `t3.medium`
  ```bash
  grep "instance_type:" server-management/vars/servers.yml
  ```

#### Server Count
- [ ] Total servers: 30 (10 web, 10 app, 10 db)
  ```bash
  grep -c "name:" server-management/vars/servers.yml
  ```
  Expected: 30

---

## 7. Connectivity Tests

### From Your Computer
- [ ] Can reach AWS
  ```bash
  aws s3 ls
  ```

- [ ] Can reach Bastion
  ```bash
  ssh -i ~/.ssh/vprofile-key.pem -o ConnectTimeout=5 ubuntu@bastion-public-ip echo "Connected"
  ```

### From Bastion to VPC
- [ ] Bastion can reach private subnets
  ```bash
  # SSH to bastion, then:
  ping -c 1 10.0.7.10  # Example private IP
  ```

---

## 8. Budget & Cost Setup

### Cost Alerts
- [ ] AWS billing alerts configured (optional but recommended)
  ```bash
  aws budgets create-budget --account-id $(aws sts get-caller-identity --query Account --output text) ...
  ```

### Estimated Costs Reviewed
- [ ] Reviewed estimated monthly costs: ~$900-1000
  - 30 × t3.medium: ~$900/month
  - Data transfer: ~$50-100
  - CloudWatch: ~$10

---

## 9. Backup & Disaster Recovery

### Before Deployment
- [ ] Bastion host backed up (if contains data)
- [ ] Database backups configured (if using managed DB)
- [ ] VPC/network configuration documented

### Post-Deployment
- [ ] Plan for automated backups
- [ ] Setup CloudWatch alarms
- [ ] Document recovery procedures

---

## 10. Final Readiness Check

Run the deployment validation:

```bash
cd server-management

# Check prerequisites
./deploy.sh help
```

Then answer these questions:

- [ ] All prerequisites installed? YES / NO
- [ ] AWS credentials working? YES / NO
- [ ] VPC and subnets exist? YES / NO
- [ ] Bastion host running? YES / NO
- [ ] SSH key accessible? YES / NO
- [ ] Configuration files valid? YES / NO
- [ ] Budget approved? YES / NO
- [ ] Ready to deploy? YES / NO

---

## Ready to Deploy?

If all items above are checked, you're ready!

### Start Deployment

```bash
cd server-management
./deploy.sh deploy
```

### Monitor Progress

In another terminal:
```bash
tail -f logs/deployment_*.log
```

### Expected Duration
- **Full deployment**: 45-60 minutes
- **User interaction**: ~10 confirmations (answer "yes")
- **Can be paused**: Yes, at phase boundaries

---

## Troubleshooting Checklist Issues

### Issue: Tool not found (Ansible, AWS CLI, etc.)

**Solution**:
```bash
# Install missing tools
pip install ansible boto3

# Configure AWS
aws configure
```

### Issue: AWS credentials not working

**Solution**:
```bash
# Test credentials
aws sts get-caller-identity

# If fails, reconfigure
aws configure
unset AWS_PROFILE  # If using profiles
```

### Issue: SSH key permission error

**Solution**:
```bash
chmod 600 ~/.ssh/vprofile-key.pem
```

### Issue: Can't reach Bastion

**Solution**:
```bash
# Check security group allows SSH
aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=Bastion-host-sg" \
  --region us-east-2

# Add your IP if needed (replace YOUR_IP)
aws ec2 authorize-security-group-ingress \
  --group-name Bastion-host-sg \
  --protocol tcp \
  --port 22 \
  --cidr YOUR_IP/32 \
  --region us-east-2
```

### Issue: VPC or subnets not found

**Solution**:
Check if running in correct region:
```bash
# List VPCs
aws ec2 describe-vpcs --region us-east-2

# List subnets
aws ec2 describe-subnets --region us-east-2
```

If VPC/subnets missing, you need to create them first (via Terraform or AWS Console).

---

## After Deployment

Once deployment completes:

1. [ ] Review deployment summary
2. [ ] Check cost report in `reports/`
3. [ ] Test connectivity to servers
4. [ ] Verify security groups
5. [ ] Review documentation
6. [ ] Setup monitoring alerts
7. [ ] Configure application load balancer (ALB)
8. [ ] Deploy your application

---

## Keep This Checklist

Save this checklist for:
- [ ] Future deployments
- [ ] Team onboarding
- [ ] Disaster recovery testing
- [ ] Infrastructure audits

Print it out: `cat PRE_DEPLOYMENT_CHECKLIST.md`
