#!/usr/bin/env python3
"""
DNS Cache Manager - DNS Cache Management and Optimization System
Manages DNS caching, TTL optimization, and cache invalidation for email infrastructure
"""

import json
import yaml
import time
import logging
import asyncio
import aiohttp
import redis
from typing import Dict, List, Optional, Any, Tuple, Union
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from pathlib import Path
import os
import sys
import hashlib
import pickle
from dns_manager import DNSManager

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/dns-cache-manager.log'),
        logging.StreamHandler(sys.stdout)
    ]
)
logger = logging.getLogger(__name__)

@dataclass
class CacheEntry:
    """DNS cache entry data structure"""
    key: str
    value: Any
    created_at: datetime
    expires_at: datetime
    access_count: int = 0
    last_accessed: datetime = None
    ttl: int = 300
    
    def is_expired(self) -> bool:
        return datetime.now() > self.expires_at
    
    def is_stale(self, stale_threshold: int = 60) -> bool:
        """Check if entry is stale (approaching expiration)"""
        stale_time = self.expires_at - timedelta(seconds=stale_threshold)
        return datetime.now() > stale_time
    
    def to_dict(self) -> Dict:
        return {
            **asdict(self),
            'created_at': self.created_at.isoformat(),
            'expires_at': self.expires_at.isoformat(),
            'last_accessed': self.last_accessed.isoformat() if self.last_accessed else None
        }

@dataclass
class CacheStats:
    """Cache statistics"""
    total_entries: int
    hit_rate: float
    miss_rate: float
    expired_entries: int
    memory_usage: int
    avg_ttl: float
    most_accessed: List[str]
    
class DNSCacheManager:
    """DNS cache management and optimization system"""
    
    def __init__(self, config_path: str = None):
        """Initialize DNS cache manager"""
        self.config = self._load_config(config_path)
        self.cache_backend = self.config['cache']['backend']  # 'memory', 'redis', 'hybrid'
        self.memory_cache = {}
        self.redis_client = None
        self.cache_stats = {
            'hits': 0,
            'misses': 0,
            'sets': 0,
            'deletes': 0,
            'evictions': 0
        }
        
        # Initialize cache backend
        asyncio.create_task(self._initialize_backend())
        
    def _load_config(self, config_path: str = None) -> Dict:
        """Load configuration from file"""
        if not config_path:
            config_path = os.path.join(os.path.dirname(__file__), 'cache-config.yaml')
        
        try:
            with open(config_path, 'r') as f:
                return yaml.safe_load(f)
        except FileNotFoundError:
            logger.warning(f"Config file not found: {config_path}, using defaults")
            return self._get_default_config()
    
    def _get_default_config(self) -> Dict:
        """Get default configuration"""
        return {
            'cache': {
                'backend': 'memory',  # memory, redis, hybrid
                'ttl_default': 300,
                'ttl_min': 60,
                'ttl_max': 86400,
                'max_entries': 10000,
                'cleanup_interval': 300,
                'prefetch_threshold': 60,
                'stale_serve_threshold': 30
            },
            'redis': {
                'host': 'localhost',
                'port': 6379,
                'db': 0,
                'password': None,
                'connection_pool_size': 10
            },
            'optimization': {
                'auto_ttl_adjustment': True,
                'ttl_adjustment_factor': 1.2,
                'min_access_for_adjustment': 10,
                'prefetch_popular_records': True,
                'compress_large_entries': True,
                'compression_threshold': 1024
            },
            'monitoring': {
                'stats_retention_hours': 24,
                'alert_on_high_miss_rate': True,
                'miss_rate_threshold': 0.3
            }
        }
    
    async def _initialize_backend(self):
        """Initialize cache backend"""
        if self.cache_backend in ['redis', 'hybrid']:
            try:
                self.redis_client = redis.Redis(
                    host=self.config['redis']['host'],
                    port=self.config['redis']['port'],
                    db=self.config['redis']['db'],
                    password=self.config['redis']['password'],
                    decode_responses=False
                )
                # Test connection
                await asyncio.to_thread(self.redis_client.ping)
                logger.info("Redis cache backend initialized")
            except Exception as e:
                logger.error(f"Failed to initialize Redis: {e}")
                if self.cache_backend == 'redis':
                    self.cache_backend = 'memory'
                    logger.info("Falling back to memory cache")
        
        # Start cleanup task
        asyncio.create_task(self._periodic_cleanup())
    
    def _generate_cache_key(self, domain: str, record_type: str, nameserver: str = None) -> str:
        """Generate cache key for DNS record"""
        key_parts = [domain.lower(), record_type.upper()]
        if nameserver:
            key_parts.append(nameserver)
        
        key_string = ':'.join(key_parts)
        return hashlib.md5(key_string.encode()).hexdigest()
    
    async def get(self, domain: str, record_type: str, nameserver: str = None) -> Optional[Any]:
        """Get DNS record from cache"""
        cache_key = self._generate_cache_key(domain, record_type, nameserver)
        
        try:
            # Try memory cache first
            if cache_key in self.memory_cache:
                entry = self.memory_cache[cache_key]
                
                if entry.is_expired():
                    del self.memory_cache[cache_key]
                    self.cache_stats['misses'] += 1
                    return None
                
                # Update access stats
                entry.access_count += 1
                entry.last_accessed = datetime.now()
                
                self.cache_stats['hits'] += 1
                
                # Check if entry is stale and needs refresh
                if entry.is_stale(self.config['cache']['prefetch_threshold']):
                    asyncio.create_task(self._prefetch_record(domain, record_type, nameserver))
                
                return entry.value
            
            # Try Redis cache if configured
            if self.redis_client and self.cache_backend in ['redis', 'hybrid']:
                try:
                    redis_data = await asyncio.to_thread(self.redis_client.get, cache_key)
                    if redis_data:
                        entry_data = pickle.loads(redis_data)
                        entry = CacheEntry(**entry_data)
                        
                        if not entry.is_expired():
                            # Move to memory cache if hybrid mode
                            if self.cache_backend == 'hybrid':
                                self.memory_cache[cache_key] = entry
                            
                            entry.access_count += 1
                            entry.last_accessed = datetime.now()
                            self.cache_stats['hits'] += 1
                            
                            return entry.value
                        else:
                            # Remove expired entry
                            await asyncio.to_thread(self.redis_client.delete, cache_key)
                except Exception as e:
                    logger.warning(f"Redis cache get error: {e}")
            
            self.cache_stats['misses'] += 1
            return None
            
        except Exception as e:
            logger.error(f"Cache get error: {e}")
            self.cache_stats['misses'] += 1
            return None
    
    async def set(self, domain: str, record_type: str, value: Any, ttl: int = None, 
                 nameserver: str = None) -> bool:
        """Set DNS record in cache"""
        cache_key = self._generate_cache_key(domain, record_type, nameserver)
        
        if ttl is None:
            ttl = self.config['cache']['ttl_default']
        
        # Enforce TTL limits
        ttl = max(self.config['cache']['ttl_min'], 
                 min(ttl, self.config['cache']['ttl_max']))
        
        try:
            now = datetime.now()
            entry = CacheEntry(
                key=cache_key,
                value=value,
                created_at=now,
                expires_at=now + timedelta(seconds=ttl),
                ttl=ttl,
                last_accessed=now
            )
            
            # Store in memory cache
            self.memory_cache[cache_key] = entry
            
            # Evict old entries if cache is full
            if len(self.memory_cache) > self.config['cache']['max_entries']:
                await self._evict_lru_entries()
            
            # Store in Redis if configured
            if self.redis_client and self.cache_backend in ['redis', 'hybrid']:
                try:
                    entry_data = entry.to_dict()
                    redis_data = pickle.dumps(entry_data)
                    await asyncio.to_thread(
                        self.redis_client.setex, 
                        cache_key, 
                        ttl, 
                        redis_data
                    )
                except Exception as e:
                    logger.warning(f"Redis cache set error: {e}")
            
            self.cache_stats['sets'] += 1
            return True
            
        except Exception as e:
            logger.error(f"Cache set error: {e}")
            return False
    
    async def delete(self, domain: str, record_type: str, nameserver: str = None) -> bool:
        """Delete DNS record from cache"""
        cache_key = self._generate_cache_key(domain, record_type, nameserver)
        
        try:
            deleted = False
            
            # Delete from memory cache
            if cache_key in self.memory_cache:
                del self.memory_cache[cache_key]
                deleted = True
            
            # Delete from Redis cache
            if self.redis_client and self.cache_backend in ['redis', 'hybrid']:
                try:
                    redis_deleted = await asyncio.to_thread(self.redis_client.delete, cache_key)
                    deleted = deleted or bool(redis_deleted)
                except Exception as e:
                    logger.warning(f"Redis cache delete error: {e}")
            
            if deleted:
                self.cache_stats['deletes'] += 1
            
            return deleted
            
        except Exception as e:
            logger.error(f"Cache delete error: {e}")
            return False
    
    async def invalidate_domain(self, domain: str) -> int:
        """Invalidate all cache entries for a domain"""
        domain_lower = domain.lower()
        deleted_count = 0
        
        try:
            # Invalidate memory cache
            keys_to_delete = []
            for cache_key, entry in self.memory_cache.items():
                # Check if the entry belongs to this domain
                # This is a simplified check - in production, you might want to store domain info in the entry
                if domain_lower in cache_key or any(domain_lower in str(v) for v in [entry.value] if isinstance(entry.value, (str, list))):
                    keys_to_delete.append(cache_key)
            
            for key in keys_to_delete:
                del self.memory_cache[key]
                deleted_count += 1
            
            # Invalidate Redis cache
            if self.redis_client and self.cache_backend in ['redis', 'hybrid']:
                try:
                    # Get all keys (this is expensive but necessary for domain invalidation)
                    all_keys = await asyncio.to_thread(self.redis_client.keys, '*')
                    keys_to_delete = []
                    
                    for key in all_keys:
                        try:
                            redis_data = await asyncio.to_thread(self.redis_client.get, key)
                            if redis_data:
                                entry_data = pickle.loads(redis_data)
                                if (domain_lower in key.decode() or 
                                    (isinstance(entry_data.get('value'), (str, list)) and 
                                     any(domain_lower in str(v) for v in [entry_data['value']]))):
                                    keys_to_delete.append(key)
                        except Exception:
                            continue
                    
                    if keys_to_delete:
                        redis_deleted = await asyncio.to_thread(self.redis_client.delete, *keys_to_delete)
                        deleted_count += redis_deleted
                        
                except Exception as e:
                    logger.warning(f"Redis domain invalidation error: {e}")
            
            logger.info(f"Invalidated {deleted_count} cache entries for domain {domain}")
            return deleted_count
            
        except Exception as e:
            logger.error(f"Domain invalidation error: {e}")
            return 0
    
    async def _evict_lru_entries(self):
        """Evict least recently used entries from memory cache"""
        target_size = int(self.config['cache']['max_entries'] * 0.9)  # Remove 10%
        
        # Sort entries by last access time
        sorted_entries = sorted(
            self.memory_cache.items(),
            key=lambda x: x[1].last_accessed or x[1].created_at
        )
        
        # Remove oldest entries
        entries_to_remove = len(sorted_entries) - target_size
        for i in range(entries_to_remove):
            cache_key = sorted_entries[i][0]
            del self.memory_cache[cache_key]
            self.cache_stats['evictions'] += 1
    
    async def _prefetch_record(self, domain: str, record_type: str, nameserver: str = None):
        """Prefetch DNS record to refresh cache"""
        try:
            # This would integrate with DNSManager to fetch fresh data
            # For now, this is a placeholder
            logger.debug(f"Prefetching {record_type} record for {domain}")
            
            # In a real implementation, you would:
            # 1. Use DNSManager to query the record
            # 2. Store the result in cache with updated TTL
            pass
            
        except Exception as e:
            logger.error(f"Prefetch error for {domain} {record_type}: {e}")
    
    async def _periodic_cleanup(self):
        """Periodic cleanup of expired cache entries"""
        while True:
            try:
                await asyncio.sleep(self.config['cache']['cleanup_interval'])
                
                # Clean memory cache
                expired_keys = []
                for cache_key, entry in self.memory_cache.items():
                    if entry.is_expired():
                        expired_keys.append(cache_key)
                
                for key in expired_keys:
                    del self.memory_cache[key]
                
                if expired_keys:
                    logger.info(f"Cleaned up {len(expired_keys)} expired cache entries")
                
            except Exception as e:
                logger.error(f"Cache cleanup error: {e}")
    
    async def optimize_ttl(self, domain: str, record_type: str, access_pattern: Dict) -> int:
        """Optimize TTL based on access patterns"""
        if not self.config['optimization']['auto_ttl_adjustment']:
            return self.config['cache']['ttl_default']
        
        try:
            cache_key = self._generate_cache_key(domain, record_type)
            
            if cache_key in self.memory_cache:
                entry = self.memory_cache[cache_key]
                
                # Only adjust if we have enough access data
                if entry.access_count >= self.config['optimization']['min_access_for_adjustment']:
                    # Calculate optimal TTL based on access frequency
                    access_per_hour = entry.access_count / max(1, (datetime.now() - entry.created_at).total_seconds() / 3600)
                    
                    if access_per_hour > 10:  # High frequency access
                        optimal_ttl = int(entry.ttl * self.config['optimization']['ttl_adjustment_factor'])
                    elif access_per_hour < 1:  # Low frequency access
                        optimal_ttl = int(entry.ttl / self.config['optimization']['ttl_adjustment_factor'])
                    else:
                        optimal_ttl = entry.ttl
                    
                    # Enforce limits
                    optimal_ttl = max(self.config['cache']['ttl_min'], 
                                    min(optimal_ttl, self.config['cache']['ttl_max']))
                    
                    return optimal_ttl
            
            return self.config['cache']['ttl_default']
            
        except Exception as e:
            logger.error(f"TTL optimization error: {e}")
            return self.config['cache']['ttl_default']
    
    def get_cache_stats(self) -> CacheStats:
        """Get cache statistics"""
        try:
            total_requests = self.cache_stats['hits'] + self.cache_stats['misses']
            hit_rate = (self.cache_stats['hits'] / total_requests) if total_requests > 0 else 0
            miss_rate = 1 - hit_rate
            
            # Count expired entries
            expired_count = sum(1 for entry in self.memory_cache.values() if entry.is_expired())
            
            # Calculate memory usage (approximate)
            memory_usage = sys.getsizeof(self.memory_cache)
            for entry in self.memory_cache.values():
                memory_usage += sys.getsizeof(entry.value)
            
            # Calculate average TTL
            avg_ttl = sum(entry.ttl for entry in self.memory_cache.values()) / len(self.memory_cache) if self.memory_cache else 0
            
            # Find most accessed entries
            most_accessed = sorted(
                [(key, entry.access_count) for key, entry in self.memory_cache.items()],
                key=lambda x: x[1],
                reverse=True
            )[:10]
            
            return CacheStats(
                total_entries=len(self.memory_cache),
                hit_rate=hit_rate,
                miss_rate=miss_rate,
                expired_entries=expired_count,
                memory_usage=memory_usage,
                avg_ttl=avg_ttl,
                most_accessed=[item[0] for item in most_accessed]
            )
            
        except Exception as e:
            logger.error(f"Cache stats error: {e}")
            return CacheStats(0, 0, 0, 0, 0, 0, [])
    
    async def warm_cache(self, domains: List[str], record_types: List[str] = None):
        """Warm cache with DNS records for specified domains"""
        if record_types is None:
            record_types = ['A', 'MX', 'TXT']
        
        logger.info(f"Warming cache for {len(domains)} domains")
        
        # This would integrate with DNSManager to fetch records
        # For now, this is a placeholder
        for domain in domains:
            for record_type in record_types:
                try:
                    # In real implementation:
                    # 1. Query DNS record using DNSManager
                    # 2. Store result in cache
                    logger.debug(f"Warming cache: {record_type} {domain}")
                    
                except Exception as e:
                    logger.error(f"Cache warming error for {domain} {record_type}: {e}")
        
        logger.info("Cache warming completed")
    
    async def export_cache(self, filepath: str, format: str = 'json'):
        """Export cache contents to file"""
        try:
            export_data = {
                'timestamp': datetime.now().isoformat(),
                'stats': asdict(self.get_cache_stats()),
                'entries': {}
            }
            
            for cache_key, entry in self.memory_cache.items():
                export_data['entries'][cache_key] = entry.to_dict()
            
            if format.lower() == 'yaml':
                with open(filepath, 'w') as f:
                    yaml.dump(export_data, f, default_flow_style=False)
            else:
                with open(filepath, 'w') as f:
                    json.dump(export_data, f, indent=2)
            
            logger.info(f"Cache exported to {filepath}")
            
        except Exception as e:
            logger.error(f"Cache export error: {e}")
    
    async def clear_cache(self) -> int:
        """Clear all cache entries"""
        try:
            memory_count = len(self.memory_cache)
            self.memory_cache.clear()
            
            redis_count = 0
            if self.redis_client and self.cache_backend in ['redis', 'hybrid']:
                try:
                    redis_count = await asyncio.to_thread(self.redis_client.flushdb)
                except Exception as e:
                    logger.warning(f"Redis cache clear error: {e}")
            
            total_cleared = memory_count + redis_count
            logger.info(f"Cleared {total_cleared} cache entries")
            
            return total_cleared
            
        except Exception as e:
            logger.error(f"Cache clear error: {e}")
            return 0

# CLI Interface
async def main():
    """Main CLI interface"""
    import argparse
    
    parser = argparse.ArgumentParser(description='DNS Cache Manager CLI')
    parser.add_argument('command', choices=[
        'stats', 'clear', 'export', 'warm', 'get', 'set', 'delete', 'invalidate'
    ])
    parser.add_argument('--config', help='Config file path')
    parser.add_argument('--domain', help='Domain name')
    parser.add_argument('--type', default='A', help='DNS record type')
    parser.add_argument('--value', help='Cache value')
    parser.add_argument('--ttl', type=int, help='TTL in seconds')
    parser.add_argument('--output', help='Output file path')
    parser.add_argument('--format', choices=['json', 'yaml'], default='json')
    parser.add_argument('--domains', nargs='+', help='List of domains for warming')
    
    args = parser.parse_args()
    
    try:
        cache_manager = DNSCacheManager(args.config)
        
        if args.command == 'stats':
            stats = cache_manager.get_cache_stats()
            output = asdict(stats)
            
        elif args.command == 'clear':
            count = await cache_manager.clear_cache()
            output = {'cleared_entries': count}
            
        elif args.command == 'export':
            output_path = args.output or f"dns-cache-export-{int(time.time())}.{args.format}"
            await cache_manager.export_cache(output_path, args.format)
            print(f"Cache exported to {output_path}")
            return
            
        elif args.command == 'warm':
            if not args.domains:
                raise ValueError("Domains required for warm command")
            await cache_manager.warm_cache(args.domains)
            output = {'status': 'Cache warming completed'}
            
        elif args.command == 'get':
            if not args.domain:
                raise ValueError("Domain required for get command")
            value = await cache_manager.get(args.domain, args.type)
            output = {'domain': args.domain, 'type': args.type, 'value': value}
            
        elif args.command == 'set':
            if not args.domain or not args.value:
                raise ValueError("Domain and value required for set command")
            success = await cache_manager.set(args.domain, args.type, args.value, args.ttl)
            output = {'domain': args.domain, 'type': args.type, 'success': success}
            
        elif args.command == 'delete':
            if not args.domain:
                raise ValueError("Domain required for delete command")
            success = await cache_manager.delete(args.domain, args.type)
            output = {'domain': args.domain, 'type': args.type, 'deleted': success}
            
        elif args.command == 'invalidate':
            if not args.domain:
                raise ValueError("Domain required for invalidate command")
            count = await cache_manager.invalidate_domain(args.domain)
            output = {'domain': args.domain, 'invalidated_entries': count}
        
        # Output results
        if args.format == 'yaml':
            print(yaml.dump(output, default_flow_style=False))
        else:
            print(json.dumps(output, indent=2))
            
    except Exception as e:
        logger.error(f"Command failed: {e}")
        sys.exit(1)

if __name__ == '__main__':
    asyncio.run(main())