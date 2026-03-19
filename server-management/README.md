# Server Management: 30 Servers in 3-Tier Architecture

Ansible playbooks and configurations to provision, patch, and monitor 30 Ubuntu 22.04 servers on AWS, organized in a 3-tier architecture (Web, App, Database) with 10 servers per tier.

## Deployment Method

This infrastructure is deployed **automatically via GitHub Actions**. Push to `main` triggers a full deployment. Manual cleanup is available via `workflow_dispatch`.

```
GitHub Actions → SSM → Control Node (EC2) → Ansible → 30 Servers
```

No manual Ansible execution is needed. The workflow handles everything:
1. Creates VPC, subnets, IGW, NAT GW, route tables
2. Creates SSH key pair (reuses if exists)
3. Launches control node, bootstraps Ansible via SSM
4. Creates 3 security groups
5. Provisions 30 servers (10 web + 10 app + 10 db)
6. Installs tier-specific packages
7. Applies OS patches
8. Creates Application Load Balancer

## Directory Structure

```
server-management/
├── ansible.cfg                  # Ansible configuration
├── inventory/
│   ├── aws_ec2.yml              # Dynamic inventory (aws_ec2 plugin)
│   └── group_vars/
│       ├── all.yml              # Shared variables
│       ├── web_tier.yml         # Web tier config
│       ├── app_tier.yml         # App tier config
│       └── db_tier.yml          # DB tier config
├── vars/
│   ├── servers.yml              # 30 server definitions
│   ├── packages.yml             # Tier-specific package lists
│   ├── security_groups.yml      # SG rule definitions
│   ├── output_vars.yml          # VPC/subnet IDs (auto-generated)
│   ├── security_groups_output.yml  # SG IDs (auto-generated)
│   └── servers_output.yml       # Server details (auto-generated)
├── playbooks/
│   ├── security_groups.yml      # Create 3 security groups
│   ├── provision_servers.yml    # Provision 30 EC2 instances
│   ├── package_install.yml      # Install tier-specific packages
│   ├── patching.yml             # Apply OS patches (all tiers)
│   └── monitoring_and_cost.yml  # Resource monitoring + cost report
├── scripts/
│   └── resource_monitor.sh      # System metrics collector (JSON)
├── templates/
│   └── monitoring_report.html.j2  # HTML cost report template
└── docs/
    ├── SECURITY_ARCHITECTURE.md # 3-tier design + diagrams
    ├── SECURITY_GROUPS.md       # Detailed SG rules
    └── NETWORK_FLOWS.md         # Traffic flows + testing
```

## 3-Tier Architecture

```
Internet → ALB → [Web Tier] → [App Tier] → [DB Tier]
                  (public)     (private)    (private, no egress)
```

| Tier | Servers | Subnets | Packages | Ports |
|------|---------|---------|----------|-------|
| **Web** | vprofile-web-01 to -10 | Public (172.20.1-3.0/24) | nginx, certbot, fail2ban, php-fpm | 80, 443 |
| **App** | vprofile-app-01 to -10 | Private (172.20.4-6.0/24) | Java 17, Python 3, Node.js 20, Docker | 8000-9000 |
| **DB** | vprofile-db-01 to -10 | Private (172.20.4-6.0/24) | mysql-client, postgresql-client, redis-tools | 3306, 5432, 27017, 6379 |

## Security Groups

| SG | Inbound | Outbound |
|----|---------|----------|
| **vprofile-web-tier-sg** | HTTP/HTTPS from internet, SSH from VPC | App Tier (8000-9000), DNS, HTTPS, HTTP |
| **vprofile-app-tier-sg** | App ports from Web SG, SSH from VPC | DB Tier (DB ports), DNS, HTTPS, HTTP |
| **vprofile-db-tier-sg** | DB ports from App SG, SSH from VPC | **DENY ALL** |

DB tier egress is temporarily opened for package install and patching, then locked down.

## Playbooks

### security_groups.yml
Creates 3 security groups with SG-to-SG rules. Must run first.

### provision_servers.yml
Provisions 30 EC2 instances across 3 tiers and 3 AZs. Uses `state: present` for idempotency.

### package_install.yml
Installs tier-specific packages. DB tier is wrapped with temporary egress open/close.

### patching.yml
Applies `apt dist-upgrade` to all tiers. Reboots if kernel updated. DB tier wrapped with temporary egress.

### monitoring_and_cost.yml
Collects CPU/memory/disk/network metrics and generates HTML cost report.

## Manual Access

### SSM to control node
```bash
# Find current control node
aws ec2 describe-instances --region us-east-2 \
  --filters "Name=tag:Name,Values=vprofile-control-node" "Name=instance-state-name,Values=running" \
  --query "Reservations[].Instances[].InstanceId" --output text

# Connect
aws ssm start-session --target <instance-id> --region us-east-2
```

### Run playbooks manually (from control node)
```bash
sudo -u ubuntu -H bash
cd /home/ubuntu/deploy/server-management
ansible-playbook playbooks/security_groups.yml
ansible-playbook playbooks/provision_servers.yml
ansible-playbook playbooks/package_install.yml
ansible-playbook playbooks/patching.yml
```

### Test connectivity
```bash
ansible -i inventory/aws_ec2.yml web_tier -m ping
ansible -i inventory/aws_ec2.yml app_tier -m ping
ansible -i inventory/aws_ec2.yml db_tier -m ping
```

### Limit to specific tier
```bash
ansible-playbook playbooks/patching.yml --limit web_tier
ansible-playbook playbooks/patching.yml --limit app_tier
```

## Dynamic Inventory

The `aws_ec2.yml` plugin discovers instances by tags and creates groups:
- `web_tier`, `app_tier`, `db_tier` (by Tier tag)
- `web_servers`, `app_servers`, `db_servers` (by Tier tag)

```bash
ansible-inventory -i inventory/aws_ec2.yml --list | jq '.all.children'
```

## Cleanup

Use the GitHub Actions workflow with `cleanup` action, or manually:

```bash
# Terminate all instances
aws ec2 terminate-instances --region us-east-2 \
  --instance-ids $(aws ec2 describe-instances --region us-east-2 \
    --filters "Name=tag:Project,Values=Vprofile" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' --output text)
```

## Cost

- 30 x t3.medium: ~$900/month
- ALB + NAT GW: ~$55/month
- Total: ~$960-1,100/month

## Documentation

- [SECURITY_ARCHITECTURE.md](docs/SECURITY_ARCHITECTURE.md) — Architecture design and diagrams
- [SECURITY_GROUPS.md](docs/SECURITY_GROUPS.md) — Detailed SG rules
- [NETWORK_FLOWS.md](docs/NETWORK_FLOWS.md) — Traffic flows and testing
