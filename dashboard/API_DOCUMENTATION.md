# Cold Email Infrastructure Dashboard API Documentation

This document describes the API endpoints available in the Cold Email Infrastructure Dashboard.

## Base URL

```
http://localhost:5000
```

## Authentication

Most endpoints require an API key for production use. Include it in the request headers:

```
X-API-Key: your-api-key
```

Or as a query parameter:

```
?api_key=your-api-key
```

## Rate Limiting

The API implements rate limiting to prevent abuse:
- Default: 100 requests per hour per IP
- Test endpoints: Limited to 20-50 requests per hour
- Returns 429 status code when limit is exceeded

## API Endpoints

### System Status

#### GET `/api/status`
Get overall system status including DNS, Mailcow, VPS, and email configuration.

**Response:**
```json
{
  "dns": {"status": "success", "message": "...", "data": {...}},
  "mailcow": {"status": "success", "message": "...", "data": {...}},
  "vps": {"status": "success", "message": "...", "data": {...}},
  "email": {"status": "success", "message": "...", "data": {...}},
  "timestamp": "2023-12-07T10:00:00"
}
```

#### GET `/api/health`
Simple health check endpoint.

**Response:**
```json
{
  "status": "healthy",
  "timestamp": "2023-12-07T10:00:00",
  "version": "1.0.0",
  "uptime": "1 day, 2:30:15"
}
```

### Email Testing

#### POST `/api/test-email`
Send a test email with tracking capabilities.

**Request Body:**
```json
{
  "to": "recipient@example.com",
  "from": "sender@example.com",
  "subject": "Test Email",
  "body": "Email content",
  "type": "plain|html",
  "track_delivery": true
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Test email sent successfully",
  "data": {
    "message_id": "test-abc123-1701936000",
    "sent_time": "2023-12-07T10:00:00",
    "delivery_time_ms": 1250
  }
}
```

#### POST `/api/test-smtp`
Test SMTP connection with detailed diagnostics.

**Request Body:**
```json
{
  "host": "mail.example.com",
  "port": 587,
  "security": "tls|ssl|none",
  "username": "user@example.com",
  "password": "password",
  "timeout": 10
}
```

**Response:**
```json
{
  "status": "success",
  "message": "SMTP connection successful",
  "data": {
    "connected": true,
    "authenticated": true,
    "supports_tls": true,
    "supports_auth": true,
    "server_response": "220 mail.example.com ESMTP",
    "features": ["STARTTLS", "AUTH LOGIN PLAIN"],
    "connection_time": 150,
    "errors": []
  }
}
```

### DNS Validation

#### POST `/api/validate-spf`
Validate SPF record for a domain.

**Request Body:**
```json
{
  "domain": "example.com"
}
```

**Response:**
```json
{
  "status": "success",
  "message": "SPF record validated",
  "record": "v=spf1 include:_spf.google.com ~all",
  "issues": []
}
```

#### POST `/api/validate-dkim`
Validate DKIM configuration for a domain.

**Request Body:**
```json
{
  "domain": "example.com",
  "selector": "default"
}
```

**Response:**
```json
{
  "status": "success",
  "message": "DKIM record validated",
  "selector": "default",
  "record": "v=DKIM1; k=rsa; p=MIGfMA0GCS...",
  "issues": []
}
```

#### POST `/api/validate-dmarc`
Validate DMARC policy for a domain.

**Request Body:**
```json
{
  "domain": "example.com"
}
```

**Response:**
```json
{
  "status": "success",
  "message": "DMARC record validated",
  "record": "v=DMARC1; p=quarantine; rua=mailto:dmarc@example.com",
  "policy": "quarantine",
  "issues": []
}
```

### Blacklist Checking

#### POST `/api/check-blacklist`
Check IP address and domain against blacklists.

**Request Body:**
```json
{
  "ip": "192.168.1.100",
  "domain": "example.com"
}
```

**Response:**
```json
{
  "status": "success",
  "data": {
    "ip_blacklists": {
      "spamhaus_sbl": {"listed": false, "message": "..."},
      "spamhaus_css": {"listed": false, "message": "..."}
    },
    "domain_blacklists": {
      "surbl": {"listed": false, "message": "..."},
      "uribl": {"listed": false, "message": "..."}
    }
  },
  "summary": {
    "total_checks": 8,
    "listed_count": 0,
    "clean_count": 8,
    "error_count": 0,
    "reputation_score": 100
  }
}
```

### Email Warmup

#### POST `/api/warmup/start`
Start an email warmup campaign.

**Request Body:**
```json
{
  "fromEmail": "sender@example.com",
  "duration": 30,
  "dailyStart": 5,
  "maxDaily": 100,
  "warmupList": ["warmup1@example.com", "warmup2@example.com"]
}
```

**Response:**
```json
{
  "status": "success",
  "message": "Warmup campaign started successfully",
  "campaign_id": "warmup_abc12345_1701936000",
  "data": {
    "campaign_id": "warmup_abc12345_1701936000",
    "from_email": "sender@example.com",
    "duration": 30,
    "status": "active",
    "current_day": 1,
    "reputation_score": 75
  }
}
```

#### GET `/api/warmup/status`
Get status of the most recent warmup campaign.

#### GET `/api/warmup/campaigns`
List all warmup campaigns.

#### POST `/api/warmup/stop/<campaign_id>`
Stop a specific warmup campaign.

### Metrics and Monitoring

#### GET `/api/metrics`
Get comprehensive system metrics.

**Response:**
```json
{
  "status": "success",
  "data": {
    "system": {
      "cpu": {"percent": 25.5, "load_avg": [0.5, 0.3, 0.2]},
      "memory": {"percent": 45.2, "used_gb": 2.3, "total_gb": 8.0},
      "disk": {"percent": 65.1, "used_gb": 32.5, "total_gb": 50.0},
      "status": "healthy"
    },
    "delivery": {
      "today": 125,
      "delivered": 120,
      "bounced": 3,
      "deferred": 2,
      "success_rate": 96.0
    },
    "queue": {
      "size": 15,
      "status": "running",
      "processing_rate": 45,
      "health_status": "healthy"
    }
  }
}
```

#### GET `/api/queue`
Get email queue status and recent items.

### Queue Management

#### POST `/api/queue/pause`
Pause the email queue.

#### POST `/api/queue/resume`
Resume the email queue.

#### POST `/api/queue/clear`
Clear all items from the email queue.

### Logging and Alerts

#### GET `/api/logs`
Get filtered system logs.

**Query Parameters:**
- `level`: Filter by log level (info, warning, error, all)
- `limit`: Maximum number of logs to return (default: 50)
- `search`: Search term to filter logs
- `start_date`: Start date filter (YYYY-MM-DD)
- `end_date`: End date filter (YYYY-MM-DD)

**Response:**
```json
{
  "status": "success",
  "data": {
    "logs": [
      {
        "id": "uuid",
        "timestamp": "2023-12-07 10:00:00",
        "level": "info",
        "category": "email",
        "message": "Test email sent successfully",
        "source": "email_sender"
      }
    ],
    "summary": {
      "total_logs": 250,
      "filtered_count": 50,
      "level_distribution": {"info": 200, "warning": 30, "error": 20}
    }
  }
}
```

#### DELETE `/api/logs`
Clear all system logs.

#### GET `/api/alerts`
Get system alerts.

#### DELETE `/api/alerts`
Clear all system alerts.

#### POST `/api/alerts/config`
Save alert configuration.

### Configuration

#### GET `/api/config/smtp`
Get SMTP configuration.

#### POST `/api/config/smtp`
Update SMTP configuration (requires manual environment changes).

## Error Responses

All endpoints return errors in a consistent format:

```json
{
  "status": "error",
  "message": "Description of the error"
}
```

Common HTTP status codes:
- `400`: Bad Request (invalid parameters)
- `401`: Unauthorized (missing/invalid API key)
- `404`: Not Found (resource doesn't exist)
- `429`: Too Many Requests (rate limit exceeded)
- `500`: Internal Server Error

## CORS Support

The API includes CORS headers to allow cross-origin requests from web applications.

## Email Tracking

The API includes email tracking functionality:
- Tracking pixels are served from `/api/track/<message_id>`
- Opens are recorded with timestamps and user agent information
- Tracking data is available in system logs

## Production Deployment

For production deployment:

1. Set environment variables from `.env.example`
2. Change default API keys and secrets
3. Configure proper SMTP settings
4. Set `FLASK_ENV=production`
5. Use a production WSGI server (gunicorn, uwsgi)
6. Configure rate limiting and monitoring
7. Set up proper logging and log rotation

## Example Usage

### Python
```python
import requests

# Test SMTP connection
response = requests.post('http://localhost:5000/api/test-smtp', json={
    'host': 'mail.example.com',
    'port': 587,
    'security': 'tls',
    'username': 'user@example.com',
    'password': 'password'
})

print(response.json())
```

### cURL
```bash
# Send test email
curl -X POST http://localhost:5000/api/test-email \
  -H "Content-Type: application/json" \
  -d '{"to": "test@example.com", "subject": "Test", "body": "Hello World"}'

# Check system status
curl http://localhost:5000/api/status
```

### JavaScript
```javascript
// Validate SPF record
fetch('http://localhost:5000/api/validate-spf', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({domain: 'example.com'})
})
.then(response => response.json())
.then(data => console.log(data));
```