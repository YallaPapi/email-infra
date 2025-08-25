# Cold Email Infrastructure - Security Guide

## Overview

This comprehensive security guide covers all aspects of securing the Cold Email Infrastructure system, from initial deployment through ongoing maintenance. The system implements defense-in-depth security principles with multiple layers of protection.

## Security Architecture

### Multi-Layer Security Model

```
┌─────────────────────────────────────────────────────────┐
│                    Application Layer                    │
├─────────────────────────────────────────────────────────┤
│  API Authentication │ Input Validation │ Audit Logging  │
├─────────────────────────────────────────────────────────┤
│                   Network Security                      │
├─────────────────────────────────────────────────────────┤
│  Firewall Rules    │  TLS Encryption  │  Rate Limiting  │
├─────────────────────────────────────────────────────────┤
│                   System Security                       │
├─────────────────────────────────────────────────────────┤
│  OS Hardening     │  Container Security │ File Permissions│
├─────────────────────────────────────────────────────────┤
│                   Infrastructure                        │
└─────────────────────────────────────────────────────────┘
```

### Security Principles

1. **Zero Trust**: Never trust, always verify
2. **Least Privilege**: Minimum necessary permissions
3. **Defense in Depth**: Multiple security layers
4. **Fail Secure**: Secure defaults and graceful degradation
5. **Regular Updates**: Automated security updates
6. **Comprehensive Monitoring**: Log and monitor everything

## Initial Security Setup

### 1. Server Hardening

Run the automated security hardening script:

```bash
# Complete server hardening
./src/email-infrastructure/vps/scripts/setup-vps.sh --ip your.server.ip --secure

# Manual hardening steps
./scripts/security/harden-server.sh --comprehensive
```

#### SSH Hardening

**Disable Root Login:**
```bash
# /etc/ssh/sshd_config
PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
MaxAuthTries 3
ClientAliveInterval 300
ClientAliveCountMax 2
```

**SSH Key Management:**
```bash
# Generate strong SSH key (if not exists)
ssh-keygen -t ed25519 -b 4096 -C "admin@yourdomain.com"

# Disable password authentication
sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sudo systemctl restart sshd

# Use SSH key agents
eval $(ssh-agent -s)
ssh-add ~/.ssh/id_ed25519
```

#### User Account Security

```bash
# Create dedicated service user
sudo useradd -m -s /bin/bash -G docker emailinfra
sudo passwd emailinfra

# Configure sudo access
echo "emailinfra ALL=(ALL) NOPASSWD:/usr/bin/docker, /usr/bin/systemctl" | sudo tee /etc/sudoers.d/emailinfra

# Set proper file permissions
sudo chown -R emailinfra:emailinfra /home/stuart/cold-email-infrastructure
chmod 700 /home/emailinfra/.ssh
chmod 600 /home/emailinfra/.ssh/authorized_keys
```

### 2. Firewall Configuration

**UFW (Uncomplicated Firewall) Setup:**

```bash
# Reset firewall
sudo ufw --force reset

# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH access (change port if needed)
sudo ufw allow 22/tcp

# Email services
sudo ufw allow 25/tcp    # SMTP
sudo ufw allow 465/tcp   # SMTPS
sudo ufw allow 587/tcp   # SMTP Submission
sudo ufw allow 993/tcp   # IMAPS
sudo ufw allow 995/tcp   # POP3S

# Web services
sudo ufw allow 80/tcp    # HTTP
sudo ufw allow 443/tcp   # HTTPS

# DNS
sudo ufw allow 53/tcp
sudo ufw allow 53/udp

# Enable firewall
sudo ufw enable
```

**Advanced Firewall Rules:**

```bash
# Limit SSH connections
sudo ufw limit 22/tcp

# Allow specific IP ranges
sudo ufw allow from 192.168.0.0/16 to any port 22

# Block common attack ports
sudo ufw deny 23/tcp     # Telnet
sudo ufw deny 135/tcp    # RPC
sudo ufw deny 139/tcp    # NetBIOS
sudo ufw deny 445/tcp    # SMB

# Log firewall activity
sudo ufw logging on
```

**fail2ban Configuration:**

```bash
# Install and configure fail2ban
sudo apt install fail2ban

# Create custom configuration
sudo tee /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3
backend = systemd

[sshd]
enabled = true
port = 22
logpath = %(sshd_log)s
backend = %(sshd_backend)s

[postfix]
enabled = true
port = smtp,465,587
logpath = /opt/mailcow-dockerized/data/logs/postfix/current

[dovecot]
enabled = true
port = pop3,pop3s,imap,imaps,submission,465,sieve
logpath = /opt/mailcow-dockerized/data/logs/dovecot/current

[nginx-http-auth]
enabled = true
filter = nginx-http-auth
port = http,https
logpath = /opt/mailcow-dockerized/data/logs/nginx/access.log
EOF

sudo systemctl enable fail2ban
sudo systemctl start fail2ban
```

## API Security

### 1. Authentication and Authorization

**API Key Management:**

```bash
# Generate secure API keys
./src/email-infrastructure/mailcow/automation/setup-api.sh generate-key admin "Admin API Key" --read-write
./src/email-infrastructure/mailcow/automation/setup-api.sh generate-key monitoring "Monitoring Key" --read-only

# List and manage API keys
./src/email-infrastructure/mailcow/automation/setup-api.sh list-keys
./src/email-infrastructure/mailcow/automation/setup-api.sh revoke-key key_id
```

**API Key Security Configuration:**

```yaml
# config/environments/production.yaml
security:
  api:
    key_rotation_days: 30
    max_keys_per_user: 5
    require_ip_whitelist: true
    rate_limit:
      requests_per_hour: 1000
      burst_limit: 100
    
  authentication:
    require_2fa: true
    session_timeout: 900
    max_failed_attempts: 3
    lockout_duration: 1800
```

**IP Whitelisting:**

```bash
# Configure IP whitelisting for API access
./src/email-infrastructure/mailcow/automation/setup-api.sh whitelist-ip add 192.168.1.0/24
./src/email-infrastructure/mailcow/automation/setup-api.sh whitelist-ip add 10.0.0.0/8

# API key with IP restrictions
python3 -c "
from email_infrastructure.core.security import APIKeyManager
manager = APIKeyManager()
key = manager.create_key(
    name='restricted-admin',
    permissions=['read', 'write'],
    ip_whitelist=['192.168.1.100', '203.0.113.0/24'],
    expires_in=30  # days
)
print(f'API Key: {key}')
"
```

### 2. Rate Limiting

**Configure Rate Limits:**

```yaml
# config/environments/production.yaml
apis:
  rate_limiting:
    enabled: true
    global:
      requests_per_minute: 60
      burst_limit: 20
    
    per_endpoint:
      dns_create: 10  # per minute
      mailbox_create: 5
      bulk_operations: 2
    
    per_user:
      admin: 1000    # per hour
      monitoring: 500
      standard: 100
```

**Implement Rate Limiting:**

```python
# Rate limiting middleware
from email_infrastructure.api.middleware.rate_limiter import RateLimiter

@RateLimiter(limit=10, window=60)  # 10 requests per minute
def create_dns_record(request):
    # API endpoint implementation
    pass
```

### 3. Input Validation and Sanitization

**Validation Rules:**

```python
# Input validation schemas
from pydantic import BaseModel, validator
from typing import Optional

class DNSRecordCreate(BaseModel):
    type: str
    name: str
    content: str
    ttl: Optional[int] = 300
    
    @validator('type')
    def validate_record_type(cls, v):
        allowed_types = ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'SRV']
        if v not in allowed_types:
            raise ValueError(f'Invalid record type: {v}')
        return v
    
    @validator('name')
    def validate_domain_name(cls, v):
        import re
        domain_pattern = r'^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$'
        if not re.match(domain_pattern, v):
            raise ValueError(f'Invalid domain name: {v}')
        return v
```

**SQL Injection Prevention:**

```python
# Use parameterized queries
from email_infrastructure.core.database import DatabaseManager

db = DatabaseManager()
# Safe query
result = db.execute(
    "SELECT * FROM domains WHERE name = ? AND active = ?",
    (domain_name, True)
)

# Avoid string concatenation
# BAD: f"SELECT * FROM domains WHERE name = '{domain_name}'"
```

## TLS/SSL Security

### 1. Certificate Management

**Let's Encrypt Setup:**

```bash
# Production certificates
./src/email-infrastructure/mailcow/automation/ssl-manager.sh \
  setup-letsencrypt mail.yourdomain.com admin@yourdomain.com

# Configure automatic renewal
./src/email-infrastructure/mailcow/automation/ssl-manager.sh schedule-renewal

# Test renewal
./src/email-infrastructure/mailcow/automation/ssl-manager.sh renew --dry-run
```

**Custom Certificate Installation:**

```bash
# Install custom certificate
./src/email-infrastructure/mailcow/automation/ssl-manager.sh \
  install-custom /path/to/certificate.pem /path/to/private-key.pem

# Verify certificate
./src/email-infrastructure/mailcow/automation/ssl-manager.sh verify mail.yourdomain.com
```

### 2. TLS Configuration

**Strong TLS Configuration:**

```nginx
# /opt/mailcow-dockerized/data/conf/nginx/tls.conf
ssl_protocols TLSv1.2 TLSv1.3;
ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
ssl_prefer_server_ciphers off;

# Security headers
add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
add_header Referrer-Policy "strict-origin-when-cross-origin";
add_header Content-Security-Policy "default-src 'self'";

# OCSP Stapling
ssl_stapling on;
ssl_stapling_verify on;
ssl_trusted_certificate /path/to/chain.pem;

# Perfect Forward Secrecy
ssl_ecdh_curve secp384r1;
ssl_dhparam /etc/ssl/certs/dhparam.pem;
```

**Generate Strong DH Parameters:**

```bash
# Generate 4096-bit DH parameters
sudo openssl dhparam -out /etc/ssl/certs/dhparam.pem 4096
```

## Email Security

### 1. SPF Configuration

**Strict SPF Policy:**

```bash
# Generate SPF record
./src/email-infrastructure/dns/scripts/record-generator.sh \
  --domain yourdomain.com --spf-policy "v=spf1 a mx -all"

# Verify SPF record
./src/email-infrastructure/dns/monitors/dns_verifier.py spf --domain yourdomain.com
```

**SPF Template:**
```yaml
# config/templates/spf-policies.yaml
policies:
  strict:
    template: "v=spf1 a mx -all"
    description: "Only allow A and MX records"
  
  relaxed:
    template: "v=spf1 a mx include:_spf.google.com ~all"
    description: "Allow A, MX, and Google Workspace"
  
  custom:
    template: "v=spf1 ip4:{server_ip} a:{mail_server} -all"
    description: "Specific IP and server"
```

### 2. DKIM Configuration

**Strong DKIM Keys:**

```bash
# Generate 2048-bit DKIM key
./src/email-infrastructure/mailcow/automation/dkim-manager.sh \
  generate yourdomain.com 2048 default

# Rotate DKIM keys regularly
./src/email-infrastructure/mailcow/automation/dkim-manager.sh \
  rotate yourdomain.com --key-size 2048

# Verify DKIM configuration
./src/email-infrastructure/dns/monitors/dns_verifier.py \
  dkim --domain yourdomain.com --selector default
```

**DKIM Security Best Practices:**

```bash
# Multiple DKIM selectors for key rotation
./src/email-infrastructure/mailcow/automation/dkim-manager.sh \
  generate yourdomain.com 2048 selector1

./src/email-infrastructure/mailcow/automation/dkim-manager.sh \
  generate yourdomain.com 2048 selector2

# Automated key rotation script
cat > /etc/cron.monthly/dkim-rotation << 'EOF'
#!/bin/bash
# Monthly DKIM key rotation
DOMAIN="yourdomain.com"
NEW_SELECTOR="$(date +%Y%m)"

# Generate new DKIM key
/path/to/dkim-manager.sh generate "$DOMAIN" 2048 "$NEW_SELECTOR"

# Update DNS records
/path/to/dkim-manager.sh dns "$DOMAIN" "$NEW_SELECTOR"

# Wait for DNS propagation, then activate
sleep 3600
/path/to/dkim-manager.sh activate "$DOMAIN" "$NEW_SELECTOR"
EOF

chmod +x /etc/cron.monthly/dkim-rotation
```

### 3. DMARC Policy

**Implement DMARC Gradually:**

```bash
# Phase 1: Monitoring only
./src/email-infrastructure/dns/scripts/record-generator.sh \
  --domain yourdomain.com --dmarc-policy "v=DMARC1; p=none; rua=mailto:dmarc@yourdomain.com"

# Phase 2: Quarantine policy
./src/email-infrastructure/dns/scripts/record-generator.sh \
  --domain yourdomain.com --dmarc-policy "v=DMARC1; p=quarantine; pct=25; rua=mailto:dmarc@yourdomain.com"

# Phase 3: Strict policy
./src/email-infrastructure/dns/scripts/record-generator.sh \
  --domain yourdomain.com --dmarc-policy "v=DMARC1; p=reject; rua=mailto:dmarc@yourdomain.com"
```

**DMARC Report Processing:**

```python
# Automated DMARC report processing
from email_infrastructure.monitoring.reports.dmarc_analyzer import DMARCAnalyzer

analyzer = DMARCAnalyzer()
reports = analyzer.fetch_reports('dmarc@yourdomain.com')
analysis = analyzer.analyze_reports(reports)

print(f"Authentication Pass Rate: {analysis['pass_rate']}%")
print(f"Policy Violations: {analysis['violations']}")
```

## Database Security

### 1. Database Hardening

**MySQL/MariaDB Security:**

```bash
# Secure MySQL installation
cd /opt/mailcow-dockerized
docker-compose exec mysql-mailcow mysql_secure_installation

# Configure secure settings
docker-compose exec mysql-mailcow mysql -u root -p << 'EOF'
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
```

**Database User Permissions:**

```sql
-- Create restricted database users
CREATE USER 'emailinfra_ro'@'localhost' IDENTIFIED BY 'secure_password';
GRANT SELECT ON mailcow.* TO 'emailinfra_ro'@'localhost';

CREATE USER 'emailinfra_api'@'localhost' IDENTIFIED BY 'secure_password';
GRANT SELECT, INSERT, UPDATE ON mailcow.domain TO 'emailinfra_api'@'localhost';
GRANT SELECT, INSERT, UPDATE ON mailcow.mailbox TO 'emailinfra_api'@'localhost';

FLUSH PRIVILEGES;
```

### 2. Database Encryption

**Encrypt Database Connections:**

```yaml
# config/environments/production.yaml
database:
  default:
    ssl_mode: "REQUIRED"
    ssl_ca: "/path/to/ca-cert.pem"
    ssl_cert: "/path/to/client-cert.pem"
    ssl_key: "/path/to/client-key.pem"
```

**Database Backup Security:**

```bash
# Encrypted database backups
./src/email-infrastructure/mailcow/backup/backup-manager.sh create db --encrypt

# Configure backup encryption
# config/environments/production.yaml
backup:
  encryption:
    enabled: true
    key_file: "/etc/email-infrastructure/backup.key"
    algorithm: "AES256"
```

## Container Security

### 1. Docker Security

**Secure Docker Configuration:**

```bash
# Configure Docker daemon security
sudo tee /etc/docker/daemon.json << 'EOF'
{
  "icc": false,
  "userland-proxy": false,
  "no-new-privileges": true,
  "seccomp-profile": "/etc/docker/seccomp.json",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

sudo systemctl restart docker
```

**Container Hardening:**

```yaml
# docker-compose.override.yml security settings
services:
  postfix-mailcow:
    security_opt:
      - no-new-privileges:true
      - seccomp:unconfined
    read_only: true
    tmpfs:
      - /tmp:size=100M,noexec,nosuid,nodev
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
      - SETUID
      - SETGID
```

### 2. Image Security

**Scan Container Images:**

```bash
# Scan images for vulnerabilities
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd):/tmp -w /tmp \
  anchore/grype mailcow/postfix:latest

# Update images regularly
cd /opt/mailcow-dockerized
docker-compose pull
docker-compose up -d
```

**Use Minimal Images:**

```dockerfile
# Use minimal base images
FROM alpine:3.18

# Create non-root user
RUN addgroup -g 1001 -S emailinfra && \
    adduser -u 1001 -S emailinfra -G emailinfra

# Set security labels
LABEL security.scan="enabled"
LABEL security.level="high"

USER 1001
```

## Monitoring and Logging

### 1. Security Monitoring

**Configure Security Monitoring:**

```yaml
# config/environments/production.yaml
monitoring:
  security:
    enabled: true
    events:
      - failed_login_attempts
      - api_authentication_failures
      - suspicious_dns_requests
      - high_volume_email_sending
      - firewall_blocked_connections
    
    alerts:
      - type: "failed_auth"
        threshold: 5
        window: 300  # seconds
        action: "block_ip"
      
      - type: "api_abuse"
        threshold: 100
        window: 3600
        action: "rate_limit"
```

**Security Event Monitoring:**

```python
# Real-time security monitoring
from email_infrastructure.monitoring.security.event_monitor import SecurityMonitor

monitor = SecurityMonitor()

# Monitor for security events
monitor.start_monitoring([
    'authentication_failures',
    'suspicious_api_calls',
    'unusual_traffic_patterns',
    'malware_detection'
])

# Configure alert handlers
@monitor.on_event('multiple_failed_auth')
def handle_auth_failures(event):
    # Block IP address
    monitor.block_ip(event['source_ip'], duration=3600)
    
    # Send alert
    monitor.send_alert(f"Multiple failed auth from {event['source_ip']}")
```

### 2. Audit Logging

**Comprehensive Audit Logging:**

```python
# Audit logging configuration
from email_infrastructure.core.logging.audit_logger import AuditLogger

audit = AuditLogger()

# Log all administrative actions
@audit.log_action
def create_mailbox(email, **kwargs):
    # Implementation
    pass

# Log API calls
@audit.log_api_call
def api_endpoint(request):
    # Implementation
    pass
```

**Log Analysis and Correlation:**

```bash
# Analyze security logs
./scripts/security/analyze-logs.sh --since "1 hour ago" --type security

# Generate security report
./scripts/security/security-report.sh --output /tmp/security-report.html

# Real-time log monitoring
tail -f /var/log/email-infrastructure-security.log | \
  grep -E "(FAILED|ERROR|SUSPICIOUS|BLOCKED)"
```

## Backup Security

### 1. Secure Backup Strategy

**Encrypted Backup Configuration:**

```yaml
# config/environments/production.yaml
backup:
  encryption:
    enabled: true
    algorithm: "AES-256-GCM"
    key_derivation: "PBKDF2"
    iterations: 100000
  
  storage:
    local:
      path: "/var/backups/email-infrastructure"
      permissions: "600"
    
    remote:
      provider: "s3"
      bucket: "email-infra-backups"
      encryption: "aws:kms"
      access_controls: "strict"
```

**Backup Validation:**

```bash
# Automated backup validation
./src/email-infrastructure/mailcow/backup/backup-manager.sh validate latest

# Test restore process
./src/email-infrastructure/mailcow/backup/backup-manager.sh \
  test-restore backup-20241201-120000 --dry-run
```

### 2. Key Management

**Backup Encryption Keys:**

```bash
# Generate backup encryption key
openssl rand -base64 32 > /etc/email-infrastructure/backup.key
chmod 600 /etc/email-infrastructure/backup.key
chown root:root /etc/email-infrastructure/backup.key

# Store key securely (e.g., HashiCorp Vault)
vault kv put secret/email-infrastructure/backup key=@/etc/email-infrastructure/backup.key
```

## Incident Response

### 1. Security Incident Procedures

**Incident Response Plan:**

```bash
# 1. Immediate Response
./scripts/security/emergency-lockdown.sh  # Block all external access
./scripts/security/collect-forensics.sh   # Collect evidence

# 2. Investigation
./scripts/security/analyze-breach.sh      # Analyze logs and system state
./scripts/security/assess-damage.sh       # Assess scope of compromise

# 3. Containment
./scripts/security/isolate-systems.sh     # Isolate affected systems
./scripts/security/revoke-credentials.sh  # Revoke all API keys/passwords

# 4. Recovery
./scripts/security/restore-from-backup.sh # Restore from clean backup
./scripts/security/security-update.sh     # Apply security updates
```

**Automated Incident Response:**

```python
# Automated incident response
from email_infrastructure.security.incident_response import IncidentResponder

responder = IncidentResponder()

@responder.on_incident('security_breach')
def handle_security_breach(incident):
    # Immediate containment
    responder.block_all_external_access()
    responder.snapshot_system_state()
    
    # Collect evidence
    responder.collect_logs(hours=24)
    responder.capture_network_traffic()
    
    # Notify administrators
    responder.send_emergency_alert(incident)
```

### 2. Recovery Procedures

**System Recovery Checklist:**

1. **Assess Damage:**
   - Identify compromised systems
   - Determine attack vectors
   - Evaluate data integrity

2. **Containment:**
   - Isolate affected systems
   - Block malicious IPs
   - Revoke compromised credentials

3. **Eradication:**
   - Remove malware/backdoors
   - Patch vulnerabilities
   - Update security configurations

4. **Recovery:**
   - Restore from clean backups
   - Gradually restore services
   - Enhanced monitoring

5. **Lessons Learned:**
   - Document incident
   - Update security procedures
   - Improve monitoring

## Security Maintenance

### 1. Regular Security Updates

**Automated Security Updates:**

```bash
# Configure automatic security updates
sudo tee /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF

# Configure unattended upgrades
sudo tee /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id} ESMApps:${distro_codename}-apps-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
```

### 2. Security Auditing

**Regular Security Audits:**

```bash
# Monthly security audit script
cat > /etc/cron.monthly/security-audit << 'EOF'
#!/bin/bash

REPORT_DIR="/var/log/security-audits/$(date +%Y%m)"
mkdir -p "$REPORT_DIR"

# System security audit
./scripts/security/system-audit.sh > "$REPORT_DIR/system-audit.log"

# Network security scan
nmap -sS -O localhost > "$REPORT_DIR/network-scan.log"

# File integrity check
./scripts/security/integrity-check.sh > "$REPORT_DIR/integrity-check.log"

# Generate security report
./scripts/security/generate-report.sh "$REPORT_DIR"
EOF

chmod +x /etc/cron.monthly/security-audit
```

**Vulnerability Scanning:**

```bash
# Install and configure vulnerability scanner
sudo apt install lynis

# Run security audit
sudo lynis audit system

# Custom security checks
./scripts/security/custom-security-scan.sh --comprehensive
```

### 3. Security Metrics and KPIs

**Security Monitoring Dashboard:**

```yaml
# Security metrics configuration
monitoring:
  security_metrics:
    - name: "failed_auth_rate"
      threshold: 10  # per minute
    
    - name: "ssl_cert_expiry_days"
      warning: 30
      critical: 7
    
    - name: "firewall_blocked_attempts"
      threshold: 100  # per hour
    
    - name: "malware_detections"
      threshold: 1
    
    - name: "security_updates_pending"
      threshold: 5
```

This comprehensive security guide provides the foundation for maintaining a secure Cold Email Infrastructure deployment. Regular review and updates of security procedures are essential as threats evolve.