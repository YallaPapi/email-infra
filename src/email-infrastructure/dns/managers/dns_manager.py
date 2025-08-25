#!/usr/bin/env python3
"""
DNS Manager - Complete Cloudflare API Integration
Manages DNS records for cold email infrastructure with comprehensive automation
"""

import json
import yaml
import time
import logging
import asyncio
import requests
from typing import Dict, List, Optional, Union, Any
from datetime import datetime, timedelta
from dataclasses import dataclass
from pathlib import Path
import os
import sys

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/dns-manager.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class DNSRecord:
    """DNS Record data structure"""
    type: str
    name: str
    content: str
    ttl: int = 300
    priority: Optional[int] = None
    proxied: bool = False
    comment: str = ""
    
    def to_dict(self) -> Dict:
        """Convert to dictionary for API calls"""
        record = {
            "type": self.type,
            "name": self.name,
            "content": self.content,
            "ttl": self.ttl,
            "proxied": self.proxied
        }
        if self.priority is not None:
            record["priority"] = self.priority
        if self.comment:
            record["comment"] = self.comment
        return record

class CloudflareAPIError(Exception):
    """Custom exception for Cloudflare API errors"""
    pass

class DNSManager:
    """Complete DNS management system with Cloudflare integration"""
    
    def __init__(self, config_path: str = None):
        """Initialize DNS Manager with configuration"""
        self.config = self._load_config(config_path)
        self.api_token = self._get_api_token()
        self.session = requests.Session()
        self.session.headers.update({
            'Authorization': f'Bearer {self.api_token}',
            'Content-Type': 'application/json'
        })
        self.base_url = 'https://api.cloudflare.com/client/v4'
        self.zones_cache = {}
        self.rate_limit_delay = 1  # Base delay between API calls
        
    def _load_config(self, config_path: str = None) -> Dict:
        """Load configuration from file"""
        if not config_path:
            config_path = os.path.join(os.path.dirname(__file__), 'cloudflare-config.yaml')
        
        try:
            with open(config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            logger.warning(f"Config file not found: {config_path}, using defaults")
            return self._get_default_config()
    
    def _get_default_config(self) -> Dict:
        """Get default configuration"""
        return {
            'rate_limit': {
                'requests_per_second': 4,
                'burst_limit': 10
            },
            'retry': {
                'max_attempts': 3,
                'backoff_factor': 2
            },
            'dns': {
                'default_ttl': 300,
                'propagation_timeout': 300
            }
        }
    
    def _get_api_token(self) -> str:
        """Get Cloudflare API token from environment or config"""
        token = os.getenv('CLOUDFLARE_API_TOKEN')
        if not token:
            token = self.config.get('cloudflare', {}).get('api_token')
        if not token:
            raise ValueError("Cloudflare API token not found in environment or config")
        return token
    
    async def _make_request(self, method: str, endpoint: str, data: Dict = None, 
                          params: Dict = None, retry_count: int = 0) -> Dict:
        """Make API request with retry logic and rate limiting"""
        url = f"{self.base_url}/{endpoint.lstrip('/')}"
        
        # Rate limiting
        await asyncio.sleep(self.rate_limit_delay)
        
        try:
            response = self.session.request(method, url, json=data, params=params)
            
            # Handle rate limiting
            if response.status_code == 429:
                retry_after = int(response.headers.get('Retry-After', 5))
                logger.warning(f"Rate limited, waiting {retry_after} seconds")
                await asyncio.sleep(retry_after)
                return await self._make_request(method, endpoint, data, params, retry_count)
            
            response.raise_for_status()
            result = response.json()
            
            if not result.get('success', False):
                errors = result.get('errors', [])
                error_msg = '; '.join([error.get('message', str(error)) for error in errors])
                raise CloudflareAPIError(f"API Error: {error_msg}")
            
            return result
            
        except requests.RequestException as e:
            if retry_count < self.config['retry']['max_attempts']:
                delay = self.config['retry']['backoff_factor'] ** retry_count
                logger.warning(f"Request failed, retrying in {delay}s: {e}")
                await asyncio.sleep(delay)
                return await self._make_request(method, endpoint, data, params, retry_count + 1)
            else:
                logger.error(f"Request failed after {retry_count} retries: {e}")
                raise
    
    async def get_zones(self, force_refresh: bool = False) -> Dict[str, str]:
        """Get all zones (domain -> zone_id mapping)"""
        if not force_refresh and self.zones_cache:
            return self.zones_cache
        
        try:
            result = await self._make_request('GET', '/zones')
            zones = {}
            for zone in result['result']:
                zones[zone['name']] = zone['id']
            
            self.zones_cache = zones
            logger.info(f"Cached {len(zones)} zones")
            return zones
            
        except Exception as e:
            logger.error(f"Failed to get zones: {e}")
            raise
    
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
        
        raise ValueError(f"Zone not found for domain: {domain}")
    
    async def list_dns_records(self, domain: str, record_type: str = None, 
                             name: str = None) -> List[Dict]:
        """List DNS records for a domain"""
        try:
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
                result = await self._make_request('GET', f'/zones/{zone_id}/dns_records', 
                                               params=params)
                
                records = result['result']
                all_records.extend(records)
                
                # Check if there are more pages
                result_info = result.get('result_info', {})
                if page >= result_info.get('total_pages', 1):
                    break
                
                page += 1
            
            logger.info(f"Retrieved {len(all_records)} DNS records for {domain}")
            return all_records
            
        except Exception as e:
            logger.error(f"Failed to list DNS records for {domain}: {e}")
            raise
    
    async def create_dns_record(self, domain: str, record: DNSRecord) -> Dict:
        """Create a DNS record"""
        try:
            zone_id = await self.get_zone_id(domain)
            
            result = await self._make_request('POST', f'/zones/{zone_id}/dns_records', 
                                            data=record.to_dict())
            
            record_data = result['result']
            logger.info(f"Created DNS record: {record.type} {record.name} -> {record.content}")
            return record_data
            
        except Exception as e:
            logger.error(f"Failed to create DNS record {record.type} {record.name}: {e}")
            raise
    
    async def update_dns_record(self, domain: str, record_id: str, 
                              record: DNSRecord) -> Dict:
        """Update a DNS record"""
        try:
            zone_id = await self.get_zone_id(domain)
            
            result = await self._make_request('PATCH', 
                                            f'/zones/{zone_id}/dns_records/{record_id}',
                                            data=record.to_dict())
            
            record_data = result['result']
            logger.info(f"Updated DNS record: {record.type} {record.name} -> {record.content}")
            return record_data
            
        except Exception as e:
            logger.error(f"Failed to update DNS record {record_id}: {e}")
            raise
    
    async def delete_dns_record(self, domain: str, record_id: str) -> bool:
        """Delete a DNS record"""
        try:
            zone_id = await self.get_zone_id(domain)
            
            await self._make_request('DELETE', f'/zones/{zone_id}/dns_records/{record_id}')
            
            logger.info(f"Deleted DNS record: {record_id}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to delete DNS record {record_id}: {e}")
            raise
    
    async def bulk_create_records(self, domain: str, records: List[DNSRecord]) -> List[Dict]:
        """Create multiple DNS records with batch processing"""
        try:
            results = []
            batch_size = 10  # Process in batches to avoid rate limits
            
            for i in range(0, len(records), batch_size):
                batch = records[i:i + batch_size]
                batch_results = []
                
                for record in batch:
                    try:
                        result = await self.create_dns_record(domain, record)
                        batch_results.append(result)
                    except Exception as e:
                        logger.error(f"Failed to create record {record.name}: {e}")
                        batch_results.append({'error': str(e)})
                
                results.extend(batch_results)
                
                # Rate limiting between batches
                if i + batch_size < len(records):
                    await asyncio.sleep(2)
            
            logger.info(f"Bulk created {len(results)} DNS records for {domain}")
            return results
            
        except Exception as e:
            logger.error(f"Failed bulk create for {domain}: {e}")
            raise
    
    async def sync_records_from_template(self, domain: str, template_path: str) -> Dict:
        """Sync DNS records from a template file"""
        try:
            with open(template_path, 'r') as f:
                template = yaml.safe_load(f)
            
            # Get existing records
            existing_records = await self.list_dns_records(domain)
            existing_map = {f"{r['type']}:{r['name']}": r for r in existing_records}
            
            results = {
                'created': [],
                'updated': [],
                'deleted': [],
                'errors': []
            }
            
            # Process template records
            for record_data in template.get('records', []):
                try:
                    record = DNSRecord(**record_data)
                    key = f"{record.type}:{record.name}"
                    
                    if key in existing_map:
                        # Update existing record
                        existing_record = existing_map[key]
                        if (existing_record['content'] != record.content or 
                            existing_record['ttl'] != record.ttl):
                            
                            result = await self.update_dns_record(domain, 
                                                                existing_record['id'], 
                                                                record)
                            results['updated'].append(result)
                        
                        # Remove from existing map so it won't be deleted
                        del existing_map[key]
                    else:
                        # Create new record
                        result = await self.create_dns_record(domain, record)
                        results['created'].append(result)
                        
                except Exception as e:
                    logger.error(f"Failed to process record {record_data}: {e}")
                    results['errors'].append({'record': record_data, 'error': str(e)})
            
            # Delete records not in template (if configured)
            if template.get('delete_extra', False):
                for record in existing_map.values():
                    try:
                        await self.delete_dns_record(domain, record['id'])
                        results['deleted'].append(record)
                    except Exception as e:
                        logger.error(f"Failed to delete record {record['id']}: {e}")
                        results['errors'].append({'record': record, 'error': str(e)})
            
            logger.info(f"Synced DNS records for {domain}: "
                       f"{len(results['created'])} created, "
                       f"{len(results['updated'])} updated, "
                       f"{len(results['deleted'])} deleted")
            
            return results
            
        except Exception as e:
            logger.error(f"Failed to sync records from template: {e}")
            raise
    
    async def backup_dns_records(self, domain: str, backup_path: str) -> bool:
        """Backup DNS records to a file"""
        try:
            records = await self.list_dns_records(domain)
            
            backup_data = {
                'domain': domain,
                'backup_date': datetime.now().isoformat(),
                'records': records
            }
            
            with open(backup_path, 'w') as f:
                json.dump(backup_data, f, indent=2)
            
            logger.info(f"Backed up {len(records)} DNS records for {domain} to {backup_path}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to backup DNS records: {e}")
            raise
    
    async def restore_dns_records(self, backup_path: str, domain: str = None) -> bool:
        """Restore DNS records from a backup file"""
        try:
            with open(backup_path, 'r') as f:
                backup_data = json.load(f)
            
            target_domain = domain or backup_data['domain']
            
            # Clear existing records (optional)
            existing_records = await self.list_dns_records(target_domain)
            
            for record_data in existing_records:
                if record_data['type'] not in ['NS', 'SOA']:  # Keep essential records
                    await self.delete_dns_record(target_domain, record_data['id'])
            
            # Restore records
            records_to_create = []
            for record_data in backup_data['records']:
                if record_data['type'] not in ['NS', 'SOA']:
                    record = DNSRecord(
                        type=record_data['type'],
                        name=record_data['name'],
                        content=record_data['content'],
                        ttl=record_data.get('ttl', 300),
                        priority=record_data.get('priority'),
                        proxied=record_data.get('proxied', False)
                    )
                    records_to_create.append(record)
            
            await self.bulk_create_records(target_domain, records_to_create)
            
            logger.info(f"Restored {len(records_to_create)} DNS records to {target_domain}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to restore DNS records: {e}")
            raise
    
    async def get_zone_analytics(self, domain: str, days: int = 7) -> Dict:
        """Get DNS analytics for a zone"""
        try:
            zone_id = await self.get_zone_id(domain)
            
            since = (datetime.now() - timedelta(days=days)).isoformat() + 'Z'
            until = datetime.now().isoformat() + 'Z'
            
            params = {
                'since': since,
                'until': until,
                'continuous': 'true'
            }
            
            result = await self._make_request('GET', 
                                            f'/zones/{zone_id}/analytics/dashboard',
                                            params=params)
            
            return result['result']
            
        except Exception as e:
            logger.error(f"Failed to get zone analytics: {e}")
            raise
    
    async def export_zone_file(self, domain: str, export_path: str) -> bool:
        """Export DNS zone file"""
        try:
            zone_id = await self.get_zone_id(domain)
            
            result = await self._make_request('GET', f'/zones/{zone_id}/dns_records/export')
            
            with open(export_path, 'w') as f:
                f.write(result['result'])
            
            logger.info(f"Exported zone file for {domain} to {export_path}")
            return True
            
        except Exception as e:
            logger.error(f"Failed to export zone file: {e}")
            raise
    
    async def validate_dns_records(self, domain: str) -> Dict:
        """Validate DNS records for email infrastructure"""
        try:
            records = await self.list_dns_records(domain)
            
            validation = {
                'valid': True,
                'warnings': [],
                'errors': [],
                'recommendations': []
            }
            
            record_types = {}
            for record in records:
                record_type = record['type']
                if record_type not in record_types:
                    record_types[record_type] = []
                record_types[record_type].append(record)
            
            # Check MX records
            mx_records = record_types.get('MX', [])
            if not mx_records:
                validation['errors'].append("No MX records found")
                validation['valid'] = False
            elif len(mx_records) < 2:
                validation['warnings'].append("Only one MX record found, consider adding backup")
            
            # Check SPF records
            spf_records = [r for r in record_types.get('TXT', []) 
                          if r['content'].startswith('v=spf1')]
            if not spf_records:
                validation['errors'].append("No SPF record found")
                validation['valid'] = False
            elif len(spf_records) > 1:
                validation['errors'].append("Multiple SPF records found")
                validation['valid'] = False
            
            # Check DMARC records
            dmarc_records = [r for r in record_types.get('TXT', []) 
                           if r['name'].startswith('_dmarc')]
            if not dmarc_records:
                validation['warnings'].append("No DMARC record found")
            
            # Check DKIM records
            dkim_records = [r for r in record_types.get('TXT', []) 
                          if '_domainkey' in r['name']]
            if not dkim_records:
                validation['warnings'].append("No DKIM records found")
            
            # Check A records
            a_records = record_types.get('A', [])
            if not a_records:
                validation['warnings'].append("No A records found")
            
            # TTL recommendations
            for record in records:
                if record['ttl'] < 300:
                    validation['recommendations'].append(
                        f"Consider increasing TTL for {record['name']} "
                        f"({record['type']}) from {record['ttl']} to 300+"
                    )
            
            return validation
            
        except Exception as e:
            logger.error(f"Failed to validate DNS records: {e}")
            raise

# CLI Interface
async def main():
    """Main CLI interface"""
    import argparse
    
    parser = argparse.ArgumentParser(description='DNS Manager CLI')
    parser.add_argument('command', choices=[
        'list', 'create', 'update', 'delete', 'bulk-create', 
        'sync', 'backup', 'restore', 'validate', 'export'
    ])
    parser.add_argument('--domain', required=True, help='Domain name')
    parser.add_argument('--config', help='Config file path')
    parser.add_argument('--type', help='DNS record type')
    parser.add_argument('--name', help='DNS record name')
    parser.add_argument('--content', help='DNS record content')
    parser.add_argument('--ttl', type=int, default=300, help='DNS record TTL')
    parser.add_argument('--priority', type=int, help='DNS record priority (MX)')
    parser.add_argument('--template', help='Template file path')
    parser.add_argument('--backup', help='Backup file path')
    parser.add_argument('--output', help='Output file path')
    
    args = parser.parse_args()
    
    try:
        dns_manager = DNSManager(args.config)
        
        if args.command == 'list':
            records = await dns_manager.list_dns_records(args.domain, 
                                                       args.type, args.name)
            print(json.dumps(records, indent=2))
            
        elif args.command == 'create':
            record = DNSRecord(
                type=args.type,
                name=args.name,
                content=args.content,
                ttl=args.ttl,
                priority=args.priority
            )
            result = await dns_manager.create_dns_record(args.domain, record)
            print(json.dumps(result, indent=2))
            
        elif args.command == 'sync':
            if not args.template:
                raise ValueError("Template file required for sync command")
            result = await dns_manager.sync_records_from_template(args.domain, 
                                                                args.template)
            print(json.dumps(result, indent=2))
            
        elif args.command == 'backup':
            backup_path = args.backup or f"{args.domain}-backup.json"
            await dns_manager.backup_dns_records(args.domain, backup_path)
            print(f"Backup saved to {backup_path}")
            
        elif args.command == 'validate':
            result = await dns_manager.validate_dns_records(args.domain)
            print(json.dumps(result, indent=2))
            
    except Exception as e:
        logger.error(f"Command failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    asyncio.run(main())