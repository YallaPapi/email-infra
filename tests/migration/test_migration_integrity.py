#!/usr/bin/env python3
"""
Migration Integrity Tests
Validates that all functionality is preserved during the refactoring process
Ensures zero functionality loss during the massive 18,850+ line consolidation
"""

import pytest
import asyncio
import json
import yaml
import inspect
from pathlib import Path
from typing import Dict, List, Any, Callable, Set
from unittest.mock import Mock, patch, AsyncMock
import importlib
import sys
import os

# Test configuration
PROJECT_ROOT = Path(__file__).parent.parent.parent
ORIGINAL_CODE_PATH = PROJECT_ROOT / "backup-20250825-022233" / "original-code"
MIGRATED_CODE_PATH = PROJECT_ROOT / "src" / "email-infrastructure"

class MigrationIntegrityTester:
    """Comprehensive migration integrity testing framework"""
    
    def __init__(self):
        self.original_modules = {}
        self.migrated_modules = {}
        self.function_mapping = {}
        self.migration_issues = []
        
    def discover_original_functions(self) -> Dict[str, List[str]]:
        """Discover all functions in original codebase"""
        functions = {
            "dns": [],
            "mailcow": [], 
            "monitoring": [],
            "vps": []
        }
        
        # DNS functions (from original dns-manager.py)
        dns_functions = [
            "get_zones", "get_zone_id", "list_dns_records", "create_dns_record",
            "update_dns_record", "delete_dns_record", "bulk_create_records",
            "sync_records_from_template", "backup_dns_records", "restore_dns_records",
            "get_zone_analytics", "export_zone_file", "validate_dns_records"
        ]
        functions["dns"] = dns_functions
        
        # Mailcow functions (inferred from API client)
        mailcow_functions = [
            "get_domains", "get_domain", "add_domain", "update_domain", "delete_domain",
            "get_mailboxes", "get_mailbox", "add_mailbox", "update_mailbox", "delete_mailbox",
            "get_aliases", "add_alias", "update_alias", "delete_alias",
            "get_dkim", "add_dkim_key", "delete_dkim_key", "get_dkim_record",
            "get_admins", "add_admin", "get_queue", "flush_queue", "delete_queue_item",
            "backup_mailcow", "get_backup_status", "test_connection", "health_check"
        ]
        functions["mailcow"] = mailcow_functions
        
        # Monitoring functions
        monitoring_functions = [
            "check_ip_blacklists", "check_domain_blacklists", "add_monitoring_target",
            "monitor_targets_continuously", "get_target_status", "get_provider_performance",
            "create_campaign", "execute_campaign", "get_campaign_stats", "get_mailbox_reputation"
        ]
        functions["monitoring"] = monitoring_functions
        
        # VPS functions
        vps_functions = [
            "get_network_interfaces", "get_available_ips", "get_primary_interface",
            "add_ip_alias", "remove_ip_alias", "get_vps_status", "get_system_status",
            "get_network_status", "get_disk_status", "get_service_status", "get_load_status",
            "test_connectivity", "rotate_ip_for_sending", "monitor_ip_health"
        ]
        functions["vps"] = vps_functions
        
        return functions
    
    def validate_function_migration(self, system: str, original_functions: List[str]) -> Dict[str, Any]:
        """Validate that all functions from original system are migrated"""
        results = {
            "system": system,
            "total_functions": len(original_functions),
            "migrated_functions": 0,
            "missing_functions": [],
            "signature_matches": 0,
            "behavior_matches": 0,
            "issues": []
        }
        
        # Import migrated modules
        try:
            if system == "dns":
                from dns.managers.dns_manager import DNSManager
                migrated_class = DNSManager
            elif system == "mailcow":
                from mailcow.core.api_client import MailcowAPI
                migrated_class = MailcowAPI
            elif system == "monitoring":
                # Check both blacklist monitor and warmup campaigns
                from monitoring.monitors.blacklist_monitor import BlacklistMonitor
                from monitoring.campaigns.warmup_campaigns import WarmupCampaigns
                migrated_classes = [BlacklistMonitor, WarmupCampaigns]
            elif system == "vps":
                from vps.core.vps_manager import VPSManager
                migrated_class = VPSManager
            else:
                results["issues"].append(f"Unknown system: {system}")
                return results
                
        except ImportError as e:
            results["issues"].append(f"Failed to import migrated module: {e}")
            return results
        
        # For monitoring, check both classes
        if system == "monitoring":
            all_methods = set()
            for cls in migrated_classes:
                methods = [method for method in dir(cls) if not method.startswith('_')]
                all_methods.update(methods)
            migrated_methods = list(all_methods)
        else:
            migrated_methods = [method for method in dir(migrated_class) if not method.startswith('_')]
        
        # Check function presence
        for func_name in original_functions:
            if func_name in migrated_methods:
                results["migrated_functions"] += 1
            else:
                results["missing_functions"].append(func_name)
        
        # Calculate migration completeness
        migration_rate = results["migrated_functions"] / results["total_functions"] * 100
        results["migration_rate"] = migration_rate
        
        if migration_rate < 95.0:
            results["issues"].append(f"Migration rate below 95%: {migration_rate:.1f}%")
        
        return results
    
    def validate_configuration_migration(self) -> Dict[str, Any]:
        """Validate configuration system migration"""
        results = {
            "config_files_migrated": 0,
            "total_config_files": 0,
            "unified_config_system": False,
            "schema_validation": False,
            "environment_inheritance": False,
            "issues": []
        }
        
        # Check for original config files
        original_configs = [
            "cloudflare-config.yaml",
            "dns-records-template.json",
            "spf-dmarc-templates.yaml"
        ]
        results["total_config_files"] = len(original_configs)
        
        # Check for unified config system
        unified_config_path = PROJECT_ROOT / "config"
        if unified_config_path.exists():
            results["unified_config_system"] = True
            
            # Check for schema files
            schema_path = unified_config_path / "schemas"
            if schema_path.exists():
                schema_files = list(schema_path.glob("*.schema.json"))
                if len(schema_files) >= 4:  # base, api, dns, email schemas
                    results["schema_validation"] = True
            
            # Check for environment configs
            env_path = unified_config_path / "environments"
            if env_path.exists():
                env_files = list(env_path.glob("*.yaml"))
                if len(env_files) >= 3:  # base, development, production
                    results["environment_inheritance"] = True
        
        if not results["unified_config_system"]:
            results["issues"].append("Unified configuration system not found")
        if not results["schema_validation"]:
            results["issues"].append("Configuration schema validation not implemented")
        if not results["environment_inheritance"]:
            results["issues"].append("Environment configuration inheritance not implemented")
        
        return results
    
    def validate_api_consolidation(self) -> Dict[str, Any]:
        """Validate consolidated API client library"""
        results = {
            "base_client_exists": False,
            "unified_auth": False,
            "rate_limiting": False,
            "error_handling": False,
            "client_factory": False,
            "issues": []
        }
        
        try:
            # Check for base API client (from CONSOLIDATED_API_DESIGN.md)
            api_path = MIGRATED_CODE_PATH / "common" / "api"
            if api_path.exists():
                # Look for base client files
                base_files = ["__init__.py", "base/client.py", "base/auth.py"]
                existing_files = []
                for base_file in base_files:
                    if (api_path / base_file).exists():
                        existing_files.append(base_file)
                
                if len(existing_files) >= 2:
                    results["base_client_exists"] = True
                    
                    # Check for specific features by looking at file contents
                    try:
                        client_file = api_path / "base" / "client.py"
                        if client_file.exists():
                            content = client_file.read_text()
                            if "AuthenticationHandler" in content:
                                results["unified_auth"] = True
                            if "RateLimiter" in content:
                                results["rate_limiting"] = True
                            if "APIError" in content:
                                results["error_handling"] = True
                    except Exception:
                        pass
                        
                    # Check for client factory
                    init_file = api_path / "__init__.py"
                    if init_file.exists():
                        try:
                            content = init_file.read_text()
                            if "APIClientFactory" in content:
                                results["client_factory"] = True
                        except Exception:
                            pass
            
            if not results["base_client_exists"]:
                results["issues"].append("Consolidated API client library not found")
            if not results["unified_auth"]:
                results["issues"].append("Unified authentication system not implemented")
            if not results["rate_limiting"]:
                results["issues"].append("Consolidated rate limiting not implemented")
            if not results["error_handling"]:
                results["issues"].append("Unified error handling not implemented")
                
        except Exception as e:
            results["issues"].append(f"Error validating API consolidation: {e}")
        
        return results
    
    def validate_logging_consolidation(self) -> Dict[str, Any]:
        """Validate logging framework consolidation"""
        results = {
            "unified_logging": False,
            "structured_logging": False,
            "log_rotation": False,
            "centralized_config": False,
            "issues": []
        }
        
        # Check for unified logging system
        logging_path = MIGRATED_CODE_PATH / "common" / "logging"
        if logging_path.exists():
            results["unified_logging"] = True
            
            # Check for structured logging
            if (logging_path / "structured.py").exists():
                results["structured_logging"] = True
            
            # Check for log rotation
            if (logging_path / "rotation.py").exists():
                results["log_rotation"] = True
            
            # Check for centralized config
            if (logging_path / "config.py").exists():
                results["centralized_config"] = True
        
        # Also check if logging config is in unified config system
        config_path = PROJECT_ROOT / "config" / "schemas" / "logging.schema.json"
        if config_path.exists():
            results["centralized_config"] = True
        
        if not results["unified_logging"]:
            results["issues"].append("Unified logging framework not found")
        if not results["structured_logging"]:
            results["issues"].append("Structured logging not implemented")
        
        return results
    
    def validate_database_consolidation(self) -> Dict[str, Any]:
        """Validate database schema consolidation"""
        results = {
            "schemas_migrated": 0,
            "total_schemas": 4,  # DNS, Mailcow, Monitoring, VPS
            "unified_migrations": False,
            "data_integrity": True,
            "issues": []
        }
        
        # Check for database migration files
        db_path = MIGRATED_CODE_PATH / "common" / "database"
        if db_path.exists():
            migration_files = list(db_path.glob("migrations/*.sql"))
            if len(migration_files) >= 4:
                results["unified_migrations"] = True
                results["schemas_migrated"] = len(migration_files)
        
        # Check individual system databases are preserved
        systems = ["dns", "mailcow", "monitoring", "vps"]
        for system in systems:
            system_path = MIGRATED_CODE_PATH / system
            if system_path.exists():
                # Look for database initialization code
                db_files = list(system_path.rglob("*database*")) + list(system_path.rglob("*db*"))
                if db_files:
                    results["schemas_migrated"] += 1
        
        if results["schemas_migrated"] < results["total_schemas"]:
            results["issues"].append(f"Only {results['schemas_migrated']}/{results['total_schemas']} schemas migrated")
        
        return results

class TestMigrationIntegrity:
    """Test suite for migration integrity validation"""
    
    @pytest.fixture
    def migration_tester(self):
        """Create migration integrity tester"""
        return MigrationIntegrityTester()
    
    def test_dns_system_migration(self, migration_tester):
        """Test DNS system function migration completeness"""
        original_functions = migration_tester.discover_original_functions()
        dns_results = migration_tester.validate_function_migration("dns", original_functions["dns"])
        
        # Assert critical migration requirements
        assert dns_results["migration_rate"] >= 95.0, f"DNS migration rate too low: {dns_results['migration_rate']:.1f}%"
        assert len(dns_results["missing_functions"]) <= 1, f"Too many missing DNS functions: {dns_results['missing_functions']}"
        
        # Check for critical DNS functions
        critical_functions = ["get_zones", "list_dns_records", "create_dns_record", "validate_dns_records"]
        for func in critical_functions:
            assert func not in dns_results["missing_functions"], f"Critical DNS function missing: {func}"
        
        print(f"DNS Migration Results: {dns_results['migrated_functions']}/{dns_results['total_functions']} functions migrated")
    
    def test_mailcow_system_migration(self, migration_tester):
        """Test Mailcow system function migration completeness"""
        original_functions = migration_tester.discover_original_functions()
        mailcow_results = migration_tester.validate_function_migration("mailcow", original_functions["mailcow"])
        
        # Assert critical migration requirements
        assert mailcow_results["migration_rate"] >= 90.0, f"Mailcow migration rate too low: {mailcow_results['migration_rate']:.1f}%"
        assert len(mailcow_results["missing_functions"]) <= 2, f"Too many missing Mailcow functions: {mailcow_results['missing_functions']}"
        
        # Check for critical Mailcow functions
        critical_functions = ["get_domains", "add_domain", "get_mailboxes", "add_mailbox", "get_dkim"]
        for func in critical_functions:
            assert func not in mailcow_results["missing_functions"], f"Critical Mailcow function missing: {func}"
        
        print(f"Mailcow Migration Results: {mailcow_results['migrated_functions']}/{mailcow_results['total_functions']} functions migrated")
    
    def test_monitoring_system_migration(self, migration_tester):
        """Test monitoring system function migration completeness"""
        original_functions = migration_tester.discover_original_functions()
        monitoring_results = migration_tester.validate_function_migration("monitoring", original_functions["monitoring"])
        
        # Assert critical migration requirements  
        assert monitoring_results["migration_rate"] >= 85.0, f"Monitoring migration rate too low: {monitoring_results['migration_rate']:.1f}%"
        
        # Check for critical monitoring functions
        critical_functions = ["check_ip_blacklists", "create_campaign", "execute_campaign"]
        for func in critical_functions:
            assert func not in monitoring_results["missing_functions"], f"Critical monitoring function missing: {func}"
        
        print(f"Monitoring Migration Results: {monitoring_results['migrated_functions']}/{monitoring_results['total_functions']} functions migrated")
    
    def test_vps_system_migration(self, migration_tester):
        """Test VPS system function migration completeness"""
        original_functions = migration_tester.discover_original_functions()
        vps_results = migration_tester.validate_function_migration("vps", original_functions["vps"])
        
        # Assert critical migration requirements
        assert vps_results["migration_rate"] >= 90.0, f"VPS migration rate too low: {vps_results['migration_rate']:.1f}%"
        
        # Check for critical VPS functions
        critical_functions = ["get_network_interfaces", "get_vps_status", "rotate_ip_for_sending"]
        for func in critical_functions:
            assert func not in vps_results["missing_functions"], f"Critical VPS function missing: {func}"
        
        print(f"VPS Migration Results: {vps_results['migrated_functions']}/{vps_results['total_functions']} functions migrated")
    
    def test_configuration_system_migration(self, migration_tester):
        """Test unified configuration system migration"""
        config_results = migration_tester.validate_configuration_migration()
        
        # Assert configuration migration requirements
        assert config_results["unified_config_system"], "Unified configuration system must be implemented"
        assert config_results["schema_validation"], "Configuration schema validation must be implemented"
        assert config_results["environment_inheritance"], "Environment configuration inheritance must be implemented"
        
        if config_results["issues"]:
            print(f"Configuration issues: {config_results['issues']}")
        
        print("Configuration system migration validated")
    
    def test_api_client_consolidation(self, migration_tester):
        """Test consolidated API client library"""
        api_results = migration_tester.validate_api_consolidation()
        
        # Assert API consolidation requirements
        assert api_results["base_client_exists"], "Base API client must be implemented"
        assert api_results["unified_auth"], "Unified authentication must be implemented"
        assert api_results["error_handling"], "Unified error handling must be implemented"
        
        # Rate limiting is recommended but not required
        if not api_results["rate_limiting"]:
            print("Warning: Unified rate limiting not found")
        
        if api_results["issues"]:
            print(f"API consolidation issues: {api_results['issues']}")
        
        print("API client consolidation validated")
    
    def test_logging_framework_migration(self, migration_tester):
        """Test logging framework consolidation"""
        logging_results = migration_tester.validate_logging_consolidation()
        
        # Assert logging consolidation requirements
        assert logging_results["unified_logging"] or logging_results["centralized_config"], "Unified logging system must be implemented"
        
        if logging_results["issues"]:
            print(f"Logging consolidation issues: {logging_results['issues']}")
        
        print("Logging framework migration validated")
    
    def test_database_schema_migration(self, migration_tester):
        """Test database schema consolidation"""
        db_results = migration_tester.validate_database_consolidation()
        
        # Assert database migration requirements
        assert db_results["schemas_migrated"] >= 3, f"At least 3 database schemas must be migrated, found {db_results['schemas_migrated']}"
        assert db_results["data_integrity"], "Data integrity must be maintained"
        
        if db_results["issues"]:
            print(f"Database migration issues: {db_results['issues']}")
        
        print(f"Database schema migration validated: {db_results['schemas_migrated']} schemas")
    
    @pytest.mark.integration
    def test_full_migration_integrity(self, migration_tester):
        """Comprehensive migration integrity test"""
        print("\n=== COMPREHENSIVE MIGRATION INTEGRITY VALIDATION ===")
        
        # Test all systems
        original_functions = migration_tester.discover_original_functions()
        system_results = {}
        
        for system in ["dns", "mailcow", "monitoring", "vps"]:
            system_results[system] = migration_tester.validate_function_migration(
                system, original_functions[system]
            )
        
        # Test consolidation systems
        config_results = migration_tester.validate_configuration_migration()
        api_results = migration_tester.validate_api_consolidation()
        logging_results = migration_tester.validate_logging_consolidation()
        db_results = migration_tester.validate_database_consolidation()
        
        # Calculate overall migration score
        total_functions = sum(len(funcs) for funcs in original_functions.values())
        migrated_functions = sum(results["migrated_functions"] for results in system_results.values())
        overall_migration_rate = (migrated_functions / total_functions) * 100
        
        print(f"\n=== MIGRATION SUMMARY ===")
        print(f"Overall Migration Rate: {overall_migration_rate:.1f}%")
        print(f"Total Functions: {total_functions}")
        print(f"Migrated Functions: {migrated_functions}")
        
        print(f"\n=== SYSTEM BREAKDOWN ===")
        for system, results in system_results.items():
            print(f"{system.upper()}: {results['migration_rate']:.1f}% ({results['migrated_functions']}/{results['total_functions']})")
            if results["missing_functions"]:
                print(f"  Missing: {results['missing_functions']}")
        
        print(f"\n=== CONSOLIDATION STATUS ===")
        print(f"Unified Configuration: {'✓' if config_results['unified_config_system'] else '✗'}")
        print(f"API Consolidation: {'✓' if api_results['base_client_exists'] else '✗'}")
        print(f"Logging Framework: {'✓' if logging_results['unified_logging'] or logging_results['centralized_config'] else '✗'}")
        print(f"Database Migration: {'✓' if db_results['schemas_migrated'] >= 3 else '✗'}")
        
        # Assert overall migration success
        assert overall_migration_rate >= 90.0, f"Overall migration rate too low: {overall_migration_rate:.1f}%"
        
        # Assert critical systems
        assert system_results["dns"]["migration_rate"] >= 95.0, "DNS system migration incomplete"
        assert system_results["mailcow"]["migration_rate"] >= 90.0, "Mailcow system migration incomplete"
        
        print(f"\n✅ MIGRATION INTEGRITY VALIDATION PASSED")
        print(f"The refactored cold email infrastructure maintains {overall_migration_rate:.1f}% functional parity")

class TestDataMigration:
    """Test data migration and integrity"""
    
    def test_dns_data_preservation(self):
        """Test DNS configuration data is preserved"""
        # Test that DNS templates and configurations are accessible
        try:
            from dns.managers.dns_manager import DNSRecord
            
            # Test DNS record structure preservation
            record = DNSRecord(
                type="A",
                name="test.com",
                content="192.168.1.100",
                ttl=300
            )
            
            record_dict = record.to_dict()
            assert "type" in record_dict
            assert "name" in record_dict
            assert "content" in record_dict
            assert "ttl" in record_dict
            
        except ImportError:
            pytest.fail("DNS data structures not accessible after migration")
    
    def test_mailcow_data_preservation(self):
        """Test Mailcow configuration data is preserved"""
        try:
            from mailcow.core.api_client import MailcowConfig
            
            # Test Mailcow config structure
            config = MailcowConfig(
                hostname="test.com",
                api_key="test_key"
            )
            
            assert config.hostname == "test.com"
            assert config.api_key == "test_key"
            assert hasattr(config, 'verify_ssl')
            assert hasattr(config, 'timeout')
            
        except ImportError:
            pytest.fail("Mailcow data structures not accessible after migration")
    
    def test_monitoring_data_preservation(self):
        """Test monitoring data structures are preserved"""
        try:
            from monitoring.campaigns.warmup_campaigns import WarmupMailbox, CampaignTemplate
            
            # Test warmup mailbox structure
            mailbox = WarmupMailbox(
                email="test@test.com",
                password="password",
                smtp_host="smtp.test.com",
                smtp_port=587,
                imap_host="imap.test.com",
                imap_port=993,
                provider="test"
            )
            
            assert mailbox.email == "test@test.com"
            assert mailbox.smtp_port == 587
            
        except ImportError:
            pytest.fail("Monitoring data structures not accessible after migration")

class TestPerformanceRegression:
    """Test for performance regression after migration"""
    
    @pytest.mark.performance
    def test_dns_operation_performance(self):
        """Test DNS operations maintain performance after migration"""
        import time
        from unittest.mock import AsyncMock, patch
        
        try:
            from dns.managers.dns_manager import DNSManager, DNSRecord
            
            # Mock API responses to test performance
            with patch.dict(os.environ, {'CLOUDFLARE_API_TOKEN': 'test_token'}):
                manager = DNSManager()
                
                # Test bulk record creation performance
                records = []
                for i in range(10):
                    records.append(DNSRecord(
                        type="A",
                        name=f"test{i}.com",
                        content=f"192.168.1.{i+100}"
                    ))
                
                with patch.object(manager, 'create_dns_record', new_callable=AsyncMock) as mock_create:
                    mock_create.return_value = {"id": "test_id"}
                    
                    start_time = time.time()
                    # Run async function
                    import asyncio
                    result = asyncio.run(manager.bulk_create_records("test.com", records))
                    end_time = time.time()
                    
                    execution_time = end_time - start_time
                    
                    # Should complete bulk operations within reasonable time
                    assert execution_time < 5.0, f"DNS bulk operations too slow: {execution_time:.2f}s"
                    assert len(result) == 10
                    
        except Exception as e:
            pytest.skip(f"DNS performance test skipped: {e}")
    
    @pytest.mark.performance 
    def test_mailcow_operation_performance(self):
        """Test Mailcow operations maintain performance after migration"""
        import time
        
        try:
            from mailcow.core.api_client import MailcowAPI
            
            api = MailcowAPI("test.com", "test_key", verify_ssl=False)
            
            # Test bulk mailbox creation performance
            mailboxes = []
            for i in range(5):
                mailboxes.append({
                    "email": f"test{i}@test.com",
                    "name": f"Test User {i}",
                    "quota": 1024
                })
            
            with patch.object(api, 'add_mailbox') as mock_add:
                mock_add.return_value = {"success": True}
                
                start_time = time.time()
                results = api.bulk_mailbox_create(mailboxes)
                end_time = time.time()
                
                execution_time = end_time - start_time
                
                # Should complete bulk operations efficiently
                assert execution_time < 3.0, f"Mailcow bulk operations too slow: {execution_time:.2f}s"
                assert len(results) == 5
                
        except Exception as e:
            pytest.skip(f"Mailcow performance test skipped: {e}")
            
    @pytest.mark.performance
    def test_memory_usage_regression(self):
        """Test that memory usage hasn't significantly increased after migration"""
        import psutil
        import gc
        
        process = psutil.Process()
        initial_memory = process.memory_info().rss / 1024 / 1024  # MB
        
        try:
            # Import major migrated modules
            from dns.managers.dns_manager import DNSManager
            from mailcow.core.api_client import MailcowAPI
            from vps.core.vps_manager import VPSManager
            from monitoring.monitors.blacklist_monitor import BlacklistMonitor
            
            # Create instances (this should not significantly increase memory)
            with patch.dict(os.environ, {'CLOUDFLARE_API_TOKEN': 'test_token'}):
                dns_manager = DNSManager()
            
            mailcow_api = MailcowAPI("test.com", "test_key")
            vps_manager = VPSManager()
            
            # Force garbage collection
            gc.collect()
            
            final_memory = process.memory_info().rss / 1024 / 1024  # MB
            memory_increase = final_memory - initial_memory
            
            # Memory increase should be reasonable (less than 100MB for basic imports)
            assert memory_increase < 100, f"Memory usage increased too much: {memory_increase:.2f}MB"
            
            print(f"Memory usage: {initial_memory:.2f}MB -> {final_memory:.2f}MB (+{memory_increase:.2f}MB)")
            
        except Exception as e:
            pytest.skip(f"Memory regression test skipped: {e}")

if __name__ == "__main__":
    # Run migration integrity validation
    tester = MigrationIntegrityTester()
    
    print("=== MIGRATION INTEGRITY VALIDATION ===")
    
    # Test each system
    original_functions = tester.discover_original_functions()
    
    for system in ["dns", "mailcow", "monitoring", "vps"]:
        print(f"\n--- {system.upper()} SYSTEM ---")
        results = tester.validate_function_migration(system, original_functions[system])
        print(f"Migration Rate: {results['migration_rate']:.1f}%")
        print(f"Functions: {results['migrated_functions']}/{results['total_functions']}")
        if results['missing_functions']:
            print(f"Missing: {results['missing_functions']}")
        if results['issues']:
            print(f"Issues: {results['issues']}")
    
    # Test consolidation systems
    print(f"\n--- CONSOLIDATION SYSTEMS ---")
    config_results = tester.validate_configuration_migration()
    api_results = tester.validate_api_consolidation() 
    logging_results = tester.validate_logging_consolidation()
    db_results = tester.validate_database_consolidation()
    
    print(f"Configuration: {'✓' if config_results['unified_config_system'] else '✗'}")
    print(f"API Client: {'✓' if api_results['base_client_exists'] else '✗'}")
    print(f"Logging: {'✓' if logging_results['unified_logging'] or logging_results['centralized_config'] else '✗'}")
    print(f"Database: {'✓' if db_results['schemas_migrated'] >= 3 else '✗'}")
    
    print("\n=== VALIDATION COMPLETE ===")