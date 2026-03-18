# Security Groups Configuration

This document provides detailed information about all security groups in the 3-tier architecture.

## Security Groups Summary

| SG Name | Tier | Purpose | Strictness |
|---------|------|---------|-----------|
| `vprofile-web-tier-sg` | Web | Internet-facing servers | Medium |
| `vprofile-app-tier-sg` | App | Application servers | Strict |
| `vprofile-db-tier-sg` | DB | Database servers | Very Strict |
| `Bastion-host-sg` | Mgmt | Bastion/Jump host (existing) | Medium |

---

## 1. Web Tier Security Group (`vprofile-web-tier-sg`)

**Purpose**: Controls traffic to/from web servers in public subnets

**Location**: Public subnets (pubsub1, pubsub2, pubsub3)

**Servers**: vprofile-web-01 through vprofile-web-10

### Ingress Rules (Inbound)

| # | Protocol | Port | Source | Description |
|---|----------|------|--------|-------------|
| 1 | TCP | 80 | 0.0.0.0/0 | HTTP from internet |
| 2 | TCP | 443 | 0.0.0.0/0 | HTTPS from internet |
| 3 | TCP | 22 | `Bastion-host-sg` | SSH from Bastion host |

**Rationale**:
- Ports 80/443: Required for public web traffic
- Port 22: SSH restricted to Bastion for administrative access
- No other inbound ports open

### Egress Rules (Outbound)

| # | Protocol | Port | Destination | Description |
|---|----------|------|-------------|-------------|
| 1 | TCP | 8000-9000 | `vprofile-app-tier-sg` | To App tier servers |
| 2 | UDP | 53 | 0.0.0.0/0 | DNS queries (resolving names) |
| 3 | TCP | 443 | 0.0.0.0/0 | HTTPS (package updates, APIs) |

**Rationale**:
- Ports 8000-9000: Forward requests to app servers
- Port 53 (DNS): Required for domain name resolution
- Port 443 (HTTPS): Ubuntu security updates, npm/pip repos

**Blocked Outbound**:
- ❌ Port 3306 (MySQL): Web tier cannot access database directly
- ❌ SSH to other tiers: Web cannot SSH to app/db
- ❌ All other ports: Minimizes attack surface

---

## 2. App Tier Security Group (`vprofile-app-tier-sg`)

**Purpose**: Controls traffic to/from application servers in private subnets

**Location**: Private subnets (privsub1, privsub2, privsub3)

**Servers**: vprofile-app-01 through vprofile-app-10

### Ingress Rules (Inbound)

| # | Protocol | Port | Source | Description |
|---|----------|------|--------|-------------|
| 1 | TCP | 8000-9000 | `vprofile-web-tier-sg` | App traffic from Web tier |
| 2 | TCP | 22 | `Bastion-host-sg` | SSH from Bastion host |

**Rationale**:
- Ports 8000-9000: Only Web tier can reach app servers
- Port 22: SSH from Bastion only (no direct internet access)
- No other inbound ports open

**Blocked Inbound**:
- ❌ Direct access from internet (not in public subnet)
- ❌ Database ports: App receives data, not the other way
- ❌ SSH from web tier: Better security hygiene

### Egress Rules (Outbound)

| # | Protocol | Port | Destination | Description |
|---|----------|------|-------------|-------------|
| 1 | TCP | 3306 | `vprofile-db-tier-sg` | MySQL/MariaDB |
| 2 | TCP | 5432 | `vprofile-db-tier-sg` | PostgreSQL |
| 3 | TCP | 27017 | `vprofile-db-tier-sg` | MongoDB |
| 4 | TCP | 6379 | `vprofile-db-tier-sg` | Redis |
| 5 | UDP | 53 | 0.0.0.0/0 | DNS queries |
| 6 | TCP | 443 | 0.0.0.0/0 | HTTPS (CloudWatch, repos) |

**Rationale**:
- DB ports: Only database tier receives these (app initiates connections)
- Port 53 (DNS): Required for hostname resolution
- Port 443 (HTTPS): CloudWatch monitoring, pip/npm repos, AWS API calls

**Blocked Outbound**:
- ❌ To Web tier: App doesn't respond on port 80/443 (web initiates)
- ❌ Random ports: Only necessary ports allowed
- ❌ SSH outbound: No lateral movement between servers

---

## 3. Database Tier Security Group (`vprofile-db-tier-sg`)

**Purpose**: Controls traffic to/from database servers in private subnets
**Strictest security posture**: DENY ALL outbound traffic

**Location**: Private subnets (privsub1, privsub2, privsub3)

**Servers**: vprofile-db-01 through vprofile-db-10

### Ingress Rules (Inbound)

| # | Protocol | Port | Source | Description |
|---|----------|------|--------|-------------|
| 1 | TCP | 3306 | `vprofile-app-tier-sg` | MySQL/MariaDB from App tier |
| 2 | TCP | 5432 | `vprofile-app-tier-sg` | PostgreSQL from App tier |
| 3 | TCP | 27017 | `vprofile-app-tier-sg` | MongoDB from App tier |
| 4 | TCP | 6379 | `vprofile-app-tier-sg` | Redis from App tier |
| 5 | TCP | 22 | `Bastion-host-sg` | SSH from Bastion (emergency) |

**Rationale**:
- Only app tier can connect on database ports
- Multiple DB protocols supported for flexibility
- SSH restricted to Bastion for emergency access only

**Blocked Inbound**:
- ❌ From internet: Not in public subnet, security group blocks it
- ❌ From web tier: No direct web-to-database communication
- ❌ From app tier on other ports: Only database ports allowed

### Egress Rules (Outbound)

**DENY ALL** ⛔

| Status | Description |
|--------|-------------|
| ❌ | NO outbound traffic allowed |
| ❌ | No DNS, no HTTPS, no HTTP |
| ❌ | No SSH to other servers |
| ❌ | Database cannot call external APIs |
| ❌ | Database cannot reach CloudWatch directly |

**Rationale**:
- Maximum security: Database servers are read-only (from app perspective)
- Prevents data exfiltration attacks
- Database cannot become a pivot point for attacks
- If compromised, attacker cannot use it to reach other systems

**How it works with monitoring**:
- App servers collect DB metrics and send to CloudWatch
- DB tier doesn't send data directly to CloudWatch
- Log aggregation done on app tier or separate logging server

---

## 4. Bastion Host Security Group (`Bastion-host-sg`)

**Purpose**: Manages SSH access to the infrastructure (existing, not created by this playbook)

**Location**: Public subnet (pubsub1)

**Servers**: bastion-host (existing instance)

### Typical Ingress Rules

| # | Protocol | Port | Source | Description |
|---|----------|------|--------|-------------|
| 1 | TCP | 22 | YOUR_IP/32 | SSH from your IP |

### Typical Egress Rules

| # | Protocol | Port | Destination | Description |
|---|----------|------|-------------|-------------|
| 1 | TCP | 22 | `vprofile-web-tier-sg` | SSH to Web tier |
| 2 | TCP | 22 | `vprofile-app-tier-sg` | SSH to App tier |
| 3 | TCP | 22 | `vprofile-db-tier-sg` | SSH to Database tier |
| 4 | TCP | 443 | 0.0.0.0/0 | HTTPS (systems updates) |
| 5 | UDP | 53 | 0.0.0.0/0 | DNS |

---

## Port Ranges Explained

### Application Ports (8000-9000)

The range 8000-9000 is used for application services. Common allocations:

| Port | Typical Service |
|------|-----------------|
| 8000 | Django, Flask default |
| 8008 | Alternative app port |
| 8080 | Tomcat, common app port |
| 3000 | Node.js default |
| 5000 | Flask alternative |
| 9000 | Various app frameworks |

All ports 8000-9000 are allowed to provide flexibility without needing to update security groups for each service.

### Database Ports

| Port | Database | Default |
|------|----------|---------|
| 3306 | MySQL / MariaDB | Yes |
| 5432 | PostgreSQL | Yes |
| 27017 | MongoDB | Yes |
| 6379 | Redis | Yes |

All four are enabled to support different database choices.

---

## Modifying Security Groups

### Adding a New Port

**Example**: Allow port 9200 (Elasticsearch) from App tier to Database tier

1. **Via Ansible** (recommended):
   ```yaml
   # Edit vars/security_groups.yml
   # Add to db_tier_sg rules_ingress:
   - proto: tcp
     from_port: 9200
     to_port: 9200
     group_id: vprofile-app-tier-sg
     rule_desc: "Elasticsearch from App tier"

   # Run playbook
   ansible-playbook playbooks/security_groups.yml
   ```

2. **Via AWS Console**:
   - Go to EC2 → Security Groups
   - Select `vprofile-db-tier-sg`
   - Inbound rules → Edit
   - Add rule: Type=Custom TCP, Port=9200, Source=vprofile-app-tier-sg
   - Save

3. **Via AWS CLI**:
   ```bash
   aws ec2 authorize-security-group-ingress \
     --group-id sg-xxxxx \
     --protocol tcp \
     --port 9200 \
     --source-group vprofile-app-tier-sg
   ```

### Restricting a Port

**Example**: Remove HTTP (port 80) from Web tier

1. **Via Ansible**:
   ```yaml
   # Edit vars/security_groups.yml
   # Remove port 80 from web_tier_sg rules_ingress
   ```

2. **Via AWS Console**:
   - Security Groups → vprofile-web-tier-sg → Inbound
   - Find HTTP rule (port 80)
   - Delete rule

3. **Via AWS CLI**:
   ```bash
   aws ec2 revoke-security-group-ingress \
     --group-id sg-xxxxx \
     --protocol tcp \
     --port 80 \
     --cidr 0.0.0.0/0
   ```

---

## Testing Security Groups

### Verify Rules Are Applied

```bash
# List all rules for Web tier
aws ec2 describe-security-groups \
  --region us-east-2 \
  --filters Name=group-name,Values=vprofile-web-tier-sg

# Check specific rule exists
aws ec2 describe-security-groups \
  --region us-east-2 \
  --filters Name=group-name,Values=vprofile-db-tier-sg \
  --query 'SecurityGroups[0].IpPermissions'
```

### Test Connectivity Between Tiers

```bash
# SSH to app server via Bastion
ssh -J ubuntu@bastion-ip ubuntu@app-server-ip

# Test app can reach database
ansible -i inventory/aws_ec2.yml app_tier -m shell -a "nc -zv db-server-ip 3306"

# Test web cannot reach database
ansible -i inventory/aws_ec2.yml web_tier -m shell -a "nc -zv db-server-ip 3306"
# Should timeout (connection refused)
```

### Troubleshooting Connection Issues

| Issue | Diagnosis | Solution |
|-------|-----------|----------|
| Web → App fails | Check sg rules | Verify app SG allows 8000-9000 from web SG |
| App → DB fails | Check sg rules | Verify db SG allows port 3306 from app SG |
| Cannot SSH to server | Check Bastion access | Verify Bastion-host-sg allows your IP on 22 |
| DNS fails | Check sg rules | Verify port 53 UDP is allowed to 0.0.0.0/0 |
| Apt updates fail | Check sg rules | Verify port 443 TCP to 0.0.0.0/0 for HTTPS |

---

## Security Group Best Practices Applied

✅ **Least Privilege**: Only open necessary ports
✅ **Defense in Depth**: Multiple layers of rules
✅ **Explicit Deny**: Close everything except what's needed
✅ **Clear Naming**: Names describe purpose (tier-sg pattern)
✅ **Documentation**: Each rule has description/rationale
✅ **SG-to-SG References**: Not CIDR blocks where possible
✅ **Immutable Tags**: Consistent tagging for tracking
✅ **Audit Trail**: AWS CloudTrail logs all changes

---

## Common Ports Reference

### Web Services
| Port | Service | Use |
|------|---------|-----|
| 80 | HTTP | Unencrypted web traffic |
| 443 | HTTPS | Encrypted web traffic |
| 8080 | Alternative HTTP | Proxy, alternative apps |

### Databases
| Port | Database |
|------|----------|
| 3306 | MySQL / MariaDB |
| 5432 | PostgreSQL |
| 27017 | MongoDB |
| 6379 | Redis |

### Administration & Services
| Port | Service |
|------|---------|
| 22 | SSH |
| 53 | DNS (UDP/TCP) |
| 123 | NTP |
| 3389 | RDP |

### DNS & Network
| Port | Service | Type |
|------|---------|------|
| 53 | DNS | UDP/TCP |
| 67,68 | DHCP | UDP |
| 123 | NTP | UDP |

---

## Related Documentation

- See `SECURITY_ARCHITECTURE.md` for overall design
- See `NETWORK_FLOWS.md` for traffic flow diagrams
- See AWS Security Group documentation: https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html
