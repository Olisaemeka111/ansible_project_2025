# 3-Tier Security Architecture

## Overview

This document describes the security architecture for a 3-tier web application deployed on AWS with Ansible. The architecture implements defense-in-depth principles with tightly scoped security groups, network isolation, and least-privilege access controls.

## Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                         INTERNET (0.0.0.0/0)                    │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         ALB / Network Load Balancer (Optional)           │  │
│  │         Ports: 80 (HTTP), 443 (HTTPS)                    │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                     │
│                           ▼                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │         PUBLIC SUBNETS (3 AZs: a, b, c)                  │  │
│  │ ┌────────────────────────────────────────────────────┐   │  │
│  │ │  WEB TIER (Tier: web, Role: web-server)           │   │  │
│  │ │  • 10 servers (vprofile-web-01 to -10)            │   │  │
│  │ │  • Instance Type: t3.medium                        │   │  │
│  │ │  • Inbound:  80, 443 (from 0.0.0.0/0)             │   │  │
│  │ │  •            22 (from Bastion)                    │   │  │
│  │ │  • Outbound: 8000-9000 (to App Tier)              │   │  │
│  │ │  •           DNS (53), HTTPS (443)                │   │  │
│  │ │  • Security Group: vprofile-web-tier-sg           │   │  │
│  │ └────────────────────────────────────────────────────┘   │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                     │
│                           ▼                                     │
└─────────────────────────────────────────────────────────────────┘
              │
              │  (Internal Traffic Only)
              │
┌─────────────────────────────────────────────────────────────────┐
│                      PRIVATE SUBNETS (3 AZs)                    │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  APP TIER (Tier: app, Role: app-server)                 │  │
│  │  • 10 servers (vprofile-app-01 to -10)                  │  │
│  │  • Instance Type: t3.medium                             │  │
│  │  • Inbound:  8000-9000 (from Web Tier)                 │  │
│  │  •           22 (from Bastion)                          │  │
│  │  • Outbound: 3306, 5432, 27017, 6379 (to DB Tier)     │  │
│  │  •           DNS (53), HTTPS (443)                     │  │
│  │  • Security Group: vprofile-app-tier-sg                │  │
│  └──────────────────────────────────────────────────────────┘  │
│                           │                                     │
│                           ▼                                     │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  DATABASE TIER (Tier: db, Role: db-server)              │  │
│  │  • 10 servers (vprofile-db-01 to -10)                   │  │
│  │  • Instance Type: t3.medium                             │  │
│  │  • Inbound:  3306 (MySQL)   from App Tier             │  │
│  │  •           5432 (PostgreSQL) from App Tier           │  │
│  │  •           27017 (MongoDB) from App Tier             │  │
│  │  •           6379 (Redis) from App Tier                │  │
│  │  •           22 (SSH from Bastion, emergency only)     │  │
│  │  • Outbound: DENY ALL (⛔ No outbound traffic)          │  │
│  │  • Security Group: vprofile-db-tier-sg                 │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  Bastion Host (Existing):                                      │
│  • Allows SSH access to all tiers                             │
│  • Acts as jump host for emergency access                     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Key Principles

### 1. **Least Privilege Access**
- Each tier only has access to what it needs
- Web tier cannot directly access database
- Database tier cannot initiate outbound connections
- SSH access restricted to Bastion host

### 2. **Network Segmentation**
- **Web Tier**: Public subnets, exposed to internet via ALB
- **App Tier**: Private subnets, only receives traffic from web tier
- **Database Tier**: Private subnets, only receives traffic from app tier
- No cross-tier communication except in defined direction

### 3. **Defense in Depth**
- Security groups (network level)
- Instance-level firewall rules (UFW on web tier)
- Application-level access controls
- SSH key-based authentication only

### 4. **Immutability & Auditability**
- Instances tagged with tier, role, project, owner
- All changes tracked in Ansible playbooks
- Security group changes logged in AWS CloudTrail

## Traffic Flows

### Allowed Flows ✅

```
User Request (80/443)
    ↓
[Internet] → [ALB/NLB] → [Web Tier]
    ↓
[Web Tier] → [App Tier] (8000-9000)
    ↓
[App Tier] → [Database Tier] (3306, 5432, 27017, 6379)
    ↓
[Database] ← [App Tier] (response)
    ↓
[Web] ← [App Tier] (response)
    ↓
[User] ← [Web Tier] (response)
```

### Blocked Flows ❌

```
[User] ↛ [App Tier]        - No direct access to app servers
[User] ↛ [Database Tier]   - No direct access to databases
[Web] ↛ [Database]         - Web tier cannot reach database
[App] ↛ [Web]              - App tier cannot initiate to web
[DB] → [Internet]          - Database cannot send outbound
[Web] → [App] (except 8000-9000)
[App] → [DB] (except DB ports)
```

## Instance Details

### Distribution Across Availability Zones

```
Availability Zone a (us-east-2a)
├── Web Server (pubsub1)
├── App Server (privsub1)
└── Database Server (privsub1)

Availability Zone b (us-east-2b)
├── Web Server (pubsub2)
├── App Server (privsub2)
└── Database Server (privsub2)

Availability Zone c (us-east-2c)
├── Web Server (pubsub3)
├── App Server (privsub3)
└── Database Server (privsub3)

... pattern repeats for remaining 7 servers of each tier
```

### Server Naming Convention

- **Web Tier**: `vprofile-web-01` to `vprofile-web-10`
- **App Tier**: `vprofile-app-01` to `vprofile-app-10`
- **Database Tier**: `vprofile-db-01` to `vprofile-db-10`

### Common Tags

All instances are tagged with:
- `Project: Vprofile`
- `Owner: DevOps Team`
- `Tier: web|app|db` (tier classification)
- `Role: web-server|app-server|db-server` (server role)
- `ManagedBy: Ansible` (configuration management)

## Security Best Practices Implemented

### ✅ Network Level
- [x] Security groups with least privilege rules
- [x] No open ports except required ones
- [x] Security group-to-security group rules (not CIDR)
- [x] Separate SGs per tier for granular control
- [x] Private subnets for app and database tiers

### ✅ SSH Access
- [x] SSH (port 22) only from Bastion host
- [x] Key-based authentication (no passwords)
- [x] Bastion acts as jump host / bastion host pattern
- [x] SSH to database tier for emergency management only

### ✅ Outbound Traffic Control
- [x] Web tier: Restricted to app tier + DNS + HTTPS for repos
- [x] App tier: Restricted to database tier + DNS + HTTPS
- [x] Database tier: DENY ALL (no outbound) - strictest posture

### ✅ Monitoring & Logging
- [x] CloudWatch monitoring enabled on all instances
- [x] VPC Flow Logs for network monitoring (setup separately)
- [x] All playbook changes logged in Ansible audit trail
- [x] AWS CloudTrail for infrastructure changes

### ✅ High Availability
- [x] Servers distributed across 3 availability zones
- [x] Multiple instances per tier (10 each)
- [x] ALB for load balancing across web tier
- [x] RDS Multi-AZ for databases (setup separately)

## Database Port Support

The database tier allows connections on these ports (from app tier only):

| Port | Protocol | Database | Purpose |
|------|----------|----------|---------|
| 3306 | TCP | MySQL / MariaDB | Relational database |
| 5432 | TCP | PostgreSQL | Advanced relational DB |
| 27017 | TCP | MongoDB | NoSQL document DB |
| 6379 | TCP | Redis | In-memory cache/store |

## DB Tier Temporary Egress Pattern

The database tier has `DENY ALL` egress by design. However, package installation and patching
require temporary internet access. Both `package_install.yml` and `patching.yml` implement
an automated open/close pattern:

1. **Open** temporary egress on DB tier SG (DNS 53, HTTPS 443, HTTP 80)
2. **Run** the installation or patching tasks on DB tier servers
3. **Lock down** egress back to `rules_egress: []` (deny all)

This ensures DB servers never have persistent outbound access while still allowing
maintenance operations. The egress window is only open for the duration of the task.

## Deployment Order

1. **Create Security Groups** (must be first)
   ```bash
   ansible-playbook playbooks/security_groups.yml
   ```

2. **Provision Instances** (uses security group IDs from step 1)
   ```bash
   ansible-playbook playbooks/provision_servers.yml
   ```

3. **Install Packages** (tier-specific, auto-manages DB egress)
   ```bash
   ansible-playbook playbooks/package_install.yml
   ```

4. **Apply Patches** (tier-specific, auto-manages DB egress)
   ```bash
   ansible-playbook playbooks/patching.yml
   ```

## Testing & Validation

See `docs/NETWORK_FLOWS.md` for detailed testing procedures.

Quick connectivity tests:

```bash
# Test web tier
ansible -i inventory/aws_ec2.yml web_tier -m ping

# Test app tier
ansible -i inventory/aws_ec2.yml app_tier -m ping

# Test database tier
ansible -i inventory/aws_ec2.yml db_tier -m ping

# Test inter-tier connectivity
ansible -i inventory/aws_ec2.yml app_tier -m shell -a "curl http://10.0.0.x:8080"  # should work
ansible -i inventory/aws_ec2.yml web_tier -m shell -a "curl http://10.0.0.x:3306"  # should fail
```

## Modifications & Extensions

### Adding More Servers
Edit `vars/servers.yml`:
- Add entries to `web_servers`, `app_servers`, or `db_servers` lists
- Rerun `provision_servers.yml`

### Changing Security Rules
Edit `vars/security_groups.yml` or modify rules directly in AWS Console:
- Changes apply immediately to new instances
- Existing instances keep old rules until security group is updated

### Changing Instance Types
Edit `vars/servers.yml`:
- Update `instance_type: t3.medium` to desired type
- Rerun `provision_servers.yml` (or terminate and reprovision)

### Adding New Database Ports
Edit `vars/security_groups.yml`:
- Add new port to `db_tier_sg` ingress rules from app tier
- Rerun `security_groups.yml` or modify in AWS Console

## Security Considerations

### Network ACLs (NACLs)
- Currently using default VPC NACLs (allow all)
- Consider restricting at NACL level for additional security
- Not required if security groups are properly configured

### VPC Flow Logs
- Recommended: Enable VPC Flow Logs for audit trail
- Log to CloudWatch Logs or S3
- Useful for debugging connectivity issues and security analysis

### WAF (Web Application Firewall)
- Consider AWS WAF on ALB for:
  - DDoS protection
  - SQL injection / XSS prevention
  - Rate limiting
  - Geographic restrictions

### Encryption
- Data in transit: Use HTTPS/SSL
- Data at rest: Enable EBS encryption (setup separately)
- Secrets: Use AWS Secrets Manager or SSM Parameter Store

### Compliance
- This architecture supports:
  - PCI-DSS (with additional monitoring/logging)
  - HIPAA (with encryption)
  - SOC 2 (with proper logging)
  - GDPR (with data residency config)

## Cost Estimation

- **30 × t3.medium instances**: ~$0.0416/hour = ~$30/hour = ~$900/month
- **EBS storage**: ~$0.10 per GB/month
- **ALB**: ~$22.50/month + $0.006 per LCU
- **Data transfer**: ~$0.09/GB out to internet
- **Monitoring**: CloudWatch metrics included, logs ~$0.50/GB

**Total estimated**: $900-1000/month for compute

## Related Documentation

- See `SECURITY_GROUPS.md` for detailed rule explanations
- See `NETWORK_FLOWS.md` for traffic flow diagrams and tests
- See `README.md` for deployment and operation instructions
- See `GETTING_STARTED.md` for step-by-step setup guide
