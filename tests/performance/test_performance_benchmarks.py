#!/usr/bin/env python3
"""
Performance Benchmarks and Regression Tests
Comprehensive performance testing to ensure no degradation during refactoring
Tests throughput, response times, memory usage, and system limits
"""

import pytest
import asyncio
import time
import psutil
import threading
import statistics
import json
import os
from pathlib import Path
from typing import Dict, List, Any, Tuple
from unittest.mock import Mock, patch, AsyncMock
from concurrent.futures import ThreadPoolExecutor, as_completed
import memory_profiler
from dataclasses import dataclass
from datetime import datetime, timedelta

# Performance test configuration
PERFORMANCE_CONFIG = {
    'dns_operations_per_second': 10,
    'mailcow_operations_per_second': 5,
    'monitoring_checks_per_minute': 60,
    'vps_status_checks_per_second': 2,
    'concurrent_connections': 20,
    'test_duration_seconds': 30,
    'memory_limit_mb': 512,
    'response_time_threshold_ms': 1000,
    'cpu_usage_threshold_percent': 80
}

@dataclass
class PerformanceMetrics:
    """Performance metrics data structure"""
    operation: str
    total_operations: int
    successful_operations: int
    failed_operations: int
    duration_seconds: float
    operations_per_second: float
    avg_response_time_ms: float
    min_response_time_ms: float
    max_response_time_ms: float
    p95_response_time_ms: float
    memory_usage_mb: float
    cpu_usage_percent: float
    errors: List[str]

class PerformanceProfiler:
    """Performance profiling utility"""
    
    def __init__(self):
        self.metrics = {}
        self.start_time = None
        self.end_time = None
        self.process = psutil.Process()
        
    def start_profiling(self, operation: str):
        """Start performance profiling for an operation"""
        self.start_time = time.time()
        self.metrics[operation] = {
            'start_memory': self.process.memory_info().rss / 1024 / 1024,
            'start_cpu': self.process.cpu_percent(),
            'response_times': [],
            'errors': [],
            'operations': 0,
            'successful_operations': 0
        }
        
    def record_operation(self, operation: str, response_time_ms: float, success: bool, error: str = None):
        """Record individual operation metrics"""
        if operation in self.metrics:
            self.metrics[operation]['operations'] += 1
            self.metrics[operation]['response_times'].append(response_time_ms)
            
            if success:
                self.metrics[operation]['successful_operations'] += 1
            elif error:
                self.metrics[operation]['errors'].append(error)
    
    def end_profiling(self, operation: str) -> PerformanceMetrics:
        """End profiling and calculate metrics"""
        self.end_time = time.time()
        duration = self.end_time - self.start_time
        
        metrics_data = self.metrics[operation]
        response_times = metrics_data['response_times']
        
        return PerformanceMetrics(
            operation=operation,
            total_operations=metrics_data['operations'],
            successful_operations=metrics_data['successful_operations'],
            failed_operations=metrics_data['operations'] - metrics_data['successful_operations'],
            duration_seconds=duration,
            operations_per_second=metrics_data['operations'] / duration,
            avg_response_time_ms=statistics.mean(response_times) if response_times else 0,
            min_response_time_ms=min(response_times) if response_times else 0,
            max_response_time_ms=max(response_times) if response_times else 0,
            p95_response_time_ms=statistics.quantiles(response_times, n=20)[18] if len(response_times) > 20 else 0,
            memory_usage_mb=self.process.memory_info().rss / 1024 / 1024,
            cpu_usage_percent=self.process.cpu_percent(),
            errors=metrics_data['errors']
        )

class TestDNSPerformance:
    """DNS system performance tests"""
    
    @pytest.fixture
    def dns_manager(self):
        """Create DNS manager for performance testing"""
        try:
            from dns.managers.dns_manager import DNSManager
            with patch.dict(os.environ, {'CLOUDFLARE_API_TOKEN': 'test_token'}):
                return DNSManager()
        except ImportError:
            pytest.skip("DNS manager not available")
    
    @pytest.mark.performance
    def test_dns_zone_listing_performance(self, dns_manager):
        """Test DNS zone listing performance under load"""
        profiler = PerformanceProfiler()
        profiler.start_profiling("dns_zone_listing")
        
        # Mock zone response
        mock_response = {
            'success': True,
            'result': [{'id': f'zone_{i}', 'name': f'test{i}.com'} for i in range(100)]
        }
        
        with patch.object(dns_manager, '_make_request', new_callable=AsyncMock) as mock_request:
            mock_request.return_value = mock_response
            
            async def run_zone_tests():
                tasks = []
                for i in range(50):  # 50 concurrent zone listing operations
                    start_time = time.time()
                    try:
                        task = dns_manager.get_zones()
                        tasks.append(task)
                    except Exception as e:
                        profiler.record_operation("dns_zone_listing", 0, False, str(e))
                
                # Wait for all tasks to complete
                results = await asyncio.gather(*tasks, return_exceptions=True)
                
                for i, result in enumerate(results):
                    end_time = time.time()
                    response_time = (end_time - start_time) * 1000  # Convert to ms
                    
                    if isinstance(result, Exception):
                        profiler.record_operation("dns_zone_listing", response_time, False, str(result))
                    else:
                        profiler.record_operation("dns_zone_listing", response_time, True)
            
            # Run the async test
            asyncio.run(run_zone_tests())
        
        metrics = profiler.end_profiling("dns_zone_listing")
        
        # Performance assertions
        assert metrics.operations_per_second >= PERFORMANCE_CONFIG['dns_operations_per_second'], \
            f"DNS zone listing too slow: {metrics.operations_per_second:.2f} ops/sec"
        assert metrics.avg_response_time_ms <= PERFORMANCE_CONFIG['response_time_threshold_ms'], \
            f"DNS response time too high: {metrics.avg_response_time_ms:.2f}ms"
        assert metrics.memory_usage_mb <= PERFORMANCE_CONFIG['memory_limit_mb'], \
            f"DNS memory usage too high: {metrics.memory_usage_mb:.2f}MB"
        
        print(f"DNS Zone Listing Performance: {metrics.operations_per_second:.2f} ops/sec, "
              f"{metrics.avg_response_time_ms:.2f}ms avg response time")
    
    @pytest.mark.performance
    def test_dns_record_crud_performance(self, dns_manager):
        """Test DNS record CRUD operations performance"""
        from dns.managers.dns_manager import DNSRecord
        
        profiler = PerformanceProfiler()
        profiler.start_profiling("dns_record_crud")
        
        # Mock responses for CRUD operations
        mock_responses = {
            'create': {'success': True, 'result': {'id': 'record_123'}},
            'read': {'success': True, 'result': [{'id': 'record_123', 'type': 'A', 'name': 'test', 'content': '192.168.1.100'}]},
            'update': {'success': True, 'result': {'id': 'record_123', 'modified_on': '2023-01-01T00:00:00Z'}},
            'delete': {'success': True}
        }
        
        with patch.object(dns_manager, 'get_zone_id', new_callable=AsyncMock) as mock_zone_id:
            with patch.object(dns_manager, '_make_request', new_callable=AsyncMock) as mock_request:
                mock_zone_id.return_value = 'zone_123'
                
                async def crud_operations():
                    operations = ['create', 'read', 'update', 'delete']
                    
                    for i in range(20):  # 20 complete CRUD cycles
                        for op in operations:
                            start_time = time.time()
                            
                            try:
                                if op == 'create':
                                    mock_request.return_value = mock_responses['create']
                                    record = DNSRecord(type="A", name=f"test{i}", content=f"192.168.1.{i+100}")
                                    await dns_manager.create_dns_record("test.com", record)
                                elif op == 'read':
                                    mock_request.return_value = mock_responses['read']
                                    await dns_manager.list_dns_records("test.com")
                                elif op == 'update':
                                    mock_request.return_value = mock_responses['update']
                                    record = DNSRecord(type="A", name=f"test{i}", content=f"192.168.1.{i+101}")
                                    await dns_manager.update_dns_record("test.com", "record_123", record)
                                elif op == 'delete':
                                    mock_request.return_value = mock_responses['delete']
                                    await dns_manager.delete_dns_record("test.com", "record_123")
                                
                                end_time = time.time()
                                response_time = (end_time - start_time) * 1000
                                profiler.record_operation("dns_record_crud", response_time, True)
                                
                            except Exception as e:
                                end_time = time.time()
                                response_time = (end_time - start_time) * 1000
                                profiler.record_operation("dns_record_crud", response_time, False, str(e))
                
                await crud_operations()
        
        metrics = profiler.end_profiling("dns_record_crud")
        
        # Performance assertions
        assert metrics.operations_per_second >= 5, f"DNS CRUD operations too slow: {metrics.operations_per_second:.2f} ops/sec"
        assert metrics.avg_response_time_ms <= 500, f"DNS CRUD response time too high: {metrics.avg_response_time_ms:.2f}ms"
        assert metrics.successful_operations / metrics.total_operations >= 0.95, "DNS CRUD success rate too low"
        
        print(f"DNS CRUD Performance: {metrics.operations_per_second:.2f} ops/sec")

class TestMailcowPerformance:
    """Mailcow system performance tests"""
    
    @pytest.fixture
    def mailcow_api(self):
        """Create Mailcow API for performance testing"""
        try:
            from mailcow.core.api_client import MailcowAPI
            return MailcowAPI("mail.test.com", "test_key", verify_ssl=False)
        except ImportError:
            pytest.skip("Mailcow API not available")
    
    @pytest.mark.performance
    def test_mailcow_domain_operations_performance(self, mailcow_api):
        """Test Mailcow domain operations performance"""
        profiler = PerformanceProfiler()
        profiler.start_profiling("mailcow_domains")
        
        with patch.object(mailcow_api, '_request') as mock_request:
            mock_request.return_value = {"success": True}
            
            # Test concurrent domain operations
            def domain_operation(domain_id):
                start_time = time.time()
                
                try:
                    # Simulate domain operations
                    mailcow_api.get_domains()
                    mailcow_api.add_domain(f"test{domain_id}.com", description=f"Test domain {domain_id}")
                    mailcow_api.update_domain(f"test{domain_id}.com", active=True)
                    mailcow_api.delete_domain(f"test{domain_id}.com")
                    
                    end_time = time.time()
                    response_time = (end_time - start_time) * 1000
                    profiler.record_operation("mailcow_domains", response_time, True)
                    
                except Exception as e:
                    end_time = time.time()
                    response_time = (end_time - start_time) * 1000
                    profiler.record_operation("mailcow_domains", response_time, False, str(e))
            
            # Run concurrent operations
            with ThreadPoolExecutor(max_workers=10) as executor:
                futures = [executor.submit(domain_operation, i) for i in range(30)]
                for future in as_completed(futures):
                    future.result()  # Wait for completion
        
        metrics = profiler.end_profiling("mailcow_domains")
        
        # Performance assertions
        assert metrics.operations_per_second >= PERFORMANCE_CONFIG['mailcow_operations_per_second'], \
            f"Mailcow domain operations too slow: {metrics.operations_per_second:.2f} ops/sec"
        assert metrics.avg_response_time_ms <= 2000, f"Mailcow response time too high: {metrics.avg_response_time_ms:.2f}ms"
        
        print(f"Mailcow Domain Performance: {metrics.operations_per_second:.2f} ops/sec")
    
    @pytest.mark.performance
    def test_mailcow_bulk_mailbox_performance(self, mailcow_api):
        """Test bulk mailbox creation performance"""
        profiler = PerformanceProfiler()
        profiler.start_profiling("mailcow_bulk_mailboxes")
        
        with patch.object(mailcow_api, 'add_mailbox') as mock_add:
            mock_add.return_value = {"success": True}
            
            # Create bulk mailbox data
            mailboxes = []
            for i in range(50):
                mailboxes.append({
                    "email": f"bulkuser{i}@test.com",
                    "name": f"Bulk User {i}",
                    "quota": 1024
                })
            
            start_time = time.time()
            
            try:
                results = mailcow_api.bulk_mailbox_create(mailboxes)
                
                end_time = time.time()
                response_time = (end_time - start_time) * 1000
                
                # Record metrics for each mailbox
                for result in results:
                    success = result.get('success', True) is not False
                    profiler.record_operation("mailcow_bulk_mailboxes", response_time / len(results), success)
                
            except Exception as e:
                end_time = time.time()
                response_time = (end_time - start_time) * 1000
                profiler.record_operation("mailcow_bulk_mailboxes", response_time, False, str(e))
        
        metrics = profiler.end_profiling("mailcow_bulk_mailboxes")
        
        # Performance assertions
        assert metrics.operations_per_second >= 10, f"Mailcow bulk operations too slow: {metrics.operations_per_second:.2f} ops/sec"
        assert metrics.successful_operations >= 45, "Mailcow bulk operation success rate too low"
        
        print(f"Mailcow Bulk Mailbox Performance: {metrics.operations_per_second:.2f} ops/sec")

class TestVPSPerformance:
    """VPS system performance tests"""
    
    @pytest.fixture
    def vps_manager(self):
        """Create VPS manager for performance testing"""
        try:
            from vps.core.vps_manager import VPSManager
            return VPSManager()
        except ImportError:
            pytest.skip("VPS manager not available")
    
    @pytest.mark.performance
    def test_vps_status_collection_performance(self, vps_manager):
        """Test VPS status collection performance"""
        profiler = PerformanceProfiler()
        profiler.start_profiling("vps_status")
        
        with patch('psutil.cpu_percent', return_value=25.5):
            with patch('psutil.virtual_memory') as mock_memory:
                with patch('psutil.net_if_stats') as mock_net_stats:
                    with patch('psutil.disk_usage') as mock_disk:
                        # Mock system data
                        mock_memory.return_value = Mock(total=8589934592, used=2147483648, percent=25.0)
                        mock_net_stats.return_value = {'eth0': Mock(isup=True, mtu=1500)}
                        mock_disk.return_value = Mock(total=107374182400, used=26843545600, free=80530636800)
                        
                        # Test concurrent status collections
                        def collect_status():
                            start_time = time.time()
                            
                            try:
                                status = vps_manager.get_vps_status()
                                
                                end_time = time.time()
                                response_time = (end_time - start_time) * 1000
                                
                                # Verify status completeness
                                required_keys = ['timestamp', 'hostname', 'system', 'network', 'disk']
                                if all(key in status for key in required_keys):
                                    profiler.record_operation("vps_status", response_time, True)
                                else:
                                    profiler.record_operation("vps_status", response_time, False, "Incomplete status")
                                    
                            except Exception as e:
                                end_time = time.time()
                                response_time = (end_time - start_time) * 1000
                                profiler.record_operation("vps_status", response_time, False, str(e))
                        
                        # Run concurrent status collections
                        with ThreadPoolExecutor(max_workers=5) as executor:
                            futures = [executor.submit(collect_status) for _ in range(100)]
                            for future in as_completed(futures):
                                future.result()
        
        metrics = profiler.end_profiling("vps_status")
        
        # Performance assertions
        assert metrics.operations_per_second >= PERFORMANCE_CONFIG['vps_status_checks_per_second'], \
            f"VPS status collection too slow: {metrics.operations_per_second:.2f} ops/sec"
        assert metrics.avg_response_time_ms <= 200, f"VPS status response time too high: {metrics.avg_response_time_ms:.2f}ms"
        
        print(f"VPS Status Performance: {metrics.operations_per_second:.2f} ops/sec")
    
    @pytest.mark.performance
    def test_network_interface_detection_performance(self, vps_manager):
        """Test network interface detection performance"""
        profiler = PerformanceProfiler()
        profiler.start_profiling("network_interfaces")
        
        # Mock network interface data
        mock_stats = {
            'eth0': Mock(isup=True, mtu=1500, speed=1000),
            'eth1': Mock(isup=True, mtu=1500, speed=1000),
            'lo': Mock(isup=True, mtu=65536, speed=0)
        }
        
        mock_addrs = {
            'eth0': [Mock(family=2, address='192.168.1.100', netmask='255.255.255.0', broadcast='192.168.1.255')],
            'eth1': [Mock(family=2, address='10.0.0.100', netmask='255.255.255.0', broadcast='10.0.0.255')],
            'lo': [Mock(family=2, address='127.0.0.1', netmask='255.0.0.0', broadcast=None)]
        }
        
        with patch('psutil.net_if_stats', return_value=mock_stats):
            with patch('psutil.net_if_addrs', return_value=mock_addrs):
                
                # Test interface detection performance
                for i in range(50):
                    start_time = time.time()
                    
                    try:
                        interfaces = vps_manager.get_network_interfaces()
                        
                        end_time = time.time()
                        response_time = (end_time - start_time) * 1000
                        
                        if len(interfaces) >= 2:  # Should find at least eth0 and eth1
                            profiler.record_operation("network_interfaces", response_time, True)
                        else:
                            profiler.record_operation("network_interfaces", response_time, False, "Insufficient interfaces detected")
                            
                    except Exception as e:
                        end_time = time.time()
                        response_time = (end_time - start_time) * 1000
                        profiler.record_operation("network_interfaces", response_time, False, str(e))
        
        metrics = profiler.end_profiling("network_interfaces")
        
        # Performance assertions
        assert metrics.operations_per_second >= 20, f"Network interface detection too slow: {metrics.operations_per_second:.2f} ops/sec"
        assert metrics.avg_response_time_ms <= 50, f"Interface detection response time too high: {metrics.avg_response_time_ms:.2f}ms"
        
        print(f"Network Interface Performance: {metrics.operations_per_second:.2f} ops/sec")

class TestMonitoringPerformance:
    """Monitoring system performance tests"""
    
    @pytest.fixture
    def blacklist_monitor(self):
        """Create blacklist monitor for performance testing"""
        try:
            from monitoring.monitors.blacklist_monitor import BlacklistMonitor
            return BlacklistMonitor()
        except ImportError:
            pytest.skip("Blacklist monitor not available")
    
    @pytest.mark.performance
    def test_blacklist_checking_performance(self, blacklist_monitor):
        """Test blacklist checking performance under load"""
        profiler = PerformanceProfiler()
        profiler.start_profiling("blacklist_checks")
        
        # Mock DNS resolution for blacklist checks
        with patch('dns.resolver.Resolver.resolve') as mock_resolve:
            mock_resolve.side_effect = lambda query, record_type: Mock()
            
            async def run_blacklist_tests():
                test_ips = [f"192.168.1.{i}" for i in range(100, 200)]  # 100 test IPs
                
                tasks = []
                for ip in test_ips[:20]:  # Test 20 IPs concurrently
                    start_time = time.time()
                    
                    try:
                        task = blacklist_monitor.check_ip_blacklists(ip)
                        tasks.append((task, start_time, ip))
                    except Exception as e:
                        profiler.record_operation("blacklist_checks", 0, False, str(e))
                
                # Wait for all tasks
                for task, start_time, ip in tasks:
                    try:
                        results = await task
                        end_time = time.time()
                        response_time = (end_time - start_time) * 1000
                        
                        if results and len(results) > 0:
                            profiler.record_operation("blacklist_checks", response_time, True)
                        else:
                            profiler.record_operation("blacklist_checks", response_time, False, "No results")
                            
                    except Exception as e:
                        end_time = time.time()
                        response_time = (end_time - start_time) * 1000
                        profiler.record_operation("blacklist_checks", response_time, False, str(e))
            
            # Run the async test
            asyncio.run(run_blacklist_tests())
        
        metrics = profiler.end_profiling("blacklist_checks")
        
        # Performance assertions
        assert metrics.operations_per_second >= 1, f"Blacklist checking too slow: {metrics.operations_per_second:.2f} ops/sec"
        assert metrics.avg_response_time_ms <= 5000, f"Blacklist check response time too high: {metrics.avg_response_time_ms:.2f}ms"
        
        print(f"Blacklist Check Performance: {metrics.operations_per_second:.2f} ops/sec")

class TestSystemIntegrationPerformance:
    """System integration performance tests"""
    
    @pytest.mark.performance
    def test_full_workflow_performance(self):
        """Test complete workflow performance (DNS + Mailcow + Monitoring)"""
        profiler = PerformanceProfiler()
        profiler.start_profiling("full_workflow")
        
        try:
            from dns.managers.dns_manager import DNSManager, DNSRecord
            from mailcow.core.api_client import MailcowAPI
            from monitoring.monitors.blacklist_monitor import BlacklistMonitor
        except ImportError:
            pytest.skip("Required modules not available")
        
        # Initialize systems
        with patch.dict(os.environ, {'CLOUDFLARE_API_TOKEN': 'test_token'}):
            dns_manager = DNSManager()
        mailcow_api = MailcowAPI("mail.test.com", "test_key", verify_ssl=False)
        blacklist_monitor = BlacklistMonitor()
        
        # Mock all external API calls
        with patch.object(dns_manager, '_make_request', new_callable=AsyncMock) as mock_dns:
            with patch.object(mailcow_api, '_request') as mock_mailcow:
                with patch.object(blacklist_monitor, 'check_ip_blacklists', new_callable=AsyncMock) as mock_blacklist:
                    
                    # Configure mocks
                    mock_dns.return_value = {'success': True, 'result': {'id': 'record_123'}}
                    mock_mailcow.return_value = {'success': True}
                    mock_blacklist.return_value = [Mock(status='clear')]
                    
                    async def full_workflow():
                        for i in range(10):  # 10 complete workflows
                            start_time = time.time()
                            
                            try:
                                # Step 1: Create DNS record
                                record = DNSRecord(type="A", name=f"mail{i}.test.com", content=f"192.168.1.{i+100}")
                                await dns_manager.create_dns_record("test.com", record)
                                
                                # Step 2: Create mailbox
                                mailcow_api.add_mailbox(f"user{i}@test.com", "password123")
                                
                                # Step 3: Check blacklist status
                                await blacklist_monitor.check_ip_blacklists(f"192.168.1.{i+100}")
                                
                                end_time = time.time()
                                response_time = (end_time - start_time) * 1000
                                profiler.record_operation("full_workflow", response_time, True)
                                
                            except Exception as e:
                                end_time = time.time()
                                response_time = (end_time - start_time) * 1000
                                profiler.record_operation("full_workflow", response_time, False, str(e))
                    
                    # Run workflow test
                    asyncio.run(full_workflow())
        
        metrics = profiler.end_profiling("full_workflow")
        
        # Performance assertions
        assert metrics.avg_response_time_ms <= PERFORMANCE_CONFIG['test_duration_seconds'] * 1000, \
            f"Full workflow too slow: {metrics.avg_response_time_ms:.2f}ms"
        assert metrics.successful_operations >= 8, "Full workflow success rate too low"
        
        print(f"Full Workflow Performance: {metrics.avg_response_time_ms:.2f}ms avg, "
              f"{metrics.successful_operations}/{metrics.total_operations} successful")

class TestLoadTesting:
    """Load testing for system limits"""
    
    @pytest.mark.performance
    def test_concurrent_connection_limits(self):
        """Test system behavior under high concurrent load"""
        profiler = PerformanceProfiler()
        profiler.start_profiling("concurrent_load")
        
        try:
            from dns.managers.dns_manager import DNSManager
            from mailcow.core.api_client import MailcowAPI
        except ImportError:
            pytest.skip("Required modules not available")
        
        # Create multiple client instances
        clients = []
        with patch.dict(os.environ, {'CLOUDFLARE_API_TOKEN': 'test_token'}):
            for i in range(PERFORMANCE_CONFIG['concurrent_connections']):
                clients.append({
                    'dns': DNSManager(),
                    'mailcow': MailcowAPI(f"mail{i}.test.com", f"key_{i}", verify_ssl=False)
                })
        
        def concurrent_operation(client_id, client):
            start_time = time.time()
            
            try:
                # Simulate mixed operations
                with patch.object(client['dns'], '_make_request', new_callable=AsyncMock) as mock_dns:
                    with patch.object(client['mailcow'], '_request') as mock_mailcow:
                        mock_dns.return_value = {'success': True, 'result': []}
                        mock_mailcow.return_value = {'success': True}
                        
                        # Run operations
                        asyncio.run(client['dns'].get_zones())
                        client['mailcow'].get_domains()
                        
                        end_time = time.time()
                        response_time = (end_time - start_time) * 1000
                        profiler.record_operation("concurrent_load", response_time, True)
                        
            except Exception as e:
                end_time = time.time()
                response_time = (end_time - start_time) * 1000
                profiler.record_operation("concurrent_load", response_time, False, str(e))
        
        # Run concurrent operations
        with ThreadPoolExecutor(max_workers=PERFORMANCE_CONFIG['concurrent_connections']) as executor:
            futures = [
                executor.submit(concurrent_operation, i, clients[i]) 
                for i in range(len(clients))
            ]
            
            for future in as_completed(futures):
                future.result()
        
        metrics = profiler.end_profiling("concurrent_load")
        
        # Load testing assertions
        assert metrics.successful_operations >= PERFORMANCE_CONFIG['concurrent_connections'] * 0.8, \
            "System failed under concurrent load"
        assert metrics.avg_response_time_ms <= 5000, \
            f"Response time degraded under load: {metrics.avg_response_time_ms:.2f}ms"
        
        print(f"Concurrent Load Test: {metrics.successful_operations}/{metrics.total_operations} successful, "
              f"{metrics.avg_response_time_ms:.2f}ms avg response time")

    @pytest.mark.performance  
    @memory_profiler.profile
    def test_memory_leak_detection(self):
        """Test for memory leaks during extended operation"""
        initial_memory = psutil.Process().memory_info().rss / 1024 / 1024
        
        try:
            from dns.managers.dns_manager import DNSManager
            from mailcow.core.api_client import MailcowAPI
        except ImportError:
            pytest.skip("Required modules not available")
        
        # Simulate extended operations
        with patch.dict(os.environ, {'CLOUDFLARE_API_TOKEN': 'test_token'}):
            dns_manager = DNSManager()
        mailcow_api = MailcowAPI("mail.test.com", "test_key", verify_ssl=False)
        
        # Run operations repeatedly
        for i in range(1000):
            with patch.object(dns_manager, '_make_request', new_callable=AsyncMock) as mock_dns:
                with patch.object(mailcow_api, '_request') as mock_mailcow:
                    mock_dns.return_value = {'success': True, 'result': []}
                    mock_mailcow.return_value = {'success': True}
                    
                    # Perform operations
                    asyncio.run(dns_manager.get_zones())
                    mailcow_api.get_domains()
                    
                    # Periodic memory check
                    if i % 100 == 0:
                        current_memory = psutil.Process().memory_info().rss / 1024 / 1024
                        memory_growth = current_memory - initial_memory
                        
                        # Memory growth should be reasonable
                        assert memory_growth < 50, f"Potential memory leak: {memory_growth:.2f}MB growth after {i} operations"
        
        final_memory = psutil.Process().memory_info().rss / 1024 / 1024
        total_growth = final_memory - initial_memory
        
        print(f"Memory usage: {initial_memory:.2f}MB -> {final_memory:.2f}MB (+{total_growth:.2f}MB)")
        
        # Final memory check
        assert total_growth < 100, f"Memory leak detected: {total_growth:.2f}MB growth"

def save_performance_report(metrics_list: List[PerformanceMetrics], report_path: Path):
    """Save performance test results to JSON report"""
    report_data = {
        'timestamp': datetime.now().isoformat(),
        'test_config': PERFORMANCE_CONFIG,
        'results': []
    }
    
    for metrics in metrics_list:
        report_data['results'].append({
            'operation': metrics.operation,
            'total_operations': metrics.total_operations,
            'successful_operations': metrics.successful_operations,
            'duration_seconds': metrics.duration_seconds,
            'operations_per_second': metrics.operations_per_second,
            'avg_response_time_ms': metrics.avg_response_time_ms,
            'p95_response_time_ms': metrics.p95_response_time_ms,
            'memory_usage_mb': metrics.memory_usage_mb,
            'cpu_usage_percent': metrics.cpu_usage_percent,
            'error_count': len(metrics.errors)
        })
    
    with open(report_path, 'w') as f:
        json.dump(report_data, f, indent=2)

if __name__ == "__main__":
    print("Running performance benchmarks...")
    
    # Create reports directory
    reports_dir = Path(__file__).parent.parent / "reports"
    reports_dir.mkdir(exist_ok=True)
    
    # Run performance tests and collect metrics
    # This would normally be done by pytest, but we can simulate it
    print("Performance benchmark framework ready for execution with pytest -m performance")