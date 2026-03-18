# Quick Reference Guide

## Common Commands

### View All Servers in Inventory
```bash
ansible-inventory -i inventory/aws_ec2.yml --list | jq '.all.children'
```

### Test Connection to All Servers
```bash
ansible -i inventory/aws_ec2.yml app_servers -m ping
```

### Test Connection to Specific Batch
```bash
ansible -i inventory/aws_ec2.yml batch_1 -m ping
```

### Get OS Info from All Servers
```bash
ansible -i inventory/aws_ec2.yml app_servers -m setup -a 'filter=ansible_distribution*'
```

### Run Ad-hoc Command on All Servers
```bash
ansible -i inventory/aws_ec2.yml app_servers -m shell -a 'df -h'
```

### Run Command on Specific Server
```bash
ansible -i inventory/aws_ec2.yml vprofile-app-01 -m shell -a 'free -h'
```

## Playbook Commands

### Provision All 30 Servers
```bash
ansible-playbook playbooks/provision_servers.yml
```

### Install Packages on All Servers (processes 10 at a time)
```bash
ansible-playbook playbooks/package_install.yml
```

### Install Packages on Batch 1 Only
```bash
ansible-playbook playbooks/package_install.yml --limit batch_1
```

### Apply Patches to All Servers
```bash
ansible-playbook playbooks/patching.yml
```

### Apply Patches to Batches 2 and 3
```bash
ansible-playbook playbooks/patching.yml --limit "batch_2,batch_3"
```

### Run Monitoring and Generate Cost Report
```bash
ansible-playbook playbooks/monitoring_and_cost.yml
```

### Dry Run (Preview Changes Without Applying)
```bash
ansible-playbook playbooks/patching.yml --check
```

### Verbose Output (Debug)
```bash
ansible-playbook playbooks/package_install.yml -vv
```

### Run with Extra Variables
```bash
ansible-playbook playbooks/provision_servers.yml -e "instance_type=t3.small"
```

## Useful One-Liners

### Get All Instance IDs
```bash
aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:Project,Values=Vprofile" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text
```

### List Instances by Batch
```bash
aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:Batch,Values=batch_1" \
  --query 'Reservations[].Instances[].{ID:InstanceId,Name:Tags[0].Value,IP:PrivateIpAddress,State:State.Name}' \
  --output table
```

### Get Instance IP Addresses
```bash
aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:Project,Values=Vprofile" \
  --query 'Reservations[].Instances[].[PrivateIpAddress,Tags[?Key==`Name`].Value|[0]]' \
  --output text
```

### Check Instance Status
```bash
aws ec2 describe-instance-status \
  --region us-east-2 \
  --filters "Name=instance-state-name,Values=running" \
  --query 'InstanceStatuses[].{ID:InstanceId,Status:InstanceStatus.Status}'
```

### Get Security Group Info
```bash
aws ec2 describe-security-groups \
  --region us-east-2 \
  --filters "Name=group-name,Values=vprofile-app-sg" \
  --output table
```

### Estimate Monthly Cost for Running Instances
```bash
# t3.medium: $0.0416/hour
HOURS_IN_MONTH=730
INSTANCE_COUNT=30
HOURLY_RATE=0.0416
python3 -c "print(f'Estimated monthly cost: ${HOURS_IN_MONTH * INSTANCE_COUNT * HOURLY_RATE:.2f}')"
```

### SSH into Specific Instance (via Bastion)
```bash
# Note: requires bastion configuration; example with bastion host
INSTANCE_IP="172.20.4.5"
BASTION_IP="bastion.example.com"
ssh -J ubuntu@${BASTION_IP} ubuntu@${INSTANCE_IP}
```

### View Recent Ansible Logs
```bash
# If you saved output to a log file
tail -f deployment_*.log
```

### Check Package Installation on Instance
```bash
ansible -i inventory/aws_ec2.yml batch_1 -m shell -a 'which java node docker'
```

### Check Patch Status
```bash
ansible -i inventory/aws_ec2.yml app_servers -m shell -a 'sudo apt list --upgradable'
```

## Monitoring Commands

### View Cost Report in Terminal
```bash
# Run monitoring playbook and capture output
ansible-playbook playbooks/monitoring_and_cost.yml | grep -A 50 "Cost Information"
```

### Check Latest Cost Report HTML
```bash
# Open the latest report in default browser
LATEST_REPORT=$(ls -t reports/cost_report_*.html | head -1)
open "$LATEST_REPORT"  # macOS
xdg-open "$LATEST_REPORT"  # Linux
start "$LATEST_REPORT"  # Windows
```

### Export Metrics to CSV
```bash
# Parse JSON metrics to CSV
jq -r '.[] | [.hostname, .private_ip, (.memory.percent_used|round), (.disk.percent_used|round)] | @csv' \
  reports/metrics_*.json > metrics_export.csv
```

### Monitor Real-Time Instance Metrics
```bash
# Check CPU load on all instances
ansible -i inventory/aws_ec2.yml app_servers -m shell -a 'cat /proc/loadavg'

# Check memory usage on all instances
ansible -i inventory/aws_ec2.yml app_servers -m shell -a 'free -h'

# Check disk usage on all instances
ansible -i inventory/aws_ec2.yml app_servers -m shell -a 'df -h /'
```

## Batch-Specific Operations

### Show All Servers in Batch 1
```bash
ansible -i inventory/aws_ec2.yml batch_1 --list-hosts
```

### Count Servers per Batch
```bash
echo "Batch 1:" && ansible -i inventory/aws_ec2.yml batch_1 --list-hosts | wc -l
echo "Batch 2:" && ansible -i inventory/aws_ec2.yml batch_2 --list-hosts | wc -l
echo "Batch 3:" && ansible -i inventory/aws_ec2.yml batch_3 --list-hosts | wc -l
```

### Update Hosts File with Instance IPs
```bash
# Create a static hosts file from dynamic inventory
ansible -i inventory/aws_ec2.yml app_servers --list-hosts > /tmp/instances.txt
cat /tmp/instances.txt
```

## Cleanup Operations

### Stop All Instances
```bash
aws ec2 stop-instances \
  --region us-east-2 \
  --instance-ids $(aws ec2 describe-instances \
    --region us-east-2 \
    --filters "Name=tag:Project,Values=Vprofile" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text)
```

### Terminate All Instances
```bash
INSTANCE_IDS=$(aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:Project,Values=Vprofile" \
  --query 'Reservations[].Instances[].InstanceId' \
  --output text)

aws ec2 terminate-instances \
  --region us-east-2 \
  --instance-ids $INSTANCE_IDS
```

### Delete Security Group
```bash
# Wait for instances to terminate first (5-10 minutes)
aws ec2 delete-security-group \
  --region us-east-2 \
  --group-name vprofile-app-sg
```

## Environment Variables

Set these to customize behavior:

```bash
# AWS Region
export AWS_REGION=us-east-2
export AWS_DEFAULT_REGION=us-east-2

# AWS Credentials (if not using ~/.aws/credentials)
export AWS_ACCESS_KEY_ID=your_key_id
export AWS_SECRET_ACCESS_KEY=your_secret_key

# Ansible settings
export ANSIBLE_INVENTORY=inventory/aws_ec2.yml
export ANSIBLE_HOST_KEY_CHECKING=False
```

## Tips

1. **Always test with `-limit batch_1` first** before running on all servers
2. **Use `--check` mode** to preview what will happen
3. **Monitor instances** in AWS Console while running playbooks
4. **Keep backups** of important config files
5. **Review logs** in `/tmp/` after each playbook run
6. **Test connectivity** with `ansible -m ping` before running operations
7. **Run cost reports regularly** to track spending
8. **Use tags** to organize and filter instances
