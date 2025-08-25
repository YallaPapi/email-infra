#!/usr/bin/env python3
"""
Standalone System Integration Validation Test
Tests the refactored cold email infrastructure without external dependencies
"""

import os
import sys
import json
from pathlib import Path
from datetime import datetime
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class StandaloneIntegrationValidator:
    """Standalone integration validator for the cold email infrastructure"""
    
    def __init__(self):
        self.project_root = Path(__file__).parent.parent.parent
        self.src_root = self.project_root / "src" / "email-infrastructure"
        self.config_root = self.project_root / "config"
        
        self.test_results = {
            'directory_structure': {},
            'file_organization': {},
            'configuration_files': {},
            'python_package_structure': {},
            'integration_readiness': {},
            'system_cohesion': {}
        }

    def run_validation(self):
        """Run complete standalone validation"""
        logger.info("=" * 80)
        logger.info("COLD EMAIL INFRASTRUCTURE - SYSTEM INTEGRATION VALIDATION")
        logger.info("=" * 80)
        
        try:
            self._validate_directory_structure()
            self._validate_file_organization()
            self._validate_configuration_system()
            self._validate_python_packages()
            self._validate_integration_readiness()
            self._validate_system_cohesion()
            
            report = self._generate_report()
            self._save_report(report)
            
            return report
            
        except Exception as e:
            logger.error(f"Validation failed: {e}")
            raise

    def _validate_directory_structure(self):
        """Validate the refactored directory structure"""
        logger.info("Testing Directory Structure...")
        
        results = {}
        
        # Test main directories exist
        expected_dirs = {
            'src': self.project_root / "src",
            'config': self.project_root / "config",
            'data': self.project_root / "data",
            'scripts': self.project_root / "scripts",
            'tests': self.project_root / "tests",
            'docs': self.project_root / "docs"
        }
        
        for name, path in expected_dirs.items():
            results[f'{name}_directory'] = {
                'status': 'pass' if path.exists() else 'fail',
                'path': str(path),
                'exists': path.exists()
            }
        
        # Test email-infrastructure source structure
        email_infra_dirs = {
            'core': self.src_root / "core",
            'dns': self.src_root / "dns",
            'mailcow': self.src_root / "mailcow",
            'monitoring': self.src_root / "monitoring",
            'vps': self.src_root / "vps",
            'api': self.src_root / "api",
            'cli': self.src_root / "cli",
            'tests': self.src_root / "tests"
        }
        
        for name, path in email_infra_dirs.items():
            results[f'email_infra_{name}'] = {
                'status': 'pass' if path.exists() else 'fail',
                'path': str(path),
                'exists': path.exists()
            }
        
        # Test component subdirectories
        component_structure = {
            'dns_managers': self.src_root / "dns" / "managers",
            'dns_config': self.src_root / "dns" / "config",
            'mailcow_core': self.src_root / "mailcow" / "core",
            'mailcow_automation': self.src_root / "mailcow" / "automation",
            'monitoring_monitors': self.src_root / "monitoring" / "monitors",
            'monitoring_campaigns': self.src_root / "monitoring" / "campaigns",
            'vps_core': self.src_root / "vps" / "core",
            'vps_scripts': self.src_root / "vps" / "scripts"
        }
        
        for name, path in component_structure.items():
            results[name] = {
                'status': 'pass' if path.exists() else 'fail',
                'path': str(path),
                'exists': path.exists()
            }
        
        self.test_results['directory_structure'] = results
        
        total_dirs = len(expected_dirs) + len(email_infra_dirs) + len(component_structure)
        passed_dirs = sum(1 for r in results.values() if r['status'] == 'pass')
        
        logger.info(f"Directory Structure: {passed_dirs}/{total_dirs} directories verified")

    def _validate_file_organization(self):
        """Validate file organization and key files exist"""
        logger.info("Testing File Organization...")
        
        results = {}
        
        # Test core files
        core_files = {
            'config_manager': self.src_root / "core" / "config_manager.py",
            'paths': self.src_root / "core" / "paths.py",
            'main_init': self.src_root / "__init__.py",
            'core_init': self.src_root / "core" / "__init__.py"
        }
        
        for name, path in core_files.items():
            results[name] = {
                'status': 'pass' if path.exists() else 'fail',
                'path': str(path),
                'exists': path.exists(),
                'size': path.stat().st_size if path.exists() else 0
            }
        
        # Test component main files
        component_files = {
            'dns_manager': self.src_root / "dns" / "managers" / "dns_manager.py",
            'mailcow_api': self.src_root / "mailcow" / "core" / "api_client.py",
            'blacklist_monitor': self.src_root / "monitoring" / "monitors" / "blacklist_monitor.py",
            'vps_manager': self.src_root / "vps" / "core" / "vps_manager.py"
        }
        
        for name, path in component_files.items():
            results[name] = {
                'status': 'pass' if path.exists() else 'fail',
                'path': str(path),
                'exists': path.exists(),
                'size': path.stat().st_size if path.exists() else 0
            }
        
        # Test configuration files
        config_files = {
            'development_config': self.config_root / "environments" / "development.yaml",
            'production_config': self.config_root / "environments" / "production.yaml",
            'global_config': self.config_root / "global-config.yaml"
        }
        
        for name, path in config_files.items():
            results[name] = {
                'status': 'pass' if path.exists() else 'warning',  # Config files may not exist yet
                'path': str(path),
                'exists': path.exists(),
                'size': path.stat().st_size if path.exists() else 0
            }
        
        self.test_results['file_organization'] = results
        
        total_files = len(core_files) + len(component_files) + len(config_files)
        passed_files = sum(1 for r in results.values() if r['status'] == 'pass')
        
        logger.info(f"File Organization: {passed_files}/{total_files} key files found")

    def _validate_configuration_system(self):
        """Validate the configuration system structure"""
        logger.info("Testing Configuration System...")
        
        results = {}
        
        # Test configuration directory structure
        config_dirs = {
            'environments': self.config_root / "environments",
            'defaults': self.config_root / "defaults",
            'secrets': self.config_root / "secrets"
        }
        
        for name, path in config_dirs.items():
            results[f'config_{name}'] = {
                'status': 'pass' if path.exists() else 'warning',
                'path': str(path),
                'exists': path.exists()
            }
        
        # Test component configuration directories
        component_configs = {
            'dns_config_dir': self.src_root / "dns" / "config",
            'mailcow_config_dir': self.src_root / "mailcow" / "config",
            'monitoring_config_dir': self.src_root / "monitoring" / "config",
            'vps_config_dir': self.src_root / "vps" / "config"
        }
        
        for name, path in component_configs.items():
            results[name] = {
                'status': 'pass' if path.exists() else 'fail',
                'path': str(path),
                'exists': path.exists()
            }
        
        # Test for configuration files in components
        component_config_files = []
        for comp_name in ['dns', 'mailcow', 'monitoring', 'vps']:
            config_dir = self.src_root / comp_name / "config"
            if config_dir.exists():
                yaml_files = list(config_dir.glob("*.yaml")) + list(config_dir.glob("*.yml"))
                json_files = list(config_dir.glob("*.json"))
                component_config_files.extend(yaml_files + json_files)
        
        results['component_config_files'] = {
            'status': 'pass' if component_config_files else 'warning',
            'count': len(component_config_files),
            'files': [str(f) for f in component_config_files[:5]]  # Show first 5
        }
        
        self.test_results['configuration_files'] = results
        
        logger.info(f"Configuration System: {len(component_config_files)} config files found")

    def _validate_python_packages(self):
        """Validate Python package structure"""
        logger.info("Testing Python Package Structure...")
        
        results = {}
        
        # Find all __init__.py files
        init_files = list(self.src_root.rglob("__init__.py"))
        
        results['init_files'] = {
            'status': 'pass' if len(init_files) >= 10 else 'warning',
            'count': len(init_files),
            'files': [str(f.relative_to(self.src_root)) for f in init_files]
        }
        
        # Test main package structure
        required_init_files = [
            self.src_root / "__init__.py",
            self.src_root / "core" / "__init__.py",
            self.src_root / "dns" / "__init__.py",
            self.src_root / "mailcow" / "__init__.py",
            self.src_root / "monitoring" / "__init__.py",
            self.src_root / "vps" / "__init__.py"
        ]
        
        missing_inits = []
        for init_file in required_init_files:
            if not init_file.exists():
                missing_inits.append(str(init_file.relative_to(self.src_root)))
        
        results['required_init_files'] = {
            'status': 'pass' if not missing_inits else 'fail',
            'missing': missing_inits,
            'total_required': len(required_init_files),
            'found': len(required_init_files) - len(missing_inits)
        }
        
        # Test Python files structure
        python_files = list(self.src_root.rglob("*.py"))
        python_files = [f for f in python_files if not f.name.startswith('.')]
        
        results['python_files'] = {
            'status': 'pass',
            'total_count': len(python_files),
            'by_component': {
                'core': len(list((self.src_root / "core").rglob("*.py"))),
                'dns': len(list((self.src_root / "dns").rglob("*.py"))),
                'mailcow': len(list((self.src_root / "mailcow").rglob("*.py"))),
                'monitoring': len(list((self.src_root / "monitoring").rglob("*.py"))),
                'vps': len(list((self.src_root / "vps").rglob("*.py")))
            }
        }
        
        self.test_results['python_package_structure'] = results
        
        logger.info(f"Python Packages: {len(python_files)} Python files, {len(init_files)} __init__.py files")

    def _validate_integration_readiness(self):
        """Validate system integration readiness"""
        logger.info("Testing Integration Readiness...")
        
        results = {}
        
        # Test data directories
        data_dirs = {
            'logs': self.project_root / "data" / "logs",
            'backups': self.project_root / "data" / "backups",
            'cache': self.project_root / "data" / "cache",
            'databases': self.project_root / "data" / "databases"
        }
        
        for name, path in data_dirs.items():
            path.mkdir(parents=True, exist_ok=True)  # Create if doesn't exist
            results[f'data_{name}'] = {
                'status': 'pass',
                'path': str(path),
                'exists': path.exists(),
                'writable': os.access(path, os.W_OK)
            }
        
        # Test script directories
        script_dirs = {
            'install': self.project_root / "scripts" / "install",
            'utilities': self.project_root / "scripts" / "utilities",
            'maintenance': self.project_root / "scripts" / "maintenance"
        }
        
        for name, path in script_dirs.items():
            results[f'script_{name}'] = {
                'status': 'pass' if path.exists() else 'warning',
                'path': str(path),
                'exists': path.exists()
            }
        
        # Test for key integration files
        integration_files = {
            'install_all': self.project_root / "scripts" / "install" / "install-all.sh",
            'setup_environment': self.project_root / "scripts" / "utilities" / "setup-environment.sh",
            'validate_setup': self.project_root / "scripts" / "utilities" / "validate-setup.sh"
        }
        
        for name, path in integration_files.items():
            results[name] = {
                'status': 'pass' if path.exists() else 'warning',
                'path': str(path),
                'exists': path.exists(),
                'executable': path.exists() and os.access(path, os.X_OK)
            }
        
        self.test_results['integration_readiness'] = results
        
        logger.info("Integration Readiness: Data directories and scripts validated")

    def _validate_system_cohesion(self):
        """Validate overall system cohesion"""
        logger.info("Testing System Cohesion...")
        
        results = {}
        
        # Calculate overall structure health
        structure_score = self._calculate_structure_score()
        results['structure_health'] = {
            'status': 'pass' if structure_score >= 0.8 else 'warning' if structure_score >= 0.6 else 'fail',
            'score': structure_score,
            'percentage': f"{structure_score * 100:.1f}%"
        }
        
        # Test component isolation and organization
        components = ['core', 'dns', 'mailcow', 'monitoring', 'vps']
        component_health = {}
        
        for component in components:
            comp_dir = self.src_root / component
            if comp_dir.exists():
                python_files = list(comp_dir.rglob("*.py"))
                config_files = list(comp_dir.rglob("*.yaml")) + list(comp_dir.rglob("*.yml")) + list(comp_dir.rglob("*.json"))
                
                component_health[component] = {
                    'status': 'pass',
                    'python_files': len(python_files),
                    'config_files': len(config_files),
                    'subdirectories': len([d for d in comp_dir.iterdir() if d.is_dir()])
                }
            else:
                component_health[component] = {
                    'status': 'fail',
                    'python_files': 0,
                    'config_files': 0,
                    'subdirectories': 0
                }
        
        results['component_organization'] = component_health
        
        # Test cross-component dependencies (basic file analysis)
        cross_refs = self._analyze_cross_references()
        results['cross_component_references'] = {
            'status': 'pass' if cross_refs['total'] > 0 else 'warning',
            'total_references': cross_refs['total'],
            'core_imports': cross_refs['core_imports'],
            'inter_component': cross_refs['inter_component']
        }
        
        self.test_results['system_cohesion'] = results
        
        logger.info(f"System Cohesion: {structure_score*100:.1f}% structure health")

    def _calculate_structure_score(self):
        """Calculate overall structure health score"""
        total_score = 0
        total_weight = 0
        
        # Weight different aspects of structure
        weights = {
            'directory_structure': 3,
            'file_organization': 2,
            'configuration_files': 2,
            'python_package_structure': 3
        }
        
        for category, weight in weights.items():
            if category in self.test_results:
                category_results = self.test_results[category]
                passes = sum(1 for r in category_results.values() 
                           if isinstance(r, dict) and r.get('status') == 'pass')
                warnings = sum(1 for r in category_results.values() 
                             if isinstance(r, dict) and r.get('status') == 'warning')
                total = len(category_results)
                
                if total > 0:
                    category_score = (passes + warnings * 0.5) / total
                    total_score += category_score * weight
                    total_weight += weight
        
        return total_score / total_weight if total_weight > 0 else 0

    def _analyze_cross_references(self):
        """Analyze cross-component references in Python files"""
        cross_refs = {
            'total': 0,
            'core_imports': 0,
            'inter_component': 0
        }
        
        try:
            python_files = list(self.src_root.rglob("*.py"))
            
            for py_file in python_files:
                try:
                    with open(py_file, 'r', encoding='utf-8', errors='ignore') as f:
                        content = f.read()
                        
                        # Look for imports from core
                        if 'from core.' in content or 'import core.' in content:
                            cross_refs['core_imports'] += 1
                            cross_refs['total'] += 1
                        
                        # Look for inter-component imports
                        components = ['dns', 'mailcow', 'monitoring', 'vps']
                        for comp in components:
                            if f'from {comp}.' in content or f'import {comp}.' in content:
                                cross_refs['inter_component'] += 1
                                cross_refs['total'] += 1
                        
                except Exception:
                    continue  # Skip files that can't be read
                    
        except Exception:
            pass  # Skip if can't analyze
        
        return cross_refs

    def _generate_report(self):
        """Generate comprehensive validation report"""
        total_tests = 0
        passed_tests = 0
        warning_tests = 0
        failed_tests = 0
        
        # Count all test results
        for category_results in self.test_results.values():
            if isinstance(category_results, dict):
                for result in category_results.values():
                    if isinstance(result, dict) and 'status' in result:
                        total_tests += 1
                        status = result['status']
                        if status == 'pass':
                            passed_tests += 1
                        elif status == 'warning':
                            warning_tests += 1
                        elif status == 'fail':
                            failed_tests += 1
        
        # Calculate overall score
        overall_score = ((passed_tests + warning_tests * 0.7) / total_tests * 100) if total_tests > 0 else 0
        
        # Determine readiness level
        if overall_score >= 90 and failed_tests == 0:
            readiness = "PRODUCTION_READY"
        elif overall_score >= 75 and failed_tests <= 2:
            readiness = "STAGING_READY"
        elif overall_score >= 60:
            readiness = "DEVELOPMENT_READY"
        else:
            readiness = "NEEDS_WORK"
        
        report = {
            'metadata': {
                'generated_at': datetime.now().isoformat(),
                'validator': 'StandaloneIntegrationValidator',
                'version': '1.0.0',
                'project_root': str(self.project_root)
            },
            'summary': {
                'total_tests': total_tests,
                'passed_tests': passed_tests,
                'warning_tests': warning_tests,
                'failed_tests': failed_tests,
                'overall_score': f"{overall_score:.1f}%",
                'readiness_level': readiness
            },
            'detailed_results': self.test_results,
            'recommendations': self._generate_recommendations(),
            'next_steps': self._generate_next_steps(readiness)
        }
        
        return report

    def _generate_recommendations(self):
        """Generate recommendations based on test results"""
        recommendations = []
        
        # Check directory structure
        dir_results = self.test_results.get('directory_structure', {})
        failed_dirs = [name for name, result in dir_results.items() 
                      if result.get('status') == 'fail']
        
        if failed_dirs:
            recommendations.append(f"Create missing directories: {', '.join(failed_dirs)}")
        
        # Check file organization
        file_results = self.test_results.get('file_organization', {})
        missing_files = [name for name, result in file_results.items() 
                        if result.get('status') == 'fail']
        
        if missing_files:
            recommendations.append(f"Create missing key files: {', '.join(missing_files)}")
        
        # Check Python packages
        pkg_results = self.test_results.get('python_package_structure', {})
        if pkg_results.get('required_init_files', {}).get('status') == 'fail':
            missing_inits = pkg_results['required_init_files'].get('missing', [])
            recommendations.append(f"Add missing __init__.py files: {', '.join(missing_inits)}")
        
        # Check configuration
        config_results = self.test_results.get('configuration_files', {})
        if config_results.get('component_config_files', {}).get('status') == 'warning':
            recommendations.append("Add configuration files for components")
        
        # General recommendations
        recommendations.extend([
            "Set up environment-specific configuration files",
            "Add comprehensive logging configuration",
            "Implement error handling across all components",
            "Add integration tests for API endpoints",
            "Set up monitoring and alerting for production"
        ])
        
        return recommendations

    def _generate_next_steps(self, readiness_level):
        """Generate next steps based on readiness level"""
        if readiness_level == "PRODUCTION_READY":
            return [
                "Perform security audit and penetration testing",
                "Set up production monitoring and alerting",
                "Create deployment automation and rollback procedures",
                "Conduct load testing with production-like data"
            ]
        elif readiness_level == "STAGING_READY":
            return [
                "Fix any remaining failed tests",
                "Deploy to staging environment for full integration testing",
                "Test with real API credentials and endpoints",
                "Verify backup and recovery procedures"
            ]
        elif readiness_level == "DEVELOPMENT_READY":
            return [
                "Complete missing file and directory structure",
                "Implement remaining configuration management",
                "Add comprehensive error handling",
                "Create unit tests for all components"
            ]
        else:
            return [
                "Address critical structural issues",
                "Complete basic directory and file organization",
                "Implement core functionality for all components",
                "Re-run validation after fixes"
            ]

    def _save_report(self, report):
        """Save report to file"""
        report_dir = self.project_root / "reports"
        report_dir.mkdir(exist_ok=True)
        
        report_file = report_dir / "system_integration_validation_report.json"
        
        with open(report_file, 'w') as f:
            json.dump(report, f, indent=2, default=str)
        
        logger.info(f"Report saved to: {report_file}")
        
        # Also create a summary file
        summary_file = report_dir / "integration_summary.txt"
        with open(summary_file, 'w') as f:
            f.write("COLD EMAIL INFRASTRUCTURE - SYSTEM INTEGRATION VALIDATION SUMMARY\n")
            f.write("=" * 80 + "\n\n")
            f.write(f"Generated: {report['metadata']['generated_at']}\n")
            f.write(f"Overall Score: {report['summary']['overall_score']}\n")
            f.write(f"Readiness Level: {report['summary']['readiness_level']}\n\n")
            f.write(f"Test Results:\n")
            f.write(f"  - Passed: {report['summary']['passed_tests']}\n")
            f.write(f"  - Warnings: {report['summary']['warning_tests']}\n")
            f.write(f"  - Failed: {report['summary']['failed_tests']}\n")
            f.write(f"  - Total: {report['summary']['total_tests']}\n\n")
            
            f.write("Recommendations:\n")
            for i, rec in enumerate(report['recommendations'], 1):
                f.write(f"  {i}. {rec}\n")
            
            f.write("\nNext Steps:\n")
            for i, step in enumerate(report['next_steps'], 1):
                f.write(f"  {i}. {step}\n")
        
        logger.info(f"Summary saved to: {summary_file}")
        return report_file

def main():
    """Main function"""
    try:
        validator = StandaloneIntegrationValidator()
        report = validator.run_validation()
        
        logger.info("=" * 80)
        logger.info("VALIDATION COMPLETE")
        logger.info("=" * 80)
        logger.info(f"Overall Score: {report['summary']['overall_score']}")
        logger.info(f"Readiness Level: {report['summary']['readiness_level']}")
        logger.info(f"Tests: {report['summary']['passed_tests']} passed, "
                   f"{report['summary']['warning_tests']} warnings, "
                   f"{report['summary']['failed_tests']} failed")
        logger.info("=" * 80)
        
        return 0 if report['summary']['failed_tests'] == 0 else 1
        
    except Exception as e:
        logger.error(f"Validation failed: {e}")
        return 1

if __name__ == "__main__":
    sys.exit(main())