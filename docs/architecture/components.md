# Cold Email Infrastructure - Component Architecture

## Overview

The Cold Email Infrastructure is built with a modular architecture consisting of four main components, each with specific responsibilities and well-defined interfaces. This document provides detailed information about each component's architecture, APIs, and integration points.

## System Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    API Gateway Layer                    │
├─────────────────────────────────────────────────────────┤
│  DNS Management    │  Mailcow       │  Monitoring      │  VPS Management
│  Component         │  Component     │  Component       │  Component
├──────────────────┼───────────────┼─────────────────┼─────────────────┤
│                    Core Infrastructure Layer            │
├─────────────────────────────────────────────────────────┤
│  Unified Config    │  Logging       │  Database        │  Security
│  Manager          │  Framework     │  Layer           │  Framework
└─────────────────────────────────────────────────────────┘
```

## DNS Management Component

### Architecture

The DNS Management Component provides comprehensive DNS automation with Cloudflare integration.

```
src/email-infrastructure/dns/
├── managers/                 # Core DNS management logic
│   ├── dns_manager.py       # Primary DNS operations
│   └── cache_manager.py     # DNS caching and optimization
├── monitors/                 # DNS monitoring and verification
│   ├── dns_monitor.py       # Continuous DNS health monitoring
│   └── dns_verifier.py      # DNS record verification
├── providers/                # DNS provider integrations
│   └── cloudflare.py        # Cloudflare API integration
├── config/                   # DNS configuration
│   ├── cloudflare-config.yaml
│   ├── dns-records-template.json
│   └── spf-dmarc-templates.yaml
└── scripts/                  # Automation scripts
    └── record-generator.sh   # DNS record generation
```

### Key Features

#### DNS Manager (`managers/dns_manager.py`)

**Core Capabilities:**
- Complete Cloudflare API integration with rate limiting
- Bulk DNS record operations with batch processing
- Multi-domain support with zone management
- Backup and restore functionality
- Template-based record synchronization

**API Interface:**
```python
class DNSManager:
    async def create_dns_record(self, domain: str, record: DNSRecord) -> Dict
    async def update_dns_record(self, domain: str, record_id: str, record: DNSRecord) -> Dict
    async def delete_dns_record(self, domain: str, record_id: str) -> bool
    async def list_dns_records(self, domain: str, record_type: str = None) -> List[Dict]
    async def bulk_create_records(self, domain: str, records: List[DNSRecord]) -> List[Dict]
    async def sync_records_from_template(self, domain: str, template_path: str) -> Dict
    async def backup_dns_records(self, domain: str, backup_path: str) -> bool
```

#### DNS Verifier (`monitors/dns_verifier.py`)

**Verification Capabilities:**
- DNS propagation checking across multiple nameservers
- Real-time record validation and syntax checking
- Comprehensive domain validation scoring
- Blacklist monitoring integration

**API Interface:**
```python
class DNSVerifier:
    async def check_single_record(self, name: str, record_type: str, expected: str) -> DNSCheckResult
    async def check_propagation(self, name: str, record_type: str, expected: str) -> PropagationResult
    async def wait_for_propagation(self, name: str, record_type: str, expected: str) -> PropagationResult
    async def verify_spf_record(self, domain: str) -> Dict
    async def verify_dkim_record(self, domain: str, selector: str) -> Dict
    async def verify_dmarc_record(self, domain: str) -> Dict
    async def comprehensive_domain_check(self, domain: str, server_ip: str) -> Dict
```

#### Cache Manager (`managers/cache_manager.py`)

**Caching Features:**
- Multi-backend cache support (Memory, Redis, Hybrid)
- Intelligent TTL optimization based on access patterns
- Cache warming and prefetching
- LRU eviction policies

### Configuration

#### Cloudflare Configuration
```yaml
cloudflare:
  api_token: ${CLOUDFLARE_API_TOKEN}
  base_url: "https://api.cloudflare.com/client/v4"
  
rate_limit:
  requests_per_second: 4
  burst_limit: 10
  
dns:
  default_ttl: 300
  propagation_timeout: 1800
  
cache:
  backend: "hybrid"  # memory, redis, hybrid
  ttl: 300
  max_size: 10000
```

#### DNS Record Templates
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
    },
    {
      "type": "MX",
      "name": "${domain}",
      "content": "mail.${domain}",
      "priority": 10,
      "ttl": 300
    },
    {
      "type": "TXT",
      "name": "${domain}",
      "content": "v=spf1 a mx include:_spf.google.com ~all",
      "ttl": 300
    }
  ]
}
```

### Integration Points

- **API Layer**: RESTful API endpoints for external access
- **Configuration System**: Unified configuration management
- **Monitoring Component**: DNS health status integration
- **Logging System**: Structured logging with correlation IDs

## Mailcow Management Component

### Architecture

The Mailcow Component provides complete mail server automation and management.

```
src/email-infrastructure/mailcow/
├── core/                     # Core Mailcow functionality
│   └── api_client.py        # Mailcow API client
├── managers/                 # Management modules
│   ├── domain_manager.py    # Domain management
│   ├── mailbox_manager.py   # Mailbox management
│   └── dkim_manager.py      # DKIM key management
├── automation/               # Automation scripts
│   ├── install-mailcow.sh   # Installation automation
│   ├── domain-manager.sh    # Domain CLI management
│   ├── mailbox-manager.sh   # Mailbox CLI management
│   └── ssl-manager.sh       # SSL certificate management
├── backup/                   # Backup and restore
│   └── backup-manager.sh    # Comprehensive backup system
├── config/                   # Mailcow configuration
│   └── mailcow-config.yaml
└── templates/                # Configuration templates
    ├── mailcow.conf.template
    └── docker-compose.override.yml.template
```

### Key Features

#### Mailcow API Client (`core/api_client.py`)

**Core Capabilities:**
- Complete Mailcow API integration
- Domain and mailbox management
- DKIM key generation and management
- SSL certificate automation
- Quota and policy management

**API Interface:**
```python
class MailcowAPI:
    def add_domain(self, domain: str, description: str = "", quota: int = 5120) -> Dict
    def delete_domain(self, domain: str) -> bool
    def get_domains(self) -> List[Dict]
    
    def add_mailbox(self, email: str, password: str, name: str, quota: int = 2048) -> Dict
    def delete_mailbox(self, email: str) -> bool
    def get_mailboxes(self, domain: str = None) -> List[Dict]
    def update_mailbox_quota(self, email: str, quota: int) -> Dict
    
    def add_dkim_key(self, domain: str, key_size: int = 2048, selector: str = "default") -> Dict
    def get_dkim_record(self, domain: str, selector: str = "default") -> str
    def delete_dkim_key(self, domain: str, selector: str = "default") -> bool
    
    def get_status(self) -> Dict
    def test_connection(self) -> bool
```

#### Domain Manager

**Features:**
- Automated domain setup with DNS verification
- Bulk domain operations
- Domain policy management
- Integration with DNS component

**CLI Interface:**
```bash
./automation/domain-manager.sh add example.com "Example Domain" 5120 25 500
./automation/domain-manager.sh list table
./automation/domain-manager.sh dns example.com
./automation/domain-manager.sh check-dns example.com
./automation/domain-manager.sh bulk-add domains.txt
```

#### Mailbox Manager

**Features:**
- Secure mailbox provisioning with automatic password generation
- Bulk mailbox creation
- Quota management and monitoring
- Password security validation

**CLI Interface:**
```bash
./automation/mailbox-manager.sh create user@example.com "" "User Name" 2048
./automation/mailbox-manager.sh list example.com table
./automation/mailbox-manager.sh update user@example.com quota 4096
./automation/mailbox-manager.sh bulk-create mailboxes.csv
```

#### SSL Manager

**Features:**
- Let's Encrypt integration with staging support
- Custom certificate installation
- Automatic renewal and monitoring
- Certificate validation and verification

**CLI Interface:**
```bash
./automation/ssl-manager.sh setup-letsencrypt mail.example.com admin@example.com
./automation/ssl-manager.sh install-custom /path/to/cert.pem /path/to/key.pem
./automation/ssl-manager.sh verify mail.example.com
./automation/ssl-manager.sh renew
```

### Configuration

#### Mailcow Configuration
```yaml
mailcow:
  hostname: ${MAILCOW_HOSTNAME}
  api:
    endpoint: "https://${MAILCOW_HOSTNAME}/api/v1"
    key: ${MAILCOW_API_KEY}
    verify_ssl: true
    timeout: 30
  
  domains:
    default_quota: 5120
    default_mailboxes: 25
    default_aliases: 500
  
  ssl:
    provider: "letsencrypt"
    staging: false
    
  security:
    admin_password_complexity: "high"
    session_timeout: 3600
    failed_login_attempts: 3
```

### Integration Points

- **DNS Component**: Automatic DNS record creation for domains
- **Monitoring Component**: Mail server health monitoring
- **VPS Component**: Server resource monitoring
- **Backup System**: Automated backup integration

## Monitoring Component

### Architecture

The Monitoring Component provides comprehensive system monitoring, alerting, and email campaign management.

```
src/email-infrastructure/monitoring/
├── core/                     # Core monitoring functionality
│   └── monitor_base.py      # Base monitoring classes
├── monitors/                 # Specific monitors
│   └── blacklist_monitor.py # IP blacklist monitoring
├── campaigns/                # Email campaign management
│   ├── warmup_campaigns.py  # Warmup campaign management
│   ├── warmup_scheduler.py  # Campaign scheduling
│   └── warmup_tracker.py    # Campaign tracking and analytics
├── config/                   # Monitoring configuration
├── scripts/                  # Monitoring scripts
├── templates/                # Report templates
├── logs/                     # Log storage
└── reports/                  # Generated reports
```

### Key Features

#### Blacklist Monitor (`monitors/blacklist_monitor.py`)

**Monitoring Capabilities:**
- Real-time IP reputation tracking across multiple blacklist providers
- Automated delisting assistance
- Historical reputation tracking
- Integration with DNS and VPS components

**API Interface:**
```python
class BlacklistMonitor:
    def check_ip_blacklist(self, ip_address: str) -> Dict
    def add_ip_monitoring(self, ip_address: str, domain: str) -> bool
    def remove_ip_monitoring(self, ip_address: str) -> bool
    def get_monitoring_status(self, ip_address: str) -> Dict
    def get_reputation_history(self, ip_address: str, days: int = 30) -> List[Dict]
```

#### Warmup Campaigns (`campaigns/warmup_campaigns.py`)

**Campaign Management:**
- Automated email warmup campaigns
- Progressive sending volume increase
- Multiple campaign strategies
- Performance tracking and optimization

**API Interface:**
```python
class WarmupCampaigns:
    def start_warmup_campaign(self, domain: str, mailboxes: List[str], campaign_type: str = "standard") -> str
    def stop_warmup_campaign(self, campaign_id: str) -> bool
    def get_campaign_status(self, campaign_id: str) -> Dict
    def get_campaign_statistics(self, campaign_id: str) -> Dict
    def list_active_campaigns(self) -> List[Dict]
```

#### Warmup Scheduler (`campaigns/warmup_scheduler.py`)

**Scheduling Features:**
- Intelligent email scheduling based on recipient time zones
- Volume management and rate limiting
- Retry logic for failed sends
- Campaign optimization based on performance metrics

### Configuration

#### Monitoring Configuration
```yaml
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
    
  warmup:
    enabled: true
    campaigns:
      standard:
        initial_daily_limit: 50
        increase_rate: 10
        target_daily_limit: 1000
        duration_days: 30
  
  alerts:
    channels:
      email:
        enabled: true
        recipients: ["admin@example.com"]
      slack:
        enabled: true
        webhook_url: ${SLACK_WEBHOOK_URL}
```

### Integration Points

- **DNS Component**: DNS health monitoring integration
- **Mailcow Component**: Mail server performance monitoring
- **VPS Component**: System resource monitoring
- **Alert System**: Multi-channel notification system

## VPS Management Component

### Architecture

The VPS Component provides server provisioning, configuration, and monitoring capabilities.

```
src/email-infrastructure/vps/
├── core/                     # Core VPS functionality
│   └── vps_manager.py       # Primary VPS operations
├── providers/                # VPS provider integrations
│   ├── hetzner.py           # Hetzner Cloud integration
│   └── digitalocean.py      # DigitalOcean integration
├── scripts/                  # VPS automation scripts
│   ├── setup-vps.sh         # VPS setup and hardening
│   ├── health-check.sh      # System health monitoring
│   └── system-info.sh       # System information collection
├── config/                   # VPS configuration
│   ├── network-config.yaml  # Network configuration
│   ├── firewall-rules.json  # Firewall rules
│   └── alert-thresholds.yaml # Alert thresholds
├── monitoring/               # VPS-specific monitoring
└── logs/                     # VPS operation logs
```

### Key Features

#### VPS Manager (`core/vps_manager.py`)

**Management Capabilities:**
- Multi-provider VPS provisioning (Hetzner, DigitalOcean, AWS)
- Automated server hardening and security configuration
- Resource monitoring and alerting
- Backup and snapshot management

**API Interface:**
```python
class VPSManager:
    def create_vps(self, provider: str, config: Dict) -> Dict
    def delete_vps(self, instance_id: str) -> bool
    def get_vps_info(self, instance_id: str) -> Dict
    def get_system_metrics(self, instance_id: str) -> Dict
    def update_firewall_rules(self, instance_id: str, rules: List[Dict]) -> bool
    def create_snapshot(self, instance_id: str, name: str) -> str
    def restore_snapshot(self, instance_id: str, snapshot_id: str) -> bool
```

#### VPS Setup Script (`scripts/setup-vps.sh`)

**Setup Features:**
- Automated Ubuntu/Debian server setup
- Security hardening (firewall, fail2ban, SSH configuration)
- Docker and Docker Compose installation
- System monitoring setup
- Network configuration optimization

**CLI Interface:**
```bash
./scripts/setup-vps.sh --ip 192.168.1.100 --secure
./scripts/setup-vps.sh --configure-firewall --mailcow --monitoring
./scripts/health-check.sh --ip 192.168.1.100 --detailed
./scripts/system-info.sh --json --output /tmp/system-info.json
```

### Configuration

#### VPS Configuration
```yaml
vps:
  providers:
    hetzner:
      api_token: ${HETZNER_API_TOKEN}
      enabled: true
      regions: ["fsn1", "nbg1", "hel1"]
    
    digitalocean:
      api_token: ${DO_API_TOKEN}
      enabled: false
      regions: ["fra1", "ams3", "nyc3"]
  
  security:
    firewall:
      enabled: true
      default_policy: "DROP"
      rules:
        - port: 22
          protocol: tcp
          source: "0.0.0.0/0"
          action: "ACCEPT"
        - port: [25, 80, 443, 465, 587, 993, 995]
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
```

### Integration Points

- **Monitoring Component**: System resource monitoring
- **DNS Component**: Server IP management
- **Mailcow Component**: Mail server deployment
- **Backup System**: Server backup integration

## Core Infrastructure Layer

### Unified Configuration Manager

**Responsibilities:**
- Hierarchical configuration management (dev/staging/prod)
- Environment variable substitution
- Configuration validation with JSON Schema
- Hot-reload capabilities

### Logging Framework

**Features:**
- Structured logging with JSON output
- Component-specific loggers with correlation IDs
- Multiple output handlers (file, console, syslog)
- Log aggregation and rotation

### Database Layer

**Capabilities:**
- SQLite-based data storage with connection pooling
- Migration system for schema updates
- Backup and restore functionality
- Performance monitoring and optimization

### Security Framework

**Security Features:**
- API key management with rotation
- Password policy enforcement
- Audit logging for all operations
- IP-based access control
- Sensitive data masking in logs

## Inter-Component Communication

### Event Bus System

Components communicate through an event bus for loose coupling:

```python
from email_infrastructure.core.event_bus import EventBus

# DNS component publishes events
EventBus.publish('dns.record.created', {
    'domain': 'example.com',
    'record_type': 'A',
    'record_value': '192.168.1.100'
})

# Monitoring component subscribes to events
@EventBus.subscribe('dns.record.created')
def on_dns_record_created(event_data):
    # Update monitoring for new record
    pass
```

### API Integration

Components expose standardized APIs for cross-component communication:

```python
# DNS Manager API call from Mailcow component
from email_infrastructure.dns.managers.dns_manager import DNSManager

dns_manager = DNSManager()
await dns_manager.create_dns_record('example.com', {
    'type': 'TXT',
    'name': 'default._domainkey.example.com',
    'content': 'v=DKIM1; k=rsa; p=...'
})
```

## Scalability and Performance

### Horizontal Scaling

- **Load Balancing**: API gateway with multiple backend instances
- **Database Sharding**: Domain-based data partitioning
- **Cache Distribution**: Redis cluster for shared caching
- **Queue Systems**: Celery for asynchronous task processing

### Performance Optimization

- **Connection Pooling**: Database and API client connection reuse
- **Caching Strategy**: Multi-layer caching (memory, Redis, CDN)
- **Batch Processing**: Bulk operations for DNS and mailbox management
- **Async Processing**: Non-blocking I/O for external API calls

## Monitoring and Observability

### Health Checks

Each component exposes health check endpoints:

```http
GET /api/v1/dns/health
GET /api/v1/mailcow/health
GET /api/v1/monitoring/health
GET /api/v1/vps/health
```

### Metrics Collection

- **Prometheus**: Metrics collection and storage
- **Grafana**: Visualization and dashboards
- **Custom Metrics**: Component-specific performance metrics
- **Alert Manager**: Intelligent alerting based on metrics

### Distributed Tracing

- **OpenTelemetry**: Distributed request tracing
- **Correlation IDs**: Request tracking across components
- **Performance Profiling**: Bottleneck identification
- **Error Tracking**: Centralized error collection and analysis

This component architecture provides a robust, scalable foundation for the Cold Email Infrastructure system, with clear separation of concerns, standardized interfaces, and comprehensive monitoring capabilities.