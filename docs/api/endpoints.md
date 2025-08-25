# Cold Email Infrastructure - API Reference

## Overview

The Cold Email Infrastructure provides a comprehensive REST API for managing all aspects of the system, including DNS records, mail server configuration, monitoring, and VPS management. The API is built with Python FastAPI and provides OpenAPI/Swagger documentation.

## Authentication

All API endpoints require authentication using API keys. The system supports multiple authentication methods:

### API Key Authentication

```bash
# Include API key in header
curl -H "Authorization: Bearer YOUR_API_KEY" \
     https://your-domain.com/api/v1/dns/domains
```

### Environment Variables

```bash
export EMAIL_INFRA_API_KEY="your_api_key_here"
export EMAIL_INFRA_API_URL="https://your-domain.com/api/v1"
```

## Base URLs

- **Production**: `https://your-domain.com/api/v1`
- **Staging**: `https://staging.your-domain.com/api/v1`
- **Development**: `http://localhost:8000/api/v1`

## API Endpoints

### DNS Management API

#### List DNS Records

Get all DNS records for a domain.

```http
GET /api/v1/dns/domains/{domain}/records
```

**Parameters:**
- `domain` (string, required): Target domain name
- `record_type` (string, optional): Filter by record type (A, MX, TXT, etc.)
- `limit` (integer, optional): Number of records to return (default: 100)
- `offset` (integer, optional): Pagination offset (default: 0)

**Example Request:**
```bash
curl -H "Authorization: Bearer $API_KEY" \
     "$API_URL/dns/domains/example.com/records?record_type=A"
```

**Example Response:**
```json
{
  "success": true,
  "data": {
    "domain": "example.com",
    "records": [
      {
        "id": "record_id_123",
        "type": "A",
        "name": "example.com",
        "content": "192.168.1.100",
        "ttl": 300,
        "created_on": "2024-01-01T00:00:00Z",
        "modified_on": "2024-01-01T00:00:00Z"
      }
    ],
    "total_count": 15,
    "pagination": {
      "limit": 100,
      "offset": 0,
      "has_more": false
    }
  }
}
```

#### Create DNS Record

Create a new DNS record for a domain.

```http
POST /api/v1/dns/domains/{domain}/records
```

**Parameters:**
- `domain` (string, required): Target domain name

**Request Body:**
```json
{
  "type": "A",
  "name": "mail.example.com",
  "content": "192.168.1.100",
  "ttl": 300,
  "priority": 10
}
```

**Example Request:**
```bash
curl -X POST \
     -H "Authorization: Bearer $API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"type":"A","name":"mail.example.com","content":"192.168.1.100","ttl":300}' \
     "$API_URL/dns/domains/example.com/records"
```

**Example Response:**
```json
{
  "success": true,
  "data": {
    "id": "new_record_id_456",
    "type": "A",
    "name": "mail.example.com",
    "content": "192.168.1.100",
    "ttl": 300,
    "created_on": "2024-01-01T12:00:00Z"
  }
}
```

#### Update DNS Record

Update an existing DNS record.

```http
PUT /api/v1/dns/domains/{domain}/records/{record_id}
```

**Parameters:**
- `domain` (string, required): Target domain name
- `record_id` (string, required): DNS record ID

**Request Body:**
```json
{
  "content": "192.168.1.101",
  "ttl": 600
}
```

#### Delete DNS Record

Delete a DNS record.

```http
DELETE /api/v1/dns/domains/{domain}/records/{record_id}
```

#### Bulk DNS Operations

Create multiple DNS records at once.

```http
POST /api/v1/dns/domains/{domain}/records/bulk
```

**Request Body:**
```json
{
  "records": [
    {
      "type": "A",
      "name": "example.com",
      "content": "192.168.1.100",
      "ttl": 300
    },
    {
      "type": "MX",
      "name": "example.com",
      "content": "mail.example.com",
      "priority": 10,
      "ttl": 300
    }
  ]
}
```

#### DNS Verification

Verify DNS record propagation.

```http
GET /api/v1/dns/verify/{domain}
```

**Parameters:**
- `domain` (string, required): Domain to verify
- `record_type` (string, optional): Specific record type to verify
- `expected_value` (string, optional): Expected record value

**Example Response:**
```json
{
  "success": true,
  "data": {
    "domain": "example.com",
    "verification_results": {
      "a_record": {
        "status": "verified",
        "expected": "192.168.1.100",
        "actual": "192.168.1.100",
        "propagated": true,
        "nameservers_checked": 8,
        "nameservers_confirmed": 8
      },
      "mx_record": {
        "status": "verified",
        "expected": "mail.example.com",
        "actual": "mail.example.com",
        "propagated": true
      }
    },
    "overall_status": "verified"
  }
}
```

### Mailcow Management API

#### List Domains

Get all configured mail domains.

```http
GET /api/v1/mailcow/domains
```

**Example Response:**
```json
{
  "success": true,
  "data": {
    "domains": [
      {
        "domain_name": "example.com",
        "description": "Example Domain",
        "aliases": 0,
        "mailboxes": 5,
        "quota": 5120,
        "bytes_total": 10737418240,
        "msgs_total": 1234,
        "active": 1,
        "created": "2024-01-01 00:00:00"
      }
    ]
  }
}
```

#### Create Domain

Add a new mail domain.

```http
POST /api/v1/mailcow/domains
```

**Request Body:**
```json
{
  "domain": "example.com",
  "description": "Example Domain",
  "quota": 5120,
  "mailboxes": 25,
  "aliases": 500,
  "active": true
}
```

#### List Mailboxes

Get mailboxes for a domain.

```http
GET /api/v1/mailcow/domains/{domain}/mailboxes
```

**Example Response:**
```json
{
  "success": true,
  "data": {
    "mailboxes": [
      {
        "username": "user@example.com",
        "name": "User Name",
        "active": 1,
        "domain": "example.com",
        "local_part": "user",
        "quota": 2048,
        "bytes": 1048576,
        "messages": 42,
        "created": "2024-01-01 00:00:00",
        "last_imap_login": "2024-01-15 14:30:00"
      }
    ]
  }
}
```

#### Create Mailbox

Create a new mailbox.

```http
POST /api/v1/mailcow/mailboxes
```

**Request Body:**
```json
{
  "local_part": "user",
  "domain": "example.com",
  "name": "User Name",
  "password": "SecurePassword123!",
  "quota": 2048,
  "active": true
}
```

#### Generate DKIM Keys

Generate DKIM keys for a domain.

```http
POST /api/v1/mailcow/domains/{domain}/dkim
```

**Request Body:**
```json
{
  "key_size": 2048,
  "selector": "default"
}
```

**Example Response:**
```json
{
  "success": true,
  "data": {
    "domain": "example.com",
    "selector": "default",
    "dkim_record": "v=DKIM1; k=rsa; p=MIIBIjANBgkq...",
    "dns_record": {
      "type": "TXT",
      "name": "default._domainkey.example.com",
      "value": "v=DKIM1; k=rsa; p=MIIBIjANBgkq..."
    }
  }
}
```

### Monitoring API

#### System Status

Get overall system status.

```http
GET /api/v1/monitoring/status
```

**Example Response:**
```json
{
  "success": true,
  "data": {
    "overall_status": "healthy",
    "components": {
      "dns": {
        "status": "healthy",
        "last_check": "2024-01-15T14:30:00Z",
        "response_time": 45
      },
      "mailcow": {
        "status": "healthy",
        "containers": {
          "postfix": "running",
          "dovecot": "running",
          "nginx": "running",
          "mysql": "running"
        }
      },
      "monitoring": {
        "status": "healthy",
        "active_monitors": 5,
        "failed_checks": 0
      }
    },
    "uptime": "15d 4h 23m",
    "timestamp": "2024-01-15T14:30:00Z"
  }
}
```

#### Blacklist Check

Check IP blacklist status.

```http
GET /api/v1/monitoring/blacklist/{ip_address}
```

**Example Response:**
```json
{
  "success": true,
  "data": {
    "ip_address": "192.168.1.100",
    "status": "clean",
    "checks": [
      {
        "provider": "spamhaus",
        "status": "clean",
        "checked_at": "2024-01-15T14:30:00Z",
        "response_time": 234
      },
      {
        "provider": "barracuda",
        "status": "clean",
        "checked_at": "2024-01-15T14:30:00Z",
        "response_time": 156
      }
    ],
    "overall_score": 10,
    "last_check": "2024-01-15T14:30:00Z"
  }
}
```

#### Start Monitoring

Start monitoring for a domain or IP.

```http
POST /api/v1/monitoring/start
```

**Request Body:**
```json
{
  "type": "domain",
  "target": "example.com",
  "checks": ["dns", "blacklist", "ssl"],
  "interval": 300
}
```

#### Get Monitoring Reports

Retrieve monitoring reports.

```http
GET /api/v1/monitoring/reports
```

**Parameters:**
- `start_date` (string, optional): Start date (ISO format)
- `end_date` (string, optional): End date (ISO format)
- `type` (string, optional): Report type (summary, detailed, alerts)

### VPS Management API

#### List VPS Instances

Get all managed VPS instances.

```http
GET /api/v1/vps/instances
```

**Example Response:**
```json
{
  "success": true,
  "data": {
    "instances": [
      {
        "id": "vps_123",
        "name": "mail-server-1",
        "provider": "hetzner",
        "ip_address": "192.168.1.100",
        "status": "running",
        "created": "2024-01-01T00:00:00Z",
        "specs": {
          "cpu": 4,
          "memory": 8192,
          "disk": 160,
          "location": "fsn1"
        }
      }
    ]
  }
}
```

#### Create VPS Instance

Create a new VPS instance.

```http
POST /api/v1/vps/instances
```

**Request Body:**
```json
{
  "name": "mail-server-2",
  "provider": "hetzner",
  "server_type": "cx31",
  "location": "fsn1",
  "image": "ubuntu-22.04",
  "ssh_keys": ["ssh-key-id"],
  "user_data": "#!/bin/bash\napt update && apt upgrade -y"
}
```

#### VPS System Information

Get system information for a VPS.

```http
GET /api/v1/vps/instances/{instance_id}/info
```

**Example Response:**
```json
{
  "success": true,
  "data": {
    "instance_id": "vps_123",
    "system_info": {
      "cpu_usage": 23.5,
      "memory_usage": 67.2,
      "disk_usage": 45.8,
      "load_average": [1.2, 1.5, 1.8],
      "uptime": "15d 4h 23m",
      "network": {
        "bytes_sent": 1234567890,
        "bytes_recv": 9876543210,
        "packets_sent": 123456,
        "packets_recv": 987654
      }
    }
  }
}
```

### Warmup Campaign API

#### List Campaigns

Get all warmup campaigns.

```http
GET /api/v1/warmup/campaigns
```

#### Create Campaign

Create a new warmup campaign.

```http
POST /api/v1/warmup/campaigns
```

**Request Body:**
```json
{
  "domain": "example.com",
  "mailboxes": ["user1@example.com", "user2@example.com"],
  "campaign_type": "standard",
  "initial_daily_limit": 50,
  "target_daily_limit": 1000,
  "increase_rate": 10,
  "duration_days": 30
}
```

#### Campaign Statistics

Get campaign performance statistics.

```http
GET /api/v1/warmup/campaigns/{campaign_id}/stats
```

## Python SDK

The system provides a Python SDK for easy API integration:

### Installation

```bash
pip install cold-email-infrastructure-sdk
```

### Basic Usage

```python
from email_infrastructure.api import EmailInfraAPI

# Initialize API client
api = EmailInfraAPI(
    api_key="your_api_key",
    base_url="https://your-domain.com/api/v1"
)

# DNS operations
domains = api.dns.list_domains()
record = api.dns.create_record("example.com", {
    "type": "A",
    "name": "mail.example.com",
    "content": "192.168.1.100",
    "ttl": 300
})

# Mailcow operations
domain = api.mailcow.create_domain("example.com", {
    "description": "Example Domain",
    "quota": 5120
})

mailbox = api.mailcow.create_mailbox("user@example.com", {
    "name": "User Name",
    "password": "SecurePassword123!",
    "quota": 2048
})

# Monitoring operations
status = api.monitoring.get_status()
blacklist_check = api.monitoring.check_blacklist("192.168.1.100")

# VPS operations
instances = api.vps.list_instances()
system_info = api.vps.get_system_info("vps_123")
```

### Advanced Usage

```python
# Bulk DNS operations
records = [
    {"type": "A", "name": "example.com", "content": "192.168.1.100"},
    {"type": "MX", "name": "example.com", "content": "mail.example.com", "priority": 10}
]
result = api.dns.create_records_bulk("example.com", records)

# Async operations
import asyncio

async def async_operations():
    # Async DNS verification
    verification = await api.dns.verify_domain_async("example.com")
    
    # Async monitoring
    monitors = await api.monitoring.start_monitoring_async([
        {"type": "domain", "target": "example.com"},
        {"type": "ip", "target": "192.168.1.100"}
    ])
    
    return verification, monitors

# Run async operations
verification, monitors = asyncio.run(async_operations())
```

## CLI Integration

The API can be accessed via command-line tools:

### DNS Management CLI

```bash
# List DNS records
email-infra dns list example.com

# Create DNS record
email-infra dns create example.com A mail.example.com 192.168.1.100

# Verify DNS
email-infra dns verify example.com
```

### Mailcow Management CLI

```bash
# List domains
email-infra mailcow domains list

# Create domain
email-infra mailcow domain create example.com --quota 5120

# Create mailbox
email-infra mailcow mailbox create user@example.com --name "User Name"

# Generate DKIM
email-infra mailcow dkim generate example.com
```

### Monitoring CLI

```bash
# System status
email-infra monitoring status

# Blacklist check
email-infra monitoring blacklist check 192.168.1.100

# Start monitoring
email-infra monitoring start domain example.com
```

## Error Handling

### HTTP Status Codes

- `200`: Success
- `201`: Created
- `400`: Bad Request
- `401`: Unauthorized
- `403`: Forbidden
- `404`: Not Found
- `409`: Conflict
- `429`: Rate Limited
- `500`: Internal Server Error

### Error Response Format

```json
{
  "success": false,
  "error": {
    "code": "INVALID_DOMAIN",
    "message": "The specified domain is not valid",
    "details": {
      "domain": "invalid.domain",
      "reason": "Domain not found in Cloudflare"
    }
  },
  "timestamp": "2024-01-15T14:30:00Z",
  "request_id": "req_123456"
}
```

### Common Error Codes

- `INVALID_API_KEY`: Invalid or expired API key
- `RATE_LIMITED`: Too many requests
- `DOMAIN_NOT_FOUND`: Domain not found
- `RECORD_NOT_FOUND`: DNS record not found
- `MAILBOX_EXISTS`: Mailbox already exists
- `QUOTA_EXCEEDED`: Quota limit exceeded
- `VALIDATION_ERROR`: Request validation failed

## Rate Limiting

The API implements rate limiting to ensure fair usage:

- **Default Limit**: 100 requests per hour per API key
- **Burst Limit**: 20 requests per minute
- **Headers**: Rate limit information in response headers

```http
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 95
X-RateLimit-Reset: 1642248000
```

## Webhooks

Configure webhooks to receive real-time notifications:

### Webhook Configuration

```json
{
  "url": "https://your-app.com/webhooks/email-infra",
  "events": ["dns.record.created", "mailbox.created", "monitoring.alert"],
  "secret": "your_webhook_secret"
}
```

### Webhook Payload

```json
{
  "event": "dns.record.created",
  "data": {
    "domain": "example.com",
    "record": {
      "type": "A",
      "name": "mail.example.com",
      "content": "192.168.1.100"
    }
  },
  "timestamp": "2024-01-15T14:30:00Z",
  "signature": "sha256=..."
}
```

## API Versioning

The API uses semantic versioning with URL-based versioning:

- **Current Version**: v1
- **Base URL**: `/api/v1`
- **Deprecation Policy**: 6 months notice before breaking changes

## OpenAPI/Swagger Documentation

Interactive API documentation is available at:

- **Swagger UI**: `https://your-domain.com/api/docs`
- **ReDoc**: `https://your-domain.com/api/redoc`
- **OpenAPI Schema**: `https://your-domain.com/api/openapi.json`

For additional API support and examples, see the [Developer Guide](../development/developer-guide.md).