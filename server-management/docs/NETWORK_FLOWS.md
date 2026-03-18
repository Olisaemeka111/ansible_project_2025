# Network Flows & Testing

This document describes the traffic flows in the 3-tier architecture and provides testing procedures to validate the security posture.

## Traffic Flow Diagram

### Happy Path - Normal User Request

```
User (Internet)
    │
    │ TCP 80/443 (HTTPS)
    │
    ▼
┌─────────────────┐
│  ALB/NLB        │ (Terminates SSL, distributes traffic)
└────────┬────────┘
         │
         │ Forward to port 8080
         │ (or configured app port)
         │
         ├─ ┌────────────────────┐
         ├─ │ vprofile-web-01    │ (10.0.4.10)
         ├─ │ (Nginx/Apache)     │
         ├─ └────────────────────┘
         │
         ├─ ┌────────────────────┐
         ├─ │ vprofile-web-02    │ (10.0.5.20)
         │  │ (Nginx/Apache)     │
         │  └────────────────────┘
         │
         └─ ┌────────────────────┐
            │ vprofile-web-03    │ (10.0.6.30)
            │ (Nginx/Apache)     │
            └────────────────────┘
         │
         │ (TCP 8000-9000, allowed by SG)
         │
         ├─ ┌────────────────────┐
         ├─ │ vprofile-app-01    │ (10.0.7.10)
         ├─ │ (Java/Node/Python) │
         │  └────────────────────┘
         │
         ├─ ┌────────────────────┐
         ├─ │ vprofile-app-02    │ (10.0.8.20)
         │  │ (Java/Node/Python) │
         │  └────────────────────┘
         │
         └─ ┌────────────────────┐
            │ vprofile-app-03    │ (10.0.9.30)
            │ (Java/Node/Python) │
            └────────────────────┘
         │
         │ (TCP 3306/5432/27017/6379, allowed by SG)
         │
         ├─ ┌────────────────────┐
         ├─ │ vprofile-db-01     │ (MySQL/PostgreSQL)
         │  │ (10.0.10.10)       │
         │  └────────────────────┘
         │
         ├─ ┌────────────────────┐
         ├─ │ vprofile-db-02     │ (MongoDB/Redis)
         │  │ (10.0.11.20)       │
         │  └────────────────────┘
         │
         └─ ┌────────────────────┐
            │ vprofile-db-03     │ (Cache/Queue)
            │ (10.0.12.30)       │
            └────────────────────┘
         │
         │ (Database returns data)
         │ (Response flows back through tiers)
         │
         ▼
User (with response data)
```

### SSH Access Flow

```
Admin (Your Computer)
    │
    │ TCP 22 (SSH)
    │
    ▼
┌─────────────────────────────────┐
│  Bastion Host (Jump Host)       │
│  (Exists in public subnet)      │
│  (SSH from YOUR_IP allowed)     │
└────────────┬────────────────────┘
             │
             │ SSH via Private Network
             │ (No internet path)
             │
             ├─ ┌─────────────────────────┐
             ├─ │ vprofile-web-01         │ ✓ Allowed (Bastion→Web SG)
             │  │ (Manage web config)     │
             │  └─────────────────────────┘
             │
             ├─ ┌─────────────────────────┐
             ├─ │ vprofile-app-01         │ ✓ Allowed (Bastion→App SG)
             │  │ (Deploy application)    │
             │  └─────────────────────────┘
             │
             └─ ┌─────────────────────────┐
                │ vprofile-db-01          │ ✓ Allowed (Bastion→DB SG)
                │ (Manage databases)      │
                │ (Emergency access only) │
                └─────────────────────────┘
```

### Blocked Flows

```
User (Internet) ↛ App Tier         ❌ NOT in public subnet
                                       Security group blocks

User (Internet) ↛ Database Tier    ❌ NOT in public subnet
                                       Security group blocks

Web Tier ↛ Database Tier           ❌ No SG rule allows it
                                       Different port range

Database Tier → Internet            ❌ DENY ALL egress
                                       Cannot send data out

App Tier → Web Tier                 ❌ No SG rule allows
(reverse direction)                     One-way communication

Database Tier ↛ Other Tiers         ❌ No egress rules
(any outbound)                          Completely locked down
```

---

## Testing Procedures

### Phase 1: Verify Instances & Tags

```bash
# List all instances
aws ec2 describe-instances \
  --region us-east-2 \
  --filters "Name=tag:Project,Values=Vprofile" \
  --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],IP:PrivateIpAddress,Tier:Tags[?Key==`Tier`].Value|[0],State:State.Name}' \
  --output table

# Expected output: 30 instances (10 web, 10 app, 10 db) all in running state
```

### Phase 2: Verify Dynamic Inventory Groups

```bash
# Show all groups
ansible-inventory -i inventory/aws_ec2.yml --list | jq '.all.children | keys'

# Expected output: ["all_servers", "aws_ec2", "web_tier", "app_tier", "db_tier"]

# Count instances per tier
ansible -i inventory/aws_ec2.yml web_tier --list-hosts | wc -l   # Should be 10
ansible -i inventory/aws_ec2.yml app_tier --list-hosts | wc -l    # Should be 10
ansible -i inventory/aws_ec2.yml db_tier --list-hosts | wc -l     # Should be 10
```

### Phase 3: Basic Connectivity Tests

```bash
# Ping all servers
echo "Testing Web Tier..."
ansible -i inventory/aws_ec2.yml web_tier -m ping

echo "Testing App Tier..."
ansible -i inventory/aws_ec2.yml app_tier -m ping

echo "Testing Database Tier..."
ansible -i inventory/aws_ec2.yml db_tier -m ping

# Expected: "pong" response from all servers (requires Bastion SSH access)
```

### Phase 4: Inter-Tier Connectivity Tests

#### Test 4.1: Web → App Tier (Should SUCCEED ✅)

```bash
# Get an app server IP
APP_SERVER_IP=$(ansible -i inventory/aws_ec2.yml app_tier -m debug -a var=ansible_host --limit vprofile-app-01 | grep vprofile-app-01 -A2 | grep -oE '10\.[0-9.]+')

# From web tier, try to reach app server on port 8000
ansible -i inventory/aws_ec2.yml web_tier -m shell -a "nc -zv $APP_SERVER_IP 8000" --limit vprofile-web-01

# Expected output:
# "Connection to $APP_SERVER_IP 8000 port [tcp/*] succeeded!"
```

#### Test 4.2: Web → Database Tier (Should FAIL ❌)

```bash
# Get a database server IP
DB_SERVER_IP=$(ansible -i inventory/aws_ec2.yml db_tier -m debug -a var=ansible_host --limit vprofile-db-01 | grep vprofile-db-01 -A2 | grep -oE '10\.[0-9.]+')

# From web tier, try to reach database on MySQL port 3306
ansible -i inventory/aws_ec2.yml web_tier -m shell -a "nc -zv $DB_SERVER_IP 3306" --limit vprofile-web-01

# Expected output:
# "nc: connect to $DB_SERVER_IP port 3306 (tcp) failed: Connection refused"
# or timeout after several seconds
```

#### Test 4.3: App → Database Tier (Should SUCCEED ✅)

```bash
# Get a database server IP
DB_SERVER_IP=$(ansible -i inventory/aws_ec2.yml db_tier -m debug -a var=ansible_host --limit vprofile-db-01 | grep vprofile-db-01 -A2 | grep -oE '10\.[0-9.]+')

# From app tier, try to reach database on port 3306
ansible -i inventory/aws_ec2.yml app_tier -m shell -a "nc -zv $DB_SERVER_IP 3306" --limit vprofile-app-01

# Expected output:
# "Connection to $DB_SERVER_IP 3306 port [tcp/*] succeeded!"
```

#### Test 4.4: Database → App Tier Reverse (Should FAIL ❌)

```bash
# Get an app server IP
APP_SERVER_IP=$(ansible -i inventory/aws_ec2.yml app_tier -m debug -a var=ansible_host --limit vprofile-app-01 | grep vprofile-app-01 -A2 | grep -oE '10\.[0-9.]+')

# From database tier, try to SSH to app server
ansible -i inventory/aws_ec2.yml db_tier -m shell -a "nc -zv $APP_SERVER_IP 22" --limit vprofile-db-01

# Expected output:
# "nc: connect to $APP_SERVER_IP port 22 (tcp) failed: Connection refused"
# Database tier has no egress rules - should timeout/fail
```

### Phase 5: Outbound Traffic Tests

#### Test 5.1: Web Tier DNS (Should SUCCEED ✅)

```bash
# DNS from web tier
ansible -i inventory/aws_ec2.yml web_tier -m shell -a "nslookup google.com" --limit vprofile-web-01

# Expected: DNS query succeeds (port 53 allowed outbound)
```

#### Test 5.2: Database Tier DNS (Should FAIL ❌)

```bash
# DNS from database tier
ansible -i inventory/aws_ec2.yml db_tier -m shell -a "nslookup google.com" --limit vprofile-db-01

# Expected: DNS query times out or fails
# Database tier has DENY ALL egress - no DNS allowed
```

#### Test 5.3: Database Tier HTTPS (Should FAIL ❌)

```bash
# HTTPS from database tier
ansible -i inventory/aws_ec2.yml db_tier -m shell -a "curl https://www.google.com" --limit vprofile-db-01

# Expected: Connection times out or fails
# Database tier has DENY ALL egress - no outbound to internet
```

### Phase 6: SSH Access Tests

#### Test 6.1: SSH from Bastion to Web Tier (Should SUCCEED ✅)

```bash
# SSH into bastion first
ssh -i ~/.ssh/vprofile-key.pem ubuntu@bastion-public-ip

# From bastion, SSH to web server
ssh -i ~/.ssh/vprofile-key.pem ubuntu@vprofile-web-01-private-ip

# Expected: SSH succeeds
# Bastion-host-sg allows egress SSH to vprofile-web-tier-sg
```

#### Test 6.2: SSH from Bastion to Database Tier (Should SUCCEED ✅)

```bash
# SSH into bastion
ssh -i ~/.ssh/vprofile-key.pem ubuntu@bastion-public-ip

# From bastion, SSH to database server
ssh -i ~/.ssh/vprofile-key.pem ubuntu@vprofile-db-01-private-ip

# Expected: SSH succeeds (emergency management)
```

#### Test 6.3: Direct SSH from Internet to Web Tier (Should FAIL ❌)

```bash
# Try SSH directly from your computer to web server
ssh -i ~/.ssh/vprofile-key.pem ubuntu@vprofile-web-01-private-ip

# Expected: Connection times out or Connection refused
# Web tier is in private network (no public IP), requires Bastion hop
```

### Phase 7: Application-Level Tests

#### Test 7.1: Verify Web Server is Running

```bash
# Check nginx/apache running on web tier
ansible -i inventory/aws_ec2.yml web_tier -m shell -a "sudo systemctl status nginx" --limit vprofile-web-01

# Expected: Active (running)
```

#### Test 7.2: Verify Application Port Open

```bash
# Check app server listening on port 8080
ansible -i inventory/aws_ec2.yml app_tier -m shell -a "sudo netstat -tlnp | grep 8080" --limit vprofile-app-01

# Expected: Shows process listening on 8080
# (if application is running)
```

#### Test 7.3: Verify Database Port Open

```bash
# Check database server listening on port 3306
ansible -i inventory/aws_ec2.yml db_tier -m shell -a "sudo netstat -tlnp | grep 3306" --limit vprofile-db-01

# Expected: Shows MySQL process listening on 3306
# (if MySQL is installed and running)
```

---

## Common Test Scenarios

### Scenario 1: User Makes Web Request

```
1. User visits https://myapp.com
2. DNS resolves to ALB IP
3. ALB forwards to Web Tier servers (port 8080)
4. Web server receives request, forwards to App Tier (port 8000)
5. App server processes, connects to Database (port 3306)
6. Database returns data
7. App returns response to Web
8. Web returns HTML/JSON to user
```

**Expected result**: ✅ Success

### Scenario 2: Admin Deploys Code

```
1. Admin SSH to Bastion (their IP → port 22)
2. Bastion SSH to App server (Bastion IP → port 22)
3. Admin updates application files
4. Admin restarts app service
5. Web servers automatically discover new app servers (via load balancer)
6. Traffic flows to updated application
```

**Expected result**: ✅ Success

### Scenario 3: Database Backup

```
1. Backup script runs on Database Tier server
2. Creates backup file
3. Tries to upload to S3 (outbound HTTPS)
```

**Expected result**: ❌ Fails (DENY ALL outbound)

**Solution**: Configure backup on App Tier or use VPC endpoints for S3

### Scenario 4: Lateral Movement Attack

```
1. Attacker compromises Web server
2. Attacker tries to SSH to Database server
3. Attacker tries to access database directly on port 3306
```

**Expected result**: ❌ Both fail (no direct connectivity)

**Why protected**:
- No SG rule allows Web → Database
- Database needs credentials (if running DB server)
- Multiple layers of security (SG + DB auth + app server in between)

---

## Troubleshooting Connectivity Issues

### "Connection refused" vs "Connection timed out"

| Error | Meaning | Cause |
|-------|---------|-------|
| Connection refused | Host received traffic but denied it | Security group rule blocking |
| Connection timed out | No response at all | Security group rule blocking + no route |
| No route to host | Network can't reach destination | Subnet routing issue |

### Web → App Fails

**Symptoms**: Web server can't reach app server on port 8000

**Diagnosis**:
```bash
# 1. Verify app server is running
ansible -i inventory/aws_ec2.yml app_tier -m shell -a "ps aux | grep app"

# 2. Check app SG allows inbound from web SG
aws ec2 describe-security-groups --group-names vprofile-app-tier-sg \
  --query 'SecurityGroups[0].IpPermissions'

# 3. Test from web server
ansible -i inventory/aws_ec2.yml web_tier -m shell -a "curl http://10.0.x.x:8000"
```

**Solutions**:
- [ ] Ensure app service is running
- [ ] Check app tier SG inbound rule for port 8000 from web SG
- [ ] Verify network routing (check route tables)
- [ ] Verify no NACLs are blocking traffic

### App → Database Fails

**Symptoms**: App can't connect to database on port 3306

**Diagnosis**:
```bash
# 1. Check database is running
ansible -i inventory/aws_ec2.yml db_tier -m shell -a "sudo systemctl status mysql" --limit vprofile-db-01

# 2. Check database SG allows inbound from app SG
aws ec2 describe-security-groups --group-names vprofile-db-tier-sg \
  --query 'SecurityGroups[0].IpPermissions' | grep 3306

# 3. Test connectivity
ansible -i inventory/aws_ec2.yml app_tier -m shell -a "nc -zv 10.0.x.x 3306"
```

**Solutions**:
- [ ] Ensure MySQL/PostgreSQL is installed and running
- [ ] Check DB SG inbound rule for port 3306 from app SG
- [ ] Verify database credentials are correct
- [ ] Check database is listening on 3306 (not localhost only)

### Cannot SSH to Database Tier

**Symptoms**: Can't SSH from Bastion to database server

**Diagnosis**:
```bash
# 1. Verify Bastion can reach database tier on port 22
ansible -i inventory/aws_ec2.yml db_tier -m shell -a "sudo systemctl status ssh"

# 2. Check DB SG allows SSH from Bastion SG
aws ec2 describe-security-groups --group-names vprofile-db-tier-sg \
  --query 'SecurityGroups[0].IpPermissions' | grep 22

# 3. Test from Bastion
ssh -v -i ~/.ssh/vprofile-key.pem ubuntu@db-private-ip
```

**Solutions**:
- [ ] Ensure SSH is enabled/running on database tier
- [ ] Verify DB SG inbound rule allows SSH from Bastion SG
- [ ] Check you're using correct SSH key (`vprofile-key`)
- [ ] Verify Bastion can reach private subnets (routing)

---

## Performance Testing

### Test Baseline Latency

```bash
# Ping app server from web server
ansible -i inventory/aws_ec2.yml web_tier -m shell -a "ping -c 4 app-server-ip" --limit vprofile-web-01

# Expected: <5ms latency within same region
```

### Test Database Query Latency

```bash
# Connect to database from app server and time query
ansible -i inventory/aws_ec2.yml app_tier -m shell -a "time mysql -h db-server-ip -u user -p'password' -e 'SELECT 1'" --limit vprofile-app-01

# Expected: <10ms query time
```

---

## Related Documentation

- See `SECURITY_ARCHITECTURE.md` for overall design
- See `SECURITY_GROUPS.md` for detailed rule explanations
- See `README.md` for operation instructions
