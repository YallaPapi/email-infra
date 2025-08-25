#!/usr/bin/env python3
"""
Pytest Configuration and Fixtures for Cold Email Infrastructure Testing
Provides shared fixtures, configuration, and utilities for all test modules
"""

import os
import sys
import json
import yaml
import pytest
import asyncio
import logging
from pathlib import Path
from typing import Dict, Any, List, Optional
from unittest.mock import Mock, AsyncMock, MagicMock, patch
import sqlite3
from datetime import datetime, timedelta
import tempfile
import shutil

# Add source directory to path
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root / "src" / "email-infrastructure"))

# Import system modules for testing
from dns.managers.dns_manager import DNSManager, DNSRecord
from mailcow.core.api_client import MailcowAPI, MailcowConfig
from vps.core.vps_manager import VPSManager
from monitoring.monitors.blacklist_monitor import BlacklistMonitor
from monitoring.campaigns.warmup_campaigns import WarmupCampaigns

# Test configuration
TEST_CONFIG_DIR = project_root / "tests" / "config"
TEST_DATA_DIR = project_root / "tests" / "data"
TEST_LOGS_DIR = project_root / "tests" / "logs"

# Create test directories
TEST_CONFIG_DIR.mkdir(parents=True, exist_ok=True)
TEST_DATA_DIR.mkdir(parents=True, exist_ok=True)
TEST_LOGS_DIR.mkdir(parents=True, exist_ok=True)

# Configure logging for tests
logging.basicConfig(
    level=logging.DEBUG,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(TEST_LOGS_DIR / 'test.log'),
        logging.StreamHandler()
    ]
)

@pytest.fixture(scope="session")
def event_loop():
    """Create an instance of the default event loop for the test session."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()

@pytest.fixture(scope="session")
def test_config():
    """Test configuration fixture"""
    return {
        'cloudflare': {
            'api_token': 'test_token_' + 'x' * 40,
            'test_domain': 'test-domain.com'
        },
        'mailcow': {
            'hostname': 'mail.test.com',
            'api_key': 'test_api_key_123',
            'verify_ssl': False
        },
        'vps': {
            'test_ip': '192.168.1.100',
            'primary_interface': 'eth0'
        },
        'monitoring': {
            'check_interval': 60,
            'alert_threshold': 1
        },
        'database': {
            'use_memory': True
        }
    }

@pytest.fixture
def temp_dir():
    """Create temporary directory for test files"""
    temp_path = tempfile.mkdtemp()
    yield Path(temp_path)
    shutil.rmtree(temp_path)

@pytest.fixture
def mock_config_file(temp_dir, test_config):
    """Create temporary config file for testing"""
    config_file = temp_dir / "test_config.yaml"
    with open(config_file, 'w') as f:
        yaml.dump(test_config, f)
    return config_file

@pytest.fixture
def mock_dns_config(temp_dir):
    """Mock DNS configuration"""
    config = {
        'cloudflare': {
            'api_token': 'test_token_mock',
            'base_url': 'https://api.cloudflare.com/client/v4'
        },
        'rate_limit': {
            'requests_per_second': 10,
            'burst_limit': 20
        },
        'retry': {
            'max_attempts': 2,
            'backoff_factor': 1
        },
        'dns': {
            'default_ttl': 300,
            'propagation_timeout': 60
        }
    }
    
    config_file = temp_dir / "cloudflare-config.yaml"
    with open(config_file, 'w') as f:
        yaml.dump(config, f)
    return config_file

@pytest.fixture
def sample_dns_records():
    """Sample DNS records for testing"""
    return [
        DNSRecord(type="A", name="test", content="192.168.1.100", ttl=300),
        DNSRecord(type="MX", name="mail", content="mail.test.com", ttl=300, priority=10),
        DNSRecord(type="TXT", name="_dmarc", content="v=DMARC1; p=none;", ttl=300),
        DNSRecord(type="TXT", name="test", content="v=spf1 include:_spf.test.com ~all", ttl=300),
        DNSRecord(type="CNAME", name="www", content="test.com", ttl=300)
    ]

@pytest.fixture
def mock_mailcow_config():
    """Mock Mailcow configuration"""
    return MailcowConfig(
        hostname="mail.test.com",
        api_key="test_api_key_12345",
        verify_ssl=False,
        timeout=30
    )

@pytest.fixture
def mock_database(temp_dir):
    """Create temporary SQLite database for testing"""
    db_path = temp_dir / "test_database.db"
    conn = sqlite3.connect(str(db_path))
    
    # Create tables for different modules
    cursor = conn.cursor()
    
    # DNS records table
    cursor.execute('''
        CREATE TABLE dns_records (
            id INTEGER PRIMARY KEY,
            domain TEXT,
            type TEXT,
            name TEXT,
            content TEXT,
            ttl INTEGER,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    # Mailcow domains table
    cursor.execute('''
        CREATE TABLE mailcow_domains (
            id INTEGER PRIMARY KEY,
            domain_name TEXT UNIQUE,
            active BOOLEAN DEFAULT TRUE,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    # VPS monitoring table
    cursor.execute('''
        CREATE TABLE vps_status (
            id INTEGER PRIMARY KEY,
            timestamp TIMESTAMP,
            cpu_usage REAL,
            memory_usage REAL,
            disk_usage REAL,
            network_status TEXT
        )
    ''')
    
    # Blacklist monitoring table
    cursor.execute('''
        CREATE TABLE blacklist_checks (
            id INTEGER PRIMARY KEY,
            ip_address TEXT,
            provider TEXT,
            is_blacklisted BOOLEAN,
            check_time TIMESTAMP,
            response_time REAL
        )
    ''')
    
    conn.commit()
    yield db_path
    conn.close()

@pytest.fixture
def mock_cloudflare_api():
    """Mock Cloudflare API responses"""
    mock_api = Mock()
    
    # Mock successful zone response
    mock_api.get_zones.return_value = {
        'success': True,
        'result': [
            {'id': 'zone123', 'name': 'test.com', 'status': 'active'},
            {'id': 'zone456', 'name': 'example.com', 'status': 'active'}
        ]
    }
    
    # Mock DNS records response
    mock_api.list_dns_records.return_value = {
        'success': True,
        'result': [
            {
                'id': 'record123',
                'type': 'A',
                'name': 'test.com',
                'content': '192.168.1.100',
                'ttl': 300
            }
        ]
    }
    
    # Mock create record response
    mock_api.create_dns_record.return_value = {
        'success': True,
        'result': {'id': 'new_record_123'}
    }
    
    return mock_api

@pytest.fixture
def mock_mailcow_api():
    """Mock Mailcow API responses"""
    mock_api = Mock()
    
    # Mock domains
    mock_api.get_domains.return_value = [
        {
            'domain_name': 'test.com',
            'active': True,
            'mailboxes': 10,
            'quota': 1024
        }
    ]
    
    # Mock mailboxes
    mock_api.get_mailboxes.return_value = [
        {
            'username': 'user@test.com',
            'active': True,
            'quota': 1024,
            'name': 'Test User'
        }
    ]
    
    # Mock successful operations
    mock_api.add_domain.return_value = {'success': True}
    mock_api.add_mailbox.return_value = {'success': True}
    mock_api.get_dkim.return_value = {'pubkey': 'test_dkim_key'}
    
    return mock_api

@pytest.fixture
def mock_network_interfaces():
    """Mock network interfaces for VPS testing"""
    return {
        'eth0': {
            'name': 'eth0',
            'is_up': True,
            'mtu': 1500,
            'speed': 1000,
            'addresses': [
                {
                    'ip': '192.168.1.100',
                    'netmask': '255.255.255.0',
                    'broadcast': '192.168.1.255',
                    'family': 'IPv4'
                }
            ]
        },
        'lo': {
            'name': 'lo',
            'is_up': True,
            'mtu': 65536,
            'speed': 0,
            'addresses': [
                {
                    'ip': '127.0.0.1',
                    'netmask': '255.0.0.0',
                    'broadcast': None,
                    'family': 'IPv4'
                }
            ]
        }
    }

@pytest.fixture
def mock_vps_status():
    """Mock VPS status for testing"""
    return {
        'timestamp': datetime.now().isoformat(),
        'hostname': 'test-vps',
        'system': {
            'cpu_usage_percent': 15.5,
            'cpu_count': 4,
            'memory_total_gb': 8.0,
            'memory_used_gb': 2.1,
            'memory_percent': 26.25,
            'uptime': '5 days, 12:34:56',
            'boot_time': datetime.now().isoformat()
        },
        'network': {
            'interfaces_count': 2,
            'available_ips': ['192.168.1.100'],
            'ip_count': 1,
            'connectivity': {
                'internet': True,
                'dns': True,
                'smtp_port': True
            },
            'primary_interface': 'eth0'
        },
        'disk': {
            'total_gb': 100.0,
            'used_gb': 25.5,
            'free_gb': 74.5,
            'percent': 25.5
        },
        'services': {
            'docker': True,
            'ufw': True,
            'fail2ban': True,
            'ssh': True
        },
        'load': {
            'load_1min': 0.5,
            'load_5min': 0.3,
            'load_15min': 0.2,
            'cpu_count': 4
        }
    }

@pytest.fixture
def mock_blacklist_providers():
    """Mock blacklist providers for testing"""
    return [
        {
            'name': 'Test Blacklist',
            'dns_suffix': 'test.blacklist.org',
            'type': 'ip_blacklist',
            'weight': 2.0
        },
        {
            'name': 'Another Test List', 
            'dns_suffix': 'another.test.org',
            'type': 'ip_blacklist',
            'weight': 1.5
        }
    ]

@pytest.fixture
def mock_warmup_mailboxes():
    """Mock warmup mailboxes for testing"""
    return [
        {
            'email': 'warmup1@test.com',
            'password': 'test_password_1',
            'smtp_host': 'smtp.test.com',
            'smtp_port': 587,
            'imap_host': 'imap.test.com', 
            'imap_port': 993,
            'provider': 'test_provider'
        },
        {
            'email': 'warmup2@test.com',
            'password': 'test_password_2',
            'smtp_host': 'smtp.test.com',
            'smtp_port': 587,
            'imap_host': 'imap.test.com',
            'imap_port': 993,
            'provider': 'test_provider'
        }
    ]

# DNS Manager Fixtures
@pytest.fixture
async def dns_manager(mock_dns_config):
    """Create DNS manager instance for testing"""
    with patch.dict(os.environ, {'CLOUDFLARE_API_TOKEN': 'test_token'}):
        manager = DNSManager(str(mock_dns_config))
        yield manager

# Mailcow API Fixtures  
@pytest.fixture
def mailcow_api(mock_mailcow_config):
    """Create Mailcow API instance for testing"""
    return MailcowAPI(
        hostname=mock_mailcow_config.hostname,
        api_key=mock_mailcow_config.api_key,
        verify_ssl=mock_mailcow_config.verify_ssl,
        timeout=mock_mailcow_config.timeout
    )

# VPS Manager Fixtures
@pytest.fixture
def vps_manager(temp_dir):
    """Create VPS manager instance for testing"""
    return VPSManager(config_path=str(temp_dir))

# Blacklist Monitor Fixtures
@pytest.fixture
def blacklist_monitor(temp_dir):
    """Create blacklist monitor instance for testing"""
    config_dir = temp_dir / "blacklist_config"
    config_dir.mkdir(exist_ok=True)
    return BlacklistMonitor(str(config_dir / "config.json"))

# Warmup Campaigns Fixtures
@pytest.fixture
def warmup_campaigns(temp_dir):
    """Create warmup campaigns instance for testing"""
    config_dir = temp_dir / "campaigns_config"
    config_dir.mkdir(exist_ok=True)
    return WarmupCampaigns(str(config_dir / "config.json"))

# HTTP Mock Fixtures
@pytest.fixture
def mock_http_responses():
    """Mock HTTP responses for API calls"""
    responses = {
        'cloudflare_zones': {
            'success': True,
            'result': [
                {'id': 'zone123', 'name': 'test.com'},
                {'id': 'zone456', 'name': 'example.com'}
            ]
        },
        'cloudflare_records': {
            'success': True,
            'result': [
                {
                    'id': 'record123',
                    'type': 'A',
                    'name': 'test',
                    'content': '192.168.1.100',
                    'ttl': 300
                }
            ]
        },
        'mailcow_status': {
            'status': 'active',
            'containers': ['mailcow-dockerized_postfix-mailcow_1']
        },
        'blacklist_response': {
            'listed': False,
            'response_time': 0.1
        }
    }
    return responses

# Performance Testing Fixtures
@pytest.fixture
def performance_config():
    """Configuration for performance testing"""
    return {
        'dns_operations_per_second': 10,
        'mailcow_operations_per_second': 5,
        'concurrent_connections': 10,
        'test_duration_seconds': 30,
        'memory_limit_mb': 512,
        'response_time_threshold_ms': 1000
    }

# Data Generation Fixtures
@pytest.fixture
def test_domains():
    """Generate test domains"""
    return [
        'test1.com',
        'example-test.org', 
        'demo.net',
        'sample-domain.info',
        'testing.biz'
    ]

@pytest.fixture
def test_ip_addresses():
    """Generate test IP addresses"""
    return [
        '192.168.1.100',
        '10.0.0.50',
        '172.16.0.10',
        '203.0.113.100',  # TEST-NET-3
        '198.51.100.50'   # TEST-NET-2
    ]

@pytest.fixture
def test_email_addresses():
    """Generate test email addresses"""
    return [
        'test1@test.com',
        'user@example.org',
        'admin@demo.net',
        'noreply@sample.info',
        'support@testing.biz'
    ]

# Integration Test Fixtures
@pytest.fixture(scope="session")
def integration_test_config():
    """Configuration for integration tests"""
    return {
        'run_integration_tests': os.getenv('RUN_INTEGRATION_TESTS', 'false').lower() == 'true',
        'test_timeout': int(os.getenv('TEST_TIMEOUT', '30')),
        'max_retries': int(os.getenv('MAX_RETRIES', '3')),
        'cleanup_on_failure': os.getenv('CLEANUP_ON_FAILURE', 'true').lower() == 'true'
    }

# Cleanup Fixtures
@pytest.fixture(autouse=True)
def cleanup_test_data():
    """Cleanup test data after each test"""
    yield
    # Cleanup logic here if needed
    pass

# Error Simulation Fixtures
@pytest.fixture
def network_error():
    """Simulate network errors"""
    return Exception("Network connection failed")

@pytest.fixture
def api_error():
    """Simulate API errors"""
    return Exception("API request failed with status 500")

@pytest.fixture
def timeout_error():
    """Simulate timeout errors"""
    return asyncio.TimeoutError("Request timed out")

# Validation Fixtures
@pytest.fixture
def validation_schemas():
    """JSON schemas for response validation"""
    return {
        'dns_record': {
            'type': 'object',
            'properties': {
                'id': {'type': 'string'},
                'type': {'type': 'string'},
                'name': {'type': 'string'},
                'content': {'type': 'string'},
                'ttl': {'type': 'integer'}
            },
            'required': ['id', 'type', 'name', 'content', 'ttl']
        },
        'vps_status': {
            'type': 'object',
            'properties': {
                'timestamp': {'type': 'string'},
                'hostname': {'type': 'string'},
                'system': {'type': 'object'},
                'network': {'type': 'object'},
                'disk': {'type': 'object'}
            },
            'required': ['timestamp', 'hostname', 'system', 'network', 'disk']
        }
    }

# Pytest configuration
def pytest_configure(config):
    """Configure pytest settings"""
    config.addinivalue_line(
        "markers", "unit: mark test as a unit test"
    )
    config.addinivalue_line(
        "markers", "integration: mark test as an integration test"
    )
    config.addinivalue_line(
        "markers", "e2e: mark test as an end-to-end test"
    )
    config.addinivalue_line(
        "markers", "performance: mark test as a performance test"
    )
    config.addinivalue_line(
        "markers", "slow: mark test as slow running"
    )

def pytest_collection_modifyitems(config, items):
    """Modify test collection to add markers"""
    for item in items:
        # Add unit test marker by default
        if not any(mark.name in ['integration', 'e2e', 'performance'] for mark in item.iter_markers()):
            item.add_marker(pytest.mark.unit)
        
        # Add slow marker for tests that take longer than 5 seconds
        if 'slow' in item.nodeid:
            item.add_marker(pytest.mark.slow)