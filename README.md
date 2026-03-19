# 3-Tier AWS Infrastructure with Ansible & GitHub Actions

## Project Overview

Fully automated deployment of a **30-server, 3-tier architecture** on AWS using Ansible for configuration management and GitHub Actions for CI/CD orchestration. Everything is created from scratch — no pre-existing infrastructure required.

**Repository:** https://github.com/Olisaemeka111/ansible_project_2025.git

---

## What Was Built

### Infrastructure Created (Automated via GitHub Actions)

| Resource | Details |
|----------|---------|
| **VPC** | `172.20.0.0/16` in `us-east-2` |
| **Subnets** | 6 total — 3 public (`172.20.1-3.0/24`) + 3 private (`172.20.4-6.0/24`) |
| **Internet Gateway** | Attached to VPC for public subnet internet access |
| **NAT Gateway** | In public subnet for private subnet outbound access |
| **Route Tables** | Public (IGW) + Private (NAT GW) |
| **SSH Key Pair** | `vprofile-key` — created once, reused across runs via S3 |
| **Control Node** | EC2 instance with Ansible bootstrapped via AWS SSM |
| **Security Groups** | 3 tier-specific SGs with least-privilege rules |
| **EC2 Instances** | 30 servers (10 web + 10 app + 10 db) across 3 AZs |
| **Application Load Balancer** | Routes HTTP traffic to web tier |
| **S3 Bucket** | Code distribution and SSH key storage |

### Server Inventory (30 Instances)

**Web Tier** (10 servers in public subnets):
```
vprofile-web-01  172.20.1.86   18.191.235.250  us-east-2a
vprofile-web-02  172.20.2.238  18.191.177.217  us-east-2b
vprofile-web-03  172.20.3.166  3.19.245.158    us-east-2c
vprofile-web-04  172.20.1.205  3.149.255.14    us-east-2a
vprofile-web-05  172.20.2.227  18.223.99.253   us-east-2b
vprofile-web-06  172.20.3.50   18.217.101.46   us-east-2c
vprofile-web-07  172.20.1.200  18.188.238.72   us-east-2a
vprofile-web-08  172.20.2.209  3.16.136.214    us-east-2b
vprofile-web-09  172.20.3.34   52.14.163.155   us-east-2c
vprofile-web-10  172.20.1.24   3.135.193.92    us-east-2a
```

**App Tier** (10 servers in private subnets):
```
vprofile-app-01 through vprofile-app-10
172.20.4.x / 172.20.5.x / 172.20.6.x (private only)
```

**Database Tier** (10 servers in private subnets):
```
vprofile-db-01 through vprofile-db-10
172.20.4.x / 172.20.5.x / 172.20.6.x (private only, no outbound)
```

**ALB DNS:** `vprofile-web-alb-908000172.us-east-2.elb.amazonaws.com`

---

## Architecture

```
                        INTERNET
                           |
                    [ ALB (HTTP/HTTPS) ]
                           |
              +------------+------------+
              |            |            |
         us-east-2a   us-east-2b   us-east-2c
              |            |            |
    +---------+--+---------+--+---------+--+
    | PUBLIC SUBNETS (172.20.1-3.0/24)     |
    | [Web Tier] 10 servers                |
    | nginx, certbot, fail2ban, php-fpm    |
    | Inbound: 80, 443, 22                 |
    | Outbound: App Tier (8000-9000)       |
    +--------------------------------------+
              |
              | ports 8000-9000
              |
    +--------------------------------------+
    | PRIVATE SUBNETS (172.20.4-6.0/24)    |
    | [App Tier] 10 servers                |
    | Java 17, Python 3, Node.js 20,       |
    | Docker CE, build tools               |
    | Inbound: 8000-9000 from Web SG       |
    | Outbound: DB Tier (3306,5432,27017,  |
    |           6379) + DNS + HTTPS        |
    +--------------------------------------+
              |
              | DB ports only
              |
    +--------------------------------------+
    | PRIVATE SUBNETS (172.20.4-6.0/24)    |
    | [DB Tier] 10 servers                 |
    | mysql-client, postgresql-client,      |
    | redis-tools, sqlite3, collectd       |
    | Inbound: 3306, 5432, 27017, 6379     |
    |          from App SG only            |
    | Outbound: DENY ALL                   |
    +--------------------------------------+
```

---

## Security Groups

| Security Group | Inbound | Outbound |
|----------------|---------|----------|
| **vprofile-web-tier-sg** | HTTP (80), HTTPS (443) from `0.0.0.0/0`; SSH (22) from VPC CIDR | App Tier (8000-9000), DNS (53), HTTPS (443), HTTP (80) |
| **vprofile-app-tier-sg** | Ports 8000-9000 from Web SG; SSH (22) from VPC CIDR | DB Tier (3306, 5432, 27017, 6379), DNS (53), HTTPS (443), HTTP (80) |
| **vprofile-db-tier-sg** | MySQL (3306), PostgreSQL (5432), MongoDB (27017), Redis (6379) from App SG; SSH (22) from VPC CIDR | **DENY ALL** (no outbound traffic) |

> DB tier egress is temporarily opened for package installation and patching, then immediately locked down.

---

## GitHub Actions Workflow

### Triggers
- **Push to `main`** — deploys automatically
- **Manual dispatch** — choose `deploy` or `cleanup`

### Deployment Steps (Visible in GitHub Actions UI)

| Step | Description |
|------|-------------|
| 1. Create VPC | VPC with CIDR `172.20.0.0/16` |
| 2. Create subnets | 3 public + 3 private across 3 AZs |
| 3. Create Internet Gateway | Attach IGW to VPC |
| 4. Create NAT Gateway | For private subnet outbound access |
| 5. Create route tables | Public (IGW) + Private (NAT) |
| 6. Create/reuse SSH key pair | Idempotent — checks AWS + S3 before creating |
| 7. Generate vars files | Update Ansible vars with new VPC/subnet IDs |
| 8. Upload code to S3 | Distribute code to control node |
| 9. Launch control node | EC2 with SSM agent for remote execution |
| 10. Bootstrap control node | Install Ansible, AWS CLI, collections |
| 11. Deploy SSH key | Copy key from S3 to control node |
| 12. Sync code | Copy playbooks to control node |
| **Phase 1** | Create 3 security groups |
| **Phase 2** | Provision 30 servers (10 per tier) |
| **Phase 3** | Verify SSH connectivity to all 30 instances |
| **Phase 4** | Install tier-specific packages |
| **Phase 5** | Apply OS patches |
| 13. Create ALB | Application Load Balancer for web tier |
| 14. Display EC2 inventory | Show all 30 instances with IPs |
| 15. Deployment summary | Final report |

### Cleanup (Manual Dispatch)
Destroys **everything** in reverse order: ALB, instances, security groups, NAT GW, IGW, subnets, route tables, VPC, SSH key pair.

---

## Packages Installed Per Tier

### Web Tier
- nginx, certbot, python3-certbot-nginx, fail2ban, ufw, php-fpm, php-mysql
- Common: curl, wget, git, htop, jq, awscli, vim, nano, net-tools

### App Tier
- **Java 17**: openjdk-17-jdk/jre/headless
- **Python 3**: python3, pip3, venv, dev tools + pip packages (boto3, botocore, requests, python-dotenv)
- **Node.js 20**: via NodeSource repository
- **Docker CE**: docker-ce, docker-compose-plugin, docker-buildx-plugin, containerd.io
- Build tools: build-essential, libssl-dev, libffi-dev

### Database Tier
- mysql-client, postgresql-client, redis-tools, sqlite3
- Monitoring: collectd

---

## Directory Structure

```
Ansible-infrastructure/
├── .github/workflows/
│   └── deploy-infrastructure.yml    # Main CI/CD workflow (deploy + cleanup)
├── server-management/
│   ├── ansible.cfg                  # Ansible configuration
│   ├── inventory/
│   │   ├── aws_ec2.yml              # Dynamic inventory (aws_ec2 plugin)
│   │   └── group_vars/
│   │       ├── all.yml              # Shared variables
│   │       ├── web_tier.yml         # Web tier config
│   │       ├── app_tier.yml         # App tier config
│   │       └── db_tier.yml          # DB tier config
│   ├── vars/
│   │   ├── servers.yml              # 30 server definitions
│   │   ├── packages.yml             # Tier-specific package lists
│   │   ├── security_groups.yml      # SG rule definitions
│   │   ├── output_vars.yml          # VPC/subnet IDs
│   │   ├── security_groups_output.yml  # Generated SG IDs
│   │   └── servers_output.yml       # Generated server details
│   ├── playbooks/
│   │   ├── security_groups.yml      # Create 3 security groups
│   │   ├── provision_servers.yml    # Provision 30 EC2 instances
│   │   ├── package_install.yml      # Install tier-specific packages
│   │   ├── patching.yml             # Apply OS patches (all tiers)
│   │   └── monitoring_and_cost.yml  # Resource monitoring + cost report
│   ├── scripts/
│   │   └── resource_monitor.sh      # System metrics collector (JSON)
│   ├── templates/
│   │   └── monitoring_report.html.j2  # HTML cost report template
│   └── docs/
│       ├── SECURITY_ARCHITECTURE.md # 3-tier design + diagrams
│       ├── SECURITY_GROUPS.md       # Detailed SG rules + troubleshooting
│       └── NETWORK_FLOWS.md         # Traffic flows + testing procedures
└── README.md                        # This file
```

---

## How to Use

### Deploy (Automatic)
```bash
git push origin main
# Workflow triggers automatically, creates everything from scratch
```

### Deploy (Manual)
Go to **Actions** > **Deploy 3-Tier Infrastructure** > **Run workflow** > Select `deploy`

### Cleanup All Resources
Go to **Actions** > **Deploy 3-Tier Infrastructure** > **Run workflow** > Select `cleanup`

### Required GitHub Secrets
| Secret | Description |
|--------|-------------|
| `AWS_ACCESS_KEY_ID` | IAM user with EC2/VPC/ELB/SSM/S3 permissions |
| `AWS_SECRET_ACCESS_KEY` | Corresponding secret key |

---

## Key Technical Decisions

| Decision | Rationale |
|----------|-----------|
| **SSM for remote execution** | No SSH needed from GitHub runner to control node |
| **S3 for code distribution** | Reliable delivery of playbooks + SSH keys |
| **SSH key reuse** | Checks AWS + S3 before creating new — prevents key mismatch |
| **`sudo -u ubuntu -H`** | `-H` flag ensures HOME=/home/ubuntu for SSH key resolution |
| **Temporary DB egress** | Opens HTTP/HTTPS/DNS only for install/patch, then locks down |
| **SG-to-SG references** | More secure than CIDR — rules follow instances, not IPs |
| **`serial: 10`** | Process all 10 servers in a tier simultaneously |
| **Concurrency control** | `cancel-in-progress: true` prevents overlapping deployments |
| **Idempotent provisioning** | `state: present` with Name tag — safe to rerun |

---

## Cost Estimate

| Resource | Monthly Cost |
|----------|-------------|
| 30 x t3.medium | ~$900 ($0.0416/hr each) |
| ALB | ~$23 + LCU charges |
| NAT Gateway | ~$32 + data processing |
| EBS Storage | ~$0.10/GB/month |
| Data Transfer | ~$0.09/GB outbound |
| **Total** | **~$960-1,100/month** |

---

## Author

**Olisa Arinze**
Contact: olisa.arinze@icloud.com
