#!/usr/bin/env python3
"""
Unit Tests for DNS Manager
Comprehensive testing of DNS management functionality including Cloudflare API integration
"""

import pytest
import asyncio
from unittest.mock import Mock, AsyncMock, patch, MagicMock
import json
import yaml
from datetime import datetime, timedelta
import os
import requests

# Import the DNS Manager under test
from dns.managers.dns_manager import DNSManager, DNSRecord, CloudflareAPIError

class TestDNSManager:
    """Test suite for DNS Manager functionality"""

    @pytest.fixture
    def mock_cloudflare_response(self):
        """Mock successful Cloudflare API response"""
        return {
            'success': True,
            'result': [
                {
                    'id': 'test_zone_123',
                    'name': 'test.com',
                    'status': 'active'
                }
            ],
            'result_info': {
                'page': 1,
                'per_page': 20,
                'count': 1,
                'total_count': 1,
                'total_pages': 1
            }
        }

    @pytest.fixture
    def mock_dns_records_response(self):
        """Mock DNS records response"""
        return {
            'success': True,
            'result': [
                {
                    'id': 'record_123',
                    'type': 'A',
                    'name': 'test.com',
                    'content': '192.168.1.100',
                    'ttl': 300,
                    'proxied': False
                },
                {
                    'id': 'record_456', 
                    'type': 'MX',
                    'name': 'test.com',
                    'content': 'mail.test.com',
                    'ttl': 300,
                    'priority': 10
                }
            ]
        }

    @pytest.fixture
    def dns_manager(self, mock_dns_config):
        """Create DNS manager instance for testing"""
        with patch.dict(os.environ, {'CLOUDFLARE_API_TOKEN': 'test_token_12345'}):
            manager = DNSManager(str(mock_dns_config))
            return manager

    def test_dns_manager_initialization(self, dns_manager):
        """Test DNS manager initializes correctly"""
        assert dns_manager.api_token == 'test_token_12345'
        assert dns_manager.base_url == 'https://api.cloudflare.com/client/v4'
        assert dns_manager.zones_cache == {}
        assert dns_manager.rate_limit_delay == 1

    def test_dns_record_creation(self):
        """Test DNS record data structure"""
        record = DNSRecord(
            type="A",
            name="test.example.com", 
            content="192.168.1.100",
            ttl=300,
            priority=None,
            proxied=False
        )
        
        assert record.type == "A"
        assert record.name == "test.example.com"
        assert record.content == "192.168.1.100"
        assert record.ttl == 300
        assert record.proxied is False
        
        record_dict = record.to_dict()
        assert record_dict['type'] == "A"
        assert record_dict['name'] == "test.example.com" 
        assert record_dict['content'] == "192.168.1.100"
        assert 'priority' not in record_dict  # Should not include None priority

    def test_dns_record_with_priority(self):
        """Test DNS record with priority (MX record)"""
        mx_record = DNSRecord(
            type="MX",
            name="test.com",
            content="mail.test.com",
            ttl=300,
            priority=10
        )
        
        record_dict = mx_record.to_dict()
        assert record_dict['priority'] == 10

    @pytest.mark.asyncio
    async def test_get_zones_success(self, dns_manager, mock_cloudflare_response):
        """Test successful zones retrieval"""
        with patch.object(dns_manager, '_make_request', new_callable=AsyncMock) as mock_request:
            mock_request.return_value = mock_cloudflare_response
            
            zones = await dns_manager.get_zones()
            
            assert 'test.com' in zones
            assert zones['test.com'] == 'test_zone_123'
            assert dns_manager.zones_cache == zones
            
            mock_request.assert_called_once_with('GET', '/zones')

    @pytest.mark.asyncio
    async def test_get_zones_caching(self, dns_manager, mock_cloudflare_response):
        """Test zones caching functionality"""
        # First call should make API request
        with patch.object(dns_manager, '_make_request', new_callable=AsyncMock) as mock_request:
            mock_request.return_value = mock_cloudflare_response
            
            zones1 = await dns_manager.get_zones()
            mock_request.assert_called_once()
            
            # Second call should use cache
            zones2 = await dns_manager.get_zones()
            mock_request.assert_called_once()  # Still only one call
            
            assert zones1 == zones2

    @pytest.mark.asyncio
    async def test_get_zones_force_refresh(self, dns_manager, mock_cloudflare_response):
        """Test forced zones refresh"""
        with patch.object(dns_manager, '_make_request', new_callable=AsyncMock) as mock_request:
            mock_request.return_value = mock_cloudflare_response
            
            # First call
            await dns_manager.get_zones()
            assert mock_request.call_count == 1
            
            # Force refresh should make new API call
            await dns_manager.get_zones(force_refresh=True)
            assert mock_request.call_count == 2

    @pytest.mark.asyncio
    async def test_get_zone_id_exact_match(self, dns_manager):
        """Test getting zone ID for exact domain match"""
        dns_manager.zones_cache = {'test.com': 'zone_123', 'example.com': 'zone_456'}
        
        zone_id = await dns_manager.get_zone_id('test.com')
        assert zone_id == 'zone_123'

    @pytest.mark.asyncio
    async def test_get_zone_id_parent_domain(self, dns_manager):
        """Test getting zone ID for subdomain (parent domain match)"""
        dns_manager.zones_cache = {'test.com': 'zone_123', 'example.com': 'zone_456'}
        
        zone_id = await dns_manager.get_zone_id('mail.test.com')
        assert zone_id == 'zone_123'

    @pytest.mark.asyncio
    async def test_get_zone_id_not_found(self, dns_manager):
        """Test zone ID lookup for non-existent domain"""
        dns_manager.zones_cache = {'test.com': 'zone_123'}
        
        with pytest.raises(ValueError, match="Zone not found for domain"):
            await dns_manager.get_zone_id('notfound.com')

    @pytest.mark.asyncio
    async def test_list_dns_records_success(self, dns_manager, mock_dns_records_response):
        """Test successful DNS records listing"""
        with patch.object(dns_manager, 'get_zone_id', new_callable=AsyncMock) as mock_get_zone:
            with patch.object(dns_manager, '_make_request', new_callable=AsyncMock) as mock_request:
                mock_get_zone.return_value = 'zone_123'
                mock_request.return_value = mock_dns_records_response
                
                records = await dns_manager.list_dns_records('test.com')
                
                assert len(records) == 2
                assert records[0]['type'] == 'A'
                assert records[1]['type'] == 'MX'
                
                mock_get_zone.assert_called_once_with('test.com')
                mock_request.assert_called_once()

    @pytest.mark.asyncio
    async def test_list_dns_records_with_filters(self, dns_manager, mock_dns_records_response):
        """Test DNS records listing with type and name filters"""
        with patch.object(dns_manager, 'get_zone_id', new_callable=AsyncMock) as mock_get_zone:
            with patch.object(dns_manager, '_make_request', new_callable=AsyncMock) as mock_request:
                mock_get_zone.return_value = 'zone_123'
                mock_request.return_value = mock_dns_records_response
                
                await dns_manager.list_dns_records('test.com', record_type='A', name='test.com')
                
                # Check that parameters were passed correctly
                call_args = mock_request.call_args
                assert call_args[0][0] == 'GET'  # method
                assert 'params' in call_args[1]
                assert call_args[1]['params']['type'] == 'A'
                assert call_args[1]['params']['name'] == 'test.com'

    @pytest.mark.asyncio
    async def test_create_dns_record_success(self, dns_manager):
        """Test successful DNS record creation"""
        mock_response = {
            'success': True,
            'result': {'id': 'new_record_123'}
        }
        
        test_record = DNSRecord(
            type="A",
            name="new.test.com",
            content="192.168.1.200",
            ttl=300
        )
        
        with patch.object(dns_manager, 'get_zone_id', new_callable=AsyncMock) as mock_get_zone:
            with patch.object(dns_manager, '_make_request', new_callable=AsyncMock) as mock_request:
                mock_get_zone.return_value = 'zone_123'
                mock_request.return_value = mock_response
                
                result = await dns_manager.create_dns_record('test.com', test_record)
                
                assert result['id'] == 'new_record_123'
                mock_get_zone.assert_called_once_with('test.com')
                mock_request.assert_called_once_with(
                    'POST',
                    '/zones/zone_123/dns_records',
                    data=test_record.to_dict()
                )

    @pytest.mark.asyncio
    async def test_update_dns_record_success(self, dns_manager):
        """Test successful DNS record update"""
        mock_response = {
            'success': True,
            'result': {'id': 'record_123', 'modified_on': datetime.now().isoformat()}
        }
        
        updated_record = DNSRecord(
            type="A",
            name="updated.test.com", 
            content="192.168.1.201",
            ttl=600
        )
        
        with patch.object(dns_manager, 'get_zone_id', new_callable=AsyncMock) as mock_get_zone:
            with patch.object(dns_manager, '_make_request', new_callable=AsyncMock) as mock_request:
                mock_get_zone.return_value = 'zone_123'
                mock_request.return_value = mock_response
                
                result = await dns_manager.update_dns_record('test.com', 'record_123', updated_record)
                
                assert result['id'] == 'record_123'
                mock_request.assert_called_once_with(
                    'PATCH',
                    '/zones/zone_123/dns_records/record_123',
                    data=updated_record.to_dict()
                )

    @pytest.mark.asyncio
    async def test_delete_dns_record_success(self, dns_manager):
        """Test successful DNS record deletion"""
        mock_response = {'success': True}
        
        with patch.object(dns_manager, 'get_zone_id', new_callable=AsyncMock) as mock_get_zone:
            with patch.object(dns_manager, '_make_request', new_callable=AsyncMock) as mock_request:
                mock_get_zone.return_value = 'zone_123'
                mock_request.return_value = mock_response
                
                result = await dns_manager.delete_dns_record('test.com', 'record_123')
                
                assert result is True
                mock_request.assert_called_once_with(
                    'DELETE',
                    '/zones/zone_123/dns_records/record_123'
                )

    @pytest.mark.asyncio
    async def test_bulk_create_records(self, dns_manager):
        """Test bulk DNS record creation"""
        test_records = [
            DNSRecord(type="A", name="bulk1.test.com", content="192.168.1.101"),
            DNSRecord(type="A", name="bulk2.test.com", content="192.168.1.102"),
            DNSRecord(type="CNAME", name="bulk3.test.com", content="bulk1.test.com")
        ]
        
        mock_response = {'success': True, 'result': {'id': 'record_123'}}
        
        with patch.object(dns_manager, 'create_dns_record', new_callable=AsyncMock) as mock_create:
            mock_create.return_value = mock_response['result']
            
            results = await dns_manager.bulk_create_records('test.com', test_records)
            
            assert len(results) == 3
            assert mock_create.call_count == 3
            
            # Verify all records were processed
            for result in results:
                assert 'id' in result

    @pytest.mark.asyncio 
    async def test_bulk_create_records_with_errors(self, dns_manager):
        """Test bulk creation with some failures"""
        test_records = [
            DNSRecord(type="A", name="good.test.com", content="192.168.1.101"),
            DNSRecord(type="A", name="bad.test.com", content="invalid_ip"),
        ]
        
        async def mock_create_side_effect(domain, record):
            if record.name == "good.test.com":
                return {'id': 'record_123'}
            else:
                raise Exception("Invalid IP address")
        
        with patch.object(dns_manager, 'create_dns_record', side_effect=mock_create_side_effect):
            results = await dns_manager.bulk_create_records('test.com', test_records)
            
            assert len(results) == 2
            assert 'id' in results[0]  # Success
            assert 'error' in results[1]  # Failure

    @pytest.mark.asyncio
    async def test_api_error_handling(self, dns_manager):
        """Test API error handling"""
        error_response = {
            'success': False,
            'errors': [
                {'code': 1003, 'message': 'Invalid API token'}
            ]
        }
        
        with patch.object(dns_manager, '_make_request', new_callable=AsyncMock) as mock_request:
            mock_request.return_value = error_response
            
            with pytest.raises(CloudflareAPIError, match="API Error"):
                await dns_manager.get_zones()

    @pytest.mark.asyncio
    async def test_rate_limiting_handling(self, dns_manager):
        """Test rate limiting and retry logic"""
        with patch('asyncio.sleep') as mock_sleep:
            with patch.object(dns_manager.session, 'request') as mock_request:
                # First call returns 429 (rate limited)
                mock_response_429 = Mock()
                mock_response_429.status_code = 429
                mock_response_429.headers = {'Retry-After': '5'}
                
                # Second call succeeds
                mock_response_200 = Mock()
                mock_response_200.status_code = 200
                mock_response_200.json.return_value = {'success': True, 'result': []}
                mock_response_200.raise_for_status.return_value = None
                
                mock_request.side_effect = [mock_response_429, mock_response_200]
                
                await dns_manager._make_request('GET', '/zones')
                
                # Verify sleep was called with retry-after value
                mock_sleep.assert_called_with(5)
                assert mock_request.call_count == 2

    @pytest.mark.asyncio
    async def test_request_retry_logic(self, dns_manager):
        """Test request retry logic on network failures"""
        with patch('asyncio.sleep') as mock_sleep:
            with patch.object(dns_manager.session, 'request') as mock_request:
                # Configure to fail twice then succeed
                mock_request.side_effect = [
                    requests.RequestException("Network error"),
                    requests.RequestException("Network error"),
                    Mock(status_code=200, json=lambda: {'success': True, 'result': []})
                ]
                
                # Should succeed after retries
                result = await dns_manager._make_request('GET', '/zones')
                
                assert result['success'] is True
                assert mock_request.call_count == 3
                assert mock_sleep.call_count == 2  # Two retry delays

    @pytest.mark.asyncio
    async def test_dns_validation_success(self, dns_manager):
        """Test DNS validation for email infrastructure"""
        mock_records = [
            {'type': 'MX', 'name': 'test.com', 'content': 'mail.test.com', 'priority': 10},
            {'type': 'MX', 'name': 'test.com', 'content': 'backup.test.com', 'priority': 20},
            {'type': 'TXT', 'name': 'test.com', 'content': 'v=spf1 include:_spf.test.com ~all'},
            {'type': 'TXT', 'name': '_dmarc.test.com', 'content': 'v=DMARC1; p=none;'},
            {'type': 'TXT', 'name': 'selector._domainkey.test.com', 'content': 'v=DKIM1; k=rsa; p=...'},
            {'type': 'A', 'name': 'test.com', 'content': '192.168.1.100'},
        ]
        
        with patch.object(dns_manager, 'list_dns_records', new_callable=AsyncMock) as mock_list:
            mock_list.return_value = mock_records
            
            validation = await dns_manager.validate_dns_records('test.com')
            
            assert validation['valid'] is True
            assert len(validation['errors']) == 0
            assert len(validation['warnings']) == 0

    @pytest.mark.asyncio
    async def test_dns_validation_missing_records(self, dns_manager):
        """Test DNS validation with missing critical records"""
        mock_records = [
            {'type': 'A', 'name': 'test.com', 'content': '192.168.1.100'},
        ]
        
        with patch.object(dns_manager, 'list_dns_records', new_callable=AsyncMock) as mock_list:
            mock_list.return_value = mock_records
            
            validation = await dns_manager.validate_dns_records('test.com')
            
            assert validation['valid'] is False
            assert "No MX records found" in validation['errors']
            assert "No SPF record found" in validation['errors']

    @pytest.mark.asyncio
    async def test_backup_dns_records(self, dns_manager, mock_dns_records_response, temp_dir):
        """Test DNS records backup functionality"""
        backup_file = temp_dir / "dns_backup.json"
        
        with patch.object(dns_manager, 'list_dns_records', new_callable=AsyncMock) as mock_list:
            mock_list.return_value = mock_dns_records_response['result']
            
            success = await dns_manager.backup_dns_records('test.com', str(backup_file))
            
            assert success is True
            assert backup_file.exists()
            
            # Verify backup content
            with open(backup_file, 'r') as f:
                backup_data = json.load(f)
            
            assert backup_data['domain'] == 'test.com'
            assert 'backup_date' in backup_data
            assert len(backup_data['records']) == 2

    def test_configuration_loading(self, temp_dir):
        """Test configuration file loading"""
        # Create test config
        config_data = {
            'cloudflare': {'api_token': 'config_token'},
            'rate_limit': {'requests_per_second': 5},
            'retry': {'max_attempts': 5}
        }
        
        config_file = temp_dir / "test_config.yaml"
        with open(config_file, 'w') as f:
            yaml.dump(config_data, f)
        
        with patch.dict(os.environ, {'CLOUDFLARE_API_TOKEN': ''}):
            dns_manager = DNSManager(str(config_file))
            
            assert dns_manager.api_token == 'config_token'
            assert dns_manager.config['rate_limit']['requests_per_second'] == 5
            assert dns_manager.config['retry']['max_attempts'] == 5

    def test_environment_variable_precedence(self, mock_dns_config):
        """Test environment variable takes precedence over config file"""
        with patch.dict(os.environ, {'CLOUDFLARE_API_TOKEN': 'env_token'}):
            dns_manager = DNSManager(str(mock_dns_config))
            assert dns_manager.api_token == 'env_token'

    def test_missing_api_token_raises_error(self, mock_dns_config):
        """Test that missing API token raises ValueError"""
        with patch.dict(os.environ, {}, clear=True):
            # Remove CLOUDFLARE_API_TOKEN from environment
            with pytest.raises(ValueError, match="Cloudflare API token not found"):
                DNSManager(str(mock_dns_config))

class TestDNSManagerIntegration:
    """Integration tests for DNS Manager"""

    @pytest.mark.integration
    @pytest.mark.asyncio
    async def test_full_dns_workflow(self, dns_manager):
        """Test complete DNS management workflow"""
        domain = "integration-test.com"
        
        # Mock the API calls in sequence
        with patch.object(dns_manager, '_make_request', new_callable=AsyncMock) as mock_request:
            # Mock responses for the workflow
            mock_request.side_effect = [
                # get_zones call
                {'success': True, 'result': [{'id': 'zone_123', 'name': domain}]},
                # list_dns_records call
                {'success': True, 'result': []},
                # create_dns_record call
                {'success': True, 'result': {'id': 'record_123'}},
                # update_dns_record call  
                {'success': True, 'result': {'id': 'record_123', 'modified_on': datetime.now().isoformat()}},
                # delete_dns_record call
                {'success': True}
            ]
            
            # Step 1: Get zones
            zones = await dns_manager.get_zones()
            assert domain in zones
            
            # Step 2: List existing records
            records = await dns_manager.list_dns_records(domain)
            assert len(records) == 0
            
            # Step 3: Create new record
            new_record = DNSRecord(type="A", name=f"test.{domain}", content="192.168.1.100")
            created = await dns_manager.create_dns_record(domain, new_record)
            assert created['id'] == 'record_123'
            
            # Step 4: Update the record
            updated_record = DNSRecord(type="A", name=f"test.{domain}", content="192.168.1.101")
            updated = await dns_manager.update_dns_record(domain, 'record_123', updated_record)
            assert updated['id'] == 'record_123'
            
            # Step 5: Delete the record
            deleted = await dns_manager.delete_dns_record(domain, 'record_123')
            assert deleted is True
            
            # Verify all API calls were made
            assert mock_request.call_count == 5

    @pytest.mark.performance
    @pytest.mark.asyncio
    async def test_bulk_operations_performance(self, dns_manager):
        """Test performance of bulk DNS operations"""
        import time
        
        # Create 50 test records
        test_records = []
        for i in range(50):
            test_records.append(
                DNSRecord(type="A", name=f"bulk{i}.test.com", content=f"192.168.1.{i+100}")
            )
        
        with patch.object(dns_manager, 'create_dns_record', new_callable=AsyncMock) as mock_create:
            mock_create.return_value = {'id': 'record_123'}
            
            start_time = time.time()
            results = await dns_manager.bulk_create_records('test.com', test_records)
            end_time = time.time()
            
            # Performance assertions
            execution_time = end_time - start_time
            assert execution_time < 30  # Should complete within 30 seconds
            assert len(results) == 50
            
            # Should have reasonable throughput
            operations_per_second = len(test_records) / execution_time
            assert operations_per_second >= 1  # At least 1 operation per second