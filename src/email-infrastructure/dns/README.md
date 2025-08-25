# DNS Automation System for Cold Email Infrastructure

This comprehensive DNS automation system provides complete DNS management, monitoring, and optimization for cold email infrastructure with Cloudflare integration.

## Overview

The DNS automation system consists of several interconnected components:

- **DNS Manager** (`dns-manager.py`) - Complete Cloudflare API integration for DNS record management
- **Record Generator** (`record-generator.sh`) - Automated generation of all required email infrastructure DNS records
- **DNS Verifier** (`dns-verifier.py`) - DNS propagation checking and record validation
- **DNS Monitor** (`dns-monitor.py`) - Continuous monitoring and health checking
- **Cache Manager** (`cache-manager.py`) - DNS cache optimization and management
- **Configuration Templates** - Pre-built templates for various deployment scenarios

## Features

### DNS Management
- Full Cloudflare API integration with rate limiting and retry logic
- Bulk DNS record operations with batch processing
- Multi-domain support with zone management
- Backup and restore functionality
- Template-based record synchronization
- Zone file export and import

### Record Generation
- Automated generation of A, MX, TXT (SPF/DKIM/DMARC), SRV, and CNAME records
- Support for multiple output formats (JSON, YAML, BIND, Cloudflare CLI)
- PTR/reverse DNS record management
- Configurable SPF and DMARC policies
- Auto-detection of existing DKIM keys

### DNS Verification & Monitoring
- DNS propagation checking across multiple nameservers
- Real-time record validation and syntax checking
- Blacklist monitoring for IP addresses
- Email deliverability testing
- Health checks for mail infrastructure
- Comprehensive domain validation scoring

### Cache Management
- Multi-backend cache support (Memory, Redis, Hybrid)
- Intelligent TTL optimization based on access patterns
- Cache warming and prefetching
- LRU eviction policies
- Cache invalidation and domain-wide clearing

## Quick Start

### 1. Installation

```bash
# Install Python dependencies
pip install -r requirements.txt

# Set up configuration
cp cloudflare-config.yaml.example cloudflare-config.yaml
# Edit configuration with your Cloudflare API token
```

### 2. Basic DNS Management

```bash
# Generate DNS records for a domain
./record-generator.sh -d example.com -i 192.168.1.100 --deploy

# Verify DNS records
python3 dns-verifier.py comprehensive --domain example.com --ip 192.168.1.100

# Start monitoring
python3 dns-monitor.py start --config dns-monitor-config.yaml
```

### 3. Cloudflare API Setup

1. Get your Cloudflare API token from the dashboard
2. Set the environment variable: `export CLOUDFLARE_API_TOKEN="your_token_here"`
3. Or configure it in `cloudflare-config.yaml`

## Detailed Usage

### DNS Manager

The DNS Manager provides complete Cloudflare API integration:

```python
from dns_manager import DNSManager, DNSRecord

# Initialize manager
dns = DNSManager('cloudflare-config.yaml')

# Create a DNS record
record = DNSRecord('A', 'mail.example.com', '192.168.1.100', ttl=300)
await dns.create_dns_record('example.com', record)

# List all records
records = await dns.list_dns_records('example.com')

# Sync from template
await dns.sync_records_from_template('example.com', 'template.yaml')
```

Available commands:
- `list` - List DNS records
- `create` - Create a DNS record  
- `update` - Update existing record
- `delete` - Delete a record
- `bulk-create` - Create multiple records
- `sync` - Sync records from template
- `backup` - Backup existing records
- `restore` - Restore from backup
- `validate` - Validate DNS configuration

### Record Generator

Generate all required DNS records for email infrastructure:

```bash
# Basic usage
./record-generator.sh -d example.com -i 192.168.1.100

# Advanced options
./record-generator.sh \
  --domain example.com \
  --ip 192.168.1.100 \
  --subdomain mail \
  --dkim-selector default \
  --format yaml \
  --output records.yaml \
  --deploy
```

Options:
- `-d, --domain` - Target domain (required)
- `-i, --ip` - Server IP address (required)
- `-s, --subdomain` - Mail subdomain (default: mail)
- `-k, --dkim-selector` - DKIM selector (default: default)
- `-f, --format` - Output format (json/yaml/bind/cloudflare)
- `--deploy` - Deploy to Cloudflare automatically
- `--validate` - Validate generated records

### DNS Verifier

Verify DNS records and check propagation:

```bash
# Check single record
python3 dns-verifier.py check --domain example.com --type A --expected 192.168.1.100

# Check propagation across nameservers
python3 dns-verifier.py propagation --domain example.com --type A --expected 192.168.1.100

# Wait for propagation to complete
python3 dns-verifier.py wait-propagation --domain example.com --type A --expected 192.168.1.100

# Comprehensive domain check
python3 dns-verifier.py comprehensive --domain example.com --ip 192.168.1.100

# Check specific email records
python3 dns-verifier.py spf --domain example.com
python3 dns-verifier.py dmarc --domain example.com
python3 dns-verifier.py dkim --domain example.com --selector default
```

### DNS Monitor

Continuous monitoring of DNS health:

```bash
# Start monitoring daemon
python3 dns-monitor.py start --daemon

# Run single health check
python3 dns-monitor.py health --domain example.com --ip 192.168.1.100

# Check blacklist status
python3 dns-monitor.py blacklist --ip 192.168.1.100

# Test email deliverability
python3 dns-monitor.py deliverability --domain example.com
```

### Cache Manager

Optimize DNS caching:

```bash
# View cache statistics
python3 cache-manager.py stats

# Warm cache for domains
python3 cache-manager.py warm --domains example.com example2.com

# Clear cache
python3 cache-manager.py clear

# Export cache data
python3 cache-manager.py export --output cache-dump.json
```

## Configuration

### Cloudflare Configuration (`cloudflare-config.yaml`)

```yaml
cloudflare:
  api_token: ${CLOUDFLARE_API_TOKEN}
  
rate_limit:
  requests_per_second: 4
  burst_limit: 10
  
dns:
  default_ttl: 300
  
email:
  mail_subdomain: "mail"
  dkim:
    default_selector: "default"
  spf:
    default_policy: "~all"
  dmarc:
    default_policy: "quarantine"
```

### Monitoring Configuration

Configure monitoring rules in your config file:

```yaml
rules:
  - name: "mx_records"
    domain: "example.com"
    record_type: "MX"
    record_name: "example.com"
    expected_value: "mail.example.com"
    check_interval: 300
    alert_threshold: 3
    
alerts:
  webhook_url: "https://hooks.slack.com/..."
  email_recipients: ["admin@example.com"]
  alert_cooldown: 3600
```

## Templates

### DNS Records Template (`dns-records-template.json`)

Complete template with all email infrastructure records:

```json
{
  "variables": {
    "domain": "example.com",
    "server_ip": "192.168.1.100",
    "dkim_selector": "default"
  },
  "records": [
    {
      "type": "A",
      "name": "${domain}",
      "content": "${server_ip}",
      "ttl": 300
    }
  ]
}
```

### SPF/DMARC Templates (`spf-dmarc-templates.yaml`)

Pre-configured templates for different deployment strategies:

```yaml
templates:
  spf:
    standard:
      template: "v=spf1 ip4:{server_ip} a:{mail_server} include:_spf.google.com ~all"
  dmarc:
    quarantine:
      template: "v=DMARC1;p=quarantine;rua=mailto:{report_email};fo=1"
```

## Deployment Strategies

### 1. New Domain Setup

```bash
# Generate and deploy all records
./record-generator.sh -d newdomain.com -i 192.168.1.100 --deploy

# Verify deployment
python3 dns-verifier.py comprehensive --domain newdomain.com --ip 192.168.1.100

# Start monitoring
python3 dns-monitor.py start --domain newdomain.com
```

### 2. Existing Domain Migration

```bash
# Backup existing records
python3 dns-manager.py backup --domain example.com --backup existing-backup.json

# Generate new records without deploying
./record-generator.sh -d example.com -i 192.168.1.100 --validate

# Deploy gradually
python3 dns-manager.py sync --domain example.com --template records.yaml

# Monitor propagation
python3 dns-verifier.py wait-propagation --domain example.com --type MX --expected "mail.example.com"
```

### 3. Multi-Domain Bulk Operations

```python
domains = ["domain1.com", "domain2.com", "domain3.com"]

for domain in domains:
    # Generate records
    subprocess.run(["./record-generator.sh", "-d", domain, "-i", server_ip, "--deploy"])
    
    # Verify
    result = await verifier.comprehensive_domain_check(domain, server_ip)
    print(f"{domain}: {result['overall_status']}")
```

## Monitoring and Alerts

### Health Checks

The system performs comprehensive health checks:

- **DNS Resolution** - Verify all records resolve correctly
- **Propagation Status** - Check propagation across global nameservers  
- **Blacklist Status** - Monitor IP reputation across major blacklists
- **Email Deliverability** - Test SMTP connectivity to major providers
- **Record Validation** - Validate SPF, DKIM, and DMARC syntax

### Alert Types

- **DNS Failures** - When records fail to resolve
- **Propagation Issues** - When propagation is incomplete
- **Blacklist Listings** - When IPs appear on blacklists
- **Configuration Errors** - Invalid record configurations
- **Performance Degradation** - High response times or error rates

### Integration Options

- **Webhooks** - HTTP callbacks for external systems
- **Slack** - Direct Slack channel notifications
- **Email** - SMTP-based email alerts
- **Discord** - Discord channel notifications

## Performance Optimization

### DNS Caching

- **Multi-tier caching** - Memory and Redis backends
- **Intelligent prefetching** - Refresh popular records before expiration
- **TTL optimization** - Automatic TTL adjustment based on access patterns
- **Cache warming** - Preload important records

### Rate Limiting

- **API rate limiting** - Respect Cloudflare API limits
- **Exponential backoff** - Automatic retry with increasing delays
- **Request queuing** - Queue requests during high load
- **Burst handling** - Handle traffic spikes gracefully

## Security Features

### API Security

- **Token-based authentication** - Secure API access
- **IP restrictions** - Limit access to specific IPs
- **Audit logging** - Log all DNS operations
- **Sensitive data masking** - Protect sensitive information in logs

### DNS Security

- **DNSSEC support** - Domain Name System Security Extensions
- **CAA records** - Certificate Authority Authorization
- **SPF hardening** - Strict SPF policies to prevent spoofing
- **DMARC enforcement** - Gradual DMARC policy enforcement

## Troubleshooting

### Common Issues

1. **API Authentication Errors**
   ```bash
   # Check API token
   export CLOUDFLARE_API_TOKEN="your_token"
   python3 dns-manager.py list --domain example.com
   ```

2. **DNS Propagation Delays**
   ```bash
   # Check propagation status
   python3 dns-verifier.py propagation --domain example.com --type A --expected 192.168.1.100
   ```

3. **Blacklist Issues**
   ```bash
   # Check blacklist status
   python3 dns-monitor.py blacklist --ip 192.168.1.100
   ```

### Debug Mode

Enable debug logging:

```bash
# Set debug level
export LOG_LEVEL=DEBUG

# Run with verbose output
python3 dns-manager.py --verbose list --domain example.com
```

### Health Check Commands

```bash
# Quick health check
python3 dns-verifier.py comprehensive --domain example.com --ip 192.168.1.100

# Detailed monitoring
python3 dns-monitor.py health --domain example.com --ip 192.168.1.100 --format yaml
```

## API Reference

### DNS Manager API

```python
class DNSManager:
    async def create_dns_record(domain: str, record: DNSRecord) -> Dict
    async def update_dns_record(domain: str, record_id: str, record: DNSRecord) -> Dict
    async def delete_dns_record(domain: str, record_id: str) -> bool
    async def list_dns_records(domain: str, record_type: str = None) -> List[Dict]
    async def bulk_create_records(domain: str, records: List[DNSRecord]) -> List[Dict]
    async def sync_records_from_template(domain: str, template_path: str) -> Dict
    async def backup_dns_records(domain: str, backup_path: str) -> bool
    async def validate_dns_records(domain: str) -> Dict
```

### DNS Verifier API

```python
class DNSVerifier:
    async def check_single_record(name: str, record_type: str, expected: str) -> DNSCheckResult
    async def check_propagation(name: str, record_type: str, expected: str) -> PropagationResult
    async def wait_for_propagation(name: str, record_type: str, expected: str) -> PropagationResult
    async def verify_spf_record(domain: str) -> Dict
    async def verify_dkim_record(domain: str, selector: str) -> Dict
    async def verify_dmarc_record(domain: str) -> Dict
    async def comprehensive_domain_check(domain: str, server_ip: str) -> Dict
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For support and questions:
- Create an issue on GitHub
- Check the documentation
- Review the troubleshooting guide
- Enable debug logging for detailed information

## Changelog

See CHANGELOG.md for version history and updates.