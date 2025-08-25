#!/usr/bin/env python3
"""
Blacklist Monitor - Real-time blacklist checking and monitoring
Monitors IP addresses and domains across multiple blacklist databases
"""

import sys
import os
import json
import logging
import asyncio
import aiohttp
import sqlite3
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from typing import Dict, List, Optional, Tuple, Any
from enum import Enum
import dns.resolver
import dns.reversename
import socket
import time
import hashlib

# Add parent directory to path for imports
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

class BlacklistType(Enum):
    IP_BLACKLIST = "ip_blacklist"
    DOMAIN_BLACKLIST = "domain_blacklist"
    URL_BLACKLIST = "url_blacklist"
    REPUTATION_LIST = "reputation_list"

class CheckStatus(Enum):
    CLEAR = "clear"
    BLACKLISTED = "blacklisted"
    SUSPICIOUS = "suspicious"
    TIMEOUT = "timeout"
    ERROR = "error"

@dataclass
class BlacklistProvider:
    name: str
    type: BlacklistType
    dns_suffix: str
    query_method: str  # "dns", "http", "api"
    api_endpoint: str = None
    api_key: str = None
    timeout: int = 10
    weight: float = 1.0  # Impact weight for scoring
    description: str = ""

@dataclass
class BlacklistCheck:
    timestamp: datetime
    ip_address: str
    domain: str
    provider: str
    blacklist_type: BlacklistType
    status: CheckStatus
    response_time: float
    details: str = ""
    raw_response: str = ""

@dataclass
class MonitoringTarget:
    ip_address: str
    domain: str
    check_frequency: int  # minutes
    alert_threshold: int  # number of blacklists before alerting
    is_active: bool = True
    last_check: datetime = None
    blacklist_count: int = 0
    reputation_score: float = 10.0  # 0-10 scale

class BlacklistMonitor:
    def __init__(self, config_path: str = None):
        self.config_path = config_path or os.path.join(os.path.dirname(__file__), 'config/blacklist_config.json')
        self.db_path = os.path.join(os.path.dirname(__file__), 'logs/blacklist_monitor.db')
        
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(os.path.join(os.path.dirname(__file__), 'logs/blacklist_monitor.log')),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
        # Initialize database
        self._init_database()
        
        # Load configuration
        self.config = self._load_config()
        
        # Load blacklist providers
        self.providers = self._load_blacklist_providers()
        
        # Load monitoring targets
        self.targets = self._load_monitoring_targets()
        
        # DNS resolver
        self.resolver = dns.resolver.Resolver()
        self.resolver.timeout = 5
        self.resolver.lifetime = 10
        
        self.logger.info(f"Blacklist Monitor initialized with {len(self.providers)} providers and {len(self.targets)} targets")

    def _init_database(self):
        """Initialize SQLite database for blacklist tracking"""
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Create tables
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS blacklist_checks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                check_time TIMESTAMP NOT NULL,
                ip_address TEXT NOT NULL,
                domain TEXT,
                provider TEXT NOT NULL,
                blacklist_type TEXT NOT NULL,
                is_blacklisted BOOLEAN NOT NULL,
                status TEXT NOT NULL,
                response_time REAL,
                details TEXT,
                raw_response TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS monitoring_targets (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ip_address TEXT UNIQUE NOT NULL,
                domain TEXT,
                check_frequency INTEGER DEFAULT 60,
                alert_threshold INTEGER DEFAULT 1,
                is_active BOOLEAN DEFAULT TRUE,
                last_check TIMESTAMP,
                blacklist_count INTEGER DEFAULT 0,
                reputation_score REAL DEFAULT 10.0,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS blacklist_alerts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ip_address TEXT NOT NULL,
                domain TEXT,
                alert_type TEXT NOT NULL,
                severity TEXT NOT NULL,
                message TEXT,
                blacklist_count INTEGER,
                affected_providers TEXT,
                is_resolved BOOLEAN DEFAULT FALSE,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                resolved_at TIMESTAMP
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS provider_stats (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                provider_name TEXT NOT NULL,
                check_date DATE NOT NULL,
                total_checks INTEGER DEFAULT 0,
                successful_checks INTEGER DEFAULT 0,
                failed_checks INTEGER DEFAULT 0,
                avg_response_time REAL,
                blacklisted_count INTEGER DEFAULT 0,
                UNIQUE(provider_name, check_date)
            )
        ''')
        
        # Create indexes
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_checks_ip_time ON blacklist_checks(ip_address, check_time)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_checks_provider ON blacklist_checks(provider)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_targets_ip ON monitoring_targets(ip_address)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_alerts_ip ON blacklist_alerts(ip_address)')
        
        conn.commit()
        conn.close()

    def _load_config(self) -> Dict:
        """Load blacklist monitoring configuration"""
        if not os.path.exists(self.config_path):
            default_config = {
                "check_interval": 60,  # minutes
                "concurrent_checks": 10,
                "dns_timeout": 5,
                "http_timeout": 10,
                "retry_attempts": 3,
                "alert_settings": {
                    "email_alerts": True,
                    "slack_alerts": False,
                    "webhook_alerts": True,
                    "alert_cooldown": 3600  # seconds
                },
                "reputation_scoring": {
                    "base_score": 10.0,
                    "blacklist_penalty": 2.0,
                    "recovery_rate": 0.1  # per day
                }
            }
            
            os.makedirs(os.path.dirname(self.config_path), exist_ok=True)
            with open(self.config_path, 'w') as f:
                json.dump(default_config, f, indent=2)
        
        with open(self.config_path, 'r') as f:
            return json.load(f)

    def _load_blacklist_providers(self) -> List[BlacklistProvider]:
        """Load blacklist provider configurations"""
        return [
            # Major DNS-based blacklists
            BlacklistProvider(
                name="Spamhaus SBL",
                type=BlacklistType.IP_BLACKLIST,
                dns_suffix="sbl.spamhaus.org",
                query_method="dns",
                weight=3.0,
                description="Spamhaus Block List - known spam sources"
            ),
            BlacklistProvider(
                name="Spamhaus CSS",
                type=BlacklistType.IP_BLACKLIST,
                dns_suffix="css.spamhaus.org",
                query_method="dns",
                weight=2.5,
                description="Spamhaus CSS - compromised systems"
            ),
            BlacklistProvider(
                name="Spamhaus XBL",
                type=BlacklistType.IP_BLACKLIST,
                dns_suffix="xbl.spamhaus.org",
                query_method="dns",
                weight=2.0,
                description="Spamhaus Exploits Block List"
            ),
            BlacklistProvider(
                name="Spamhaus PBL",
                type=BlacklistType.IP_BLACKLIST,
                dns_suffix="pbl.spamhaus.org",
                query_method="dns",
                weight=1.5,
                description="Spamhaus Policy Block List"
            ),
            BlacklistProvider(
                name="Barracuda",
                type=BlacklistType.IP_BLACKLIST,
                dns_suffix="b.barracudacentral.org",
                query_method="dns",
                weight=2.0,
                description="Barracuda Reputation Block List"
            ),
            BlacklistProvider(
                name="SURBL",
                type=BlacklistType.DOMAIN_BLACKLIST,
                dns_suffix="multi.surbl.org",
                query_method="dns",
                weight=2.0,
                description="Spam URI Realtime Blocklists"
            ),
            BlacklistProvider(
                name="URIBL",
                type=BlacklistType.DOMAIN_BLACKLIST,
                dns_suffix="multi.uribl.com",
                query_method="dns",
                weight=2.0,
                description="URI Realtime Block List"
            ),
            BlacklistProvider(
                name="CBL",
                type=BlacklistType.IP_BLACKLIST,
                dns_suffix="cbl.abuseat.org",
                query_method="dns",
                weight=2.5,
                description="Composite Blocking List"
            ),
            BlacklistProvider(
                name="SORBS",
                type=BlacklistType.IP_BLACKLIST,
                dns_suffix="dnsbl.sorbs.net",
                query_method="dns",
                weight=1.5,
                description="Spam and Open Relay Blocking System"
            ),
            BlacklistProvider(
                name="SpamCop",
                type=BlacklistType.IP_BLACKLIST,
                dns_suffix="bl.spamcop.net",
                query_method="dns",
                weight=2.0,
                description="SpamCop Blocking List"
            ),
            BlacklistProvider(
                name="PSBL",
                type=BlacklistType.IP_BLACKLIST,
                dns_suffix="psbl.surriel.com",
                query_method="dns",
                weight=1.5,
                description="Passive Spam Block List"
            ),
            BlacklistProvider(
                name="Invaluement",
                type=BlacklistType.IP_BLACKLIST,
                dns_suffix="ivmSIP.invaluement.com",
                query_method="dns",
                weight=1.5,
                description="Invaluement IP Reputation List"
            ),
            BlacklistProvider(
                name="DRCC",
                type=BlacklistType.IP_BLACKLIST,
                dns_suffix="list.drcc.org",
                query_method="dns",
                weight=1.0,
                description="Distributed Reputation Clearing Center"
            ),
            # Additional reputation services
            BlacklistProvider(
                name="Project Honey Pot",
                type=BlacklistType.IP_BLACKLIST,
                dns_suffix="dnsbl.httpbl.org",
                query_method="dns",
                weight=1.5,
                description="Project Honey Pot HTTP Block List"
            ),
            BlacklistProvider(
                name="Manitu",
                type=BlacklistType.IP_BLACKLIST,
                dns_suffix="ix.dnsbl.manitu.net",
                query_method="dns",
                weight=1.0,
                description="Manitu DNS Blacklist"
            )
        ]

    def _load_monitoring_targets(self) -> List[MonitoringTarget]:
        """Load monitoring targets from database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT ip_address, domain, check_frequency, alert_threshold, 
                   is_active, last_check, blacklist_count, reputation_score
            FROM monitoring_targets WHERE is_active = TRUE
        ''')
        
        targets = []
        for row in cursor.fetchall():
            targets.append(MonitoringTarget(
                ip_address=row[0],
                domain=row[1],
                check_frequency=row[2],
                alert_threshold=row[3],
                is_active=bool(row[4]),
                last_check=datetime.fromisoformat(row[5]) if row[5] else None,
                blacklist_count=row[6],
                reputation_score=row[7]
            ))
        
        conn.close()
        return targets

    async def add_monitoring_target(self, ip_address: str, domain: str = None, 
                                  check_frequency: int = 60, alert_threshold: int = 1) -> int:
        """Add a new monitoring target"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        try:
            cursor.execute('''
                INSERT INTO monitoring_targets (ip_address, domain, check_frequency, alert_threshold)
                VALUES (?, ?, ?, ?)
            ''', (ip_address, domain, check_frequency, alert_threshold))
            
            target_id = cursor.lastrowid
            conn.commit()
            
            # Add to active targets
            self.targets.append(MonitoringTarget(
                ip_address=ip_address,
                domain=domain,
                check_frequency=check_frequency,
                alert_threshold=alert_threshold
            ))
            
            self.logger.info(f"Added monitoring target: {ip_address}")
            return target_id
            
        except sqlite3.IntegrityError:
            self.logger.warning(f"Target {ip_address} already exists")
            return None
        finally:
            conn.close()

    async def check_ip_blacklists(self, ip_address: str) -> List[BlacklistCheck]:
        """Check IP address against all IP blacklist providers"""
        checks = []
        
        # Filter providers for IP blacklists
        ip_providers = [p for p in self.providers if p.type == BlacklistType.IP_BLACKLIST]
        
        # Create concurrent check tasks
        tasks = []
        for provider in ip_providers:
            task = self._check_single_provider(ip_address, None, provider)
            tasks.append(task)
        
        # Execute checks concurrently
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        for result in results:
            if isinstance(result, BlacklistCheck):
                checks.append(result)
            elif isinstance(result, Exception):
                self.logger.error(f"Blacklist check failed: {str(result)}")
        
        # Save checks to database
        await self._save_blacklist_checks(checks)
        
        return checks

    async def check_domain_blacklists(self, domain: str) -> List[BlacklistCheck]:
        """Check domain against all domain blacklist providers"""
        checks = []
        
        # Filter providers for domain blacklists
        domain_providers = [p for p in self.providers if p.type == BlacklistType.DOMAIN_BLACKLIST]
        
        # Create concurrent check tasks
        tasks = []
        for provider in domain_providers:
            task = self._check_single_provider(None, domain, provider)
            tasks.append(task)
        
        # Execute checks concurrently
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        for result in results:
            if isinstance(result, BlacklistCheck):
                checks.append(result)
            elif isinstance(result, Exception):
                self.logger.error(f"Domain blacklist check failed: {str(result)}")
        
        # Save checks to database
        await self._save_blacklist_checks(checks)
        
        return checks

    async def _check_single_provider(self, ip_address: str, domain: str, 
                                   provider: BlacklistProvider) -> BlacklistCheck:
        """Check a single blacklist provider"""
        start_time = time.time()
        
        try:
            if provider.query_method == "dns":
                status, details, raw_response = await self._check_dns_blacklist(
                    ip_address, domain, provider
                )
            elif provider.query_method == "http":
                status, details, raw_response = await self._check_http_blacklist(
                    ip_address, domain, provider
                )
            elif provider.query_method == "api":
                status, details, raw_response = await self._check_api_blacklist(
                    ip_address, domain, provider
                )
            else:
                raise ValueError(f"Unsupported query method: {provider.query_method}")
            
            response_time = time.time() - start_time
            
            return BlacklistCheck(
                timestamp=datetime.now(),
                ip_address=ip_address or "",
                domain=domain or "",
                provider=provider.name,
                blacklist_type=provider.type,
                status=status,
                response_time=response_time,
                details=details,
                raw_response=raw_response
            )
            
        except Exception as e:
            response_time = time.time() - start_time
            self.logger.error(f"Error checking {provider.name}: {str(e)}")
            
            return BlacklistCheck(
                timestamp=datetime.now(),
                ip_address=ip_address or "",
                domain=domain or "",
                provider=provider.name,
                blacklist_type=provider.type,
                status=CheckStatus.ERROR,
                response_time=response_time,
                details=str(e),
                raw_response=""
            )

    async def _check_dns_blacklist(self, ip_address: str, domain: str, 
                                 provider: BlacklistProvider) -> Tuple[CheckStatus, str, str]:
        """Check DNS-based blacklist"""
        try:
            if provider.type == BlacklistType.IP_BLACKLIST and ip_address:
                # Reverse IP for DNS query
                octets = ip_address.split('.')
                reversed_ip = '.'.join(reversed(octets))
                query = f"{reversed_ip}.{provider.dns_suffix}"
                
            elif provider.type == BlacklistType.DOMAIN_BLACKLIST and domain:
                query = f"{domain}.{provider.dns_suffix}"
                
            else:
                return CheckStatus.ERROR, "Invalid IP/domain for provider type", ""
            
            # Perform DNS query
            try:
                result = self.resolver.resolve(query, 'A')
                
                # Different blacklists use different response codes
                response_ips = [str(rdata) for rdata in result]
                raw_response = ', '.join(response_ips)
                
                # Check for blacklisted response codes
                if any(self._is_blacklisted_response(ip, provider) for ip in response_ips):
                    return CheckStatus.BLACKLISTED, f"Listed in {provider.name}", raw_response
                else:
                    return CheckStatus.SUSPICIOUS, f"Unknown response from {provider.name}", raw_response
                    
            except dns.resolver.NXDOMAIN:
                # NXDOMAIN means not blacklisted
                return CheckStatus.CLEAR, "Not listed", ""
                
            except dns.resolver.Timeout:
                return CheckStatus.TIMEOUT, "DNS query timeout", ""
                
        except Exception as e:
            return CheckStatus.ERROR, str(e), ""

    def _is_blacklisted_response(self, response_ip: str, provider: BlacklistProvider) -> bool:
        """Check if DNS response indicates blacklisting"""
        # Common blacklist response patterns
        blacklist_responses = {
            "127.0.0.2": True,   # Generic blacklist response
            "127.0.0.3": True,   # Generic blacklist response
            "127.0.0.4": True,   # Generic blacklist response
            "127.0.0.9": True,   # PBL listing
            "127.0.0.10": True,  # CSS listing
            "127.0.0.11": True,  # CSS + PBL
        }
        
        # Provider-specific responses
        if provider.name == "Spamhaus SBL":
            return response_ip.startswith("127.0.0.")
        elif provider.name == "SpamCop":
            return response_ip == "127.0.0.2"
        elif provider.name == "SURBL":
            return response_ip in ["127.0.0.2", "127.0.0.4", "127.0.0.8", "127.0.0.16", "127.0.0.32", "127.0.0.64"]
        
        # Default check
        return response_ip in blacklist_responses or response_ip.startswith("127.0.0.")

    async def _check_http_blacklist(self, ip_address: str, domain: str, 
                                  provider: BlacklistProvider) -> Tuple[CheckStatus, str, str]:
        """Check HTTP-based blacklist"""
        try:
            url = provider.api_endpoint.format(ip=ip_address, domain=domain)
            
            async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=provider.timeout)) as session:
                async with session.get(url) as response:
                    content = await response.text()
                    
                    if response.status == 200:
                        # Parse response based on provider
                        if "blacklisted" in content.lower() or "listed" in content.lower():
                            return CheckStatus.BLACKLISTED, "Listed via HTTP API", content[:500]
                        else:
                            return CheckStatus.CLEAR, "Not listed via HTTP API", content[:500]
                    else:
                        return CheckStatus.ERROR, f"HTTP {response.status}", content[:500]
                        
        except asyncio.TimeoutError:
            return CheckStatus.TIMEOUT, "HTTP request timeout", ""
        except Exception as e:
            return CheckStatus.ERROR, str(e), ""

    async def _check_api_blacklist(self, ip_address: str, domain: str, 
                                 provider: BlacklistProvider) -> Tuple[CheckStatus, str, str]:
        """Check API-based blacklist"""
        try:
            url = provider.api_endpoint
            headers = {"Authorization": f"Bearer {provider.api_key}"} if provider.api_key else {}
            
            payload = {
                "ip": ip_address,
                "domain": domain
            }
            
            async with aiohttp.ClientSession(timeout=aiohttp.ClientTimeout(total=provider.timeout)) as session:
                async with session.post(url, json=payload, headers=headers) as response:
                    data = await response.json()
                    
                    if response.status == 200:
                        # Parse API response
                        is_blacklisted = data.get('blacklisted', False)
                        details = data.get('details', 'API check completed')
                        
                        status = CheckStatus.BLACKLISTED if is_blacklisted else CheckStatus.CLEAR
                        return status, details, json.dumps(data)
                    else:
                        return CheckStatus.ERROR, f"API error {response.status}", str(data)
                        
        except asyncio.TimeoutError:
            return CheckStatus.TIMEOUT, "API request timeout", ""
        except Exception as e:
            return CheckStatus.ERROR, str(e), ""

    async def _save_blacklist_checks(self, checks: List[BlacklistCheck]):
        """Save blacklist checks to database"""
        if not checks:
            return
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        for check in checks:
            cursor.execute('''
                INSERT INTO blacklist_checks 
                (check_time, ip_address, domain, provider, blacklist_type, 
                 is_blacklisted, status, response_time, details, raw_response)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                check.timestamp,
                check.ip_address,
                check.domain,
                check.provider,
                check.blacklist_type.value,
                check.status == CheckStatus.BLACKLISTED,
                check.status.value,
                check.response_time,
                check.details,
                check.raw_response
            ))
        
        conn.commit()
        conn.close()

    async def monitor_targets_continuously(self):
        """Continuously monitor all active targets"""
        self.logger.info("Starting continuous monitoring")
        
        while True:
            try:
                for target in self.targets:
                    if not target.is_active:
                        continue
                    
                    # Check if it's time to monitor this target
                    if (target.last_check is None or 
                        datetime.now() - target.last_check >= timedelta(minutes=target.check_frequency)):
                        
                        await self._monitor_single_target(target)
                        
                        # Update last check time
                        target.last_check = datetime.now()
                        await self._update_target_info(target)
                
                # Wait before next monitoring cycle
                await asyncio.sleep(60)  # Check every minute
                
            except Exception as e:
                self.logger.error(f"Error in continuous monitoring: {str(e)}")
                await asyncio.sleep(60)

    async def _monitor_single_target(self, target: MonitoringTarget):
        """Monitor a single target"""
        self.logger.debug(f"Monitoring target: {target.ip_address}")
        
        # Check IP blacklists
        ip_checks = await self.check_ip_blacklists(target.ip_address)
        
        # Check domain blacklists if domain is available
        domain_checks = []
        if target.domain:
            domain_checks = await self.check_domain_blacklists(target.domain)
        
        all_checks = ip_checks + domain_checks
        
        # Count blacklisted results
        blacklisted_checks = [c for c in all_checks if c.status == CheckStatus.BLACKLISTED]
        blacklist_count = len(blacklisted_checks)
        
        # Update target stats
        target.blacklist_count = blacklist_count
        
        # Calculate reputation score impact
        old_score = target.reputation_score
        penalty = blacklist_count * self.config['reputation_scoring']['blacklist_penalty']
        target.reputation_score = max(0.0, old_score - penalty)
        
        # Check if alert is needed
        if blacklist_count >= target.alert_threshold:
            await self._create_alert(target, blacklisted_checks)
        
        # Update provider statistics
        await self._update_provider_stats(all_checks)
        
        self.logger.debug(f"Target {target.ip_address}: {blacklist_count} blacklists, score: {target.reputation_score:.2f}")

    async def _update_target_info(self, target: MonitoringTarget):
        """Update target information in database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            UPDATE monitoring_targets 
            SET last_check = ?, blacklist_count = ?, reputation_score = ?, updated_at = ?
            WHERE ip_address = ?
        ''', (
            target.last_check,
            target.blacklist_count,
            target.reputation_score,
            datetime.now(),
            target.ip_address
        ))
        
        conn.commit()
        conn.close()

    async def _create_alert(self, target: MonitoringTarget, blacklisted_checks: List[BlacklistCheck]):
        """Create alert for blacklisted target"""
        affected_providers = [check.provider for check in blacklisted_checks]
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Check for recent similar alerts (cooldown)
        cursor.execute('''
            SELECT id FROM blacklist_alerts 
            WHERE ip_address = ? AND alert_type = 'blacklist_detected' 
            AND created_at > datetime('now', '-1 hour')
            AND is_resolved = FALSE
        ''', (target.ip_address,))
        
        if cursor.fetchone():
            conn.close()
            return  # Alert already exists within cooldown period
        
        # Create new alert
        severity = "critical" if target.blacklist_count >= 3 else "high" if target.blacklist_count >= 2 else "medium"
        
        message = f"IP {target.ip_address} detected on {target.blacklist_count} blacklists: {', '.join(affected_providers)}"
        
        cursor.execute('''
            INSERT INTO blacklist_alerts 
            (ip_address, domain, alert_type, severity, message, blacklist_count, affected_providers)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (
            target.ip_address,
            target.domain,
            'blacklist_detected',
            severity,
            message,
            target.blacklist_count,
            json.dumps(affected_providers)
        ))
        
        alert_id = cursor.lastrowid
        conn.commit()
        conn.close()
        
        self.logger.warning(f"ALERT: {message}")
        
        # Send notifications (implement based on config)
        await self._send_alert_notifications(alert_id, target, message, severity)

    async def _send_alert_notifications(self, alert_id: int, target: MonitoringTarget, 
                                      message: str, severity: str):
        """Send alert notifications via configured channels"""
        # This would integrate with alert-manager.py
        # For now, just log the alert
        self.logger.critical(f"BLACKLIST ALERT [{severity.upper()}]: {message}")

    async def _update_provider_stats(self, checks: List[BlacklistCheck]):
        """Update provider performance statistics"""
        if not checks:
            return
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Group checks by provider
        provider_stats = {}
        for check in checks:
            if check.provider not in provider_stats:
                provider_stats[check.provider] = {
                    'total': 0,
                    'successful': 0,
                    'failed': 0,
                    'response_times': [],
                    'blacklisted': 0
                }
            
            stats = provider_stats[check.provider]
            stats['total'] += 1
            
            if check.status in [CheckStatus.CLEAR, CheckStatus.BLACKLISTED, CheckStatus.SUSPICIOUS]:
                stats['successful'] += 1
                stats['response_times'].append(check.response_time)
            else:
                stats['failed'] += 1
            
            if check.status == CheckStatus.BLACKLISTED:
                stats['blacklisted'] += 1
        
        # Update database
        today = datetime.now().date()
        
        for provider_name, stats in provider_stats.items():
            avg_response_time = sum(stats['response_times']) / len(stats['response_times']) if stats['response_times'] else 0
            
            cursor.execute('''
                INSERT OR REPLACE INTO provider_stats 
                (provider_name, check_date, total_checks, successful_checks, 
                 failed_checks, avg_response_time, blacklisted_count)
                VALUES (?, ?, 
                    COALESCE((SELECT total_checks FROM provider_stats WHERE provider_name = ? AND check_date = ?), 0) + ?,
                    COALESCE((SELECT successful_checks FROM provider_stats WHERE provider_name = ? AND check_date = ?), 0) + ?,
                    COALESCE((SELECT failed_checks FROM provider_stats WHERE provider_name = ? AND check_date = ?), 0) + ?,
                    ?, 
                    COALESCE((SELECT blacklisted_count FROM provider_stats WHERE provider_name = ? AND check_date = ?), 0) + ?)
            ''', (
                provider_name, today,
                provider_name, today, stats['total'],
                provider_name, today, stats['successful'],
                provider_name, today, stats['failed'],
                avg_response_time,
                provider_name, today, stats['blacklisted']
            ))
        
        conn.commit()
        conn.close()

    def get_target_status(self, ip_address: str) -> Dict:
        """Get current status for a monitoring target"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Get target info
        cursor.execute('''
            SELECT * FROM monitoring_targets WHERE ip_address = ?
        ''', (ip_address,))
        
        target = cursor.fetchone()
        if not target:
            return {"error": "Target not found"}
        
        # Get recent checks
        cursor.execute('''
            SELECT provider, is_blacklisted, status, check_time, details
            FROM blacklist_checks 
            WHERE ip_address = ? AND check_time >= datetime('now', '-1 day')
            ORDER BY check_time DESC
        ''', (ip_address,))
        
        recent_checks = cursor.fetchall()
        
        # Get active alerts
        cursor.execute('''
            SELECT alert_type, severity, message, created_at
            FROM blacklist_alerts 
            WHERE ip_address = ? AND is_resolved = FALSE
            ORDER BY created_at DESC
        ''', (ip_address,))
        
        active_alerts = cursor.fetchall()
        
        conn.close()
        
        return {
            "ip_address": ip_address,
            "domain": target[2],
            "is_active": bool(target[4]),
            "last_check": target[5],
            "blacklist_count": target[6],
            "reputation_score": target[7],
            "check_frequency": target[3],
            "alert_threshold": target[4],
            "recent_checks": [
                {
                    "provider": check[0],
                    "is_blacklisted": bool(check[1]),
                    "status": check[2],
                    "check_time": check[3],
                    "details": check[4]
                } for check in recent_checks
            ],
            "active_alerts": [
                {
                    "type": alert[0],
                    "severity": alert[1],
                    "message": alert[2],
                    "created_at": alert[3]
                } for alert in active_alerts
            ]
        }

    def get_provider_performance(self, days: int = 7) -> Dict:
        """Get provider performance statistics"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT 
                provider_name,
                SUM(total_checks) as total_checks,
                SUM(successful_checks) as successful_checks,
                SUM(failed_checks) as failed_checks,
                AVG(avg_response_time) as avg_response_time,
                SUM(blacklisted_count) as blacklisted_count
            FROM provider_stats 
            WHERE check_date >= DATE('now', '-{} days')
            GROUP BY provider_name
            ORDER BY total_checks DESC
        '''.format(days), ())
        
        stats = cursor.fetchall()
        conn.close()
        
        return {
            "period_days": days,
            "providers": [
                {
                    "name": stat[0],
                    "total_checks": stat[1],
                    "successful_checks": stat[2],
                    "failed_checks": stat[3],
                    "success_rate": (stat[2] / stat[1] * 100) if stat[1] > 0 else 0,
                    "avg_response_time": stat[4],
                    "blacklisted_count": stat[5]
                } for stat in stats
            ]
        }

async def main():
    """Main function for CLI usage"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Blacklist Monitor")
    parser.add_argument('--config', help='Config file path')
    parser.add_argument('--add-target', nargs=2, help='Add monitoring target: IP DOMAIN')
    parser.add_argument('--check-ip', help='Check IP against blacklists')
    parser.add_argument('--check-domain', help='Check domain against blacklists')
    parser.add_argument('--monitor', action='store_true', help='Start continuous monitoring')
    parser.add_argument('--status', help='Get target status')
    parser.add_argument('--provider-stats', type=int, default=7, help='Get provider performance stats')
    
    args = parser.parse_args()
    
    monitor = BlacklistMonitor(args.config)
    
    if args.add_target:
        ip, domain = args.add_target
        target_id = await monitor.add_monitoring_target(ip, domain)
        print(f"Added target ID: {target_id}")
        
    elif args.check_ip:
        checks = await monitor.check_ip_blacklists(args.check_ip)
        print(f"Checked {len(checks)} providers:")
        for check in checks:
            print(f"  {check.provider}: {check.status.value} ({check.response_time:.2f}s)")
        
    elif args.check_domain:
        checks = await monitor.check_domain_blacklists(args.check_domain)
        print(f"Checked {len(checks)} providers:")
        for check in checks:
            print(f"  {check.provider}: {check.status.value} ({check.response_time:.2f}s)")
        
    elif args.monitor:
        await monitor.monitor_targets_continuously()
        
    elif args.status:
        status = monitor.get_target_status(args.status)
        print(json.dumps(status, indent=2, default=str))
        
    elif args.provider_stats:
        stats = monitor.get_provider_performance(args.provider_stats)
        print(json.dumps(stats, indent=2, default=str))
        
    else:
        parser.print_help()

if __name__ == "__main__":
    asyncio.run(main())