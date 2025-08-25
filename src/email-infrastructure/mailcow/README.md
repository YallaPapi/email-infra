# Mailcow Dockerized Mail Server Automation

This repository contains a complete automation system for deploying and managing Mailcow dockerized mail servers. Everything is automated via CLI/API with no manual web UI interaction required.

## Overview

The system provides:

- **Automated Installation**: Complete Mailcow installation with zero manual configuration
- **API-First Management**: Full API wrapper and authentication system
- **Domain Management**: Automated domain setup with DNS verification and DKIM
- **Secure Mailbox Provisioning**: Automated mailbox creation with strong password generation
- **SSL Certificate Management**: Let's Encrypt, custom, and self-signed certificate support
- **Backup & Restore**: Comprehensive backup and restore procedures
- **Quota Management**: Advanced quota and policy management
- **Mail Routing**: Flexible mail routing and transport configuration
- **Database Extensions**: Enhanced database schema with audit logging and statistics
- **Monitoring & Alerting**: Built-in monitoring and notification systems

## Directory Structure

```
mailcow/
├── api/                    # API wrapper and utilities
│   └── mailcow-api.py     # Python API wrapper
├── automation/            # Automation scripts
│   ├── domain-manager.sh  # Domain management
│   ├── mailbox-manager.sh # Mailbox provisioning
│   ├── dkim-manager.sh    # DKIM key management
│   ├── quota-manager.sh   # Quota and policy management
│   ├── ssl-manager.sh     # SSL certificate management
│   └── routing-manager.sh # Mail routing rules
├── backup/                # Backup and restore
│   └── backup-manager.sh  # Comprehensive backup system
├── config/                # Configuration files
│   ├── mailcow-config.yaml
│   ├── api_key
│   └── admin_credentials
├── scripts/               # Core scripts
│   ├── install-mailcow.sh # Automated installation
│   ├── configure-mailcow.sh # Post-installation setup
│   ├── setup-api.sh      # API authentication setup
│   └── db-init.sh         # Database initialization
├── templates/             # Configuration templates
│   ├── mailcow.conf.template
│   ├── docker-compose.override.yml.template
│   └── environment.env.template
└── README.md             # This file
```

## Quick Start

### 1. Installation

Run the complete installation with a single command:

```bash
# Basic installation
sudo ./scripts/install-mailcow.sh mail.yourdomain.com admin@yourdomain.com

# With custom timezone
sudo ./scripts/install-mailcow.sh mail.yourdomain.com admin@yourdomain.com "America/New_York"
```

### 2. Post-Installation Configuration

```bash
# Configure Mailcow services
sudo ./scripts/configure-mailcow.sh

# Setup API authentication
sudo ./scripts/setup-api.sh setup
sudo ./scripts/setup-api.sh configure

# Initialize extended database features
sudo ./scripts/db-init.sh init
```

### 3. Domain and Mailbox Setup

```bash
# Add a domain
./automation/domain-manager.sh add yourdomain.com "Your Domain" 5120 20 500

# Create mailboxes with secure passwords
./automation/mailbox-manager.sh create user@yourdomain.com "" "User Name" 2048

# Generate DKIM keys
./automation/dkim-manager.sh generate yourdomain.com
```

## Detailed Usage

### Domain Management

The domain manager handles all domain-related operations:

```bash
# Add domain with custom settings
./automation/domain-manager.sh add example.com "Example Domain" 10240 50 1000

# List all domains
./automation/domain-manager.sh list table

# Generate DNS records
./automation/domain-manager.sh dns example.com

# Check DNS configuration
./automation/domain-manager.sh check-dns example.com

# Bulk add domains from file
./automation/domain-manager.sh bulk-add domains.txt
```

**Domain file format:**
```csv
domain.com,Description,quota_mb,max_mailboxes,max_aliases
example.com,Example Domain,5120,25,500
test.com,Test Domain,2048,10,200
```

### Mailbox Management

Secure mailbox provisioning with automatic password generation:

```bash
# Create mailbox (password auto-generated)
./automation/mailbox-manager.sh create user@example.com

# Create with specific password
./automation/mailbox-manager.sh create user@example.com "SecurePass123!" "User Name" 2048

# List mailboxes
./automation/mailbox-manager.sh list example.com table

# Update mailbox settings
./automation/mailbox-manager.sh update user@example.com quota 4096

# Generate secure passwords
./automation/mailbox-manager.sh generate-password 20

# Bulk create from file
./automation/mailbox-manager.sh bulk-create mailboxes.csv
```

**Mailbox file format:**
```csv
email,name,quota_mb,password
user1@example.com,John Doe,2048,
user2@example.com,Jane Smith,4096,CustomPass123!
```

### DKIM Management

Automated DKIM key generation and DNS record management:

```bash
# Generate DKIM key
./automation/dkim-manager.sh generate example.com 2048 dkim

# Get DKIM DNS record
./automation/dkim-manager.sh get example.com dns

# Test DKIM configuration
./automation/dkim-manager.sh test example.com

# List all DKIM keys
./automation/dkim-manager.sh list table

# Generate DNS zone file
./automation/dkim-manager.sh dns-zone example.com
```

### SSL Certificate Management

Comprehensive SSL certificate management:

```bash
# Setup Let's Encrypt (production)
./automation/ssl-manager.sh setup-letsencrypt mail.example.com admin@example.com

# Setup Let's Encrypt (staging for testing)
./automation/ssl-manager.sh setup-letsencrypt mail.example.com admin@example.com --staging

# Install custom certificate
./automation/ssl-manager.sh install-custom /path/to/cert.pem /path/to/key.pem

# Generate self-signed certificate
./automation/ssl-manager.sh generate-selfsigned mail.example.com 365

# Check certificate status
./automation/ssl-manager.sh verify mail.example.com

# Renew certificate
./automation/ssl-manager.sh renew
```

### Quota and Policy Management

Advanced quota management with monitoring:

```bash
# Set mailbox quota
./automation/quota-manager.sh set-mailbox user@example.com 2048

# Set domain quota
./automation/quota-manager.sh set-domain example.com 10240

# List quota usage
./automation/quota-manager.sh list mailbox table

# Set quota policies
./automation/quota-manager.sh policies 80 95

# Generate quota report
./automation/quota-manager.sh report /tmp/quota-report.txt
```

### Backup and Restore

Comprehensive backup system with multiple backup types:

```bash
# Full backup
./backup/backup-manager.sh create full

# Configuration-only backup
./backup/backup-manager.sh create config

# Database backup
./backup/backup-manager.sh create db

# List backups
./backup/backup-manager.sh list table

# Restore from backup
./backup/backup-manager.sh restore mailcow-20231201_020000 full --confirm

# Setup automated backups
./backup/backup-manager.sh schedule daily
```

### Mail Routing

Flexible mail routing and transport configuration:

```bash
# Initialize routing system
./automation/routing-manager.sh init

# Add transport rule
./automation/routing-manager.sh add-transport example.com smtp relay.example.com:587

# Setup relay
./automation/routing-manager.sh setup-relay smtp.gmail.com 587 username password true

# Test routing
./automation/routing-manager.sh test user@example.com

# List routing rules
./automation/routing-manager.sh list table
```

### API Management

Complete API management system:

```bash
# Setup API authentication
./scripts/setup-api.sh setup

# Configure Mailcow API
./scripts/setup-api.sh configure

# Test API access
./scripts/setup-api.sh test

# Generate new API key
./scripts/setup-api.sh generate-key monitoring "Read-only monitoring key"

# List API keys
./scripts/setup-api.sh list-keys

# Add IP to whitelist
./scripts/setup-api.sh whitelist-ip add 203.0.113.1
```

### Database Management

Extended database functionality:

```bash
# Initialize database extensions
./scripts/db-init.sh init

# Run maintenance
./scripts/db-init.sh maintenance

# Create database backup
./scripts/db-init.sh backup daily-backup

# Show database status
./scripts/db-init.sh status

# Execute custom SQL
./scripts/db-init.sh run-script /path/to/script.sql
```

## API Usage

The Python API wrapper provides programmatic access to all Mailcow functions:

### Basic Usage

```python
from mailcow_api import MailcowAPI, load_config

# Load configuration
config = load_config()
api = MailcowAPI(config.hostname, config.api_key)

# Test connection
if api.test_connection():
    print("Connected to Mailcow API")

# Get system status
status = api.get_status()
print(f"Containers: {len(status)}")
```

### Domain Management

```python
# Add domain
result = api.add_domain(
    domain="example.com",
    description="Example Domain",
    quota=5120,
    mailboxes=25
)

# List domains
domains = api.get_domains()
for domain in domains:
    print(f"Domain: {domain['domain_name']}")

# Generate DKIM key
api.add_dkim_key("example.com", key_size=2048)

# Get DKIM record
dkim_record = api.get_dkim_record("example.com")
print(f"DKIM: {dkim_record}")
```

### Mailbox Management

```python
# Create mailbox with auto-generated password
password = api.generate_secure_password()
result = api.add_mailbox(
    email="user@example.com",
    password=password,
    name="User Name",
    quota=2048
)

# List mailboxes
mailboxes = api.get_mailboxes("example.com")
for mailbox in mailboxes:
    print(f"Mailbox: {mailbox['username']}")

# Bulk create mailboxes
mailboxes_config = [
    {"email": "user1@example.com", "name": "User One"},
    {"email": "user2@example.com", "name": "User Two"}
]
results = api.bulk_mailbox_create(mailboxes_config)
```

### Command Line Usage

```bash
# Using the API wrapper directly
python3 api/mailcow-api.py status
python3 api/mailcow-api.py domain list
python3 api/mailcow-api.py mailbox add user@example.com --name "User Name"
python3 api/mailcow-api.py dkim add example.com --key-size 2048
```

## Configuration

### Environment Variables

Key environment variables for configuration:

```bash
# Core settings
MAILCOW_HOSTNAME=mail.example.com
ADMIN_EMAIL=admin@example.com
TZ=UTC

# Database
DBROOT=secure_root_password
DBPASS=secure_db_password

# API
MAILCOW_API_KEY=secure_api_key_here

# SSL/TLS
SKIP_LETS_ENCRYPT=n
LE_STAGING=n
ADDITIONAL_SAN=autodiscover.example.com,autoconfig.example.com

# Services
SKIP_CLAMD=n
SKIP_SOLR=n
SKIP_SOGO=n
```

### Templates

The system includes comprehensive templates for:

- **mailcow.conf**: Main configuration with all parameters
- **docker-compose.override.yml**: Custom container configurations
- **environment.env**: Environment-specific variables

Templates support variable substitution and can be customized for different deployments.

## Security Features

### Password Security

- **Secure Generation**: Cryptographically secure password generation
- **Complexity Requirements**: Configurable password complexity rules
- **Strength Validation**: Real-time password strength checking
- **Encrypted Storage**: Secure credential storage

### API Security

- **Key-Based Authentication**: Secure API key authentication
- **IP Whitelisting**: Restrict API access by IP address
- **Rate Limiting**: Prevent API abuse with configurable limits
- **Request Signing**: Optional request signing for additional security

### Audit Logging

- **Comprehensive Tracking**: All changes tracked with timestamps
- **User Attribution**: Track who made what changes
- **Data Retention**: Configurable audit log retention
- **Compliance Ready**: Audit logs suitable for compliance requirements

## Monitoring and Alerting

### Built-in Monitoring

- **Quota Monitoring**: Alert on high quota usage
- **Certificate Expiration**: SSL certificate expiration warnings
- **Service Health**: Container health monitoring
- **Performance Metrics**: System performance tracking

### Notification Channels

- **Email Notifications**: Configurable email alerts
- **Webhook Support**: HTTP webhook notifications
- **Slack Integration**: Direct Slack notifications
- **Custom Scripts**: Run custom notification scripts

## Backup Strategy

### Backup Types

- **Full Backup**: Complete system backup
- **Incremental**: Changed files only
- **Configuration**: Settings and configurations only
- **Database**: Database-only backup
- **Mail Data**: Mail storage only

### Backup Features

- **Compression**: Automatic backup compression
- **Encryption**: Optional GPG encryption
- **Verification**: Automatic backup verification
- **Rotation**: Configurable backup retention
- **Remote Storage**: Support for remote backup destinations

## Troubleshooting

### Common Issues

1. **DNS Resolution Problems**
   ```bash
   # Check DNS configuration
   ./automation/domain-manager.sh check-dns yourdomain.com
   
   # Generate correct DNS records
   ./automation/domain-manager.sh dns yourdomain.com
   ```

2. **SSL Certificate Issues**
   ```bash
   # Verify certificate status
   ./automation/ssl-manager.sh verify yourdomain.com
   
   # Check certificate expiration
   ./automation/ssl-manager.sh check-expiration 30
   ```

3. **API Connection Problems**
   ```bash
   # Test API connectivity
   ./scripts/setup-api.sh test
   
   # Check API configuration
   ./scripts/setup-api.sh list-keys
   ```

4. **Database Issues**
   ```bash
   # Check database status
   ./scripts/db-init.sh status
   
   # Test database connection
   ./scripts/db-init.sh check-connection
   ```

### Log Files

Key log files for troubleshooting:

- Installation: `/var/log/mailcow-install.log`
- Configuration: `/var/log/mailcow-configure.log`
- API: `/var/log/mailcow-api-setup.log`
- Backup: `/var/log/mailcow-backup.log`
- SSL: `/var/log/mailcow-ssl-manager.log`

### Getting Help

1. Check the logs for detailed error messages
2. Verify DNS configuration is correct
3. Ensure firewall rules allow required ports
4. Test API connectivity before proceeding
5. Use the built-in status and verification commands

## Advanced Configuration

### Custom Docker Compose

Use the override template for advanced container customization:

```bash
# Copy and customize the override template
cp templates/docker-compose.override.yml.template docker-compose.override.yml

# Edit for your specific needs
nano docker-compose.override.yml
```

### Database Extensions

The system includes custom database tables for enhanced functionality:

- **API Keys**: Enhanced API key management
- **Audit Log**: Comprehensive change tracking  
- **Statistics**: Detailed usage statistics
- **Custom Settings**: Flexible configuration storage
- **Notification Queue**: Automated notification system

### Performance Tuning

Key performance settings in templates:

```yaml
# Memory limits
PHP_MEMORY_LIMIT=512M
MYSQL_INNODB_BUFFER_POOL_SIZE=512M
REDIS_MAX_MEMORY=256mb

# Process limits  
PHP_FPM_MAX_CHILDREN=50
NGINX_WORKER_PROCESSES=auto
POSTFIX_MAX_PROCESSES=200
```

## Development and Testing

### Testing Installation

Use staging mode for testing:

```bash
# Install with Let's Encrypt staging
./automation/ssl-manager.sh setup-letsencrypt mail.example.com admin@example.com --staging

# Generate test data
./automation/mailbox-manager.sh bulk-create test-mailboxes.csv
```

### API Development

```python
# Development configuration
config = MailcowConfig(
    hostname="mail.YOUR_DOMAIN.com",
    api_key="YOUR_API_KEY",
    verify_ssl=True  # Set to False for self-signed certificates
)

# Enable debug logging
import logging
logging.basicConfig(level=logging.DEBUG)
```

### Contributing

1. Fork the repository
2. Create feature branch
3. Add comprehensive tests
4. Update documentation
5. Submit pull request

## License

This project is licensed under the MIT License. See LICENSE file for details.

## Support

For support and questions:

1. Check the troubleshooting section
2. Review log files for errors
3. Test individual components
4. Submit issues with detailed logs

## Changelog

### Version 1.0.0
- Initial release
- Complete automation system
- API wrapper and authentication
- Backup and restore functionality
- SSL certificate management
- Database extensions
- Comprehensive documentation