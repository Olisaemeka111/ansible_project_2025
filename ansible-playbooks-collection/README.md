# 40 Ansible Playbooks for CI/CD Pipelines

A comprehensive collection of 40 production-ready Ansible playbooks covering infrastructure provisioning, server configuration, and application deployment across multiple frameworks and cloud providers.

Based on "40 Ansible Playbooks You Can't Live Without in Your CI/CD Pipeline"  rewritten with modern Ansible best practices (FQCNs, current package versions, Ubuntu 22.04 LTS).

## Directory Structure

```
ansible-playbooks-collection/
├── playbooks/
│   ├── infrastructure/          # Cloud provisioning & infrastructure
│   │   ├── ec2_provisioning.yml
│   │   ├── gcp_provisioning.yml
│   │   ├── vpc_setup.yml
│   │   ├── azure_provisioning.yml
│   │   ├── rds_setup.yml
│   │   ├── jenkins_slave_setup.yml
│   │   └── load_balancer_setup.yml
│   ├── configuration/           # Server & service configuration
│   │   ├── nginx_configuration.yml
│   │   ├── docker_installation.yml
│   │   ├── openvpn_setup.yml
│   │   ├── redis_configuration.yml
│   │   ├── mysql_setup.yml
│   │   ├── ufw_firewall.yml
│   │   ├── dns_configuration.yml
│   │   ├── log_rotation.yml
│   │   ├── ssl_certificate.yml
│   │   ├── monitoring_setup.yml
│   │   ├── backup_configuration.yml
│   │   └── ansible_vault_cicd.yml
│   └── deployment/              # Application deployment
│       ├── nodejs_deployment.yml
│       ├── flask_deployment.yml
│       ├── django_deployment.yml
│       ├── rails_deployment.yml
│       ├── springboot_deployment.yml
│       ├── go_deployment.yml
│       ├── dotnet_deployment.yml
│       ├── react_deployment.yml
│       ├── vuejs_deployment.yml
│       ├── laravel_deployment.yml
│       ├── php_deployment.yml
│       ├── magento_deployment.yml
│       ├── phoenix_deployment.yml
│       ├── meteorjs_deployment.yml
│       ├── rust_rocket_deployment.yml
│       ├── scala_play_deployment.yml
│       ├── aspnet_deployment.yml
│       ├── graphql_apollo_deployment.yml
│       ├── kubernetes_dashboard.yml
│       ├── docker_compose_deployment.yml
│       └── wordpress_deployment.yml
└── templates/                   # Jinja2 templates
    ├── nginx.conf.j2
    ├── nginx_lb.conf.j2
    ├── nginx_static.conf.j2
    ├── react_nginx.conf.j2
    ├── vue_nginx.conf.j2
    ├── django_nginx.conf.j2
    ├── laravel_nginx.conf.j2
    ├── aspnet_nginx.conf.j2
    ├── magento.conf.j2
    ├── named.conf.j2
    ├── redis.conf.j2
    ├── server.conf.j2           # OpenVPN
    ├── php_app.conf.j2
    ├── logrotate.conf.j2
    ├── docker-compose.yml.j2
    ├── nodejs.service.j2
    ├── flask.service.j2
    ├── gunicorn.service.j2
    ├── puma.service.j2
    ├── springboot.service.j2
    ├── go_app.service.j2
    ├── dotnet_app.service.j2
    ├── phoenix.service.j2
    ├── meteor.service.j2
    ├── rust_rocket.service.j2
    ├── scala_play.service.j2
    ├── aspnet.service.j2
    ├── apollo.service.j2
    └── jenkins_slave.service.j2
```

## Playbook Index

| # | Playbook | Category | Description |
|---|----------|----------|-------------|
| 1 | ec2_provisioning | Infrastructure | Provision AWS EC2 instances |
| 2 | nginx_configuration | Configuration | Install and configure Nginx web server |
| 3 | gcp_provisioning | Infrastructure | Provision Google Cloud Compute instances |
| 4 | vpc_setup | Infrastructure | Create AWS VPC with full networking |
| 5 | docker_installation | Configuration | Install Docker CE on Ubuntu |
| 6 | azure_provisioning | Infrastructure | Provision Azure Virtual Machines |
| 7 | openvpn_setup | Configuration | Install and configure OpenVPN server |
| 8 | rds_setup | Infrastructure | Create AWS RDS database instance |
| 9 | jenkins_slave_setup | Infrastructure | Set up Jenkins agent nodes |
| 10 | load_balancer_setup | Infrastructure | Configure Nginx as load balancer |
| 11 | redis_configuration | Configuration | Install and configure Redis |
| 12 | mysql_setup | Configuration | Install and configure MySQL 8.0 |
| 13 | ufw_firewall | Configuration | Configure UFW firewall rules |
| 14 | dns_configuration | Configuration | Install and configure BIND9 DNS |
| 15 | nodejs_deployment | Deployment | Deploy Node.js application |
| 16 | log_rotation | Configuration | Configure logrotate for applications |
| 17 | ssl_certificate | Configuration | SSL/TLS with Let's Encrypt |
| 18 | monitoring_setup | Configuration | Install Prometheus Node Exporter |
| 19 | flask_deployment | Deployment | Deploy Flask with Gunicorn |
| 20 | backup_configuration | Configuration | Configure automated backups |
| 21 | django_deployment | Deployment | Deploy Django with Gunicorn + Nginx |
| 22 | rails_deployment | Deployment | Deploy Ruby on Rails with Puma |
| 23 | springboot_deployment | Deployment | Deploy Spring Boot JAR application |
| 24 | go_deployment | Deployment | Deploy Go binary application |
| 25 | dotnet_deployment | Deployment | Deploy .NET 8.0 application |
| 26 | react_deployment | Deployment | Deploy React SPA with Nginx |
| 27 | vuejs_deployment | Deployment | Deploy Vue.js SPA with Nginx |
| 28 | laravel_deployment | Deployment | Deploy Laravel PHP application |
| 29 | php_deployment | Deployment | Deploy generic PHP with PHP-FPM |
| 30 | magento_deployment | Deployment | Deploy Magento 2 e-commerce |
| 31 | phoenix_deployment | Deployment | Deploy Elixir Phoenix application |
| 32 | meteorjs_deployment | Deployment | Deploy Meteor.js application |
| 33 | rust_rocket_deployment | Deployment | Deploy Rust Rocket application |
| 34 | scala_play_deployment | Deployment | Deploy Scala Play Framework |
| 35 | aspnet_deployment | Deployment | Deploy ASP.NET Core application |
| 36 | graphql_apollo_deployment | Deployment | Deploy GraphQL Apollo Server |
| 37 | kubernetes_dashboard | Deployment | Deploy Kubernetes Dashboard |
| 38 | docker_compose_deployment | Deployment | Deploy with Docker Compose |
| 39 | wordpress_deployment | Deployment | Deploy WordPress with Nginx |
| 40 | ansible_vault_cicd | Configuration | Ansible Vault CI/CD integration |

## Prerequisites

### Ansible Collections

```bash
ansible-galaxy collection install amazon.aws
ansible-galaxy collection install google.cloud
ansible-galaxy collection install azure.azcollection
ansible-galaxy collection install community.mysql
ansible-galaxy collection install community.docker
ansible-galaxy collection install community.general
```

### Target OS
- Ubuntu 22.04 LTS (all playbooks target Debian/Ubuntu)

## Usage

### Run a single playbook
```bash
ansible-playbook playbooks/configuration/docker_installation.yml -i inventory
```

### Limit to specific hosts
```bash
ansible-playbook playbooks/deployment/nodejs_deployment.yml -i inventory --limit web_servers
```

### Override variables
```bash
ansible-playbook playbooks/deployment/flask_deployment.yml -i inventory \
  -e "app_name=myapi app_port=8000 git_repo=https://github.com/user/repo.git"
```

### Dry run
```bash
ansible-playbook playbooks/configuration/ufw_firewall.yml --check --diff
```

### With Ansible Vault
```bash
ansible-playbook playbooks/configuration/ansible_vault_cicd.yml \
  --vault-password-file vault_pass.txt \
  -e @vars/secrets.yml
```

## Software Versions

| Software | Version |
|----------|---------|
| Node.js | 20.x LTS |
| Java | OpenJDK 17 |
| Python | 3.10+ (Ubuntu 22.04 default) |
| PHP | 8.2 |
| .NET | 8.0 |
| Docker CE | Latest stable |
| MySQL | 8.0 |
| Redis | Latest (apt) |
| Nginx | Latest (apt) |
| Prometheus Node Exporter | 1.8.2 |

## Author

**Olisa Arinze**
