#!/usr/bin/env python3
"""
Mailcow API Python Wrapper
Comprehensive Python wrapper for Mailcow dockerized API
Handles all mailcow operations via REST API
"""

import requests
import json
import os
import sys
import argparse
import yaml
import time
import secrets
import string
from typing import Dict, List, Optional, Any, Union
from urllib.parse import urljoin, quote
import warnings
from dataclasses import dataclass
from datetime import datetime, timedelta
import logging

# Suppress SSL warnings for self-signed certificates
warnings.filterwarnings('ignore', message='Unverified HTTPS request')

@dataclass
class MailcowConfig:
    """Mailcow configuration data class"""
    hostname: str
    api_key: str
    verify_ssl: bool = True
    timeout: int = 30
    rate_limit: int = 100

class MailcowAPIError(Exception):
    """Custom exception for Mailcow API errors"""
    pass

class MailcowAPI:
    """
    Mailcow API wrapper class
    Provides methods for all Mailcow API operations
    """
    
    def __init__(self, hostname: str, api_key: str, verify_ssl: bool = True, timeout: int = 30):
        """
        Initialize Mailcow API client
        
        Args:
            hostname: Mailcow server hostname (e.g., mail.example.com)
            api_key: API key for authentication
            verify_ssl: Whether to verify SSL certificates
            timeout: Request timeout in seconds
        """
        self.hostname = hostname.rstrip('/')
        self.api_key = api_key
        self.verify_ssl = verify_ssl
        self.timeout = timeout
        self.base_url = f"https://{self.hostname}/api/v1"
        self.session = requests.Session()
        self.session.headers.update({
            'X-API-Key': self.api_key,
            'Content-Type': 'application/json'
        })
        
        # Setup logging
        self.logger = logging.getLogger(__name__)
        handler = logging.StreamHandler()
        formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        handler.setFormatter(formatter)
        self.logger.addHandler(handler)
        self.logger.setLevel(logging.INFO)
    
    def _request(self, method: str, endpoint: str, data: Optional[Dict] = None, params: Optional[Dict] = None) -> Dict:
        """
        Make API request
        
        Args:
            method: HTTP method (GET, POST, PUT, DELETE)
            endpoint: API endpoint
            data: Request data
            params: Query parameters
            
        Returns:
            API response as dictionary
            
        Raises:
            MailcowAPIError: If API request fails
        """
        url = urljoin(self.base_url + '/', endpoint.lstrip('/'))
        
        try:
            response = self.session.request(
                method=method,
                url=url,
                json=data,
                params=params,
                verify=self.verify_ssl,
                timeout=self.timeout
            )
            
            # Log request for debugging
            self.logger.debug(f"{method} {url} - Status: {response.status_code}")
            
            response.raise_for_status()
            
            # Handle empty responses
            if not response.content:
                return {}
                
            return response.json()
            
        except requests.exceptions.RequestException as e:
            error_msg = f"API request failed: {str(e)}"
            if hasattr(response, 'text'):
                error_msg += f" - Response: {response.text}"
            raise MailcowAPIError(error_msg)
        except json.JSONDecodeError as e:
            raise MailcowAPIError(f"Failed to decode JSON response: {str(e)}")
    
    def get(self, endpoint: str, params: Optional[Dict] = None) -> Dict:
        """Make GET request"""
        return self._request('GET', endpoint, params=params)
    
    def post(self, endpoint: str, data: Dict) -> Dict:
        """Make POST request"""
        return self._request('POST', endpoint, data=data)
    
    def put(self, endpoint: str, data: Dict) -> Dict:
        """Make PUT request"""
        return self._request('PUT', endpoint, data=data)
    
    def delete(self, endpoint: str, data: Optional[Dict] = None) -> Dict:
        """Make DELETE request"""
        return self._request('DELETE', endpoint, data=data)
    
    # System Status and Information
    def get_status(self) -> Dict:
        """Get system status"""
        return self.get('get/status/containers')
    
    def get_version(self) -> Dict:
        """Get Mailcow version information"""
        return self.get('get/status/version')
    
    def get_logs(self, container: str, lines: int = 100) -> Dict:
        """Get container logs"""
        return self.get(f'get/logs/{container}/{lines}')
    
    # Domain Management
    def get_domains(self) -> List[Dict]:
        """Get all domains"""
        response = self.get('get/domain/all')
        return response if isinstance(response, list) else []
    
    def get_domain(self, domain: str) -> Dict:
        """Get specific domain details"""
        return self.get(f'get/domain/{domain}')
    
    def add_domain(self, domain: str, description: str = "", aliases: int = 400, 
                   mailboxes: int = 10, quota: int = 3072, active: bool = True,
                   relay_all_recipients: bool = False, backupmx: bool = False) -> Dict:
        """
        Add new domain
        
        Args:
            domain: Domain name
            description: Domain description
            aliases: Maximum aliases
            mailboxes: Maximum mailboxes
            quota: Domain quota in MB
            active: Whether domain is active
            relay_all_recipients: Relay all recipients
            backupmx: Use as backup MX
            
        Returns:
            API response
        """
        data = {
            "domain": domain,
            "description": description,
            "aliases": aliases,
            "mailboxes": mailboxes,
            "quota": quota,
            "active": 1 if active else 0,
            "relay_all_recipients": 1 if relay_all_recipients else 0,
            "backupmx": 1 if backupmx else 0
        }
        return self.post('add/domain', data)
    
    def update_domain(self, domain: str, **kwargs) -> Dict:
        """Update domain settings"""
        data = {"items": [domain], "attr": kwargs}
        return self.post('edit/domain', data)
    
    def delete_domain(self, domain: str) -> Dict:
        """Delete domain"""
        data = [domain]
        return self.post('delete/domain', data)
    
    # Mailbox Management
    def get_mailboxes(self, domain: Optional[str] = None) -> List[Dict]:
        """Get mailboxes, optionally filtered by domain"""
        endpoint = f'get/mailbox/{domain}' if domain else 'get/mailbox/all'
        response = self.get(endpoint)
        return response if isinstance(response, list) else []
    
    def get_mailbox(self, email: str) -> Dict:
        """Get specific mailbox details"""
        return self.get(f'get/mailbox/{email}')
    
    def add_mailbox(self, email: str, password: str, name: str = "", 
                    quota: int = 3072, active: bool = True,
                    force_pw_update: bool = False, tls_enforce_in: bool = True,
                    tls_enforce_out: bool = True) -> Dict:
        """
        Add new mailbox
        
        Args:
            email: Email address
            password: Mailbox password
            name: Full name
            quota: Mailbox quota in MB
            active: Whether mailbox is active
            force_pw_update: Force password update on first login
            tls_enforce_in: Enforce TLS for incoming
            tls_enforce_out: Enforce TLS for outgoing
            
        Returns:
            API response
        """
        local, domain = email.split('@', 1)
        
        data = {
            "local_part": local,
            "domain": domain,
            "password": password,
            "password2": password,
            "name": name,
            "quota": quota,
            "active": 1 if active else 0,
            "force_pw_update": 1 if force_pw_update else 0,
            "tls_enforce_in": 1 if tls_enforce_in else 0,
            "tls_enforce_out": 1 if tls_enforce_out else 0
        }
        return self.post('add/mailbox', data)
    
    def update_mailbox(self, email: str, **kwargs) -> Dict:
        """Update mailbox settings"""
        data = {"items": [email], "attr": kwargs}
        return self.post('edit/mailbox', data)
    
    def delete_mailbox(self, email: str) -> Dict:
        """Delete mailbox"""
        data = [email]
        return self.post('delete/mailbox', data)
    
    def generate_secure_password(self, length: int = 16) -> str:
        """Generate secure password"""
        alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
        return ''.join(secrets.choice(alphabet) for _ in range(length))
    
    # Alias Management
    def get_aliases(self, domain: Optional[str] = None) -> List[Dict]:
        """Get aliases"""
        endpoint = f'get/alias/{domain}' if domain else 'get/alias/all'
        response = self.get(endpoint)
        return response if isinstance(response, list) else []
    
    def add_alias(self, address: str, goto: Union[str, List[str]], 
                  active: bool = True, sogo_visible: bool = True) -> Dict:
        """
        Add alias
        
        Args:
            address: Alias address
            goto: Destination address(es)
            active: Whether alias is active
            sogo_visible: Visible in SOGo
            
        Returns:
            API response
        """
        if isinstance(goto, list):
            goto = ','.join(goto)
            
        data = {
            "address": address,
            "goto": goto,
            "active": 1 if active else 0,
            "sogo_visible": 1 if sogo_visible else 0
        }
        return self.post('add/alias', data)
    
    def update_alias(self, alias_id: int, **kwargs) -> Dict:
        """Update alias"""
        data = {"items": [alias_id], "attr": kwargs}
        return self.post('edit/alias', data)
    
    def delete_alias(self, alias_id: int) -> Dict:
        """Delete alias"""
        data = [alias_id]
        return self.post('delete/alias', data)
    
    # DKIM Management
    def get_dkim(self, domain: str) -> Dict:
        """Get DKIM key for domain"""
        return self.get(f'get/dkim/{domain}')
    
    def add_dkim_key(self, domain: str, key_size: int = 2048, selector: str = "dkim") -> Dict:
        """
        Generate DKIM key for domain
        
        Args:
            domain: Domain name
            key_size: Key size (1024, 2048, 4096)
            selector: DKIM selector
            
        Returns:
            API response
        """
        data = {
            "domains": [domain],
            "key_size": key_size,
            "selector": selector
        }
        return self.post('add/dkim', data)
    
    def delete_dkim_key(self, domain: str) -> Dict:
        """Delete DKIM key for domain"""
        data = [domain]
        return self.post('delete/dkim', data)
    
    def get_dkim_record(self, domain: str) -> str:
        """Get DKIM DNS record for domain"""
        dkim_data = self.get_dkim(domain)
        if dkim_data and 'pubkey' in dkim_data:
            return dkim_data['pubkey']
        return ""
    
    # Admin Management
    def get_admins(self) -> List[Dict]:
        """Get all admin users"""
        response = self.get('get/admin/all')
        return response if isinstance(response, list) else []
    
    def add_admin(self, username: str, password: str, active: bool = True,
                  superadmin: bool = False) -> Dict:
        """Add admin user"""
        data = {
            "username": username,
            "password": password,
            "password2": password,
            "active": 1 if active else 0,
            "superadmin": 1 if superadmin else 0
        }
        return self.post('add/admin', data)
    
    # Queue Management
    def get_queue(self) -> List[Dict]:
        """Get mail queue"""
        response = self.get('get/mailq/all')
        return response if isinstance(response, list) else []
    
    def flush_queue(self) -> Dict:
        """Flush mail queue"""
        return self.post('edit/mailq', {"action": "flush"})
    
    def delete_queue_item(self, queue_id: str) -> Dict:
        """Delete item from queue"""
        data = {"qid": [queue_id], "action": "delete"}
        return self.post('edit/mailq', data)
    
    # Backup Operations
    def backup_mailcow(self) -> Dict:
        """Trigger mailcow backup"""
        return self.post('backup', {"backup_type": "full"})
    
    def get_backup_status(self) -> Dict:
        """Get backup status"""
        return self.get('get/backup/status')
    
    # Utility Methods
    def test_connection(self) -> bool:
        """Test API connection"""
        try:
            status = self.get_status()
            return bool(status)
        except Exception as e:
            self.logger.error(f"Connection test failed: {e}")
            return False
    
    def health_check(self) -> Dict:
        """Perform comprehensive health check"""
        health_data = {
            "api_connection": False,
            "containers": {},
            "version": {},
            "timestamp": datetime.now().isoformat()
        }
        
        try:
            # Test API connection
            health_data["api_connection"] = self.test_connection()
            
            # Get container status
            status = self.get_status()
            health_data["containers"] = status
            
            # Get version info
            version = self.get_version()
            health_data["version"] = version
            
        except Exception as e:
            health_data["error"] = str(e)
        
        return health_data
    
    def bulk_mailbox_create(self, mailboxes: List[Dict]) -> List[Dict]:
        """
        Create multiple mailboxes
        
        Args:
            mailboxes: List of mailbox configurations
            
        Returns:
            List of creation results
        """
        results = []
        
        for mailbox_config in mailboxes:
            try:
                # Generate password if not provided
                if 'password' not in mailbox_config:
                    mailbox_config['password'] = self.generate_secure_password()
                
                result = self.add_mailbox(**mailbox_config)
                result['email'] = mailbox_config['email']
                result['password'] = mailbox_config['password']
                results.append(result)
                
                # Rate limiting
                time.sleep(0.1)
                
            except Exception as e:
                results.append({
                    "email": mailbox_config.get('email', 'unknown'),
                    "error": str(e),
                    "success": False
                })
        
        return results

def load_config(config_file: str = None) -> MailcowConfig:
    """Load configuration from file or environment"""
    
    # Default config file paths
    config_paths = [
        config_file,
        os.path.join(os.path.dirname(__file__), '../config/mailcow-api.yaml'),
        os.path.expanduser('~/.mailcow/config.yaml'),
        '/etc/mailcow/config.yaml'
    ]
    
    config_data = {}
    
    # Try to load from file
    for path in config_paths:
        if path and os.path.exists(path):
            try:
                with open(path, 'r') as f:
                    config_data = yaml.safe_load(f)
                break
            except Exception as e:
                print(f"Warning: Failed to load config from {path}: {e}")
    
    # Override with environment variables
    hostname = config_data.get('hostname') or os.getenv('MAILCOW_HOSTNAME')
    api_key = config_data.get('api_key') or os.getenv('MAILCOW_API_KEY')
    
    if not hostname or not api_key:
        raise ValueError("Hostname and API key must be provided via config file or environment variables")
    
    return MailcowConfig(
        hostname=hostname,
        api_key=api_key,
        verify_ssl=config_data.get('verify_ssl', True),
        timeout=config_data.get('timeout', 30)
    )

def main():
    """Main CLI interface"""
    parser = argparse.ArgumentParser(description='Mailcow API Client')
    parser.add_argument('--config', '-c', help='Configuration file path')
    parser.add_argument('--hostname', help='Mailcow hostname')
    parser.add_argument('--api-key', help='API key')
    parser.add_argument('--no-ssl-verify', action='store_true', help='Disable SSL verification')
    
    subparsers = parser.add_subparsers(dest='command', help='Available commands')
    
    # Status command
    status_parser = subparsers.add_parser('status', help='Get system status')
    
    # Domain commands
    domain_parser = subparsers.add_parser('domain', help='Domain management')
    domain_subparsers = domain_parser.add_subparsers(dest='domain_action')
    
    domain_list = domain_subparsers.add_parser('list', help='List domains')
    domain_add = domain_subparsers.add_parser('add', help='Add domain')
    domain_add.add_argument('domain', help='Domain name')
    domain_add.add_argument('--quota', type=int, default=3072, help='Domain quota in MB')
    domain_add.add_argument('--mailboxes', type=int, default=10, help='Max mailboxes')
    
    domain_delete = domain_subparsers.add_parser('delete', help='Delete domain')
    domain_delete.add_argument('domain', help='Domain name')
    
    # Mailbox commands
    mailbox_parser = subparsers.add_parser('mailbox', help='Mailbox management')
    mailbox_subparsers = mailbox_parser.add_subparsers(dest='mailbox_action')
    
    mailbox_list = mailbox_subparsers.add_parser('list', help='List mailboxes')
    mailbox_list.add_argument('--domain', help='Filter by domain')
    
    mailbox_add = mailbox_subparsers.add_parser('add', help='Add mailbox')
    mailbox_add.add_argument('email', help='Email address')
    mailbox_add.add_argument('--password', help='Password (generated if not provided)')
    mailbox_add.add_argument('--name', help='Full name')
    mailbox_add.add_argument('--quota', type=int, default=1024, help='Quota in MB')
    
    mailbox_delete = mailbox_subparsers.add_parser('delete', help='Delete mailbox')
    mailbox_delete.add_argument('email', help='Email address')
    
    # DKIM commands
    dkim_parser = subparsers.add_parser('dkim', help='DKIM management')
    dkim_subparsers = dkim_parser.add_subparsers(dest='dkim_action')
    
    dkim_add = dkim_subparsers.add_parser('add', help='Add DKIM key')
    dkim_add.add_argument('domain', help='Domain name')
    dkim_add.add_argument('--key-size', type=int, default=2048, choices=[1024, 2048, 4096])
    
    dkim_get = dkim_subparsers.add_parser('get', help='Get DKIM record')
    dkim_get.add_argument('domain', help='Domain name')
    
    # Health check command
    health_parser = subparsers.add_parser('health', help='Health check')
    
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        return
    
    try:
        # Load configuration
        if args.hostname and args.api_key:
            config = MailcowConfig(
                hostname=args.hostname,
                api_key=args.api_key,
                verify_ssl=not args.no_ssl_verify
            )
        else:
            config = load_config(args.config)
        
        # Create API client
        api = MailcowAPI(
            hostname=config.hostname,
            api_key=config.api_key,
            verify_ssl=config.verify_ssl,
            timeout=config.timeout
        )
        
        # Execute commands
        if args.command == 'status':
            result = api.get_status()
            print(json.dumps(result, indent=2))
        
        elif args.command == 'domain':
            if args.domain_action == 'list':
                domains = api.get_domains()
                for domain in domains:
                    print(f"Domain: {domain.get('domain_name', 'N/A')}")
                    print(f"  Active: {domain.get('active', 'N/A')}")
                    print(f"  Mailboxes: {domain.get('mailboxes', 'N/A')}")
                    print(f"  Quota: {domain.get('quota', 'N/A')} MB")
                    print()
            
            elif args.domain_action == 'add':
                result = api.add_domain(
                    domain=args.domain,
                    quota=args.quota,
                    mailboxes=args.mailboxes
                )
                print(json.dumps(result, indent=2))
            
            elif args.domain_action == 'delete':
                result = api.delete_domain(args.domain)
                print(json.dumps(result, indent=2))
        
        elif args.command == 'mailbox':
            if args.mailbox_action == 'list':
                mailboxes = api.get_mailboxes(args.domain)
                for mailbox in mailboxes:
                    print(f"Email: {mailbox.get('username', 'N/A')}")
                    print(f"  Name: {mailbox.get('name', 'N/A')}")
                    print(f"  Active: {mailbox.get('active', 'N/A')}")
                    print(f"  Quota: {mailbox.get('quota', 'N/A')} MB")
                    print()
            
            elif args.mailbox_action == 'add':
                password = args.password or api.generate_secure_password()
                result = api.add_mailbox(
                    email=args.email,
                    password=password,
                    name=args.name or '',
                    quota=args.quota
                )
                print(f"Mailbox created: {args.email}")
                print(f"Password: {password}")
                print(json.dumps(result, indent=2))
            
            elif args.mailbox_action == 'delete':
                result = api.delete_mailbox(args.email)
                print(json.dumps(result, indent=2))
        
        elif args.command == 'dkim':
            if args.dkim_action == 'add':
                result = api.add_dkim_key(args.domain, args.key_size)
                print(json.dumps(result, indent=2))
            
            elif args.dkim_action == 'get':
                record = api.get_dkim_record(args.domain)
                if record:
                    print(f"DKIM record for {args.domain}:")
                    print(record)
                else:
                    print(f"No DKIM key found for {args.domain}")
        
        elif args.command == 'health':
            health = api.health_check()
            print(json.dumps(health, indent=2))
    
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()