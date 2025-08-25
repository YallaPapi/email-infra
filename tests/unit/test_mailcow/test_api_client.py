#!/usr/bin/env python3
"""
Unit Tests for Mailcow API Client
Comprehensive testing of Mailcow API operations and email server management
"""

import pytest
import json
import requests
from unittest.mock import Mock, patch, MagicMock
from requests.exceptions import RequestException, Timeout

# Import the Mailcow API client under test
from mailcow.core.api_client import MailcowAPI, MailcowConfig, MailcowAPIError

class TestMailcowAPI:
    """Test suite for Mailcow API client functionality"""

    @pytest.fixture
    def mailcow_config(self):
        """Standard Mailcow configuration for testing"""
        return MailcowConfig(
            hostname="mail.test.com",
            api_key="test_api_key_12345",
            verify_ssl=False,
            timeout=30
        )

    @pytest.fixture
    def mailcow_api(self, mailcow_config):
        """Create Mailcow API instance for testing"""
        return MailcowAPI(
            hostname=mailcow_config.hostname,
            api_key=mailcow_config.api_key,
            verify_ssl=mailcow_config.verify_ssl,
            timeout=mailcow_config.timeout
        )

    @pytest.fixture
    def mock_successful_response(self):
        """Mock successful HTTP response"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"status": "success", "data": []}
        mock_response.text = '{"status": "success", "data": []}'
        mock_response.raise_for_status.return_value = None
        return mock_response

    @pytest.fixture
    def mock_domains_response(self):
        """Mock domains API response"""
        return [
            {
                "domain_name": "test.com",
                "active": True,
                "aliases": 100,
                "mailboxes": 10,
                "quota": 3072,
                "backupmx": False
            },
            {
                "domain_name": "example.org",
                "active": True,
                "aliases": 50,
                "mailboxes": 5,
                "quota": 1024,
                "backupmx": False
            }
        ]

    @pytest.fixture
    def mock_mailboxes_response(self):
        """Mock mailboxes API response"""
        return [
            {
                "username": "user@test.com",
                "name": "Test User",
                "active": True,
                "quota": 1024,
                "percent_in_use": 25.5,
                "messages": 150
            },
            {
                "username": "admin@test.com", 
                "name": "Admin User",
                "active": True,
                "quota": 2048,
                "percent_in_use": 10.2,
                "messages": 75
            }
        ]

    def test_mailcow_api_initialization(self, mailcow_api):
        """Test Mailcow API client initializes correctly"""
        assert mailcow_api.hostname == "mail.test.com"
        assert mailcow_api.api_key == "test_api_key_12345"
        assert mailcow_api.verify_ssl is False
        assert mailcow_api.timeout == 30
        assert mailcow_api.base_url == "https://mail.test.com/api/v1"
        
        # Check session headers
        assert mailcow_api.session.headers['X-API-Key'] == "test_api_key_12345"
        assert mailcow_api.session.headers['Content-Type'] == "application/json"

    def test_hostname_stripping(self):
        """Test hostname trailing slash removal"""
        api = MailcowAPI("mail.test.com/", "test_key")
        assert api.hostname == "mail.test.com"

    @patch('requests.Session.request')
    def test_successful_get_request(self, mock_request, mailcow_api, mock_successful_response):
        """Test successful GET request"""
        mock_request.return_value = mock_successful_response
        
        result = mailcow_api.get('test/endpoint')
        
        assert result == {"status": "success", "data": []}
        mock_request.assert_called_once_with(
            method='GET',
            url='https://mail.test.com/api/v1/test/endpoint',
            json=None,
            params=None,
            verify=False,
            timeout=30
        )

    @patch('requests.Session.request')
    def test_successful_post_request(self, mock_request, mailcow_api, mock_successful_response):
        """Test successful POST request"""
        mock_request.return_value = mock_successful_response
        test_data = {"domain": "test.com", "active": True}
        
        result = mailcow_api.post('add/domain', test_data)
        
        assert result == {"status": "success", "data": []}
        mock_request.assert_called_once_with(
            method='POST',
            url='https://mail.test.com/api/v1/add/domain',
            json=test_data,
            params=None,
            verify=False,
            timeout=30
        )

    @patch('requests.Session.request')
    def test_request_with_params(self, mock_request, mailcow_api, mock_successful_response):
        """Test request with query parameters"""
        mock_request.return_value = mock_successful_response
        params = {"domain": "test.com", "active": "1"}
        
        mailcow_api.get('get/mailbox/all', params=params)
        
        call_args = mock_request.call_args
        assert call_args[1]['params'] == params

    @patch('requests.Session.request')
    def test_http_error_handling(self, mock_request, mailcow_api):
        """Test HTTP error handling"""
        mock_response = Mock()
        mock_response.status_code = 500
        mock_response.raise_for_status.side_effect = requests.HTTPError("Internal Server Error")
        mock_response.text = "Internal Server Error"
        mock_request.return_value = mock_response
        
        with pytest.raises(MailcowAPIError, match="API request failed"):
            mailcow_api.get('test/endpoint')

    @patch('requests.Session.request')
    def test_network_error_handling(self, mock_request, mailcow_api):
        """Test network error handling"""
        mock_request.side_effect = requests.ConnectionError("Network error")
        
        with pytest.raises(MailcowAPIError, match="API request failed"):
            mailcow_api.get('test/endpoint')

    @patch('requests.Session.request')
    def test_timeout_handling(self, mock_request, mailcow_api):
        """Test timeout handling"""
        mock_request.side_effect = Timeout("Request timeout")
        
        with pytest.raises(MailcowAPIError, match="API request failed"):
            mailcow_api.get('test/endpoint')

    @patch('requests.Session.request')
    def test_empty_response_handling(self, mock_request, mailcow_api):
        """Test handling of empty responses"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.content = b''
        mock_response.raise_for_status.return_value = None
        mock_request.return_value = mock_response
        
        result = mailcow_api.get('test/endpoint')
        assert result == {}

    @patch('requests.Session.request')
    def test_json_decode_error_handling(self, mock_request, mailcow_api):
        """Test JSON decode error handling"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.content = b'invalid json'
        mock_response.json.side_effect = json.JSONDecodeError("Invalid JSON", "doc", 0)
        mock_response.raise_for_status.return_value = None
        mock_request.return_value = mock_response
        
        with pytest.raises(MailcowAPIError, match="Failed to decode JSON response"):
            mailcow_api.get('test/endpoint')

    # Domain Management Tests
    @patch('requests.Session.request')
    def test_get_domains_success(self, mock_request, mailcow_api, mock_domains_response):
        """Test successful domains retrieval"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = mock_domains_response
        mock_response.raise_for_status.return_value = None
        mock_request.return_value = mock_response
        
        domains = mailcow_api.get_domains()
        
        assert len(domains) == 2
        assert domains[0]['domain_name'] == 'test.com'
        assert domains[1]['domain_name'] == 'example.org'

    @patch('requests.Session.request')
    def test_get_domains_non_list_response(self, mock_request, mailcow_api):
        """Test domains retrieval with non-list response"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"error": "No domains found"}
        mock_response.raise_for_status.return_value = None
        mock_request.return_value = mock_response
        
        domains = mailcow_api.get_domains()
        assert domains == []

    @patch('requests.Session.request')
    def test_get_specific_domain(self, mock_request, mailcow_api):
        """Test getting specific domain details"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"domain_name": "test.com", "active": True}
        mock_response.raise_for_status.return_value = None
        mock_request.return_value = mock_response
        
        domain = mailcow_api.get_domain("test.com")
        
        assert domain['domain_name'] == 'test.com'
        mock_request.assert_called_once_with(
            method='GET',
            url='https://mail.test.com/api/v1/get/domain/test.com',
            json=None,
            params=None,
            verify=False,
            timeout=30
        )

    @patch('requests.Session.request')
    def test_add_domain_success(self, mock_request, mailcow_api):
        """Test successful domain addition"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"success": True}
        mock_response.raise_for_status.return_value = None
        mock_request.return_value = mock_response
        
        result = mailcow_api.add_domain(
            domain="newdomain.com",
            description="Test domain",
            aliases=500,
            mailboxes=20,
            quota=5120,
            active=True
        )
        
        assert result == {"success": True}
        
        # Verify request data
        call_args = mock_request.call_args
        request_data = call_args[1]['json']
        assert request_data['domain'] == "newdomain.com"
        assert request_data['description'] == "Test domain"
        assert request_data['aliases'] == 500
        assert request_data['mailboxes'] == 20
        assert request_data['quota'] == 5120
        assert request_data['active'] == 1  # Should be converted to int

    @patch('requests.Session.request')
    def test_update_domain(self, mock_request, mailcow_api):
        """Test domain update"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"success": True}
        mock_response.raise_for_status.return_value = None
        mock_request.return_value = mock_response
        
        result = mailcow_api.update_domain("test.com", quota=10240, active=False)
        
        assert result == {"success": True}
        
        # Verify request structure
        call_args = mock_request.call_args
        request_data = call_args[1]['json']
        assert request_data['items'] == ['test.com']
        assert 'attr' in request_data

    @patch('requests.Session.request')
    def test_delete_domain(self, mock_request, mailcow_api):
        """Test domain deletion"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"success": True}
        mock_response.raise_for_status.return_value = None
        mock_request.return_value = mock_response
        
        result = mailcow_api.delete_domain("test.com")
        
        assert result == {"success": True}
        
        # Verify request data
        call_args = mock_request.call_args
        request_data = call_args[1]['json']
        assert request_data == ["test.com"]

    # Mailbox Management Tests
    @patch('requests.Session.request')
    def test_get_all_mailboxes(self, mock_request, mailcow_api, mock_mailboxes_response):
        """Test getting all mailboxes"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = mock_mailboxes_response
        mock_response.raise_for_status.return_value = None
        mock_request.return_value = mock_response
        
        mailboxes = mailcow_api.get_mailboxes()
        
        assert len(mailboxes) == 2
        assert mailboxes[0]['username'] == 'user@test.com'
        
        mock_request.assert_called_once_with(
            method='GET',
            url='https://mail.test.com/api/v1/get/mailbox/all',
            json=None,
            params=None,
            verify=False,
            timeout=30
        )

    @patch('requests.Session.request')
    def test_get_domain_mailboxes(self, mock_request, mailcow_api, mock_mailboxes_response):
        """Test getting mailboxes for specific domain"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = mock_mailboxes_response
        mock_response.raise_for_status.return_value = None
        mock_request.return_value = mock_response
        
        mailboxes = mailcow_api.get_mailboxes(domain="test.com")
        
        assert len(mailboxes) == 2
        mock_request.assert_called_once_with(
            method='GET',
            url='https://mail.test.com/api/v1/get/mailbox/test.com',
            json=None,
            params=None,
            verify=False,
            timeout=30
        )

    @patch('requests.Session.request') 
    def test_add_mailbox_success(self, mock_request, mailcow_api):
        """Test successful mailbox creation"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"success": True}
        mock_response.raise_for_status.return_value = None
        mock_request.return_value = mock_response
        
        result = mailcow_api.add_mailbox(
            email="newuser@test.com",
            password="securepassword123",
            name="New User",
            quota=2048,
            active=True
        )
        
        assert result == {"success": True}
        
        # Verify request data structure
        call_args = mock_request.call_args
        request_data = call_args[1]['json']
        assert request_data['local_part'] == "newuser"
        assert request_data['domain'] == "test.com"
        assert request_data['password'] == "securepassword123"
        assert request_data['password2'] == "securepassword123"
        assert request_data['name'] == "New User"
        assert request_data['quota'] == 2048
        assert request_data['active'] == 1

    def test_mailbox_email_parsing(self, mailcow_api):
        """Test email address parsing for mailbox creation"""
        with patch.object(mailcow_api, 'post') as mock_post:
            mock_post.return_value = {"success": True}
            
            mailcow_api.add_mailbox("test.user@example.com", "password")
            
            call_args = mock_post.call_args
            request_data = call_args[0][1]  # Second argument is the data
            assert request_data['local_part'] == "test.user"
            assert request_data['domain'] == "example.com"

    @patch('requests.Session.request')
    def test_update_mailbox(self, mock_request, mailcow_api):
        """Test mailbox update"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"success": True}
        mock_response.raise_for_status.return_value = None
        mock_request.return_value = mock_response
        
        result = mailcow_api.update_mailbox("user@test.com", quota=4096, name="Updated Name")
        
        assert result == {"success": True}
        
        # Verify request structure
        call_args = mock_request.call_args
        request_data = call_args[1]['json']
        assert request_data['items'] == ['user@test.com']
        assert 'attr' in request_data

    @patch('requests.Session.request')
    def test_delete_mailbox(self, mock_request, mailcow_api):
        """Test mailbox deletion"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"success": True}
        mock_response.raise_for_status.return_value = None
        mock_request.return_value = mock_response
        
        result = mailcow_api.delete_mailbox("user@test.com")
        
        assert result == {"success": True}
        
        call_args = mock_request.call_args
        request_data = call_args[1]['json']
        assert request_data == ["user@test.com"]

    def test_generate_secure_password(self, mailcow_api):
        """Test secure password generation"""
        password = mailcow_api.generate_secure_password()
        
        assert len(password) == 16  # Default length
        assert isinstance(password, str)
        
        # Test custom length
        long_password = mailcow_api.generate_secure_password(32)
        assert len(long_password) == 32

    def test_password_character_set(self, mailcow_api):
        """Test password contains expected character types"""
        password = mailcow_api.generate_secure_password(100)  # Long password for testing
        
        has_lower = any(c.islower() for c in password)
        has_upper = any(c.isupper() for c in password)
        has_digit = any(c.isdigit() for c in password)
        has_special = any(c in "!@#$%^&*" for c in password)
        
        assert has_lower, "Password should contain lowercase letters"
        assert has_upper, "Password should contain uppercase letters"
        assert has_digit, "Password should contain digits"
        # Special characters are randomly chosen, so not guaranteed in every password

    # DKIM Management Tests
    @patch('requests.Session.request')
    def test_get_dkim_key(self, mock_request, mailcow_api):
        """Test DKIM key retrieval"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "pubkey": "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA...",
            "selector": "dkim"
        }
        mock_response.raise_for_status.return_value = None
        mock_request.return_value = mock_response
        
        dkim_data = mailcow_api.get_dkim("test.com")
        
        assert "pubkey" in dkim_data
        assert dkim_data["selector"] == "dkim"

    @patch('requests.Session.request')
    def test_add_dkim_key(self, mock_request, mailcow_api):
        """Test DKIM key generation"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"success": True}
        mock_response.raise_for_status.return_value = None
        mock_request.return_value = mock_response
        
        result = mailcow_api.add_dkim_key("test.com", key_size=2048, selector="dkim")
        
        assert result == {"success": True}
        
        call_args = mock_request.call_args
        request_data = call_args[1]['json']
        assert request_data['domains'] == ["test.com"]
        assert request_data['key_size'] == 2048
        assert request_data['selector'] == "dkim"

    def test_get_dkim_record(self, mailcow_api):
        """Test DKIM record extraction"""
        with patch.object(mailcow_api, 'get_dkim') as mock_get_dkim:
            mock_get_dkim.return_value = {
                "pubkey": "v=DKIM1; k=rsa; p=MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA..."
            }
            
            record = mailcow_api.get_dkim_record("test.com")
            assert record.startswith("v=DKIM1")

    def test_get_dkim_record_empty(self, mailcow_api):
        """Test DKIM record extraction when no key exists"""
        with patch.object(mailcow_api, 'get_dkim') as mock_get_dkim:
            mock_get_dkim.return_value = {}
            
            record = mailcow_api.get_dkim_record("test.com")
            assert record == ""

    # System Status Tests
    @patch('requests.Session.request')
    def test_get_status(self, mock_request, mailcow_api):
        """Test system status retrieval"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "postfix-mailcow": "running",
            "dovecot-mailcow": "running",
            "redis-mailcow": "running"
        }
        mock_response.raise_for_status.return_value = None
        mock_request.return_value = mock_response
        
        status = mailcow_api.get_status()
        
        assert "postfix-mailcow" in status
        assert status["postfix-mailcow"] == "running"

    @patch('requests.Session.request')
    def test_get_version(self, mock_request, mailcow_api):
        """Test version information retrieval"""
        mock_response = Mock()
        mock_response.status_code = 200
        mock_response.json.return_value = {
            "version": "2023-05",
            "git_commit": "abc123def456"
        }
        mock_response.raise_for_status.return_value = None
        mock_request.return_value = mock_response
        
        version = mailcow_api.get_version()
        
        assert version["version"] == "2023-05"
        assert "git_commit" in version

    def test_test_connection_success(self, mailcow_api):
        """Test successful connection test"""
        with patch.object(mailcow_api, 'get_status') as mock_status:
            mock_status.return_value = {"status": "ok"}
            
            result = mailcow_api.test_connection()
            assert result is True

    def test_test_connection_failure(self, mailcow_api):
        """Test failed connection test"""
        with patch.object(mailcow_api, 'get_status') as mock_status:
            mock_status.side_effect = Exception("Connection failed")
            
            result = mailcow_api.test_connection()
            assert result is False

    def test_health_check_complete(self, mailcow_api):
        """Test comprehensive health check"""
        with patch.object(mailcow_api, 'test_connection', return_value=True):
            with patch.object(mailcow_api, 'get_status', return_value={"status": "running"}):
                with patch.object(mailcow_api, 'get_version', return_value={"version": "2023-05"}):
                    
                    health = mailcow_api.health_check()
                    
                    assert health["api_connection"] is True
                    assert "containers" in health
                    assert "version" in health
                    assert "timestamp" in health

    def test_health_check_with_error(self, mailcow_api):
        """Test health check with errors"""
        with patch.object(mailcow_api, 'test_connection', side_effect=Exception("Network error")):
            health = mailcow_api.health_check()
            
            assert health["api_connection"] is False
            assert "error" in health

    # Bulk Operations Tests
    def test_bulk_mailbox_create_success(self, mailcow_api):
        """Test successful bulk mailbox creation"""
        mailboxes = [
            {"email": "user1@test.com", "name": "User 1"},
            {"email": "user2@test.com", "name": "User 2", "password": "custom_pass"},
            {"email": "user3@test.com", "name": "User 3"}
        ]
        
        with patch.object(mailcow_api, 'add_mailbox') as mock_add:
            mock_add.return_value = {"success": True}
            
            results = mailcow_api.bulk_mailbox_create(mailboxes)
            
            assert len(results) == 3
            assert mock_add.call_count == 3
            
            # Verify passwords were generated for mailboxes without them
            for result in results:
                assert "password" in result

    def test_bulk_mailbox_create_with_failures(self, mailcow_api):
        """Test bulk mailbox creation with some failures"""
        mailboxes = [
            {"email": "valid@test.com", "name": "Valid User"},
            {"email": "invalid@test.com", "name": "Invalid User"}
        ]
        
        def mock_add_side_effect(**kwargs):
            if kwargs['email'] == "valid@test.com":
                return {"success": True}
            else:
                raise Exception("Mailbox creation failed")
        
        with patch.object(mailcow_api, 'add_mailbox', side_effect=mock_add_side_effect):
            results = mailcow_api.bulk_mailbox_create(mailboxes)
            
            assert len(results) == 2
            assert results[0].get("success") is not False  # First should succeed
            assert results[1]["success"] is False  # Second should fail
            assert "error" in results[1]

class TestMailcowConfig:
    """Test Mailcow configuration data class"""
    
    def test_mailcow_config_creation(self):
        """Test MailcowConfig data class creation"""
        config = MailcowConfig(
            hostname="mail.example.com",
            api_key="test_key_123",
            verify_ssl=True,
            timeout=60,
            rate_limit=50
        )
        
        assert config.hostname == "mail.example.com"
        assert config.api_key == "test_key_123"
        assert config.verify_ssl is True
        assert config.timeout == 60
        assert config.rate_limit == 50

    def test_mailcow_config_defaults(self):
        """Test MailcowConfig default values"""
        config = MailcowConfig(
            hostname="mail.example.com",
            api_key="test_key"
        )
        
        assert config.verify_ssl is True
        assert config.timeout == 30
        assert config.rate_limit == 100

class TestMailcowAPIIntegration:
    """Integration tests for Mailcow API client"""
    
    @pytest.mark.integration
    def test_complete_domain_workflow(self, mailcow_api):
        """Test complete domain management workflow"""
        domain_name = "integration-test.com"
        
        with patch('requests.Session.request') as mock_request:
            # Mock sequence of API calls
            mock_responses = [
                # get_domains
                Mock(status_code=200, json=lambda: []),
                # add_domain
                Mock(status_code=200, json=lambda: {"success": True}),
                # get_domain
                Mock(status_code=200, json=lambda: {"domain_name": domain_name, "active": True}),
                # update_domain
                Mock(status_code=200, json=lambda: {"success": True}),
                # delete_domain
                Mock(status_code=200, json=lambda: {"success": True})
            ]
            
            for response in mock_responses:
                response.raise_for_status = Mock()
            
            mock_request.side_effect = mock_responses
            
            # Step 1: Check initial domains
            domains = mailcow_api.get_domains()
            assert len(domains) == 0
            
            # Step 2: Add new domain
            add_result = mailcow_api.add_domain(domain_name)
            assert add_result["success"] is True
            
            # Step 3: Get domain details
            domain = mailcow_api.get_domain(domain_name)
            assert domain["domain_name"] == domain_name
            
            # Step 4: Update domain
            update_result = mailcow_api.update_domain(domain_name, quota=5120)
            assert update_result["success"] is True
            
            # Step 5: Delete domain
            delete_result = mailcow_api.delete_domain(domain_name)
            assert delete_result["success"] is True
            
            # Verify all calls were made
            assert mock_request.call_count == 5

    @pytest.mark.integration 
    def test_complete_mailbox_workflow(self, mailcow_api):
        """Test complete mailbox management workflow"""
        mailbox_email = "test@integration-test.com"
        
        with patch('requests.Session.request') as mock_request:
            # Mock API responses
            mock_responses = [
                # get_mailboxes
                Mock(status_code=200, json=lambda: []),
                # add_mailbox
                Mock(status_code=200, json=lambda: {"success": True}),
                # get_mailbox
                Mock(status_code=200, json=lambda: {"username": mailbox_email, "active": True}),
                # update_mailbox
                Mock(status_code=200, json=lambda: {"success": True}),
                # delete_mailbox
                Mock(status_code=200, json=lambda: {"success": True})
            ]
            
            for response in mock_responses:
                response.raise_for_status = Mock()
            
            mock_request.side_effect = mock_responses
            
            # Complete workflow
            mailboxes = mailcow_api.get_mailboxes()
            add_result = mailcow_api.add_mailbox(mailbox_email, "password123")
            mailbox = mailcow_api.get_mailbox(mailbox_email)
            update_result = mailcow_api.update_mailbox(mailbox_email, quota=2048)
            delete_result = mailcow_api.delete_mailbox(mailbox_email)
            
            # Verify results
            assert len(mailboxes) == 0
            assert add_result["success"] is True
            assert mailbox["username"] == mailbox_email
            assert update_result["success"] is True
            assert delete_result["success"] is True
            
            assert mock_request.call_count == 5

    @pytest.mark.performance
    def test_bulk_operations_performance(self, mailcow_api):
        """Test performance of bulk operations"""
        import time
        
        # Create 20 test mailboxes
        mailboxes = []
        for i in range(20):
            mailboxes.append({
                "email": f"perf_test_{i}@test.com",
                "name": f"Performance Test User {i}",
                "quota": 1024
            })
        
        with patch.object(mailcow_api, 'add_mailbox') as mock_add:
            mock_add.return_value = {"success": True}
            
            start_time = time.time()
            results = mailcow_api.bulk_mailbox_create(mailboxes)
            end_time = time.time()
            
            # Performance assertions
            execution_time = end_time - start_time
            assert execution_time < 10  # Should complete within 10 seconds
            assert len(results) == 20
            
            # Should process at least 2 mailboxes per second
            throughput = len(mailboxes) / execution_time
            assert throughput >= 2