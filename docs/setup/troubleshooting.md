# Cold Email Infrastructure - Troubleshooting Guide

## Overview

This comprehensive troubleshooting guide covers common issues, diagnostic procedures, and solutions for the Cold Email Infrastructure system. Use this guide to quickly identify and resolve problems across all components.

## Quick Diagnostic Commands

### System Health Check

Start with these commands to get an overall system status:

```bash
# Complete system validation
./scripts/utilities/validate-setup.sh yourdomain.com your.server.ip --verbose

# Component-specific health checks
./scripts/utilities/test-components.sh

# Check system logs
tail -f /var/log/email-infrastructure.log

# Check service status
systemctl status docker
systemctl status fail2ban
systemctl status ufw
```

### Log Files Reference

Key log files for troubleshooting:

```bash
# Main system log
/var/log/email-infrastructure.log

# Component logs
/var/log/email-infrastructure-dns.log
/var/log/email-infrastructure-mailcow.log
/var/log/email-infrastructure-monitoring.log
/var/log/email-infrastructure-vps.log

# Installation logs
/var/log/email-infrastructure-install.log

# Mailcow logs
/opt/mailcow-dockerized/data/logs/
```

## Installation Issues

### 1. Installation Script Fails

**Symptoms:**
- Installation script exits with errors
- Missing dependencies
- Permission denied errors

**Diagnostic Steps:**
```bash
# Check system requirements
./scripts/utilities/validate-setup.sh --check-prerequisites

# Verify system architecture
uname -a
lsb_release -a

# Check available disk space
df -h

# Check memory
free -h

# Test internet connectivity
curl -I https://api.cloudflare.com/client/v4
```

**Solutions:**

**Missing Dependencies:**
```bash
# Update package lists
sudo apt update

# Install missing packages
sudo apt install -y curl wget git python3 python3-pip docker.io docker-compose-plugin

# Fix broken packages
sudo apt --fix-broken install
```

**Permission Issues:**
```bash
# Add user to docker group
sudo usermod -aG docker $USER
newgrp docker

# Fix directory permissions
sudo chown -R $USER:$USER /home/stuart/cold-email-infrastructure
chmod +x scripts/install/*.sh
```

**Insufficient Resources:**
```bash
# Check requirements
# Minimum: 8GB RAM, 100GB disk, 4 CPU cores

# Free up disk space
sudo apt autoremove
sudo apt autoclean
docker system prune -a
```

### 2. Environment Setup Problems

**Symptoms:**
- Environment variables not found
- Configuration files not loaded
- Path resolution errors

**Diagnostic Steps:**
```bash
# Check environment setup
source scripts/utilities/setup-environment.sh
env | grep EMAIL_INFRA

# Test configuration loading
python3 -c "
from email_infrastructure.core.config_manager import get_config
config = get_config()
print('Environment:', config['application']['environment'])
"
```

**Solutions:**

**Environment Variables Not Set:**
```bash
# Set required variables
export EMAIL_INFRA_ENV=production
export EMAIL_INFRA_ROOT=/home/stuart/cold-email-infrastructure
export CLOUDFLARE_API_TOKEN="your_token_here"

# Make permanent
echo 'export EMAIL_INFRA_ENV=production' >> ~/.bashrc
echo 'export EMAIL_INFRA_ROOT=/home/stuart/cold-email-infrastructure' >> ~/.bashrc
```

**Configuration File Issues:**
```bash
# Verify configuration files exist
ls -la config/environments/
ls -la config/global-config.yaml

# Validate YAML syntax
python3 -c "
import yaml
with open('config/environments/production.yaml') as f:
    yaml.safe_load(f)
print('Configuration valid')
"

# Fix configuration
cp config/environments/production.yaml.template config/environments/production.yaml
```

## DNS Component Issues

### 1. Cloudflare API Authentication

**Symptoms:**
- "Invalid API token" errors
- HTTP 401 Unauthorized responses
- DNS operations fail

**Diagnostic Steps:**
```bash
# Test Cloudflare API connectivity
curl -X GET "https://api.cloudflare.com/client/v4/user/tokens/verify" \
     -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
     -H "Content-Type: application/json"

# Test with DNS manager
python3 -c "
from email_infrastructure.dns.managers.dns_manager import DNSManager
dns = DNSManager()
print('API Test:', 'OK' if dns.test_connection() else 'FAILED')
"
```

**Solutions:**

**Invalid API Token:**
```bash
# Generate new API token in Cloudflare dashboard
# Required permissions: Zone:Read, DNS:Edit

# Update token
export CLOUDFLARE_API_TOKEN="new_token_here"
echo 'export CLOUDFLARE_API_TOKEN="new_token_here"' >> ~/.bashrc

# Update configuration
sed -i "s/api_token:.*/api_token: \"$CLOUDFLARE_API_TOKEN\"/" config/environments/production.yaml
```

**Token Permissions:**
- Ensure token has Zone:Read and DNS:Edit permissions
- Add specific zones if using zone-level tokens
- Verify token hasn't expired

### 2. DNS Propagation Issues

**Symptoms:**
- DNS records not resolving
- Propagation timeouts
- Inconsistent DNS responses

**Diagnostic Steps:**
```bash
# Check DNS propagation
./src/email-infrastructure/dns/monitors/dns_verifier.py \
  propagation --domain yourdomain.com --type A --expected your.server.ip

# Test specific nameservers
dig @8.8.8.8 yourdomain.com A
dig @1.1.1.1 yourdomain.com A
dig @your.nameserver yourdomain.com A

# Check propagation globally
./src/email-infrastructure/dns/monitors/dns_verifier.py \
  comprehensive --domain yourdomain.com --ip your.server.ip
```

**Solutions:**

**Slow Propagation:**
```bash
# Wait for propagation (can take up to 48 hours)
./src/email-infrastructure/dns/monitors/dns_verifier.py \
  wait-propagation --domain yourdomain.com --type A --expected your.server.ip --timeout 3600

# Check TTL settings (lower TTL = faster propagation)
python3 -c "
from email_infrastructure.dns.managers.dns_manager import DNSManager
dns = DNSManager()
records = dns.list_dns_records('yourdomain.com')
for record in records:
    print(f'{record[\"name\"]}: TTL {record[\"ttl\"]}')
"
```

**Incorrect Records:**
```bash
# Regenerate DNS records
./src/email-infrastructure/dns/scripts/record-generator.sh \
  -d yourdomain.com -i your.server.ip --deploy --force

# Verify records match template
./src/email-infrastructure/dns/monitors/dns_verifier.py \
  check --domain yourdomain.com --type A --expected your.server.ip
```

### 3. DNS Cache Issues

**Symptoms:**
- Stale DNS responses
- Cache hit/miss ratios poor
- Memory usage high

**Diagnostic Steps:**
```bash
# Check cache statistics
python3 -c "
from email_infrastructure.dns.managers.cache_manager import CacheManager
cache = CacheManager()
stats = cache.get_statistics()
print('Cache Stats:', stats)
"

# Monitor cache performance
python3 src/email-infrastructure/dns/managers/cache_manager.py stats --watch
```

**Solutions:**

**Clear Cache:**
```bash
# Clear DNS cache
python3 src/email-infrastructure/dns/managers/cache_manager.py clear

# Restart local DNS resolver
sudo systemctl restart systemd-resolved

# Flush system DNS cache
sudo resolvectl flush-caches
```

**Optimize Cache Settings:**
```yaml
# config/environments/production.yaml
dns:
  cache:
    backend: "redis"  # Use Redis for better performance
    ttl: 600
    max_size: 50000
    cleanup_interval: 300
```

## Mailcow Component Issues

### 1. Mailcow Installation Failures

**Symptoms:**
- Docker containers fail to start
- Database connection errors
- SSL certificate issues

**Diagnostic Steps:**
```bash
# Check Mailcow status
cd /opt/mailcow-dockerized
docker-compose ps

# Check container logs
docker-compose logs postfix-mailcow
docker-compose logs dovecot-mailcow
docker-compose logs nginx-mailcow

# Test Mailcow API
./src/email-infrastructure/mailcow/automation/setup-api.sh test
```

**Solutions:**

**Container Issues:**
```bash
# Restart Mailcow containers
cd /opt/mailcow-dockerized
docker-compose down
docker-compose up -d

# Check for port conflicts
netstat -tulpn | grep :80
netstat -tulpn | grep :443

# Free up conflicting ports
sudo systemctl stop apache2  # if running
sudo systemctl stop nginx    # if running
```

**Database Problems:**
```bash
# Check database connectivity
cd /opt/mailcow-dockerized
docker-compose exec mysql-mailcow mysql -u mailcow -p mailcow

# Reset database password
./src/email-infrastructure/mailcow/automation/db-init.sh reset-password

# Reinitialize database
./src/email-infrastructure/mailcow/automation/db-init.sh init --force
```

**SSL Certificate Issues:**
```bash
# Check certificate status
./src/email-infrastructure/mailcow/automation/ssl-manager.sh verify mail.yourdomain.com

# Regenerate Let's Encrypt certificate
./src/email-infrastructure/mailcow/automation/ssl-manager.sh \
  setup-letsencrypt mail.yourdomain.com admin@yourdomain.com --force

# Use staging certificate for testing
./src/email-infrastructure/mailcow/automation/ssl-manager.sh \
  setup-letsencrypt mail.yourdomain.com admin@yourdomain.com --staging
```

### 2. API Connection Problems

**Symptoms:**
- API authentication failures
- Connection timeouts
- SSL verification errors

**Diagnostic Steps:**
```bash
# Test API connectivity
./src/email-infrastructure/mailcow/automation/setup-api.sh test

# Check API configuration
cat /opt/mailcow-dockerized/data/web/inc/vars.local.inc.php | grep API

# Test direct API call
curl -k -X GET https://mail.yourdomain.com/api/v1/get/domain/all \
     -H "X-API-Key: your_api_key"
```

**Solutions:**

**API Key Issues:**
```bash
# Generate new API key
./src/email-infrastructure/mailcow/automation/setup-api.sh generate-key admin "Admin API Key"

# Update API key in configuration
export MAILCOW_API_KEY="new_api_key_here"
echo 'export MAILCOW_API_KEY="new_api_key_here"' >> ~/.bashrc
```

**SSL Issues:**
```bash
# Test with SSL verification disabled (temporary)
python3 -c "
from email_infrastructure.mailcow.core.api_client import MailcowAPI
api = MailcowAPI(verify_ssl=False)
print('API Test:', 'OK' if api.test_connection() else 'FAILED')
"

# Fix SSL certificate
./src/email-infrastructure/mailcow/automation/ssl-manager.sh \
  setup-letsencrypt mail.yourdomain.com admin@yourdomain.com --force
```

### 3. Domain and Mailbox Issues

**Symptoms:**
- Domains not appearing in interface
- Mailbox creation failures
- DKIM key generation errors

**Diagnostic Steps:**
```bash
# List domains via API
python3 -c "
from email_infrastructure.mailcow.core.api_client import MailcowAPI
api = MailcowAPI()
domains = api.get_domains()
print('Domains:', [d['domain_name'] for d in domains])
"

# Check domain DNS configuration
./src/email-infrastructure/mailcow/automation/domain-manager.sh check-dns yourdomain.com

# Test mailbox creation
./src/email-infrastructure/mailcow/automation/mailbox-manager.sh \
  create test@yourdomain.com "" "Test User" 1024
```

**Solutions:**

**Domain Issues:**
```bash
# Re-add domain with proper configuration
./src/email-infrastructure/mailcow/automation/domain-manager.sh \
  delete yourdomain.com --force

./src/email-infrastructure/mailcow/automation/domain-manager.sh \
  add yourdomain.com "Your Domain" 5120 25 500

# Verify DNS records
./src/email-infrastructure/dns/monitors/dns_verifier.py \
  comprehensive --domain yourdomain.com --ip your.server.ip
```

**DKIM Issues:**
```bash
# Regenerate DKIM keys
./src/email-infrastructure/mailcow/automation/dkim-manager.sh \
  delete yourdomain.com default

./src/email-infrastructure/mailcow/automation/dkim-manager.sh \
  generate yourdomain.com 2048 default

# Update DNS with new DKIM record
./src/email-infrastructure/mailcow/automation/dkim-manager.sh \
  dns yourdomain.com
```

## Monitoring Component Issues

### 1. Blacklist Monitoring Failures

**Symptoms:**
- False positive blacklist alerts
- Monitoring stops working
- API timeouts

**Diagnostic Steps:**
```bash
# Test blacklist check manually
python3 -c "
from email_infrastructure.monitoring.monitors.blacklist_monitor import BlacklistMonitor
monitor = BlacklistMonitor()
result = monitor.check_ip_blacklist('your.server.ip')
print('Blacklist Status:', result)
"

# Check monitoring logs
tail -f /var/log/email-infrastructure-monitoring.log

# Test individual blacklist providers
dig your.server.ip.zen.spamhaus.org
dig your.server.ip.b.barracudacentral.org
```

**Solutions:**

**Network Issues:**
```bash
# Test DNS resolution
nslookup zen.spamhaus.org
ping -c 3 zen.spamhaus.org

# Check firewall rules
sudo ufw status
sudo iptables -L

# Ensure DNS port is open
sudo ufw allow out 53
```

**Configuration Issues:**
```bash
# Update monitoring configuration
# config/environments/production.yaml
monitoring:
  blacklist:
    enabled: true
    check_interval: 3600
    timeout: 30
    providers:
      - name: "spamhaus"
        enabled: true
        weight: 10

# Restart monitoring
./src/email-infrastructure/monitoring/scripts/restart-monitoring.sh
```

### 2. Warmup Campaign Problems

**Symptoms:**
- Campaigns not starting
- Email sending failures
- Tracking not working

**Diagnostic Steps:**
```bash
# Check active campaigns
python3 -c "
from email_infrastructure.monitoring.campaigns.warmup_campaigns import WarmupCampaigns
campaigns = WarmupCampaigns()
active = campaigns.list_active_campaigns()
print('Active Campaigns:', active)
"

# Check email sending logs
tail -f /opt/mailcow-dockerized/data/logs/postfix/current

# Test SMTP connectivity
telnet localhost 587
```

**Solutions:**

**Campaign Configuration:**
```bash
# Stop problematic campaign
python3 -c "
from email_infrastructure.monitoring.campaigns.warmup_campaigns import WarmupCampaigns
campaigns = WarmupCampaigns()
campaigns.stop_warmup_campaign('campaign_id_here')
"

# Start new campaign with proper settings
python3 -c "
from email_infrastructure.monitoring.campaigns.warmup_campaigns import WarmupCampaigns
campaigns = WarmupCampaigns()
campaign_id = campaigns.start_warmup_campaign(
    'yourdomain.com',
    ['user@yourdomain.com'],
    'standard'
)
print('Campaign ID:', campaign_id)
"
```

**SMTP Issues:**
```bash
# Check Mailcow SMTP settings
cd /opt/mailcow-dockerized
docker-compose exec postfix-mailcow postconf | grep smtp

# Test email delivery
echo "Test email" | mail -s "Test" user@yourdomain.com

# Check authentication
./src/email-infrastructure/mailcow/automation/mailbox-manager.sh \
  test-auth user@yourdomain.com
```

## VPS Component Issues

### 1. VPS Connection Problems

**Symptoms:**
- SSH connection failures
- API authentication errors
- Firewall blocking connections

**Diagnostic Steps:**
```bash
# Test SSH connectivity
ssh -v root@your.server.ip

# Check firewall status
./src/email-infrastructure/vps/scripts/health-check.sh --ip your.server.ip

# Test API connectivity
python3 -c "
from email_infrastructure.vps.core.vps_manager import VPSManager
vps = VPSManager()
info = vps.get_vps_info('your_instance_id')
print('VPS Info:', info)
"
```

**Solutions:**

**SSH Issues:**
```bash
# Check SSH service status
systemctl status ssh

# Verify SSH key
ssh-keygen -l -f ~/.ssh/id_rsa.pub

# Test with password authentication
ssh -o PasswordAuthentication=yes root@your.server.ip

# Check SSH configuration
sudo nano /etc/ssh/sshd_config
sudo systemctl restart ssh
```

**Firewall Issues:**
```bash
# Check current firewall rules
sudo ufw status verbose

# Allow SSH access
sudo ufw allow 22/tcp

# Reset firewall if needed
sudo ufw --force reset
./src/email-infrastructure/vps/scripts/setup-firewall.sh --reset
```

**API Issues:**
```bash
# Update API tokens
export HETZNER_API_TOKEN="your_new_token"
export DO_API_TOKEN="your_do_token"

# Test provider APIs
curl -H "Authorization: Bearer $HETZNER_API_TOKEN" \
     https://api.hetzner.cloud/v1/servers
```

### 2. Resource Monitoring Issues

**Symptoms:**
- High resource usage alerts
- Monitoring not reporting
- Performance degradation

**Diagnostic Steps:**
```bash
# Check system resources
./src/email-infrastructure/vps/scripts/system-info.sh --detailed

# Monitor in real-time
htop
iotop
nethogs

# Check disk usage
df -h
du -sh /var/log/*
du -sh /opt/mailcow-dockerized/*
```

**Solutions:**

**High CPU Usage:**
```bash
# Find CPU-intensive processes
top -o %CPU

# Check for CPU limits in containers
cd /opt/mailcow-dockerized
docker stats

# Adjust container limits
# Edit docker-compose.override.yml
```

**High Memory Usage:**
```bash
# Check memory usage by process
ps aux --sort=-%mem | head

# Clear system caches
sudo sync && sudo sysctl vm.drop_caches=3

# Restart heavy containers
cd /opt/mailcow-dockerized
docker-compose restart nginx-mailcow postfix-mailcow
```

**Disk Space Issues:**
```bash
# Find large files
find /var -type f -size +100M -exec ls -lh {} \;
find /opt -type f -size +100M -exec ls -lh {} \;

# Clean up logs
sudo journalctl --vacuum-time=7d
sudo find /var/log -name "*.log" -type f -mtime +30 -delete

# Clean Docker data
docker system prune -a --volumes
```

## Network and Connectivity Issues

### 1. Port Access Problems

**Symptoms:**
- Services unreachable from internet
- Firewall blocking connections
- ISP port blocking

**Diagnostic Steps:**
```bash
# Check listening ports
sudo netstat -tulpn

# Test external connectivity
telnet your.server.ip 25
telnet your.server.ip 80
telnet your.server.ip 443

# Check firewall rules
sudo ufw status numbered
sudo iptables -L -n
```

**Solutions:**

**Firewall Configuration:**
```bash
# Allow required ports
sudo ufw allow 25/tcp   # SMTP
sudo ufw allow 80/tcp   # HTTP
sudo ufw allow 443/tcp  # HTTPS
sudo ufw allow 465/tcp  # SMTPS
sudo ufw allow 587/tcp  # Submission
sudo ufw allow 993/tcp  # IMAPS
sudo ufw allow 995/tcp  # POP3S

# Reload firewall
sudo ufw reload
```

**ISP Port Blocking:**
```bash
# Test alternative ports
# Configure Mailcow to use non-standard ports
# Edit /opt/mailcow-dockerized/docker-compose.override.yml

# Use proxy/tunnel service
# Configure reverse proxy with different ports
```

### 2. DNS Resolution Problems

**Symptoms:**
- Domain names not resolving
- DNS timeouts
- Incorrect IP addresses returned

**Diagnostic Steps:**
```bash
# Test DNS resolution
nslookup yourdomain.com
dig yourdomain.com A
dig yourdomain.com MX

# Check system DNS configuration
cat /etc/resolv.conf
systemd-resolve --status

# Test different DNS servers
dig @8.8.8.8 yourdomain.com A
dig @1.1.1.1 yourdomain.com A
```

**Solutions:**

**DNS Configuration:**
```bash
# Update system DNS servers
sudo nano /etc/systemd/resolved.conf
# Add: DNS=8.8.8.8 1.1.1.1

sudo systemctl restart systemd-resolved

# Flush DNS cache
sudo resolvectl flush-caches
```

**Cloudflare DNS Issues:**
```bash
# Check Cloudflare nameservers
dig NS yourdomain.com

# Verify records in Cloudflare
./src/email-infrastructure/dns/managers/dns_manager.py \
  list --domain yourdomain.com

# Update nameservers if needed
# (Change at domain registrar)
```

## Performance Issues

### 1. Slow Email Delivery

**Symptoms:**
- High email queue
- SMTP timeouts
- Delivery delays

**Diagnostic Steps:**
```bash
# Check mail queue
cd /opt/mailcow-dockerized
docker-compose exec postfix-mailcow postqueue -p

# Check SMTP logs
docker-compose logs postfix-mailcow | tail -100

# Test SMTP performance
time echo "Test" | mail -s "Performance Test" test@gmail.com
```

**Solutions:**

**Queue Management:**
```bash
# Flush mail queue
cd /opt/mailcow-dockerized
docker-compose exec postfix-mailcow postqueue -f

# Check for deferred mail
docker-compose exec postfix-mailcow postqueue -p | grep MAILER-DAEMON

# Increase concurrent delivery
docker-compose exec postfix-mailcow postconf default_process_limit=200
docker-compose restart postfix-mailcow
```

**DNS Performance:**
```bash
# Optimize DNS resolution
echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf
echo "nameserver 1.1.1.1" | sudo tee -a /etc/resolv.conf

# Clear DNS cache
sudo systemctl restart systemd-resolved
```

### 2. High System Load

**Symptoms:**
- System unresponsive
- High load averages
- Container restarts

**Diagnostic Steps:**
```bash
# Check system load
uptime
cat /proc/loadavg

# Monitor resource usage
iotop -a
top -c

# Check container resources
cd /opt/mailcow-dockerized
docker stats
```

**Solutions:**

**Resource Limits:**
```yaml
# /opt/mailcow-dockerized/docker-compose.override.yml
services:
  postfix-mailcow:
    mem_limit: 1g
    cpus: 2
    
  dovecot-mailcow:
    mem_limit: 1g
    cpus: 2
```

**System Optimization:**
```bash
# Increase file limits
echo '* soft nofile 65536' | sudo tee -a /etc/security/limits.conf
echo '* hard nofile 65536' | sudo tee -a /etc/security/limits.conf

# Optimize kernel parameters
echo 'vm.swappiness=10' | sudo tee -a /etc/sysctl.conf
echo 'net.core.rmem_max=134217728' | sudo tee -a /etc/sysctl.conf

sudo sysctl -p
```

## Emergency Procedures

### System Recovery

If the system becomes unresponsive:

```bash
# 1. Check system status
systemctl status docker
systemctl status fail2ban

# 2. Restart essential services
sudo systemctl restart docker
cd /opt/mailcow-dockerized
docker-compose restart

# 3. Check logs for errors
journalctl -xe
tail -f /var/log/email-infrastructure.log

# 4. Run system validation
./scripts/utilities/validate-setup.sh yourdomain.com your.server.ip --repair
```

### Backup and Restore

Emergency backup and restore procedures:

```bash
# Create emergency backup
./src/email-infrastructure/mailcow/backup/backup-manager.sh create emergency

# List available backups
./src/email-infrastructure/mailcow/backup/backup-manager.sh list

# Restore from backup
./src/email-infrastructure/mailcow/backup/backup-manager.sh \
  restore backup-name full --confirm
```

### Contact Information

For additional support:

1. **Check Documentation**: Review component-specific READMEs
2. **System Logs**: Always check logs for detailed error messages
3. **Component Testing**: Test each component individually
4. **Community Support**: Join the project community for assistance

### Debug Mode

Enable debug logging for detailed troubleshooting:

```bash
# Enable debug mode
export EMAIL_INFRA_LOG_LEVEL=DEBUG

# Run operations with debug output
./scripts/utilities/validate-setup.sh yourdomain.com your.server.ip --debug

# Check debug logs
tail -f /var/log/email-infrastructure-debug.log
```

This troubleshooting guide should help resolve the majority of issues encountered with the Cold Email Infrastructure system. For issues not covered here, enable debug logging and examine the system logs for detailed error information.