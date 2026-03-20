# Detailed Usage Guide: 40 Ansible Playbooks for CI/CD Pipelines

This guide provides detailed instructions for every playbook in the collection, including prerequisites, variables, example commands, and recommended execution order.

---

## Table of Contents

1. [Prerequisites & Setup](#prerequisites--setup)
2. [Infrastructure Playbooks (1-7)](#infrastructure-playbooks)
3. [Configuration Playbooks (8-19)](#configuration-playbooks)
4. [Deployment Playbooks (20-40)](#deployment-playbooks)
5. [Recommended Workflows](#recommended-workflows)
6. [Troubleshooting](#troubleshooting)

---

## Prerequisites & Setup

### Install Ansible (Ubuntu/Debian)
```bash
sudo apt update
sudo apt install -y python3 python3-pip
pip3 install ansible
```

### Install Required Collections
```bash
# AWS
ansible-galaxy collection install amazon.aws

# Google Cloud
ansible-galaxy collection install google.cloud
pip3 install google-auth requests

# Azure
ansible-galaxy collection install azure.azcollection
pip3 install azure-identity azure-mgmt-compute azure-mgmt-network azure-mgmt-resource

# MySQL
ansible-galaxy collection install community.mysql

# Docker
ansible-galaxy collection install community.docker

# General
ansible-galaxy collection install community.general
```

### Inventory Setup
Create an inventory file for your target hosts:
```ini
# inventory/hosts
[webservers]
web-01 ansible_host=10.0.1.10
web-02 ansible_host=10.0.1.11

[appservers]
app-01 ansible_host=10.0.2.10
app-02 ansible_host=10.0.2.11

[dbservers]
db-01 ansible_host=10.0.3.10

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/deploy_key
```

### Directory Convention
All commands below assume you are running from the `ansible-playbooks-collection/` directory:
```bash
cd Ansible-infrastructure/ansible-playbooks-collection/
```

---

## Infrastructure Playbooks

These playbooks provision cloud resources. They run on **localhost** (your control machine) and require cloud provider credentials.

---

### Playbook 1: EC2 Provisioning (`playbooks/infrastructure/ec2_provisioning.yml`)

**What it does:** Provisions AWS EC2 instances with configurable instance type, AMI, security group, and tags.

**Prerequisites:**
- AWS credentials configured (`aws configure` or environment variables)
- `amazon.aws` collection installed
- Existing VPC subnet ID and security group

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-2` | AWS region |
| `instance_type` | `t3.medium` | Instance size |
| `ami_id` | Ubuntu 22.04 AMI | AMI to launch |
| `key_name` | `ansible-deploy-key` | SSH key pair name |
| `vpc_subnet_id` | *(required)* | Subnet to launch in |
| `security_group` | `default` | Security group name/ID |
| `instance_count` | `1` | Number of instances |
| `instance_tags` | Name, Env, Project | Instance tags |

**Usage Examples:**
```bash
# Provision 1 instance with required variables
ansible-playbook playbooks/infrastructure/ec2_provisioning.yml \
  -e "ami_id=ami-0ea3c35c5c3284d82 key_name=vprofile-key vpc_subnet_id=subnet-0123456789"

# Provision 5 instances in a specific security group
ansible-playbook playbooks/infrastructure/ec2_provisioning.yml \
  -e "ami_id=ami-0ea3c35c5c3284d82 key_name=vprofile-key vpc_subnet_id=subnet-0123456789 instance_count=5 security_group=my-web-sg"

# Override instance type and tags
ansible-playbook playbooks/infrastructure/ec2_provisioning.yml \
  -e '{"ami_id":"ami-0ea3c35c5c3284d82","key_name":"vprofile-key","vpc_subnet_id":"subnet-xxx","instance_type":"t3.large","instance_tags":{"Name":"prod-server","Environment":"production"}}'

# Dry run
ansible-playbook playbooks/infrastructure/ec2_provisioning.yml --check \
  -e "ami_id=ami-xxx key_name=my-key vpc_subnet_id=subnet-xxx"

# Run only the provision step (skip validation)
ansible-playbook playbooks/infrastructure/ec2_provisioning.yml --tags provision \
  -e "ami_id=ami-xxx key_name=my-key vpc_subnet_id=subnet-xxx"
```

---

### Playbook 2: GCP Provisioning (`playbooks/infrastructure/gcp_provisioning.yml`)

**What it does:** Provisions Google Cloud Compute Engine instances with configurable machine type, disk, network, and labels.

**Prerequisites:**
- GCP service account JSON key or Application Default Credentials
- `google.cloud` collection installed
- `pip3 install google-auth requests`

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `gcp_project` | *(required)* | GCP project ID |
| `gcp_zone` | `us-central1-a` | GCP zone |
| `machine_type` | `e2-medium` | Machine type |
| `instance_name` | `ansible-managed-instance` | VM name |
| `image_family` | `ubuntu-2204-lts` | OS image |
| `disk_size_gb` | `20` | Boot disk size |
| `disk_type` | `pd-ssd` | Disk type |
| `enable_public_ip` | `true` | Assign external IP |
| `service_account_file` | *(optional)* | Path to SA JSON key |

**Usage Examples:**
```bash
# Basic provisioning
ansible-playbook playbooks/infrastructure/gcp_provisioning.yml \
  -e "gcp_project=my-gcp-project-123"

# With service account and custom machine type
ansible-playbook playbooks/infrastructure/gcp_provisioning.yml \
  -e "gcp_project=my-project service_account_file=/path/to/sa-key.json machine_type=n2-standard-4 disk_size_gb=50"

# Provision in a specific zone without public IP
ansible-playbook playbooks/infrastructure/gcp_provisioning.yml \
  -e "gcp_project=my-project gcp_zone=europe-west1-b enable_public_ip=false"
```

---

### Playbook 3: VPC Setup (`playbooks/infrastructure/vpc_setup.yml`)

**What it does:** Creates a complete AWS VPC networking stack: VPC, Internet Gateway, 2 public subnets, 2 private subnets, NAT Gateway, and route tables.

**Prerequisites:**
- AWS credentials configured
- `amazon.aws` collection installed

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-east-2` | AWS region |
| `vpc_cidr` | `10.0.0.0/16` | VPC CIDR block |
| `vpc_name` | `ansible-managed-vpc` | VPC name |
| `project_name` | `infrastructure` | Project tag |
| `environment` | `development` | Environment tag |
| `public_subnets` | 2 subnets (10.0.1-2.0/24) | Public subnet definitions |
| `private_subnets` | 2 subnets (10.0.3-4.0/24) | Private subnet definitions |

**Usage Examples:**
```bash
# Create VPC with defaults
ansible-playbook playbooks/infrastructure/vpc_setup.yml

# Production VPC with custom name
ansible-playbook playbooks/infrastructure/vpc_setup.yml \
  -e "project_name=myapp environment=production vpc_name=myapp-production-vpc"

# Only create subnets (if VPC exists)
ansible-playbook playbooks/infrastructure/vpc_setup.yml --tags subnets

# Verify VPC resources
ansible-playbook playbooks/infrastructure/vpc_setup.yml --tags verify
```

---

### Playbook 4: Azure Provisioning (`playbooks/infrastructure/azure_provisioning.yml`)

**What it does:** Creates a complete Azure VM deployment: resource group, VNet, subnet, NSG, public IP, NIC, and VM.

**Prerequisites:**
- Azure credentials (service principal, managed identity, or `az login`)
- `azure.azcollection` collection installed
- Azure Python SDKs installed

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `resource_group_name` | `ansible-managed-rg` | Resource group |
| `location` | `eastus2` | Azure region |
| `vm_name` | `ansible-managed-vm` | VM name |
| `vm_size` | `Standard_B2s` | VM size |
| `admin_username` | `azureuser` | SSH username |
| `ssh_public_key` | *(optional)* | SSH public key content |
| `os_disk_size_gb` | `30` | OS disk size |

**Usage Examples:**
```bash
# Create VM with SSH key
ansible-playbook playbooks/infrastructure/azure_provisioning.yml \
  -e "ssh_public_key='ssh-rsa AAAA...'"

# Production VM with larger size
ansible-playbook playbooks/infrastructure/azure_provisioning.yml \
  -e "vm_name=prod-api-01 vm_size=Standard_D4s_v3 location=westus2 environment=production"

# Only create the VM (skip networking)
ansible-playbook playbooks/infrastructure/azure_provisioning.yml --tags vm
```

---

### Playbook 5: RDS Setup (`playbooks/infrastructure/rds_setup.yml`)

**What it does:** Creates an AWS RDS database instance with subnet group, encryption, automated backups, and optional multi-AZ.

**Prerequisites:**
- AWS credentials configured
- Existing VPC with private subnets (run `vpc_setup.yml` first)
- Subnet IDs for the DB subnet group

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `db_engine` | `mysql` | `mysql` or `postgres` |
| `db_instance_class` | `db.t3.medium` | Instance class |
| `db_name` | *(required)* | Database name |
| `master_username` | *(required)* | Master DB user |
| `master_password` | *(required)* | Master DB password |
| `allocated_storage` | `20` | Storage in GB |
| `multi_az` | `false` | Multi-AZ deployment |
| `backup_retention_period` | `7` | Backup retention days |

**Usage Examples:**
```bash
# Create MySQL RDS
ansible-playbook playbooks/infrastructure/rds_setup.yml \
  -e "db_name=myappdb master_username=admin master_password='SecurePass123!'"

# Create PostgreSQL RDS with Multi-AZ
ansible-playbook playbooks/infrastructure/rds_setup.yml \
  -e "db_engine=postgres db_name=myappdb master_username=admin master_password='SecurePass123!' multi_az=true"

# Production settings
ansible-playbook playbooks/infrastructure/rds_setup.yml \
  -e "db_name=proddb master_username=admin master_password='VaultedSecret' db_instance_class=db.r6g.large allocated_storage=100 multi_az=true deletion_protection=true skip_final_snapshot=false"
```

---

### Playbook 6: Jenkins Slave Setup (`playbooks/infrastructure/jenkins_slave_setup.yml`)

**What it does:** Configures remote hosts as Jenkins agent nodes with Java 17, Docker, Maven, Gradle, and a systemd-managed agent service.

**Prerequisites:**
- Target hosts running Ubuntu 22.04
- Jenkins master running and accessible
- Agent secret from Jenkins master

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `jenkins_master_url` | `https://jenkins.example.com` | Jenkins master URL |
| `agent_name` | auto-generated | Agent node name |
| `agent_secret` | *(required)* | Agent JNLP secret |
| `maven_version` | `3.9.9` | Maven version |
| `gradle_version` | `8.12` | Gradle version |

**Usage Examples:**
```bash
# Set up a Jenkins agent
ansible-playbook playbooks/infrastructure/jenkins_slave_setup.yml \
  -i inventory/hosts --limit jenkins_agents \
  -e "jenkins_master_url=https://jenkins.mycompany.com agent_name=agent-01 agent_secret=abc123def456"

# Install only build tools
ansible-playbook playbooks/infrastructure/jenkins_slave_setup.yml \
  -i inventory/hosts --tags install
```

---

### Playbook 7: Load Balancer Setup (`playbooks/infrastructure/load_balancer_setup.yml`)

**What it does:** Installs Nginx and configures it as a reverse-proxy load balancer with upstream servers, health checks, and UFW firewall rules.

**Prerequisites:**
- Target hosts running Ubuntu 22.04
- Backend servers already running

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `lb_port` | `80` | Load balancer listen port |
| `lb_algorithm` | `least_conn` | Algorithm: `round_robin`, `least_conn`, `ip_hash` |
| `backend_servers` | 2 sample backends | List of `{host, port, weight}` |

**Usage Examples:**
```bash
# Configure LB with backend servers
ansible-playbook playbooks/infrastructure/load_balancer_setup.yml \
  -i inventory/hosts --limit load_balancers \
  -e '{"backend_servers":[{"host":"10.0.1.10","port":8080,"weight":1},{"host":"10.0.1.11","port":8080,"weight":1}]}'

# Use IP hash algorithm
ansible-playbook playbooks/infrastructure/load_balancer_setup.yml \
  -i inventory/hosts --limit load_balancers \
  -e "lb_algorithm=ip_hash"
```

---

## Configuration Playbooks

These playbooks configure services on existing servers. They target remote hosts and require SSH access with sudo privileges.

---

### Playbook 8: Nginx Configuration (`playbooks/configuration/nginx_configuration.yml`)

**What it does:** Installs Nginx and deploys customizable virtual host configurations.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `nginx_server_name` | `example.com` | Server name |
| `nginx_document_root` | `/var/www/html` | Document root |
| `nginx_listen_port` | `80` | Listen port |
| `nginx_worker_processes` | `auto` | Worker processes |

**Usage Examples:**
```bash
# Configure Nginx on web servers
ansible-playbook playbooks/configuration/nginx_configuration.yml \
  -i inventory/hosts --limit webservers

# Custom server name
ansible-playbook playbooks/configuration/nginx_configuration.yml \
  -i inventory/hosts --limit webservers \
  -e "nginx_server_name=mysite.com nginx_document_root=/var/www/mysite"
```

---

### Playbook 9: Docker Installation (`playbooks/configuration/docker_installation.yml`)

**What it does:** Installs Docker CE from the official repository with docker-compose-plugin, configures daemon settings (log rotation, storage driver), and adds users to the docker group.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `docker_users` | `["ubuntu"]` | Users to add to docker group |
| `docker_daemon_config` | JSON file logging, overlay2 | Docker daemon.json settings |

**Usage Examples:**
```bash
# Install Docker on app servers
ansible-playbook playbooks/configuration/docker_installation.yml \
  -i inventory/hosts --limit appservers

# Add multiple users to docker group
ansible-playbook playbooks/configuration/docker_installation.yml \
  -i inventory/hosts \
  -e '{"docker_users":["ubuntu","deploy","jenkins"]}'
```

---

### Playbook 10: OpenVPN Setup (`playbooks/configuration/openvpn_setup.yml`)

**What it does:** Installs OpenVPN server with Easy-RSA PKI, generates CA/server certificates, DH params, and TLS auth key. Configures IP forwarding and UFW.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `vpn_network` | `10.8.0.0` | VPN subnet |
| `vpn_port` | `1194` | VPN port |
| `vpn_protocol` | `udp` | Protocol (udp/tcp) |
| `vpn_dns_servers` | Cloudflare (1.1.1.1) | DNS pushed to clients |
| `vpn_cipher` | `AES-256-GCM` | Encryption cipher |

**Usage Examples:**
```bash
# Set up OpenVPN server
ansible-playbook playbooks/configuration/openvpn_setup.yml \
  -i inventory/hosts --limit vpn_servers

# Custom VPN network and port
ansible-playbook playbooks/configuration/openvpn_setup.yml \
  -i inventory/hosts --limit vpn_servers \
  -e "vpn_network=10.10.0.0 vpn_port=443 vpn_protocol=tcp"
```

---

### Playbook 11: Redis Configuration (`playbooks/configuration/redis_configuration.yml`)

**What it does:** Installs Redis server with configurable bind address, authentication, memory limits, and persistence settings.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `redis_bind` | `127.0.0.1 ::1` | Bind addresses |
| `redis_port` | `6379` | Listen port |
| `redis_maxmemory` | `256mb` | Max memory |
| `redis_maxmemory_policy` | `allkeys-lru` | Eviction policy |
| `redis_password` | *(empty)* | Auth password |
| `redis_appendonly` | `yes` | AOF persistence |

**Usage Examples:**
```bash
# Install Redis with password
ansible-playbook playbooks/configuration/redis_configuration.yml \
  -i inventory/hosts --limit cache_servers \
  -e "redis_password='MyRedisPass!2024' redis_maxmemory=512mb"

# Redis accessible from app tier
ansible-playbook playbooks/configuration/redis_configuration.yml \
  -i inventory/hosts --limit cache_servers \
  -e "redis_bind='0.0.0.0' redis_password='SecurePass'"
```

---

### Playbook 12: MySQL Setup (`playbooks/configuration/mysql_setup.yml`)

**What it does:** Installs MySQL 8.0, sets root password, creates application database and user with privileges.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `mysql_root_password` | *(change this)* | Root password |
| `mysql_bind_address` | `127.0.0.1` | Bind address |
| `mysql_max_connections` | `150` | Max connections |
| `app_db_name` | `application_db` | App database name |
| `app_db_user` | `app_user` | App database user |
| `app_db_password` | *(change this)* | App user password |

**Usage Examples:**
```bash
# Install MySQL with app database
ansible-playbook playbooks/configuration/mysql_setup.yml \
  -i inventory/hosts --limit dbservers \
  -e "mysql_root_password='RootP@ss!' app_db_name=myapp app_db_user=myapp_user app_db_password='AppP@ss!'"

# MySQL accessible from network
ansible-playbook playbooks/configuration/mysql_setup.yml \
  -i inventory/hosts --limit dbservers \
  -e "mysql_bind_address='0.0.0.0' app_db_host='%'"
```

---

### Playbook 13: UFW Firewall (`playbooks/configuration/ufw_firewall.yml`)

**What it does:** Installs and configures UFW with default policies, base rules (SSH, HTTP, HTTPS), and custom port rules.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `ufw_default_incoming` | `deny` | Default incoming policy |
| `ufw_default_outgoing` | `allow` | Default outgoing policy |
| `ufw_ssh_rate_limit` | `true` | Rate limit SSH |
| `ufw_base_rules` | SSH(22), HTTP(80), HTTPS(443) | Default allowed ports |
| `ufw_allowed_ports` | `[]` | Additional ports to allow |

**Usage Examples:**
```bash
# Apply default firewall rules
ansible-playbook playbooks/configuration/ufw_firewall.yml -i inventory/hosts

# Add custom ports
ansible-playbook playbooks/configuration/ufw_firewall.yml -i inventory/hosts \
  -e '{"ufw_allowed_ports":[{"port":"8080","proto":"tcp","comment":"App port"},{"port":"3000","proto":"tcp","comment":"Node.js"}]}'
```

---

### Playbook 14: DNS Configuration (`playbooks/configuration/dns_configuration.yml`)

**What it does:** Installs BIND9 DNS server with forward/reverse zones, forwarders, and A/CNAME/MX record support.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `domain_name` | `example.com` | Domain name |
| `dns_forwarders` | Google DNS | Upstream forwarders |
| `zone_records` | sample A record | DNS zone records |

**Usage Examples:**
```bash
# Set up DNS server
ansible-playbook playbooks/configuration/dns_configuration.yml \
  -i inventory/hosts --limit dns_servers \
  -e "domain_name=mycompany.internal"
```

---

### Playbook 15: Log Rotation (`playbooks/configuration/log_rotation.yml`)

**What it does:** Configures logrotate for application logs with customizable rotation frequency, retention, and compression.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `myapp` | Application name |
| `log_path` | `/var/log/{app}/*.log` | Log file pattern |
| `rotate_count` | `14` | Rotations to keep |
| `rotate_frequency` | `daily` | Rotation frequency |
| `max_size` | `100M` | Max file size |
| `post_rotate_command` | *(empty)* | Post-rotate command |

**Usage Examples:**
```bash
# Configure log rotation for an app
ansible-playbook playbooks/configuration/log_rotation.yml \
  -i inventory/hosts \
  -e "app_name=mywebapp log_path='/var/log/mywebapp/*.log' rotate_count=30"

# With post-rotate restart
ansible-playbook playbooks/configuration/log_rotation.yml \
  -i inventory/hosts \
  -e "app_name=nginx log_path='/var/log/nginx/*.log' post_rotate_command='systemctl reload nginx'"
```

---

### Playbook 16: SSL Certificate (`playbooks/configuration/ssl_certificate.yml`)

**What it does:** Obtains SSL/TLS certificates from Let's Encrypt using Certbot, configures auto-renewal, and optionally generates DH parameters.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `domain_name` | `example.com` | Primary domain |
| `certbot_email` | `admin@{domain}` | Email for Let's Encrypt |
| `certbot_plugin` | `nginx` | Plugin: `nginx`, `standalone`, `webroot` |
| `certbot_staging` | `false` | Use staging server for testing |
| `ssl_generate_dhparam` | `true` | Generate DH params |

**Usage Examples:**
```bash
# Get SSL certificate for a domain
ansible-playbook playbooks/configuration/ssl_certificate.yml \
  -i inventory/hosts --limit webservers \
  -e "domain_name=mysite.com certbot_email=admin@mysite.com"

# Test with staging server first
ansible-playbook playbooks/configuration/ssl_certificate.yml \
  -i inventory/hosts --limit webservers \
  -e "domain_name=mysite.com certbot_staging=true"

# Standalone mode (no web server needed)
ansible-playbook playbooks/configuration/ssl_certificate.yml \
  -i inventory/hosts \
  -e "domain_name=api.mysite.com certbot_plugin=standalone"
```

---

### Playbook 17: Monitoring Setup (`playbooks/configuration/monitoring_setup.yml`)

**What it does:** Installs Prometheus Node Exporter v1.8.2 for system metrics (CPU, memory, disk, network). Creates system user and systemd service.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `node_exporter_version` | `1.8.2` | Version to install |
| `node_exporter_port` | `9100` | Metrics port |
| `node_exporter_listen_address` | `0.0.0.0` | Listen address |
| `node_exporter_enabled_collectors` | systemd, cpu, mem, disk, net | Enabled collectors |

**Usage Examples:**
```bash
# Install Node Exporter on all servers
ansible-playbook playbooks/configuration/monitoring_setup.yml -i inventory/hosts

# Custom port and collectors
ansible-playbook playbooks/configuration/monitoring_setup.yml -i inventory/hosts \
  -e "node_exporter_port=9200"
```

---

### Playbook 18: Backup Configuration (`playbooks/configuration/backup_configuration.yml`)

**What it does:** Creates automated backup scripts with systemd timer scheduling, optional S3 upload, and configurable retention.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `backup_dirs` | `/var/www`, `/etc/nginx`, `/opt/app` | Directories to backup |
| `backup_dest` | `/var/backups/automated` | Local backup destination |
| `retention_days` | `30` | Days to keep backups |
| `s3_bucket` | *(empty)* | S3 bucket for offsite backup |
| `backup_schedule` | `0 2 * * *` | Cron schedule (daily 2am) |

**Usage Examples:**
```bash
# Local backups only
ansible-playbook playbooks/configuration/backup_configuration.yml \
  -i inventory/hosts \
  -e '{"backup_dirs":["/var/www","/etc/nginx","/opt/myapp"]}'

# With S3 offsite backup
ansible-playbook playbooks/configuration/backup_configuration.yml \
  -i inventory/hosts \
  -e "s3_bucket=my-backup-bucket retention_days=60"
```

---

### Playbook 19: Ansible Vault CI/CD (`playbooks/configuration/ansible_vault_cicd.yml`)

**What it does:** Demonstrates Ansible Vault integration with CI/CD pipelines. Deploys encrypted secrets, creates rotation scripts, and shows GitHub Actions/Jenkins/GitLab CI examples.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `myapp` | Application name |
| `vault_db_password` | *(vault-encrypted)* | Database password |
| `vault_api_key` | *(vault-encrypted)* | API key |
| `vault_secret_key` | *(vault-encrypted)* | Application secret key |
| `deploy_env` | from `$DEPLOY_ENV` | Deployment environment |

**Usage Examples:**
```bash
# Encrypt your secrets first
ansible-vault encrypt vars/secrets.yml

# Deploy with vault password file
ansible-playbook playbooks/configuration/ansible_vault_cicd.yml \
  -i inventory/hosts \
  --vault-password-file vault_pass.txt \
  -e @vars/secrets.yml

# Deploy with vault password prompt
ansible-playbook playbooks/configuration/ansible_vault_cicd.yml \
  -i inventory/hosts \
  --ask-vault-pass \
  -e @vars/secrets.yml
```

---

## Deployment Playbooks

These playbooks deploy applications to target servers. Each one installs runtime dependencies, deploys application code, configures systemd services, and sets up Nginx reverse proxy.

---

### Playbook 20: Node.js Deployment (`playbooks/deployment/nodejs_deployment.yml`)

**What it does:** Installs Node.js 20.x, clones git repo, runs `npm ci`, creates systemd service, and configures Nginx reverse proxy.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `myapp` | Application name |
| `app_port` | `3000` | Application port |
| `git_repo` | *(required)* | Git repository URL |
| `git_branch` | `main` | Branch to deploy |
| `node_env` | `production` | Node environment |
| `app_entry_point` | `app.js` | Main JS file |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/nodejs_deployment.yml \
  -i inventory/hosts --limit appservers \
  -e "app_name=myapi git_repo=https://github.com/user/myapi.git app_port=3000"
```

---

### Playbook 21: Flask Deployment (`playbooks/deployment/flask_deployment.yml`)

**What it does:** Installs Python 3, creates virtualenv, deploys Flask app with Gunicorn and Nginx reverse proxy.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `flaskapp` | Application name |
| `app_port` | `5000` | Application port |
| `git_repo` | *(required)* | Git repository URL |
| `gunicorn_workers` | `4` | Gunicorn worker count |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/flask_deployment.yml \
  -i inventory/hosts --limit appservers \
  -e "app_name=myflaskapi git_repo=https://github.com/user/flask-api.git gunicorn_workers=8"
```

---

### Playbook 22: Django Deployment (`playbooks/deployment/django_deployment.yml`)

**What it does:** Deploys Django with Gunicorn, runs collectstatic and migrations, configures Nginx with static/media file serving.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `djangoapp` | Application name |
| `app_port` | `8000` | Application port |
| `git_repo` | *(required)* | Git repository URL |
| `db_host` | `localhost` | Database host |
| `db_name` | `{app_name}` | Database name |
| `django_settings_module` | `{app}.settings` | Settings module |
| `allowed_hosts` | `*` | Django ALLOWED_HOSTS |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/django_deployment.yml \
  -i inventory/hosts --limit appservers \
  -e "app_name=mydjango git_repo=https://github.com/user/django-app.git db_host=10.0.3.10 db_name=djangodb"
```

---

### Playbook 23: Rails Deployment (`playbooks/deployment/rails_deployment.yml`)

**What it does:** Installs Ruby, Bundler, Node.js. Deploys Rails app with Puma server, precompiles assets, configures Nginx.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `railsapp` | Application name |
| `git_repo` | *(required)* | Git repository URL |
| `rails_env` | `production` | Rails environment |
| `puma_workers` | `2` | Puma workers |
| `puma_port` | `3000` | Puma bind port |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/rails_deployment.yml \
  -i inventory/hosts --limit appservers \
  -e "app_name=myrails git_repo=https://github.com/user/rails-app.git"
```

---

### Playbook 24: Spring Boot Deployment (`playbooks/deployment/springboot_deployment.yml`)

**What it does:** Installs Java 17, deploys JAR file, creates systemd service with JVM options, configures Nginx reverse proxy.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `springapp` | Application name |
| `app_port` | `8080` | Application port |
| `jar_source` | *(required)* | Path/URL to JAR file |
| `java_opts` | `-Xmx512m -Xms256m` | JVM options |
| `spring_profiles_active` | `production` | Active Spring profiles |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/springboot_deployment.yml \
  -i inventory/hosts --limit appservers \
  -e "app_name=orderservice jar_source=/tmp/orderservice-1.0.jar java_opts='-Xmx1g -Xms512m'"
```

---

### Playbook 25: Go Deployment (`playbooks/deployment/go_deployment.yml`)

**What it does:** Deploys pre-built Go binary, creates systemd service with environment variables, configures Nginx reverse proxy.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `goapp` | Application name |
| `app_port` | `8080` | Application port |
| `binary_source` | *(required)* | Path to Go binary |
| `app_env` | `{}` | Environment variables dict |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/go_deployment.yml \
  -i inventory/hosts --limit appservers \
  -e "app_name=mygoapi binary_source=/tmp/mygoapi app_port=8080"
```

---

### Playbook 26: .NET Deployment (`playbooks/deployment/dotnet_deployment.yml`)

**What it does:** Installs .NET 8.0 runtime, deploys published application, creates systemd service, configures Nginx reverse proxy.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `dotnetapp` | Application name |
| `app_port` | `5000` | Application port |
| `app_dll` | `{app_name}.dll` | Entry point DLL |
| `app_source` | *(required)* | Path to published files |
| `dotnet_environment` | `Production` | .NET environment |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/dotnet_deployment.yml \
  -i inventory/hosts --limit appservers \
  -e "app_name=mywebapi app_dll=MyWebApi.dll app_source=/tmp/publish/"
```

---

### Playbook 27: React Deployment (`playbooks/deployment/react_deployment.yml`)

**What it does:** Installs Node.js, builds React app, deploys static files to Nginx with SPA routing and optional API proxy.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `reactapp` | Application name |
| `git_repo` | *(required)* | Git repository URL |
| `server_name` | `_` | Nginx server name |
| `api_proxy_url` | *(optional)* | Backend API URL for `/api/` proxy |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/react_deployment.yml \
  -i inventory/hosts --limit webservers \
  -e "app_name=myreactui git_repo=https://github.com/user/react-ui.git server_name=app.mysite.com api_proxy_url=http://10.0.2.10:8080"
```

---

### Playbook 28: Vue.js Deployment (`playbooks/deployment/vuejs_deployment.yml`)

**What it does:** Identical pattern to React — builds Vue.js app, deploys to Nginx with SPA routing.

**Key Variables:** Same as React deployment.

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/vuejs_deployment.yml \
  -i inventory/hosts --limit webservers \
  -e "app_name=myvueapp git_repo=https://github.com/user/vue-app.git"
```

---

### Playbook 29: Laravel Deployment (`playbooks/deployment/laravel_deployment.yml`)

**What it does:** Installs PHP 8.2 with extensions, Composer, Nginx. Clones Laravel app, configures `.env`, runs migrations, sets permissions.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `laravelapp` | Application name |
| `git_repo` | *(required)* | Git repository URL |
| `db_host` | `localhost` | Database host |
| `db_name` | `{app_name}` | Database name |
| `db_user` | `{app_name}` | Database user |
| `db_password` | *(required)* | Database password |
| `app_key` | *(auto-generated)* | Laravel app key |
| `php_version` | `8.2` | PHP version |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/laravel_deployment.yml \
  -i inventory/hosts --limit webservers \
  -e "app_name=myblog git_repo=https://github.com/user/laravel-blog.git db_host=10.0.3.10 db_name=blog db_user=blog_user db_password='DbPass!'"
```

---

### Playbook 30: PHP Deployment (`playbooks/deployment/php_deployment.yml`)

**What it does:** Deploys generic PHP application with PHP-FPM and Nginx.

**Key Variables:** Similar to Laravel but without framework-specific steps (no artisan, no migrations).

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/php_deployment.yml \
  -i inventory/hosts --limit webservers \
  -e "app_name=myphpapp git_repo=https://github.com/user/php-app.git"
```

---

### Playbook 31: Magento Deployment (`playbooks/deployment/magento_deployment.yml`)

**What it does:** Deploys Magento 2 with PHP 8.2, required extensions (intl, soap, xsl, bcmath, gd), Composer, Nginx with Magento-specific config.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `magento` | Application name |
| `magento_version` | `2.4` | Magento version |
| `domain` | *(required)* | Store domain |
| `db_host` | `localhost` | Database host |
| `elasticsearch_host` | `localhost` | Elasticsearch host |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/magento_deployment.yml \
  -i inventory/hosts --limit webservers \
  -e "domain=store.mysite.com db_host=10.0.3.10 db_name=magento"
```

---

### Playbook 32: Phoenix (Elixir) Deployment (`playbooks/deployment/phoenix_deployment.yml`)

**What it does:** Installs Erlang and Elixir, builds Phoenix release, creates systemd service.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `phoenixapp` | Application name |
| `app_port` | `4000` | Application port |
| `git_repo` | *(required)* | Git repository URL |
| `secret_key_base` | *(required)* | Phoenix secret key |
| `database_url` | *(required)* | Database connection URL |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/phoenix_deployment.yml \
  -i inventory/hosts --limit appservers \
  -e "app_name=myphoenix git_repo=https://github.com/user/phoenix-app.git secret_key_base='long-random-string' database_url='ecto://user:pass@db:5432/mydb'"
```

---

### Playbook 33: Meteor.js Deployment (`playbooks/deployment/meteorjs_deployment.yml`)

**What it does:** Deploys Meteor.js bundle with Node.js, configures MongoDB connection, creates systemd service.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `meteorapp` | Application name |
| `app_port` | `3000` | Application port |
| `mongo_url` | *(required)* | MongoDB connection URL |
| `root_url` | `http://localhost:3000` | Meteor ROOT_URL |
| `bundle_source` | *(required)* | Path to Meteor bundle |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/meteorjs_deployment.yml \
  -i inventory/hosts --limit appservers \
  -e "app_name=mymeteor bundle_source=/tmp/mymeteor.tar.gz mongo_url='mongodb://10.0.3.10:27017/mymeteor' root_url='https://app.mysite.com'"
```

---

### Playbook 34: Rust Rocket Deployment (`playbooks/deployment/rust_rocket_deployment.yml`)

**What it does:** Deploys pre-built Rust Rocket binary, creates systemd service with Rocket environment variables.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `rocketapp` | Application name |
| `app_port` | `8000` | Application port |
| `binary_source` | *(required)* | Path to Rust binary |
| `rocket_env` | `release` | Rocket profile |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/rust_rocket_deployment.yml \
  -i inventory/hosts --limit appservers \
  -e "app_name=myrustapi binary_source=/tmp/myrustapi app_port=8000"
```

---

### Playbook 35: Scala Play Deployment (`playbooks/deployment/scala_play_deployment.yml`)

**What it does:** Installs Java 17, deploys Play Framework distribution, creates systemd service with JVM options.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `playapp` | Application name |
| `app_port` | `9000` | Application port |
| `dist_source` | *(required)* | Path to dist zip/tgz |
| `play_secret` | *(required)* | Play application secret |
| `java_opts` | `-Xmx512m -Xms256m` | JVM options |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/scala_play_deployment.yml \
  -i inventory/hosts --limit appservers \
  -e "app_name=myplayapp dist_source=/tmp/myplayapp-1.0.zip play_secret='long-random-secret'"
```

---

### Playbook 36: ASP.NET Core Deployment (`playbooks/deployment/aspnet_deployment.yml`)

**What it does:** Installs .NET 8.0 runtime, deploys published ASP.NET Core app, creates systemd service, configures Nginx reverse proxy with proper headers.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `aspnetapp` | Application name |
| `app_port` | `5000` | Application port |
| `app_dll` | `{app_name}.dll` | Entry point DLL |
| `environment` | `Production` | ASPNETCORE_ENVIRONMENT |
| `app_source` | *(required)* | Path to published files |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/aspnet_deployment.yml \
  -i inventory/hosts --limit appservers \
  -e "app_name=myaspnet app_dll=MyWebApp.dll app_source=/tmp/publish/ environment=Production"
```

---

### Playbook 37: GraphQL Apollo Deployment (`playbooks/deployment/graphql_apollo_deployment.yml`)

**What it does:** Deploys Apollo GraphQL Server with Node.js, WebSocket support for subscriptions, Nginx reverse proxy.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `apollo-graphql` | Application name |
| `app_port` | `4000` | Application port |
| `git_repo` | *(required)* | Git repository URL |
| `cors_origin` | `*` | CORS origin |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/graphql_apollo_deployment.yml \
  -i inventory/hosts --limit appservers \
  -e "app_name=mygraphql git_repo=https://github.com/user/graphql-api.git cors_origin='https://mysite.com'"
```

---

### Playbook 38: Kubernetes Dashboard (`playbooks/deployment/kubernetes_dashboard.yml`)

**What it does:** Deploys Kubernetes Dashboard, creates admin service account with cluster-admin role, generates bearer token for login.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `k8s_dashboard_version` | `v2.7.0` | Dashboard version |
| `namespace` | `kubernetes-dashboard` | K8s namespace |
| `admin_user` | `dashboard-admin` | Admin SA name |
| `kubeconfig` | `/etc/kubernetes/admin.conf` | Kubeconfig path |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/kubernetes_dashboard.yml \
  -i inventory/hosts --limit k8s_masters

# Custom kubeconfig
ansible-playbook playbooks/deployment/kubernetes_dashboard.yml \
  -i inventory/hosts --limit k8s_masters \
  -e "kubeconfig=/home/ubuntu/.kube/config"
```

---

### Playbook 39: Docker Compose Deployment (`playbooks/deployment/docker_compose_deployment.yml`)

**What it does:** Installs Docker (if needed), deploys docker-compose.yml from template, pulls images, starts services.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `myapp` | Application name |
| `app_dir` | `/opt/{app_name}` | App directory |
| `compose_services` | sample web + app | Service definitions |
| `compose_env_vars` | `{}` | Environment variables |
| `docker_registry` | *(empty)* | Private registry URL |
| `image_tag` | `latest` | Image tag to deploy |

**Usage Examples:**
```bash
# Deploy with default services
ansible-playbook playbooks/deployment/docker_compose_deployment.yml \
  -i inventory/hosts --limit appservers

# Custom services
ansible-playbook playbooks/deployment/docker_compose_deployment.yml \
  -i inventory/hosts --limit appservers \
  -e '{"app_name":"mystack","compose_services":[{"name":"api","image":"myregistry/api:v2","ports":["8080:8080"]},{"name":"worker","image":"myregistry/worker:v2"}],"compose_env_vars":{"DB_HOST":"10.0.3.10","REDIS_URL":"redis://10.0.3.11:6379"}}'
```

---

### Playbook 40: WordPress Deployment (`playbooks/deployment/wordpress_deployment.yml`)

**What it does:** Installs PHP 8.2, MySQL, Nginx. Downloads WordPress via WP-CLI, configures database, sets permissions, deploys Nginx config.

**Key Variables:**
| Variable | Default | Description |
|----------|---------|-------------|
| `app_name` | `wordpress` | Application name |
| `server_name` | hostname | Nginx server name |
| `db_host` | `localhost` | Database host |
| `db_name` | `wordpress` | Database name |
| `db_user` | `wp_user` | Database user |
| `db_password` | *(change this)* | Database password |
| `wp_admin_user` | `admin` | WP admin username |
| `wp_admin_password` | *(change this)* | WP admin password |
| `wp_admin_email` | `admin@example.com` | Admin email |

**Usage Examples:**
```bash
ansible-playbook playbooks/deployment/wordpress_deployment.yml \
  -i inventory/hosts --limit webservers \
  -e "server_name=blog.mysite.com db_password='WpDb@Pass!' wp_admin_password='AdminP@ss!' wp_admin_email=me@mysite.com"
```

---

## Recommended Workflows

### Full Stack Web Application
```bash
# 1. Create infrastructure
ansible-playbook playbooks/infrastructure/vpc_setup.yml
ansible-playbook playbooks/infrastructure/ec2_provisioning.yml -e "..."
ansible-playbook playbooks/infrastructure/rds_setup.yml -e "..."

# 2. Configure servers
ansible-playbook playbooks/configuration/ufw_firewall.yml -i inventory/hosts
ansible-playbook playbooks/configuration/docker_installation.yml -i inventory/hosts --limit appservers
ansible-playbook playbooks/configuration/monitoring_setup.yml -i inventory/hosts
ansible-playbook playbooks/configuration/log_rotation.yml -i inventory/hosts
ansible-playbook playbooks/configuration/backup_configuration.yml -i inventory/hosts

# 3. Deploy application
ansible-playbook playbooks/deployment/react_deployment.yml -i inventory/hosts --limit webservers -e "..."
ansible-playbook playbooks/deployment/nodejs_deployment.yml -i inventory/hosts --limit appservers -e "..."

# 4. SSL certificate
ansible-playbook playbooks/configuration/ssl_certificate.yml -i inventory/hosts --limit webservers -e "..."
```

### CI/CD Pipeline Integration (GitHub Actions)
```yaml
# .github/workflows/deploy.yml
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install Ansible
        run: pip3 install ansible boto3
      - name: Deploy
        env:
          ANSIBLE_VAULT_PASSWORD: ${{ secrets.ANSIBLE_VAULT_PASSWORD }}
        run: |
          echo "$ANSIBLE_VAULT_PASSWORD" > vault_pass.txt
          ansible-playbook playbooks/deployment/nodejs_deployment.yml \
            -i inventory/hosts \
            --vault-password-file vault_pass.txt \
            -e "git_branch=${{ github.sha }}"
          rm vault_pass.txt
```

---

## Troubleshooting

### Common Issues

| Problem | Solution |
|---------|----------|
| `Permission denied` | Ensure `become: true` and user has sudo rights |
| `Host unreachable` | Check SSH key, security groups, and inventory host IPs |
| `Module not found` | Install required collection: `ansible-galaxy collection install <name>` |
| `Variable undefined` | Pass required vars with `-e` or create a vars file |
| `apt lock` | Another process is using apt — wait or kill the lock |

### Dry Run (Check Mode)
Always test with `--check` before applying changes:
```bash
ansible-playbook playbooks/configuration/ufw_firewall.yml --check --diff -i inventory/hosts
```

### Verbose Output
For debugging, increase verbosity:
```bash
ansible-playbook playbooks/deployment/nodejs_deployment.yml -vvv -i inventory/hosts -e "..."
```

### Using Tags
Run only specific parts of a playbook:
```bash
# List available tags
ansible-playbook playbooks/infrastructure/ec2_provisioning.yml --list-tags

# Run only the provision step
ansible-playbook playbooks/infrastructure/ec2_provisioning.yml --tags provision -e "..."

# Skip verification
ansible-playbook playbooks/infrastructure/ec2_provisioning.yml --skip-tags verify -e "..."
```

### Variables File (Instead of -e)
For complex deployments, use a variables file:
```yaml
# vars/my_deployment.yml
app_name: mywebapp
app_port: 3000
git_repo: https://github.com/user/repo.git
db_host: 10.0.3.10
db_name: mywebapp
db_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  ...encrypted...
```

```bash
ansible-playbook playbooks/deployment/nodejs_deployment.yml \
  -i inventory/hosts \
  -e @vars/my_deployment.yml \
  --vault-password-file vault_pass.txt
```

---

## Author

**Olisa Arinze**
