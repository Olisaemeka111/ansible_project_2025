# Getting Started: 30-Server Management System

Welcome! This guide will help you get up and running with the new server management system.

## Prerequisites Checklist

Before you start, ensure you have:

- [ ] **Ansible 2.10 or higher** installed
  ```bash
  ansible --version
  # Should show version 2.10+
  ```

- [ ] **AWS CLI v2** installed and configured
  ```bash
  aws --version
  aws sts get-caller-identity  # Verify credentials work
  ```

- [ ] **SSH key pair** at `~/.ssh/vprofile-key.pem` with permissions 600
  ```bash
  ls -la ~/.ssh/vprofile-key.pem
  chmod 600 ~/.ssh/vprofile-key.pem
  ```

- [ ] **Python 3** with boto3 (for AWS API calls)
  ```bash
  python3 --version
  pip3 install boto3 botocore
  ```

- [ ] **Existing VPC** in AWS us-east-2 with ID `vpc-00ea7a9f5d7626b30`
  ```bash
  aws ec2 describe-vpcs --region us-east-2 --vpc-ids vpc-00ea7a9f5d7626b30
  ```

- [ ] **Ansible AWS collection** installed
  ```bash
  ansible-galaxy collection install amazon.aws
  ```

## Step 1: Verify Prerequisites

```bash
cd server-management

# Check Ansible
ansible --version

# Check AWS CLI
aws sts get-caller-identity

# Check boto3
python3 -c "import boto3; print('boto3 OK')"

# Check SSH key
ls -la ~/.ssh/vprofile-key.pem

# Check AWS collections
ansible-galaxy collection list | grep amazon.aws
```

If all checks pass, proceed to Step 2.

## Step 2: Update Configuration

Edit `vars/servers.yml` and update the Ubuntu 22.04 AMI ID:

```bash
# Find the latest Ubuntu 22.04 LTS AMI in us-east-2
aws ec2 describe-images \
  --region us-east-2 \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64*" \
  --query 'sort_by(Images, &CreationDate)[-1].[ImageId,Name]' \
  --output text
```

Copy the AMI ID and update line 8 in `vars/servers.yml`:

```yaml
# OLD:
ubuntu_22_04_ami: "ami-0c7217cdde317cfec"

# NEW (replace with output from above):
ubuntu_22_04_ami: "ami-YOUR_AMI_ID_HERE"
```

Save the file.

## Step 3: Test Dynamic Inventory

Before provisioning, test that the dynamic inventory plugin can access AWS:

```bash
# List all existing app servers (should be empty on first run)
ansible-inventory -i inventory/aws_ec2.yml --list | jq '.all.children'

# Or show a simpler list
ansible-inventory -i inventory/aws_ec2.yml --list | jq '.all.hosts'
```

**Expected output on first run**: Empty or minimal (only existing instances if any)

## Step 4: Provision 30 Servers

Now provision the 30 servers. This is the main operation:

```bash
# Option A: Using the wrapper script (recommended)
chmod +x manage-servers.sh
./manage-servers.sh provision

# Option B: Direct Ansible
ansible-playbook playbooks/provision_servers.yml
```

**What happens**:
- Creates security group `vprofile-app-sg`
- Creates 30 EC2 instances (t3.medium) across 3 batches
- Distributes them across 3 private subnets (3 AZs)
- Tags each with Batch number (batch_1, batch_2, batch_3)
- Generates `vars/app_servers_output.yml` with instance details

**Time**: 5-10 minutes

**Monitoring**:
- Watch AWS Console → EC2 → Instances for the 30 new instances
- Look for names: `vprofile-app-01` through `vprofile-app-30`

## Step 5: Test Connectivity

Verify instances are reachable:

```bash
# Test all instances
./manage-servers.sh ping all

# Test specific batch
./manage-servers.sh ping batch_1

# Expected: All instances should respond "pong"
```

If connectivity fails:
- Check security group allows SSH from your IP
- Verify bastion host can reach private subnets
- Check Network ACLs aren't blocking traffic

## Step 6: Install Packages

Install development tools on all servers:

```bash
# Install on all servers (processes 10 at a time)
./manage-servers.sh install all

# Or: Install on specific batch first (recommended)
./manage-servers.sh install batch_1
```

**What gets installed**:
- Java 17 JDK
- Python 3 + pip + boto3
- Node.js 20 + npm
- Docker CE + docker-compose
- Common tools: git, curl, wget, htop, jq, aws-cli

**Time**: 15-20 minutes per batch

**Verify installation** (after complete):
```bash
./manage-servers.sh shell 'java -version' batch_1
./manage-servers.sh shell 'node --version' batch_1
./manage-servers.sh shell 'docker --version' batch_1
```

## Step 7: Apply Patches

Update OS packages on all servers:

```bash
# Apply patches to all servers
./manage-servers.sh patch all

# Or: Patch specific batch first
./manage-servers.sh patch batch_1
```

**What happens**:
- Updates apt cache
- Upgrades all packages
- Reboots if kernel was updated
- Verifies services come back online

**Time**: 10-15 minutes per batch (longer if kernel updates involved)

**Note**: Servers will reboot if needed. Sessions will be interrupted.

## Step 8: Monitor Resources and Costs

Generate a cost and resource utilization report:

```bash
./manage-servers.sh monitor

# Or direct:
ansible-playbook playbooks/monitoring_and_cost.yml
```

**Output**:
- Console summary with cost breakdown
- HTML report: `reports/cost_report_YYYY-MM-DD.html`
- JSON metrics: `reports/metrics_TIMESTAMP.json`

**View report**:
```bash
# Open HTML report in browser
open reports/cost_report_*.html  # macOS
xdg-open reports/cost_report_*.html  # Linux
start reports\cost_report_*.html  # Windows
```

## Step 9: Regular Operations

### Daily Monitoring
```bash
# Check instance status
./manage-servers.sh status

# Check resource usage
./manage-servers.sh monitor
```

### Weekly Patching
```bash
# Patch one batch per week
./manage-servers.sh patch batch_1
# Next week: batch_2, then batch_3
```

### Ad-hoc Commands
```bash
# Check disk space
./manage-servers.sh shell 'df -h' all

# Check running services
./manage-servers.sh shell 'systemctl status' batch_1

# Install additional package
./manage-servers.sh shell 'sudo apt install -y <package>' all
```

## Step 10: Cleanup (When Done)

To stop instances (pause billing):
```bash
./manage-servers.sh stop all

# Later, to resume:
./manage-servers.sh start all
```

To terminate instances completely:
```bash
# ⚠️ WARNING: This cannot be undone
./manage-servers.sh terminate all
```

## Helpful Commands Quick Reference

```bash
# View all servers
./manage-servers.sh list

# Check connectivity
./manage-servers.sh ping all

# Get server details
./manage-servers.sh info all

# View cost report
./manage-servers.sh monitor

# SSH into instance
./manage-servers.sh ssh vprofile-app-01

# Run command on servers
./manage-servers.sh shell 'whoami' batch_1
```

See `QUICK_REFERENCE.md` for more commands.

## Troubleshooting

### Instances Not Appearing in Inventory
```bash
# Check if instances exist and are tagged correctly
aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:Project,Values=Vprofile" \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name]' \
  --output table
```

### SSH Connection Refused
- Check security group allows SSH (port 22)
- Verify key permissions: `chmod 600 ~/.ssh/vprofile-key.pem`
- Ensure instances have private IP addresses assigned
- Check Network ACLs aren't blocking SSH

### Ansible Hangs
- Press `Ctrl+C` to stop
- Check AWS API rate limits
- Verify AWS credentials are valid
- Try limiting to single batch: `--limit batch_1`

### Cost Report Not Generated
- Verify AWS CLI is configured and has Cost Explorer permissions
- Check region is us-east-2
- Verify instances are running (stopped instances still incur some costs)

### Out of Memory During Patching
- Reduce serial batch size (edit playbook `serial: 10` to `serial: 5`)
- Run only one batch at a time: `--limit batch_1`

## Key Files to Know

| File | Purpose |
|------|---------|
| `playbooks/provision_servers.yml` | Creates 30 EC2 instances |
| `playbooks/package_install.yml` | Installs Java, Python, Docker, Node.js |
| `playbooks/patching.yml` | Applies OS patches and updates |
| `playbooks/monitoring_and_cost.yml` | Collects metrics and costs |
| `inventory/aws_ec2.yml` | Dynamic inventory configuration |
| `vars/servers.yml` | Server definitions and settings |
| `vars/packages.yml` | Package list to install |
| `manage-servers.sh` | Command-line wrapper (recommended) |
| `README.md` | Full documentation |
| `QUICK_REFERENCE.md` | Command examples |

## Next Steps

1. ✅ Complete the steps above
2. 📊 Monitor your cost report regularly
3. 🔄 Set up automated patching schedule
4. 📈 Scale up/down by modifying `vars/servers.yml`
5. 🔐 Consider setting up AWS Secrets Manager for credentials
6. 📝 Document any custom modifications

## Getting Help

- Check `README.md` for detailed documentation
- Check `QUICK_REFERENCE.md` for command examples
- Review Ansible logs: `tail -f /tmp/patch_*.txt`
- Check AWS CloudWatch for instance metrics
- Review AWS Cost Management console for cost details

## Important Notes

- **Estimated cost**: ~$900/month for 30 t3.medium instances in us-east-2
- **Update frequency**: Monthly security patches recommended
- **Backup strategy**: Consider AMI snapshots before major changes
- **Monitoring**: Review cost report weekly to track spending
- **Scaling**: Modify `server_definitions` in `vars/servers.yml` to add/remove servers

---

**You're all set!** Start with Step 1 and work through each step in order.
