# Server Management: 30 App Servers in 3 Batches

This directory contains Ansible playbooks and configurations to provision, patch, and monitor 30 Ubuntu 22.04 app servers in AWS, organized in 3 batches of 10 servers each.

## Prerequisites

- Ansible 2.10+ installed locally
- AWS CLI v2 configured with credentials
- SSH key pair `vprofile-key` available at `~/.ssh/vprofile-key.pem`
- Existing VPC in us-east-2: `vpc-00ea7a9f5d7626b30`
- Existing private subnets in the VPC (3 subnets across 3 AZs)

## Directory Structure

```
server-management/
├── ansible.cfg              # Ansible configuration
├── inventory/
│   ├── aws_ec2.yml         # Dynamic inventory plugin
│   └── group_vars/         # Group-level variables
│       ├── all.yml
│       ├── batch_1.yml
│       ├── batch_2.yml
│       └── batch_3.yml
├── vars/
│   ├── servers.yml         # Server definitions (30 servers)
│   ├── packages.yml        # Package list
│   └── app_servers_output.yml (auto-generated)
├── playbooks/
│   ├── provision_servers.yml       # Create EC2 instances
│   ├── patching.yml                # Apply OS patches
│   ├── package_install.yml         # Install packages
│   └── monitoring_and_cost.yml     # Resource monitoring
├── scripts/
│   └── resource_monitor.sh         # Monitoring script
├── templates/
│   └── monitoring_report.html.j2   # HTML report template
├── reports/                        # (auto-generated)
└── README.md
```

## Quick Start

### 1. Update Configuration

Before provisioning, update the AMI ID in `vars/servers.yml` to match the latest Ubuntu 22.04 LTS in us-east-2:

```bash
# Find the latest Ubuntu 22.04 LTS AMI
aws ec2 describe-images \
  --region us-east-2 \
  --owners 099720109477 \
  --filters "Name=name,Values=ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64*" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text
```

Update the `ubuntu_22_04_ami` variable in `vars/servers.yml` with the result.

### 2. Provision Servers

```bash
cd server-management
ansible-playbook playbooks/provision_servers.yml
```

This will:
- Create a security group `vprofile-app-sg`
- Provision 30 EC2 instances (t3.medium) in private subnets
- Tag instances with Batch 1, 2, or 3
- Generate `vars/app_servers_output.yml` with instance details

**Estimated time**: 5-10 minutes

### 3. Test Connectivity

```bash
# List all discovered instances
ansible-inventory -i inventory/aws_ec2.yml --list | jq '.all.children'

# Ping all app servers
ansible -i inventory/aws_ec2.yml app_servers -m ping

# Ping a specific batch
ansible -i inventory/aws_ec2.yml batch_1 -m ping
```

### 4. Install Packages

```bash
# Install on all servers (processes 10 at a time)
ansible-playbook playbooks/package_install.yml

# Install on specific batch
ansible-playbook playbooks/package_install.yml --limit batch_1
```

**Packages installed**:
- Java 17 JDK
- Python 3 + pip + boto3
- Node.js 20 + npm
- Docker CE + docker-compose
- Common tools: git, curl, wget, htop, jq, aws-cli, etc.

**Estimated time**: 15-20 minutes per batch

### 5. Apply Patches

```bash
# Patch all servers (one batch at a time)
ansible-playbook playbooks/patching.yml

# Patch specific batch
ansible-playbook playbooks/patching.yml --limit batch_1
```

**What it does**:
- Updates apt cache
- Performs dist-upgrade
- Reboots if kernel was updated
- Verifies services are operational

**Estimated time**: 10-15 minutes per batch (depending on patches)

### 6. Monitor Resources & Costs

```bash
ansible-playbook playbooks/monitoring_and_cost.yml
```

**Output**:
- Collects CPU, memory, disk, network metrics from each instance
- Queries AWS Cost Explorer for current month costs
- Generates HTML report: `reports/cost_report_YYYY-MM-DD.html`
- Saves raw metrics JSON: `reports/metrics_*.json`

**Estimated time**: 2-5 minutes

## Playbook Details

### provision_servers.yml
- **Target**: localhost (runs locally)
- **Duration**: 5-10 minutes
- **Output**: `vars/app_servers_output.yml` with all instance details

Creates 30 servers distributed across 3 private subnets:
- **Batch 1**: vprofile-app-01 through vprofile-app-10
- **Batch 2**: vprofile-app-11 through vprofile-app-20
- **Batch 3**: vprofile-app-21 through vprofile-app-30

### patching.yml
- **Target**: all app_servers
- **Serial**: 10 (one batch at a time)
- **Duration**: 10-15 minutes per batch
- **Log file**: `/tmp/patch_*.txt` on each server

Applies security updates and patches OS.

### package_install.yml
- **Target**: all app_servers
- **Serial**: 10 (one batch at a time)
- **Duration**: 15-20 minutes per batch
- **Log file**: `/tmp/install_*.txt` on each server

Installs development tools, runtimes, and containers.

### monitoring_and_cost.yml
- **Target**: all app_servers first, then localhost for reporting
- **Duration**: 2-5 minutes
- **Output**:
  - HTML report: `reports/cost_report_YYYY-MM-DD.html`
  - JSON metrics: `reports/metrics_*.json`
  - Console summary with cost breakdown

Collects resource utilization and AWS cost data.

## Monitoring Script

The `scripts/resource_monitor.sh` script runs on each instance and collects:

- **CPU**: Core count, load average
- **Memory**: Total, used, free, percent used
- **Disk**: Total, used, available, percent used
- **Network**: Bytes in/out, packets in/out per interface
- **Processes**: Total and running process counts
- **Docker**: Status and running container count

Output is JSON for easy parsing and aggregation.

## Cost Tracking

Cost data is retrieved using AWS Cost Explorer API:

```bash
aws ce get-cost-and-usage \
  --time-period Start=2024-03-01 End=2024-03-17 \
  --granularity MONTHLY \
  --metrics UnblendedCost \
  --group-by Type=DIMENSION,Key=SERVICE
```

The HTML report displays:
- Total cost for the current month
- Cost breakdown by AWS service
- Per-instance resource utilization metrics
- Memory and disk usage with warning/critical thresholds

## Batch Operations

Playbooks use `serial: 10` to process servers one batch at a time for safety:

```yaml
serial: 10  # Process 10 servers in parallel, then wait before next 10
```

This prevents overwhelming the control node and allows rollback if issues occur.

### Running specific batches:

```bash
# Only run batch 1
ansible-playbook playbooks/patching.yml --limit batch_1

# Only run batch 2
ansible-playbook playbooks/patching.yml --limit batch_2

# Run batches 1 and 2
ansible-playbook playbooks/patching.yml --limit "batch_1,batch_2"
```

## Dynamic Inventory

The `inventory/aws_ec2.yml` file uses the `amazon.aws.aws_ec2` plugin to dynamically discover instances. It filters on:

- Tag: `Project: Vprofile`
- Tag: `Role: app-server`
- State: `running`

Then groups by `Batch` tag, creating:
- `batch_1` (servers 01-10)
- `batch_2` (servers 11-20)
- `batch_3` (servers 21-30)

### Test inventory:

```bash
# Show all hosts and groups
ansible-inventory -i inventory/aws_ec2.yml --list | jq

# Show just batch_1
ansible-inventory -i inventory/aws_ec2.yml --host batch_1
```

## Troubleshooting

### SSH Connection Issues
- Verify `~/.ssh/vprofile-key.pem` exists and has correct permissions (600)
- Check security group allows SSH from your IP/bastion
- Verify instances have correct private subnet and can route to your machine

### Instances Not Appearing in Inventory
```bash
# Check if instances are running and tagged correctly
aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:Project,Values=Vprofile" \
  --query 'Reservations[].Instances[].[InstanceId,Tags[?Key==`Name`].Value|[0],State.Name]' \
  --output table
```

### Ansible Collection Missing
```bash
# Install required collections
ansible-galaxy collection install amazon.aws
```

### AWS CLI Not Configured
```bash
# Configure AWS credentials
aws configure
# Or use environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
```

## Advanced Usage

### Dry Run
```bash
ansible-playbook playbooks/package_install.yml --check
```

### Verbose Output
```bash
ansible-playbook playbooks/patching.yml -vv
```

### Run as Specific User
```bash
ansible-playbook playbooks/package_install.yml --user ubuntu --become
```

### Save Output to Log
```bash
ansible-playbook playbooks/monitoring_and_cost.yml | tee deployment_$(date +%Y%m%d_%H%M%S).log
```

## AWS Cost Estimation

**Instance Types**:
- t3.medium: ~$0.0416/hour
- 30 instances = ~$1.25/hour (~$900/month)

**Bandwidth**:
- Data transfer out to internet: $0.09/GB

**Monitoring**:
- CloudWatch: minimal cost for standard metrics

**Total estimated monthly cost**: $900-1000 for compute + data transfer

## Cleanup

To destroy all provisioned infrastructure:

```bash
# First, terminate instances
aws ec2 terminate-instances \
  --region us-east-2 \
  --instance-ids $(aws ec2 describe-instances \
    --region us-east-2 \
    --filters "Name=tag:Project,Values=Vprofile" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text)

# Delete security group (after instances are terminated)
aws ec2 delete-security-group \
  --region us-east-2 \
  --group-name vprofile-app-sg
```

## Support & Documentation

- [Ansible Documentation](https://docs.ansible.com/)
- [AWS EC2 Module](https://docs.ansible.com/ansible/latest/collections/amazon/aws/ec2_instance_module.html)
- [AWS Cost Explorer API](https://docs.aws.amazon.com/aws-cost-management/latest/APIReference/API_GetCostAndUsage.html)
- [AWS CLI Reference](https://docs.aws.amazon.com/cli/latest/reference/)
