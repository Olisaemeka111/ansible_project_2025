# Quick Reference Guide

## Inventory Commands

### View all groups
```bash
ansible-inventory -i inventory/aws_ec2.yml --list | jq '.all.children'
```

### List hosts per tier
```bash
ansible -i inventory/aws_ec2.yml web_tier --list-hosts
ansible -i inventory/aws_ec2.yml app_tier --list-hosts
ansible -i inventory/aws_ec2.yml db_tier --list-hosts
```

### Test connectivity
```bash
ansible -i inventory/aws_ec2.yml web_tier -m ping
ansible -i inventory/aws_ec2.yml app_tier -m ping
ansible -i inventory/aws_ec2.yml db_tier -m ping
```

## Playbook Commands

### Full deployment sequence (run from control node)
```bash
ansible-playbook playbooks/security_groups.yml
ansible-playbook playbooks/provision_servers.yml
ansible-playbook playbooks/package_install.yml
ansible-playbook playbooks/patching.yml
ansible-playbook playbooks/monitoring_and_cost.yml
```

### Limit to specific tier
```bash
ansible-playbook playbooks/patching.yml --limit web_tier
ansible-playbook playbooks/patching.yml --limit app_tier
ansible-playbook playbooks/patching.yml --limit db_tier
```

### Dry run
```bash
ansible-playbook playbooks/patching.yml --check
```

### Verbose output
```bash
ansible-playbook playbooks/package_install.yml -vv
```

## Ad-hoc Commands

### Run shell command on a tier
```bash
ansible -i inventory/aws_ec2.yml web_tier -m shell -a 'df -h'
ansible -i inventory/aws_ec2.yml app_tier -m shell -a 'free -h'
ansible -i inventory/aws_ec2.yml db_tier -m shell -a 'uptime'
```

### Check installed packages
```bash
ansible -i inventory/aws_ec2.yml web_tier -m shell -a 'nginx -v'
ansible -i inventory/aws_ec2.yml app_tier -m shell -a 'java -version'
ansible -i inventory/aws_ec2.yml app_tier -m shell -a 'node --version'
ansible -i inventory/aws_ec2.yml app_tier -m shell -a 'docker --version'
ansible -i inventory/aws_ec2.yml db_tier -m shell -a 'mysql --version'
```

### Check patch status
```bash
ansible -i inventory/aws_ec2.yml web_tier -m shell -a 'sudo apt list --upgradable 2>/dev/null | wc -l'
```

## AWS CLI One-Liners

### List all instances by tier
```bash
aws ec2 describe-instances --region us-east-2 \
  --filters "Name=tag:Project,Values=Vprofile" "Name=tag:Tier,Values=web" \
  --query 'Reservations[].Instances[].[Tags[?Key==`Name`].Value|[0],PrivateIpAddress,State.Name]' \
  --output table
```

### Get all instance IDs
```bash
aws ec2 describe-instances --region us-east-2 \
  --filters "Name=tag:Project,Values=Vprofile" "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].InstanceId' --output text
```

### Find control node
```bash
aws ec2 describe-instances --region us-east-2 \
  --filters "Name=tag:Name,Values=vprofile-control-node" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" --output text
```

### SSM to control node
```bash
aws ssm start-session --target <instance-id> --region us-east-2
```

### Get security group rules
```bash
aws ec2 describe-security-groups --region us-east-2 \
  --filters "Name=group-name,Values=vprofile-web-tier-sg" --output table
```

## Cleanup

### Stop all instances (pause billing)
```bash
aws ec2 stop-instances --region us-east-2 \
  --instance-ids $(aws ec2 describe-instances --region us-east-2 \
    --filters "Name=tag:Project,Values=Vprofile" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' --output text)
```

### Terminate all instances
```bash
aws ec2 terminate-instances --region us-east-2 \
  --instance-ids $(aws ec2 describe-instances --region us-east-2 \
    --filters "Name=tag:Project,Values=Vprofile" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' --output text)
```

### Full cleanup via GitHub Actions
Go to **Actions** > **Deploy 3-Tier Infrastructure** > **Run workflow** > Select `cleanup`
