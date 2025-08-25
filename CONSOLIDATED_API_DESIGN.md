# Consolidated API Client Library Design

## Overview

This design consolidates the multiple API client implementations found across the codebase into a unified, reusable API client framework. Currently, there are separate implementations for Cloudflare API, Mailcow API, monitoring APIs, and various other services, each with duplicated functionality for authentication, rate limiting, retries, and error handling.

## Current API Client Duplication Analysis

### Identified API Clients:
1. **CloudflareAPI** (`dns-manager.py`) - DNS management with 500+ lines
2. **MailcowAPI** (`mailcow-api.py`) - Email server management with 300+ lines
3. **Monitoring APIs** - Multiple files with blacklist checking, warmup tracking
4. **Claude-flow API clients** - AI service integrations scattered across TypeScript

### Duplicated Patterns Found:
```python
# Pattern repeated across all API clients:
self.session = requests.Session()
self.session.headers.update({
    'Authorization': f'Bearer {api_token}',
    'Content-Type': 'application/json'
})

# Rate limiting logic (duplicated):
await asyncio.sleep(self.rate_limit_delay)
if response.status_code == 429:
    retry_after = int(response.headers.get('Retry-After', 5))
    await asyncio.sleep(retry_after)

# Retry logic (duplicated):
if retry_count < self.config['retry']['max_attempts']:
    delay = self.config['retry']['backoff_factor'] ** retry_count
    await asyncio.sleep(delay)
    return await self._make_request(method, endpoint, data, params, retry_count + 1)

# Error handling (inconsistent):
if not result.get('success', False):
    errors = result.get('errors', [])
    error_msg = '; '.join([error.get('message', str(error)) for error in errors])
    raise CustomAPIError(f"API Error: {error_msg}")
```

## Consolidated API Framework Architecture

### Directory Structure
```
/src/common/api/
├── __init__.py                      # Public API exports
├── base/
│   ├── __init__.py
│   ├── client.py                    # BaseAPIClient class
│   ├── auth.py                      # Authentication handlers
│   ├── rate_limiter.py              # Rate limiting implementation
│   ├── retry_handler.py             # Retry logic with backoff
│   └── response_handler.py          # Response parsing and validation
├── exceptions/
│   ├── __init__.py
│   ├── base.py                      # Base API exceptions
│   ├── auth.py                      # Authentication exceptions
│   ├── rate_limit.py                # Rate limiting exceptions
│   └── network.py                   # Network-related exceptions
├── clients/
│   ├── __init__.py
│   ├── cloudflare.py                # Cloudflare API client
│   ├── mailcow.py                   # Mailcow API client
│   ├── monitoring.py                # Monitoring services client
│   └── blacklist.py                 # Blacklist checking services
├── middleware/
│   ├── __init__.py
│   ├── logging.py                   # Request/response logging
│   ├── metrics.py                   # Performance metrics collection
│   ├── caching.py                   # Response caching
│   └── validation.py                # Request/response validation
└── utils/
    ├── __init__.py
    ├── url_builder.py               # URL construction utilities
    ├── serializers.py               # Data serialization helpers
    └── pagination.py                # Pagination handling
```

## Base API Client Implementation

### Core Base Client (`base/client.py`)
```python
#!/usr/bin/env python3
"""
Base API Client
Unified foundation for all API integrations
"""

import asyncio
import json
import time
from abc import ABC, abstractmethod
from typing import Dict, Any, Optional, List, Union, Callable
from dataclasses import dataclass, field
from urllib.parse import urljoin, urlparse
import aiohttp
import logging

from ..exceptions.base import APIError, NetworkError, AuthenticationError
from ..middleware.logging import RequestLogger
from ..middleware.metrics import MetricsCollector
from .auth import AuthenticationHandler
from .rate_limiter import RateLimiter
from .retry_handler import RetryHandler
from .response_handler import ResponseHandler

@dataclass
class APIConfig:
    """Configuration for API client"""
    base_url: str
    timeout: int = 30
    max_retries: int = 3
    backoff_factor: float = 2.0
    rate_limit: Optional[Dict[str, Any]] = None
    auth: Optional[Dict[str, Any]] = None
    headers: Dict[str, str] = field(default_factory=dict)
    verify_ssl: bool = True
    enable_logging: bool = True
    enable_metrics: bool = True
    enable_caching: bool = False
    cache_ttl: int = 300

class BaseAPIClient(ABC):
    """
    Base API client providing common functionality
    All specific API clients should inherit from this class
    """
    
    def __init__(self, config: APIConfig):
        self.config = config
        self.logger = logging.getLogger(f"{self.__class__.__module__}.{self.__class__.__name__}")
        
        # Initialize components
        self.auth_handler = AuthenticationHandler(config.auth) if config.auth else None
        self.rate_limiter = RateLimiter(config.rate_limit) if config.rate_limit else None
        self.retry_handler = RetryHandler(config.max_retries, config.backoff_factor)
        self.response_handler = ResponseHandler()
        
        # Initialize middleware
        self.middlewares = []
        if config.enable_logging:
            self.middlewares.append(RequestLogger(self.logger))
        if config.enable_metrics:
            self.middlewares.append(MetricsCollector())
        
        # Session configuration
        self.session: Optional[aiohttp.ClientSession] = None
        self._session_lock = asyncio.Lock()
        
    async def __aenter__(self):
        await self._ensure_session()
        return self
        
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        await self.close()
        
    async def _ensure_session(self):
        """Ensure aiohttp session is created and configured"""
        if self.session is None or self.session.closed:
            async with self._session_lock:
                if self.session is None or self.session.closed:
                    # Build headers
                    headers = {
                        'User-Agent': f'EmailInfrastructure-APIClient/1.0',
                        'Accept': 'application/json',
                        **self.config.headers
                    }
                    
                    # Add authentication headers if configured
                    if self.auth_handler:
                        auth_headers = await self.auth_handler.get_headers()
                        headers.update(auth_headers)
                    
                    # Create timeout configuration
                    timeout = aiohttp.ClientTimeout(total=self.config.timeout)
                    
                    # Create SSL context
                    ssl_context = None if self.config.verify_ssl else False
                    
                    # Create session
                    self.session = aiohttp.ClientSession(
                        headers=headers,
                        timeout=timeout,
                        connector=aiohttp.TCPConnector(ssl=ssl_context),
                        raise_for_status=False
                    )
    
    async def request(self, 
                     method: str, 
                     endpoint: str, 
                     data: Optional[Dict] = None,
                     params: Optional[Dict] = None,
                     headers: Optional[Dict] = None,
                     **kwargs) -> Dict[str, Any]:
        """
        Make HTTP request with full middleware support
        
        Args:
            method: HTTP method (GET, POST, PUT, DELETE, etc.)
            endpoint: API endpoint (relative to base_url)
            data: Request body data
            params: Query parameters
            headers: Additional headers
            **kwargs: Additional arguments passed to aiohttp
            
        Returns:
            Parsed response data
            
        Raises:
            APIError: For API-specific errors
            NetworkError: For network-related errors
            AuthenticationError: For authentication failures
        """
        await self._ensure_session()
        
        # Build full URL
        url = self._build_url(endpoint)
        
        # Prepare request data
        request_data = {
            'method': method.upper(),
            'url': url,
            'headers': headers or {},
            'params': params,
            **kwargs
        }
        
        # Handle request body based on content type
        if data is not None:
            if isinstance(data, (dict, list)):
                request_data['json'] = data
            else:
                request_data['data'] = data
        
        # Apply rate limiting
        if self.rate_limiter:
            await self.rate_limiter.acquire()
        
        # Execute request with retry logic
        return await self.retry_handler.execute(
            self._execute_request_with_middleware,
            request_data
        )
    
    async def _execute_request_with_middleware(self, request_data: Dict) -> Dict[str, Any]:
        """Execute request with middleware chain"""
        # Pre-request middleware
        for middleware in self.middlewares:
            if hasattr(middleware, 'before_request'):
                request_data = await middleware.before_request(request_data)
        
        start_time = time.time()
        
        try:
            # Execute the actual request
            async with self.session.request(**request_data) as response:
                # Read response data
                try:
                    response_data = await response.json()
                except (json.JSONDecodeError, aiohttp.ContentTypeError):
                    response_data = await response.text()
                
                # Create response context
                response_context = {
                    'status_code': response.status,
                    'headers': dict(response.headers),
                    'data': response_data,
                    'url': str(response.url),
                    'method': request_data['method'],
                    'duration': time.time() - start_time
                }
                
                # Post-request middleware
                for middleware in self.middlewares:
                    if hasattr(middleware, 'after_request'):
                        response_context = await middleware.after_request(
                            request_data, response_context
                        )
                
                # Handle response based on status code
                if response.status == 401:
                    raise AuthenticationError("Authentication failed")
                elif response.status == 429:
                    retry_after = int(response.headers.get('Retry-After', 60))
                    await asyncio.sleep(retry_after)
                    raise NetworkError(f"Rate limited, retry after {retry_after} seconds")
                elif response.status >= 500:
                    raise NetworkError(f"Server error: {response.status}")
                elif response.status >= 400:
                    error_msg = self._extract_error_message(response_data)
                    raise APIError(f"Client error {response.status}: {error_msg}")
                
                # Process successful response
                return self.response_handler.process_response(response_context)
                
        except aiohttp.ClientError as e:
            raise NetworkError(f"Network error: {str(e)}")
        except asyncio.TimeoutError:
            raise NetworkError("Request timeout")
    
    def _build_url(self, endpoint: str) -> str:
        """Build full URL from base URL and endpoint"""
        # Remove leading slash from endpoint to avoid double slashes
        endpoint = endpoint.lstrip('/')
        # Ensure base URL ends with slash for proper joining
        base_url = self.config.base_url.rstrip('/') + '/'
        return urljoin(base_url, endpoint)
    
    def _extract_error_message(self, response_data: Any) -> str:
        """Extract error message from response data"""
        if isinstance(response_data, dict):
            # Try common error message fields
            for field in ['message', 'error', 'detail', 'msg']:
                if field in response_data:
                    return str(response_data[field])
            
            # Try nested error structures
            if 'errors' in response_data:
                errors = response_data['errors']
                if isinstance(errors, list) and errors:
                    if isinstance(errors[0], dict):
                        return errors[0].get('message', str(errors[0]))
                    return str(errors[0])
                elif isinstance(errors, dict):
                    return str(errors.get('message', errors))
        
        return str(response_data)
    
    async def close(self):
        """Close the HTTP session"""
        if self.session and not self.session.closed:
            await self.session.close()
    
    # Convenience methods for common HTTP verbs
    async def get(self, endpoint: str, params: Optional[Dict] = None, **kwargs) -> Dict[str, Any]:
        """Convenience method for GET requests"""
        return await self.request('GET', endpoint, params=params, **kwargs)
    
    async def post(self, endpoint: str, data: Optional[Dict] = None, **kwargs) -> Dict[str, Any]:
        """Convenience method for POST requests"""
        return await self.request('POST', endpoint, data=data, **kwargs)
    
    async def put(self, endpoint: str, data: Optional[Dict] = None, **kwargs) -> Dict[str, Any]:
        """Convenience method for PUT requests"""
        return await self.request('PUT', endpoint, data=data, **kwargs)
    
    async def patch(self, endpoint: str, data: Optional[Dict] = None, **kwargs) -> Dict[str, Any]:
        """Convenience method for PATCH requests"""
        return await self.request('PATCH', endpoint, data=data, **kwargs)
    
    async def delete(self, endpoint: str, **kwargs) -> Dict[str, Any]:
        """Convenience method for DELETE requests"""
        return await self.request('DELETE', endpoint, **kwargs)
    
    # Abstract methods for subclasses to implement
    @abstractmethod
    def get_client_name(self) -> str:
        """Return the name of the API client"""
        pass
    
    @abstractmethod  
    def get_api_version(self) -> str:
        """Return the API version this client supports"""
        pass
```

### Authentication Handler (`base/auth.py`)
```python
#!/usr/bin/env python3
"""
Authentication Handler
Supports multiple authentication methods for API clients
"""

import base64
import hashlib
import hmac
import time
from abc import ABC, abstractmethod
from typing import Dict, Any, Optional
from dataclasses import dataclass

class AuthenticationHandler(ABC):
    """Base authentication handler"""
    
    @abstractmethod
    async def get_headers(self) -> Dict[str, str]:
        """Return authentication headers"""
        pass

class BearerTokenAuth(AuthenticationHandler):
    """Bearer token authentication"""
    
    def __init__(self, token: str):
        self.token = token
    
    async def get_headers(self) -> Dict[str, str]:
        return {'Authorization': f'Bearer {self.token}'}

class APIKeyAuth(AuthenticationHandler):
    """API key authentication"""
    
    def __init__(self, api_key: str, header_name: str = 'X-API-Key'):
        self.api_key = api_key
        self.header_name = header_name
    
    async def get_headers(self) -> Dict[str, str]:
        return {self.header_name: self.api_key}

class BasicAuth(AuthenticationHandler):
    """Basic authentication"""
    
    def __init__(self, username: str, password: str):
        self.username = username
        self.password = password
    
    async def get_headers(self) -> Dict[str, str]:
        credentials = base64.b64encode(f'{self.username}:{self.password}'.encode()).decode()
        return {'Authorization': f'Basic {credentials}'}

class HMACAuth(AuthenticationHandler):
    """HMAC authentication for secure API access"""
    
    def __init__(self, key_id: str, secret_key: str, algorithm: str = 'sha256'):
        self.key_id = key_id
        self.secret_key = secret_key.encode()
        self.algorithm = algorithm
    
    async def get_headers(self) -> Dict[str, str]:
        timestamp = str(int(time.time()))
        message = f'{self.key_id}{timestamp}'
        signature = hmac.new(
            self.secret_key,
            message.encode(),
            getattr(hashlib, self.algorithm)
        ).hexdigest()
        
        return {
            'Authorization': f'HMAC-{self.algorithm.upper()} {self.key_id}:{timestamp}:{signature}',
            'X-Timestamp': timestamp
        }

# Factory function for creating authentication handlers
def create_auth_handler(auth_config: Dict[str, Any]) -> Optional[AuthenticationHandler]:
    """Create authentication handler based on configuration"""
    if not auth_config:
        return None
    
    auth_type = auth_config.get('type', '').lower()
    
    if auth_type == 'bearer':
        return BearerTokenAuth(auth_config['token'])
    elif auth_type == 'api_key':
        return APIKeyAuth(
            auth_config['api_key'],
            auth_config.get('header_name', 'X-API-Key')
        )
    elif auth_type == 'basic':
        return BasicAuth(auth_config['username'], auth_config['password'])
    elif auth_type == 'hmac':
        return HMACAuth(
            auth_config['key_id'],
            auth_config['secret_key'],
            auth_config.get('algorithm', 'sha256')
        )
    else:
        raise ValueError(f"Unsupported authentication type: {auth_type}")
```

### Rate Limiter (`base/rate_limiter.py`)
```python
#!/usr/bin/env python3
"""
Rate Limiter
Token bucket algorithm implementation for API rate limiting
"""

import asyncio
import time
from typing import Dict, Any, Optional

class RateLimiter:
    """Token bucket rate limiter"""
    
    def __init__(self, config: Dict[str, Any]):
        self.requests_per_second = config.get('requests_per_second', 10)
        self.burst_limit = config.get('burst_limit', 20)
        self.tokens = self.burst_limit
        self.last_update = time.time()
        self._lock = asyncio.Lock()
    
    async def acquire(self, tokens: int = 1) -> None:
        """Acquire tokens for rate limiting"""
        async with self._lock:
            now = time.time()
            time_passed = now - self.last_update
            
            # Add tokens based on time passed
            tokens_to_add = time_passed * self.requests_per_second
            self.tokens = min(self.burst_limit, self.tokens + tokens_to_add)
            self.last_update = now
            
            if self.tokens >= tokens:
                self.tokens -= tokens
            else:
                # Calculate wait time
                wait_time = (tokens - self.tokens) / self.requests_per_second
                await asyncio.sleep(wait_time)
                self.tokens = max(0, self.tokens - tokens)
```

## Specific API Client Implementations

### Cloudflare API Client (`clients/cloudflare.py`)
```python
#!/usr/bin/env python3
"""
Cloudflare API Client
Unified client for all Cloudflare API operations
"""

from typing import Dict, Any, List, Optional
from ..base.client import BaseAPIClient, APIConfig
from ..exceptions.base import APIError

class CloudflareClient(BaseAPIClient):
    """Cloudflare API client with all DNS management functionality"""
    
    def __init__(self, api_token: str, **kwargs):
        config = APIConfig(
            base_url="https://api.cloudflare.com/client/v4",
            auth={
                'type': 'bearer',
                'token': api_token
            },
            rate_limit={
                'requests_per_second': 4,
                'burst_limit': 10
            },
            max_retries=3,
            **kwargs
        )
        super().__init__(config)
        self._zones_cache: Dict[str, str] = {}
    
    def get_client_name(self) -> str:
        return "CloudflareClient"
    
    def get_api_version(self) -> str:
        return "v4"
    
    async def get_zones(self, force_refresh: bool = False) -> Dict[str, str]:
        """Get all zones (domain -> zone_id mapping)"""
        if not force_refresh and self._zones_cache:
            return self._zones_cache
        
        zones = {}
        page = 1
        per_page = 50
        
        while True:
            response = await self.get('/zones', params={
                'page': page,
                'per_page': per_page
            })
            
            for zone in response['result']:
                zones[zone['name']] = zone['id']
            
            # Check if there are more pages
            result_info = response.get('result_info', {})
            if page >= result_info.get('total_pages', 1):
                break
            
            page += 1
        
        self._zones_cache = zones
        return zones
    
    async def get_zone_id(self, domain: str) -> str:
        """Get zone ID for a domain"""
        zones = await self.get_zones()
        
        # Try exact match first
        if domain in zones:
            return zones[domain]
        
        # Try to find parent domain
        parts = domain.split('.')
        for i in range(1, len(parts)):
            parent_domain = '.'.join(parts[i:])
            if parent_domain in zones:
                return zones[parent_domain]
        
        raise APIError(f"Zone not found for domain: {domain}")
    
    async def list_dns_records(self, domain: str, record_type: str = None, 
                             name: str = None) -> List[Dict]:
        """List DNS records for a domain"""
        zone_id = await self.get_zone_id(domain)
        
        params = {'per_page': 100}
        if record_type:
            params['type'] = record_type
        if name:
            params['name'] = name
        
        all_records = []
        page = 1
        
        while True:
            params['page'] = page
            response = await self.get(f'/zones/{zone_id}/dns_records', params=params)
            
            records = response['result']
            all_records.extend(records)
            
            # Check if there are more pages
            result_info = response.get('result_info', {})
            if page >= result_info.get('total_pages', 1):
                break
            
            page += 1
        
        return all_records
    
    async def create_dns_record(self, domain: str, record_data: Dict) -> Dict:
        """Create a DNS record"""
        zone_id = await self.get_zone_id(domain)
        
        response = await self.post(f'/zones/{zone_id}/dns_records', data=record_data)
        return response['result']
    
    async def update_dns_record(self, domain: str, record_id: str, record_data: Dict) -> Dict:
        """Update a DNS record"""
        zone_id = await self.get_zone_id(domain)
        
        response = await self.patch(f'/zones/{zone_id}/dns_records/{record_id}', 
                                  data=record_data)
        return response['result']
    
    async def delete_dns_record(self, domain: str, record_id: str) -> bool:
        """Delete a DNS record"""
        zone_id = await self.get_zone_id(domain)
        
        await self.delete(f'/zones/{zone_id}/dns_records/{record_id}')
        return True
    
    async def bulk_create_records(self, domain: str, records: List[Dict]) -> List[Dict]:
        """Create multiple DNS records"""
        results = []
        
        for record in records:
            try:
                result = await self.create_dns_record(domain, record)
                results.append(result)
            except Exception as e:
                results.append({'error': str(e), 'record': record})
        
        return results
```

### Mailcow API Client (`clients/mailcow.py`)
```python
#!/usr/bin/env python3
"""
Mailcow API Client
Unified client for Mailcow server management
"""

from typing import Dict, Any, List, Optional
from ..base.client import BaseAPIClient, APIConfig

class MailcowClient(BaseAPIClient):
    """Mailcow API client for email server management"""
    
    def __init__(self, hostname: str, api_key: str, verify_ssl: bool = True, **kwargs):
        config = APIConfig(
            base_url=f"https://{hostname}/api/v1",
            auth={
                'type': 'api_key',
                'api_key': api_key,
                'header_name': 'X-API-Key'
            },
            verify_ssl=verify_ssl,
            **kwargs
        )
        super().__init__(config)
    
    def get_client_name(self) -> str:
        return "MailcowClient"
    
    def get_api_version(self) -> str:
        return "v1"
    
    async def get_domains(self) -> List[Dict]:
        """Get all domains"""
        response = await self.get('/get/domain/all')
        return response.get('data', [])
    
    async def add_domain(self, domain_data: Dict) -> Dict:
        """Add a new domain"""
        response = await self.post('/add/domain', data=domain_data)
        return response
    
    async def get_mailboxes(self, domain: str = None) -> List[Dict]:
        """Get mailboxes, optionally filtered by domain"""
        endpoint = '/get/mailbox/all'
        params = {'domain': domain} if domain else None
        
        response = await self.get(endpoint, params=params)
        return response.get('data', [])
    
    async def add_mailbox(self, mailbox_data: Dict) -> Dict:
        """Add a new mailbox"""
        response = await self.post('/add/mailbox', data=mailbox_data)
        return response
    
    async def get_aliases(self, domain: str = None) -> List[Dict]:
        """Get aliases, optionally filtered by domain"""
        endpoint = '/get/alias/all'
        params = {'domain': domain} if domain else None
        
        response = await self.get(endpoint, params=params)
        return response.get('data', [])
    
    async def add_alias(self, alias_data: Dict) -> Dict:
        """Add a new alias"""
        response = await self.post('/add/alias', data=alias_data)
        return response
```

## Client Factory and Registry

### API Client Factory (`__init__.py`)
```python
#!/usr/bin/env python3
"""
API Client Factory and Registry
Centralized creation and management of API clients
"""

from typing import Dict, Any, Optional, Type
from .base.client import BaseAPIClient
from .clients.cloudflare import CloudflareClient
from .clients.mailcow import MailcowClient

# Registry of available client types
CLIENT_REGISTRY: Dict[str, Type[BaseAPIClient]] = {
    'cloudflare': CloudflareClient,
    'mailcow': MailcowClient,
}

class APIClientFactory:
    """Factory for creating API clients"""
    
    @staticmethod
    def create_client(client_type: str, config: Dict[str, Any]) -> BaseAPIClient:
        """
        Create an API client instance
        
        Args:
            client_type: Type of client (cloudflare, mailcow, etc.)
            config: Client configuration
            
        Returns:
            Configured API client instance
        """
        client_type = client_type.lower()
        
        if client_type not in CLIENT_REGISTRY:
            available = ', '.join(CLIENT_REGISTRY.keys())
            raise ValueError(f"Unknown client type '{client_type}'. Available: {available}")
        
        client_class = CLIENT_REGISTRY[client_type]
        return client_class(**config)
    
    @staticmethod
    def register_client(client_type: str, client_class: Type[BaseAPIClient]):
        """Register a new client type"""
        CLIENT_REGISTRY[client_type] = client_class
    
    @staticmethod
    def list_available_clients() -> List[str]:
        """List all available client types"""
        return list(CLIENT_REGISTRY.keys())

# Convenience functions
def create_cloudflare_client(api_token: str, **kwargs) -> CloudflareClient:
    """Create a Cloudflare API client"""
    return CloudflareClient(api_token, **kwargs)

def create_mailcow_client(hostname: str, api_key: str, **kwargs) -> MailcowClient:
    """Create a Mailcow API client"""
    return MailcowClient(hostname, api_key, **kwargs)

# Global client instances (optional)
_clients: Dict[str, BaseAPIClient] = {}

def get_client(client_id: str) -> Optional[BaseAPIClient]:
    """Get a cached client instance"""
    return _clients.get(client_id)

def set_client(client_id: str, client: BaseAPIClient):
    """Cache a client instance"""
    _clients[client_id] = client

async def close_all_clients():
    """Close all cached client instances"""
    for client in _clients.values():
        await client.close()
    _clients.clear()
```

## Usage Examples

### Basic Usage
```python
from src.common.api import create_cloudflare_client, create_mailcow_client

# Create Cloudflare client
async with create_cloudflare_client(api_token="your_token") as cf_client:
    # List DNS records
    records = await cf_client.list_dns_records("YOUR_DOMAIN.com")
    
    # Create a new record
    new_record = await cf_client.create_dns_record("YOUR_DOMAIN.com", {
        "type": "A",
        "name": "mail",
        "content": "192.168.1.100",
        "ttl": 300
    })

# Create Mailcow client
async with create_mailcow_client(hostname="mail.YOUR_DOMAIN.com", api_key="your_key") as mc_client:
    # Get all domains
    domains = await mc_client.get_domains()
    
    # Add a new mailbox
    mailbox = await mc_client.add_mailbox({
        "local_part": "user",
        "domain": "YOUR_DOMAIN.com",
        "password": "secure_password",
        "quota": 1024
    })
```

### Integration with Configuration System
```python
from src.common.config import get_section
from src.common.api import APIClientFactory

# Load API configuration
api_config = get_section('apis')

# Create clients from configuration
cf_client = APIClientFactory.create_client('cloudflare', {
    'api_token': api_config['cloudflare']['api_token']
})

mc_client = APIClientFactory.create_client('mailcow', {
    'hostname': api_config['mailcow']['hostname'],
    'api_key': api_config['mailcow']['api_key']
})
```

## Migration Benefits

### Before Consolidation:
- **3+ separate API client implementations** with 800+ lines of duplicated code
- **Inconsistent error handling** across different clients
- **Duplicated rate limiting** and retry logic
- **No standardized authentication** handling
- **Scattered configuration** patterns

### After Consolidation:
- **Single base client** with shared functionality (~400 lines)
- **Consistent error handling** across all API clients
- **Unified rate limiting** and retry mechanisms
- **Standardized authentication** with multiple methods
- **Configuration-driven** client creation
- **Built-in middleware** support (logging, metrics, caching)
- **Type-safe interfaces** with proper error handling
- **Easy to extend** for new API integrations

### Development Benefits:
- **Reduced code duplication** by ~70%
- **Faster development** of new API clients
- **Consistent patterns** across all integrations
- **Better testing** with shared test utilities
- **Improved maintainability** with centralized logic

This consolidated API client library eliminates the major duplications found across the codebase while providing a robust, extensible foundation for all API integrations in the cold email infrastructure.