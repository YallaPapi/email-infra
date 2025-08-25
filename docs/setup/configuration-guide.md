# Cold Email Infrastructure - Configuration Guide

## Overview

The Cold Email Infrastructure uses a unified, hierarchical configuration system that supports multiple environments and provides type-safe validation. This guide covers all aspects of configuration management, from basic setup to advanced customization.

## Configuration Architecture

### Hierarchical Configuration Structure

```
config/
├── schemas/                          # JSON Schema validation files
│   ├── base.schema.json             # Base configuration schema
│   ├── api.schema.json              # API client configurations
│   ├── database.schema.json         # Database connection settings
│   ├── dns.schema.json              # DNS and domain configurations
│   ├── email.schema.json            # Email service configurations
│   ├── logging.schema.json          # Logging framework settings
│   ├── monitoring.schema.json       # Monitoring and alerting
│   └── security.schema.json         # Security and authentication
├── environments/                     # Environment-specific configurations
│   ├── base.yaml                    # Base settings inherited by all environments
│   ├── development.yaml             # Development overrides
│   ├── staging.yaml                 # Staging environment settings
│   ├── production.yaml              # Production environment settings
│   └── testing.yaml                 # Testing environment settings
├── templates/                        # Configuration templates
│   ├── dns-records.yaml             # DNS record templates
│   ├── email-templates.yaml         # Email campaign templates
│   └── monitoring-alerts.yaml       # Alert notification templates
├── secrets/                          # Secret management
│   ├── .env.example                 # Example environment variables
│   └── secrets.schema.json          # Secret validation schema
└── global-config.yaml               # Global configuration file
```

## Environment Configuration

### Setting the Environment

The system automatically detects the environment from the `EMAIL_INFRA_ENV` environment variable:

```bash
# Set environment (development, staging, production, testing)
export EMAIL_INFRA_ENV=production

# Alternative: Set in configuration file
echo "EMAIL_INFRA_ENV=production" >> ~/.bashrc
```

### Base Configuration (`environments/base.yaml`)

The base configuration provides default settings inherited by all environments:

```yaml
application:
  name: "cold-email-infrastructure"
  version: "1.0.0"
  debug: false
  timezone: "UTC"

logging:
  level: "INFO"
  format: "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
  handlers:
    - type: "console"
    - type: "file"
      filename: "/var/log/email-infrastructure.log"
      max_size: "10MB"
      backup_count: 5
      when: "midnight"

database:
  default:
    type: "sqlite"
    path: "/var/lib/email-infrastructure/main.db"
    timeout: 30
    backup_enabled: true
    backup_interval: "daily"
    pool_size: 10
    max_overflow: 20

apis:
  cloudflare:
    base_url: "https://api.cloudflare.com/client/v4"
    timeout: 30
    rate_limit:
      requests_per_second: 4
      burst_limit: 10
    retry:
      max_attempts: 3
      backoff_factor: 2
      backoff_max: 60
    
  mailcow:
    verify_ssl: true
    timeout: 30
    rate_limit:
      requests_per_second: 10
      burst_limit: 20

email:
  default_domain: "example.com"
  warmup:
    enabled: true
    initial_daily_limit: 50
    increase_rate: 10
    target_daily_limit: 1000
    duration_days: 30
    rest_days: [0, 6]  # Sunday and Saturday
  
  templates:
    welcome: "templates/welcome-email.html"
    warmup: "templates/warmup-email.html"

dns:
  default_ttl: 300
  min_ttl: 120
  max_ttl: 86400
  propagation_timeout: 1800
  nameservers:
    - "8.8.8.8"
    - "8.8.4.4"
    - "1.1.1.1"
    - "1.0.0.1"
  
  records:
    spf:
      default_policy: "~all"
      include_domains: []
    dkim:
      key_size: 2048
      default_selector: "default"
    dmarc:
      policy: "quarantine"
      percentage: 100
      report_interval: 86400

monitoring:
  enabled: true
  check_interval: 300
  alert_thresholds:
    delivery_rate_min: 95.0
    bounce_rate_max: 3.0
    spam_rate_max: 0.5
    reputation_score_min: 7.0
    dns_response_time_max: 5000
    ssl_expiry_warning_days: 30
  
  blacklist_providers:
    - name: "spamhaus"
      enabled: true
      weight: 10
    - name: "barracuda"
      enabled: true
      weight: 8
    - name: "spamcop"
      enabled: true
      weight: 6
  
  notifications:
    email_alerts: false
    webhook_url: ""
    slack_enabled: false
    discord_enabled: false
    alert_cooldown: 3600

security:
  api_key_rotation_days: 90
  password_policy:
    min_length: 12
    require_uppercase: true
    require_lowercase: true
    require_numbers: true
    require_symbols: true
  audit_logging: true
  sensitive_data_masking: true
  session_timeout: 1800
  max_failed_attempts: 3
  lockout_duration: 900
  allowed_ips: []
  blocked_ips: []

vps:
  firewall:
    enabled: true
    default_policy: "deny"
    allowed_ports:
      tcp: [22, 25, 80, 443, 465, 587, 993, 995]
      udp: [53]
  
  backup:
    enabled: true
    schedule: "0 2 * * *"  # Daily at 2 AM
    retention_days: 30
    compression: true
    encryption: false
    
  monitoring:
    cpu_threshold: 80
    memory_threshold: 85
    disk_threshold: 90
    load_threshold: 5.0
```

### Environment-Specific Configurations

#### Development Environment (`environments/development.yaml`)

```yaml
# Inherits from base.yaml with overrides
application:
  debug: true

logging:
  level: "DEBUG"
  handlers:
    - type: "console"

database:
  default:
    path: "/tmp/email-infrastructure-dev.db"
    backup_enabled: false

apis:
  cloudflare:
    # Use staging API for development
    rate_limit:
      requests_per_second: 10
      burst_limit: 20
  
  mailcow:
    verify_ssl: false  # Allow self-signed certificates

email:
  warmup:
    initial_daily_limit: 10
    target_daily_limit: 100
    duration_days: 7

dns:
  default_ttl: 60  # Shorter TTL for faster testing

monitoring:
  check_interval: 60
  alert_thresholds:
    delivery_rate_min: 80.0
    dns_response_time_max: 10000
  
  notifications:
    email_alerts: false

security:
  api_key_rotation_days: 7
  audit_logging: false
  session_timeout: 3600

vps:
  firewall:
    # More permissive for development
    allowed_ports:
      tcp: [22, 25, 80, 443, 465, 587, 993, 995, 8080, 8443]
```

#### Production Environment (`environments/production.yaml`)

```yaml
# Inherits from base.yaml with overrides
logging:
  level: "WARNING"
  handlers:
    - type: "file"
      filename: "/var/log/email-infrastructure.log"
      max_size: "100MB"
      backup_count: 10
    - type: "json"
      filename: "/var/log/email-infrastructure.json"
    - type: "syslog"
      facility: "mail"

database:
  default:
    path: "/var/lib/email-infrastructure/production.db"
    backup_enabled: true
    backup_interval: "hourly"
    pool_size: 20
    max_overflow: 40

apis:
  cloudflare:
    # Production rate limits
    rate_limit:
      requests_per_second: 4
      burst_limit: 10
    retry:
      max_attempts: 5
      backoff_factor: 2

email:
  warmup:
    initial_daily_limit: 50
    target_daily_limit: 2000
    duration_days: 45

monitoring:
  check_interval: 60
  alert_thresholds:
    delivery_rate_min: 97.0
    bounce_rate_max: 2.0
    spam_rate_max: 0.3
    reputation_score_min: 8.0
    dns_response_time_max: 3000
    ssl_expiry_warning_days: 45
  
  notifications:
    email_alerts: true
    webhook_url: "${SLACK_WEBHOOK_URL}"
    slack_enabled: true
    alert_cooldown: 1800

security:
  api_key_rotation_days: 30
  password_policy:
    min_length: 16
  audit_logging: true
  session_timeout: 900
  max_failed_attempts: 3
  allowed_ips:
    - "192.168.1.0/24"
    - "10.0.0.0/8"

vps:
  firewall:
    enabled: true
    default_policy: "deny"
    # Strict production firewall rules
    allowed_ports:
      tcp: [25, 80, 443, 465, 587, 993, 995]
      udp: [53]
  
  backup:
    enabled: true
    schedule: "0 1,13 * * *"  # Twice daily
    retention_days: 60
    compression: true
    encryption: true
```

## Component-Specific Configuration

### DNS Configuration

Configure DNS management settings:

```yaml
# src/email-infrastructure/dns/config/dns-config.yaml
dns:
  providers:
    cloudflare:
      api_token: "${CLOUDFLARE_API_TOKEN}"
      rate_limit:
        requests_per_second: 4
        burst_limit: 10
      zones:
        - domain: "example.com"
          zone_id: "your_zone_id"
        - domain: "example2.com"
          zone_id: "your_zone_id_2"
  
  templates:
    email_infrastructure:
      records:
        - type: "A"
          name: "${domain}"
          content: "${server_ip}"
          ttl: 300
        - type: "A"
          name: "mail.${domain}"
          content: "${server_ip}"
          ttl: 300
        - type: "MX"
          name: "${domain}"
          content: "mail.${domain}"
          priority: 10
          ttl: 300
        - type: "TXT"
          name: "${domain}"
          content: "v=spf1 a mx include:_spf.google.com ~all"
          ttl: 300
        - type: "TXT"
          name: "_dmarc.${domain}"
          content: "v=DMARC1; p=quarantine; rua=mailto:dmarc@${domain}"
          ttl: 300
  
  monitoring:
    enabled: true
    check_interval: 300
    propagation_timeout: 1800
    nameservers:
      - "8.8.8.8"
      - "8.8.4.4"
      - "1.1.1.1"
```

### Mailcow Configuration

Configure mail server settings:

```yaml
# src/email-infrastructure/mailcow/config/mailcow-config.yaml
mailcow:
  hostname: "${MAILCOW_HOSTNAME}"
  api:
    endpoint: "https://${MAILCOW_HOSTNAME}/api/v1"
    key: "${MAILCOW_API_KEY}"
    verify_ssl: true
    timeout: 30
  
  domains:
    default_quota: 5120  # MB
    default_mailboxes: 25
    default_aliases: 500
    
  ssl:
    provider: "letsencrypt"
    staging: false
    additional_san: []
  
  services:
    skip_clamd: false
    skip_solr: false
    skip_sogo: false
    
  database:
    root_password: "${DBROOT}"
    mailcow_password: "${DBPASS}"
    
  security:
    admin_password_complexity: "high"
    session_timeout: 3600
    failed_login_attempts: 3
    
  backup:
    enabled: true
    schedule: "0 2 * * *"
    types: ["config", "database", "vmail"]
    retention: 30
    compression: true
```

### Monitoring Configuration

Configure monitoring and alerting:

```yaml
# src/email-infrastructure/monitoring/config/monitoring-config.yaml
monitoring:
  blacklist:
    enabled: true
    check_interval: 3600
    providers:
      - name: "spamhaus"
        url: "zen.spamhaus.org"
        weight: 10
      - name: "barracuda"
        url: "b.barracudacentral.org"
        weight: 8
      - name: "spamcop"
        url: "bl.spamcop.net"
        weight: 6
    
    thresholds:
      warning: 3
      critical: 5
      
  warmup:
    enabled: true
    campaigns:
      standard:
        initial_daily_limit: 50
        increase_rate: 10
        target_daily_limit: 1000
        duration_days: 30
      aggressive:
        initial_daily_limit: 100
        increase_rate: 20
        target_daily_limit: 2000
        duration_days: 20
        
  alerts:
    channels:
      email:
        enabled: true
        recipients: ["admin@example.com"]
        smtp_server: "localhost"
        smtp_port: 587
      
      slack:
        enabled: true
        webhook_url: "${SLACK_WEBHOOK_URL}"
        channel: "#alerts"
        username: "Email Infrastructure Bot"
      
      webhook:
        enabled: false
        url: "${WEBHOOK_URL}"
        method: "POST"
        headers:
          Content-Type: "application/json"
          Authorization: "Bearer ${WEBHOOK_TOKEN}"
    
    rules:
      - name: "DNS Failure"
        condition: "dns_check_failed"
        severity: "critical"
        cooldown: 1800
      
      - name: "Blacklist Detection"
        condition: "blacklist_listed"
        severity: "warning"
        cooldown: 3600
      
      - name: "SSL Expiry"
        condition: "ssl_expires_soon"
        severity: "warning"
        cooldown: 86400
```

### VPS Configuration

Configure VPS management settings:

```yaml
# src/email-infrastructure/vps/config/vps-config.yaml
vps:
  providers:
    hetzner:
      api_token: "${HETZNER_API_TOKEN}"
      enabled: true
    
    digitalocean:
      api_token: "${DO_API_TOKEN}"
      enabled: false
      
  security:
    firewall:
      enabled: true
      default_policy: "DROP"
      rules:
        - port: 22
          protocol: tcp
          source: "0.0.0.0/0"
          action: "ACCEPT"
        - port: 25
          protocol: tcp
          source: "0.0.0.0/0"
          action: "ACCEPT"
        - port: 80
          protocol: tcp
          source: "0.0.0.0/0"
          action: "ACCEPT"
        - port: 443
          protocol: tcp
          source: "0.0.0.0/0"
          action: "ACCEPT"
        - port: 465
          protocol: tcp
          source: "0.0.0.0/0"
          action: "ACCEPT"
        - port: 587
          protocol: tcp
          source: "0.0.0.0/0"
          action: "ACCEPT"
        - port: 993
          protocol: tcp
          source: "0.0.0.0/0"
          action: "ACCEPT"
        - port: 995
          protocol: tcp
          source: "0.0.0.0/0"
          action: "ACCEPT"
    
    fail2ban:
      enabled: true
      jails:
        sshd:
          enabled: true
          maxretry: 3
          bantime: 600
        postfix:
          enabled: true
          maxretry: 5
          bantime: 3600
        dovecot:
          enabled: true
          maxretry: 5
          bantime: 3600
  
  monitoring:
    enabled: true
    metrics:
      cpu:
        warning_threshold: 70
        critical_threshold: 90
      memory:
        warning_threshold: 80
        critical_threshold: 95
      disk:
        warning_threshold: 85
        critical_threshold: 95
      load:
        warning_threshold: 4.0
        critical_threshold: 8.0
    
    collection_interval: 60
    retention_days: 30
```

## Environment Variables

### Core Environment Variables

Set these environment variables for all environments:

```bash
# Core Configuration
EMAIL_INFRA_ENV=production                    # Environment (dev/staging/prod)
EMAIL_INFRA_ROOT=/path/to/project            # Project root directory
EMAIL_INFRA_LOG_LEVEL=INFO                   # Log level

# Cloudflare API
CLOUDFLARE_API_TOKEN=your_cloudflare_token   # Cloudflare API token

# Mailcow Configuration
MAILCOW_HOSTNAME=mail.example.com            # Mailcow hostname
MAILCOW_API_KEY=your_mailcow_api_key        # Mailcow API key
ADMIN_EMAIL=admin@example.com                # Admin email address
TZ=UTC                                       # Timezone

# Database
DBROOT=secure_random_password                # Database root password
DBPASS=secure_random_password                # Mailcow database password

# SSL/TLS
SKIP_LETS_ENCRYPT=n                         # Use Let's Encrypt
LE_STAGING=n                                # Let's Encrypt staging

# Monitoring
SLACK_WEBHOOK_URL=your_slack_webhook        # Slack webhook URL
WEBHOOK_URL=your_webhook_url                # Generic webhook URL
WEBHOOK_TOKEN=your_webhook_token            # Webhook authentication token

# VPS Providers
HETZNER_API_TOKEN=your_hetzner_token        # Hetzner Cloud API token
DO_API_TOKEN=your_digitalocean_token       # DigitalOcean API token

# Security
API_RATE_LIMIT=100                          # API rate limit per hour
SESSION_TIMEOUT=1800                        # Session timeout in seconds
REQUIRE_2FA=false                           # Require two-factor authentication
```

### Environment-Specific Variables

#### Development Environment

```bash
# Development overrides
EMAIL_INFRA_ENV=development
EMAIL_INFRA_LOG_LEVEL=DEBUG
MAILCOW_HOSTNAME=mail.dev.example.com
LE_STAGING=y
SKIP_LETS_ENCRYPT=y
```

#### Production Environment

```bash
# Production settings
EMAIL_INFRA_ENV=production
EMAIL_INFRA_LOG_LEVEL=WARNING
MAILCOW_HOSTNAME=mail.example.com
LE_STAGING=n
REQUIRE_2FA=true
API_RATE_LIMIT=50
```

## Configuration Validation

### Schema Validation

The system uses JSON Schema for configuration validation:

```bash
# Validate configuration
python3 config/config.py --validate --environment production

# Expected output:
# ✓ Configuration valid for environment: production
```

### Configuration Testing

Test configuration loading:

```python
from email_infrastructure.core.config_manager import get_config, get_section

# Load complete configuration
config = get_config()
print(f"Environment: {config['application']['environment']}")

# Get specific section
dns_config = get_section('dns')
print(f"Default TTL: {dns_config['default_ttl']}")

# Get specific value
log_level = get_value('logging.level')
print(f"Log Level: {log_level}")
```

## Configuration Management

### Loading Configuration

The configuration system automatically loads and merges configurations:

```python
from email_infrastructure.core.config_manager import UnifiedConfigManager

# Initialize configuration manager
config_manager = UnifiedConfigManager(environment='production')

# Load configuration
config = config_manager.load_config()

# Get specific sections
api_config = config_manager.get_section('apis')
monitoring_config = config_manager.get_section('monitoring')

# Get nested values
cloudflare_token = config_manager.get_value('apis.cloudflare.api_token')
```

### Configuration Inheritance

Configurations inherit from base and can be overridden:

1. **Base Configuration**: `environments/base.yaml`
2. **Environment Override**: `environments/{environment}.yaml`
3. **Environment Variables**: Runtime variable substitution

### Variable Substitution

The system supports environment variable substitution:

```yaml
# In configuration files, use:
api_token: "${CLOUDFLARE_API_TOKEN}"
webhook_url: "${SLACK_WEBHOOK_URL:https://default.webhook.url}"

# Variables are substituted at runtime:
# - ${VAR_NAME} - Required variable
# - ${VAR_NAME:default} - Optional with default value
```

### Hot Configuration Reload

Reload configuration without restarting:

```python
from email_infrastructure.core.config_manager import get_config_manager

config_manager = get_config_manager()
new_config = config_manager.reload_config()
```

## Advanced Configuration

### Custom Configuration Paths

Override default configuration paths:

```bash
# Custom configuration directory
export EMAIL_INFRA_CONFIG_DIR=/custom/config/path

# Custom environment
export EMAIL_INFRA_ENV=custom_env
```

### Configuration Export

Export current configuration:

```bash
# Export as YAML
python3 config/config.py --export config_export.yaml --format yaml

# Export as JSON
python3 config/config.py --export config_export.json --format json
```

### Configuration Backup

Backup configuration files:

```bash
# Create configuration backup
./scripts/maintenance/backup-config.sh

# Restore configuration backup
./scripts/maintenance/restore-config.sh backup-20241201-120000
```

## Troubleshooting Configuration

### Common Issues

1. **Environment Variable Not Found**
   ```bash
   # Check environment variables
   env | grep EMAIL_INFRA
   
   # Verify variable substitution
   python3 config/config.py --get apis.cloudflare.api_token
   ```

2. **Invalid Configuration Format**
   ```bash
   # Validate YAML syntax
   python3 -c "import yaml; yaml.safe_load(open('config/environments/production.yaml'))"
   
   # Validate against schema
   python3 config/config.py --validate
   ```

3. **Permission Issues**
   ```bash
   # Check file permissions
   ls -la config/
   
   # Fix permissions if needed
   chmod 600 config/secrets/*
   chmod 644 config/environments/*
   ```

### Debug Configuration Loading

Enable debug mode:

```bash
# Enable debug logging
export EMAIL_INFRA_LOG_LEVEL=DEBUG

# Test configuration loading
python3 -c "
from email_infrastructure.core.config_manager import get_config
config = get_config()
print('Configuration loaded successfully')
print(f'Sections: {list(config.keys())}')
"
```

For additional support, see the [Troubleshooting Guide](troubleshooting.md) or check the system logs for detailed error information.