# Cold Email Infrastructure - Installation Guide

## Overview

This guide provides step-by-step instructions for installing the complete cold email infrastructure system. The system includes DNS automation, mail server deployment, monitoring, and VPS configuration.

## Prerequisites

### System Requirements
- **Operating System**: Ubuntu 22.04 LTS or Debian 12+ (recommended)
- **Memory**: Minimum 8GB RAM (16GB recommended for production)
- **Storage**: Minimum 100GB SSD (500GB recommended for production)
- **CPU**: Minimum 4 cores (8 cores recommended for production)
- **Network**: Public IPv4 address with reverse DNS configured

### Required Accounts & Access
- **Cloudflare Account**: With API token and domain(s) using Cloudflare nameservers
- **Domain**: At least one domain with nameservers pointed to Cloudflare
- **Email Account**: For SSL certificates and administrative notifications
- **SSH Access**: Root or sudo access to the target server

### Required Software
- **Docker**: Version 20.10+
- **Docker Compose**: Version 2.0+
- **Python**: Version 3.8+
- **Git**: For cloning the repository
- **Curl**: For API testing

## Installation Methods

### Method 1: One-Command Installation (Recommended)

For most users, the one-command installation is the fastest and most reliable method:

```bash
# Download and run the complete installation
curl -fsSL https://raw.githubusercontent.com/your-repo/cold-email-infrastructure/main/scripts/install/quick-install.sh | bash -s -- \
  --domain mail.yourdomain.com \
  --ip your.server.ip \
  --email admin@yourdomain.com \
  --token your_cloudflare_api_token
```

### Method 2: Step-by-Step Installation

For advanced users who want full control over the installation process:

#### Step 1: Environment Setup

```bash
# Clone the repository
git clone https://github.com/your-repo/cold-email-infrastructure.git
cd cold-email-infrastructure

# Set up environment variables
source scripts/utilities/setup-environment.sh

# Verify environment setup
./scripts/utilities/validate-setup.sh --check-prerequisites
```

#### Step 2: System Dependencies

```bash
# Install system dependencies
./scripts/install/install-dependencies.sh

# Install Docker and Docker Compose
./scripts/install/install-docker.sh

# Install Python dependencies
./scripts/install/install-python.sh
```

#### Step 3: Configuration

```bash
# Copy configuration templates
cp config/environments/production.yaml.template config/environments/production.yaml

# Set environment variables
export CLOUDFLARE_API_TOKEN="your_cloudflare_api_token"
export EMAIL_INFRA_ENV="production"
export MAILCOW_HOSTNAME="mail.yourdomain.com"

# Configure the system
./scripts/install/configure-system.sh
```

#### Step 4: Component Installation

```bash
# Install VPS hardening and basic setup
./src/email-infrastructure/vps/scripts/setup-vps.sh --ip your.server.ip

# Set up DNS records
./src/email-infrastructure/dns/scripts/record-generator.sh \
  -d yourdomain.com -i your.server.ip --deploy

# Install Mailcow
./src/email-infrastructure/mailcow/automation/install-mailcow.sh \
  yourdomain.com admin@yourdomain.com

# Set up monitoring
./src/email-infrastructure/monitoring/scripts/setup-monitoring.sh
```

#### Step 5: Validation

```bash
# Validate complete installation
./scripts/utilities/validate-setup.sh yourdomain.com your.server.ip

# Test all components
./scripts/utilities/test-components.sh
```

## Component-Specific Installation

### DNS System Installation

```bash
# Install DNS management components
cd src/email-infrastructure/dns
pip install -r requirements-dns.txt

# Configure Cloudflare
cp config/cloudflare-config.yaml.template config/cloudflare-config.yaml
# Edit the configuration file with your API token

# Test DNS connectivity
python3 -c "
from managers.dns_manager import DNSManager
dns = DNSManager('config/cloudflare-config.yaml')
print('DNS Manager:', 'OK' if dns.test_connection() else 'FAILED')
"
```

### Mailcow Installation

```bash
# Install Mailcow dependencies
sudo apt update
sudo apt install -y curl docker.io docker-compose-plugin

# Run Mailcow installation
cd src/email-infrastructure/mailcow
sudo ./automation/install-mailcow.sh mail.yourdomain.com admin@yourdomain.com

# Configure API access
sudo ./automation/setup-api.sh setup
sudo ./automation/setup-api.sh configure
```

### VPS Setup

```bash
# Run VPS hardening script
cd src/email-infrastructure/vps
sudo ./scripts/setup-vps.sh --ip your.server.ip --secure

# Configure firewall
sudo ./scripts/configure-firewall.sh --mailcow --monitoring

# Set up monitoring
./scripts/setup-monitoring.sh --ip your.server.ip
```

### Monitoring System

```bash
# Install monitoring components
cd src/email-infrastructure/monitoring
pip install -r requirements-monitoring.txt

# Configure monitoring
cp config/monitoring-config.yaml.template config/monitoring-config.yaml
# Edit configuration file

# Start monitoring services
./scripts/start-monitoring.sh --daemon
```

## Configuration Details

### Environment Variables

Create a `.env` file or export these variables:

```bash
# Core Configuration
EMAIL_INFRA_ENV=production
EMAIL_INFRA_ROOT=/path/to/cold-email-infrastructure
CLOUDFLARE_API_TOKEN=your_cloudflare_api_token

# Mailcow Configuration
MAILCOW_HOSTNAME=mail.yourdomain.com
MAILCOW_API_KEY=generated_during_setup
ADMIN_EMAIL=admin@yourdomain.com
TZ=UTC

# Database Configuration
DBROOT=secure_random_password
DBPASS=secure_random_password

# SSL Configuration
SKIP_LETS_ENCRYPT=n
LE_STAGING=n

# Monitoring Configuration
MONITORING_ENABLED=true
SLACK_WEBHOOK_URL=your_slack_webhook_url

# Security Configuration
API_RATE_LIMIT=100
SESSION_TIMEOUT=1800
REQUIRE_2FA=false
```

### DNS Configuration

Ensure your domain is configured properly in Cloudflare:

1. **Add Domain to Cloudflare**: Add your domain and update nameservers
2. **DNS Records**: The system will create these automatically:
   - A record: `yourdomain.com` → `your.server.ip`
   - A record: `mail.yourdomain.com` → `your.server.ip`
   - MX record: `yourdomain.com` → `mail.yourdomain.com`
   - TXT records: SPF, DKIM, DMARC

3. **Verify DNS Propagation**:
   ```bash
   ./src/email-infrastructure/dns/monitors/dns_verifier.py \
     comprehensive --domain yourdomain.com --ip your.server.ip
   ```

## Post-Installation Setup

### 1. Domain and Mailbox Setup

```bash
# Add your domain to Mailcow
./src/email-infrastructure/mailcow/automation/domain-manager.sh \
  add yourdomain.com "Your Domain" 5120 25 500

# Create admin mailbox
./src/email-infrastructure/mailcow/automation/mailbox-manager.sh \
  create admin@yourdomain.com "" "Administrator" 4096

# Generate DKIM keys
./src/email-infrastructure/mailcow/automation/dkim-manager.sh \
  generate yourdomain.com
```

### 2. SSL Certificate Setup

```bash
# Set up Let's Encrypt (production)
./src/email-infrastructure/mailcow/automation/ssl-manager.sh \
  setup-letsencrypt mail.yourdomain.com admin@yourdomain.com

# Verify SSL certificate
./src/email-infrastructure/mailcow/automation/ssl-manager.sh \
  verify mail.yourdomain.com
```

### 3. Monitoring Configuration

```bash
# Configure blacklist monitoring
python3 -c "
from email_infrastructure.monitoring.monitors.blacklist_monitor import BlacklistMonitor
monitor = BlacklistMonitor()
monitor.add_ip_monitoring('your.server.ip', 'yourdomain.com')
"

# Start warmup campaigns
python3 -c "
from email_infrastructure.monitoring.campaigns.warmup_campaigns import WarmupCampaigns
campaigns = WarmupCampaigns()
campaigns.start_warmup_campaign('yourdomain.com', ['admin@yourdomain.com'])
"
```

### 4. Backup Configuration

```bash
# Set up automated backups
./src/email-infrastructure/mailcow/backup/backup-manager.sh schedule daily

# Test backup system
./src/email-infrastructure/mailcow/backup/backup-manager.sh create config
```

## Verification and Testing

### 1. System Health Check

```bash
# Run comprehensive health check
./scripts/utilities/validate-setup.sh yourdomain.com your.server.ip --verbose

# Expected output:
# ✅ DNS resolution working
# ✅ Mail server running
# ✅ SSL certificates valid
# ✅ Monitoring active
# ✅ Backup system configured
```

### 2. Component Testing

```bash
# Test DNS management
python3 -c "
from email_infrastructure.dns.monitors.dns_verifier import DNSVerifier
verifier = DNSVerifier()
result = verifier.comprehensive_domain_check('yourdomain.com', 'your.server.ip')
print('DNS Health:', result['overall_status'])
"

# Test Mailcow API
python3 -c "
from email_infrastructure.mailcow.core.api_client import MailcowAPI
api = MailcowAPI()
print('Mailcow API:', 'OK' if api.test_connection() else 'FAILED')
"

# Test monitoring
python3 -c "
from email_infrastructure.monitoring.monitors.blacklist_monitor import BlacklistMonitor
monitor = BlacklistMonitor()
status = monitor.check_ip_blacklist('your.server.ip')
print('Blacklist Status:', status['status'])
"
```

### 3. Email Delivery Test

```bash
# Send test email
./scripts/utilities/send-test-email.sh admin@yourdomain.com "Installation Complete"

# Check email logs
tail -f /opt/mailcow-dockerized/data/logs/postfix/current
```

## Troubleshooting Installation

### Common Issues

1. **DNS Propagation Delays**
   ```bash
   # Check propagation status
   ./src/email-infrastructure/dns/monitors/dns_verifier.py \
     wait-propagation --domain yourdomain.com --type A --expected your.server.ip
   ```

2. **Docker Permission Issues**
   ```bash
   # Add user to docker group
   sudo usermod -aG docker $USER
   newgrp docker
   ```

3. **Firewall Blocking Connections**
   ```bash
   # Check required ports
   sudo ufw status
   
   # Open required ports
   sudo ufw allow 25,465,587,993,995,80,443/tcp
   ```

4. **SSL Certificate Issues**
   ```bash
   # Check certificate status
   ./src/email-infrastructure/mailcow/automation/ssl-manager.sh \
     verify mail.yourdomain.com
   
   # Regenerate if needed
   ./src/email-infrastructure/mailcow/automation/ssl-manager.sh \
     setup-letsencrypt mail.yourdomain.com admin@yourdomain.com --force
   ```

### Log Files

Check these log files for detailed error information:

- Installation: `/var/log/email-infrastructure-install.log`
- DNS: `/var/log/email-infrastructure-dns.log`
- Mailcow: `/var/log/mailcow-install.log`
- Monitoring: `/var/log/email-infrastructure-monitoring.log`
- System: `/var/log/email-infrastructure.log`

### Getting Help

1. **Check Prerequisites**: Ensure all system requirements are met
2. **Review Logs**: Check log files for specific error messages
3. **Verify Configuration**: Ensure all configuration files are correct
4. **Test Components**: Test each component individually
5. **Run Validation**: Use the validation script to identify issues

```bash
# Enable debug logging
export EMAIL_INFRA_LOG_LEVEL=DEBUG

# Run installation with verbose output
./scripts/install/install-all.sh \
  --domain mail.yourdomain.com \
  --ip your.server.ip \
  --verbose \
  --debug
```

## Next Steps

After successful installation:

1. **Security Hardening**: Review the security documentation
2. **Domain Configuration**: Add additional domains as needed
3. **User Management**: Create user mailboxes
4. **Monitoring Setup**: Configure alerts and notifications
5. **Backup Testing**: Verify backup and restore procedures
6. **Performance Tuning**: Optimize for your specific workload

See the [Configuration Guide](configuration-guide.md) for detailed configuration options and the [Operations Guide](../operations/maintenance.md) for ongoing maintenance procedures.