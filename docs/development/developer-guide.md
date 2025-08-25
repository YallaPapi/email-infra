# Cold Email Infrastructure - Developer Guide

## Overview

This comprehensive developer guide covers extending, modifying, and contributing to the Cold Email Infrastructure system. The system is built with Python, follows modern software engineering practices, and provides a modular architecture for easy extension.

## Architecture Overview

### System Design Principles

1. **Modular Architecture**: Clear separation between DNS, Mailcow, Monitoring, and VPS components
2. **Unified Configuration**: Single configuration system across all components
3. **Event-Driven Communication**: Components communicate via event bus
4. **API-First Design**: All functionality accessible via REST API
5. **Testable Code**: Comprehensive test coverage with unit and integration tests
6. **Documentation**: Self-documenting code with comprehensive guides

### Project Structure

```
cold-email-infrastructure/
├── src/email-infrastructure/     # Core implementation
│   ├── core/                     # Shared components
│   │   ├── config_manager.py     # Configuration management
│   │   ├── event_bus.py          # Inter-component communication
│   │   ├── logger.py             # Logging framework
│   │   └── base_component.py     # Base component class
│   ├── dns/                      # DNS management component
│   ├── mailcow/                  # Mail server component
│   ├── monitoring/               # Monitoring component
│   ├── vps/                      # VPS management component
│   ├── api/                      # Unified API layer
│   └── tests/                    # Test suites
├── config/                       # Configuration files
├── scripts/                      # Automation scripts
├── docs/                         # Documentation
└── tools/                        # Development tools
```

## Development Environment Setup

### 1. Prerequisites

**System Requirements:**
```bash
# Python 3.8+ with development tools
sudo apt update
sudo apt install -y python3.9 python3.9-dev python3-pip python3-venv

# Development dependencies
sudo apt install -y git docker.io docker-compose-plugin build-essential

# Optional: Database tools
sudo apt install -y sqlite3 mysql-client redis-tools
```

### 2. Development Setup

**Clone and Setup:**
```bash
# Clone repository
git clone https://github.com/your-repo/cold-email-infrastructure.git
cd cold-email-infrastructure

# Create virtual environment
python3 -m venv venv
source venv/bin/activate

# Install development dependencies
pip install -r requirements-dev.txt
pip install -e .  # Install in editable mode

# Set up pre-commit hooks
pre-commit install
```

**Environment Configuration:**
```bash
# Copy development environment template
cp config/environments/development.yaml.template config/environments/development.yaml

# Set development environment variables
export EMAIL_INFRA_ENV=development
export EMAIL_INFRA_ROOT=$(pwd)
export EMAIL_INFRA_LOG_LEVEL=DEBUG

# Create development configuration
cat > .env << 'EOF'
EMAIL_INFRA_ENV=development
EMAIL_INFRA_ROOT=/path/to/project
CLOUDFLARE_API_TOKEN=your_dev_token
MAILCOW_HOSTNAME=mail.dev.local
DEBUG=true
EOF
```

### 3. Development Tools

**Install Development Tools:**
```bash
# Code quality tools
pip install black isort flake8 mypy pylint

# Testing tools
pip install pytest pytest-cov pytest-asyncio

# Documentation tools
pip install sphinx sphinx-rtd-theme

# API development
pip install fastapi uvicorn

# Database tools
pip install alembic sqlalchemy
```

**Configure IDE (VS Code):**
```json
{
  "python.defaultInterpreterPath": "./venv/bin/python",
  "python.linting.enabled": true,
  "python.linting.flake8Enabled": true,
  "python.formatting.provider": "black",
  "python.formatting.blackArgs": ["--line-length=88"],
  "python.testing.pytestEnabled": true,
  "files.exclude": {
    "**/__pycache__": true,
    "**/*.pyc": true
  }
}
```

## Component Development

### 1. Creating a New Component

**Component Structure:**
```
src/email-infrastructure/new-component/
├── __init__.py
├── core/                         # Core functionality
│   ├── __init__.py
│   └── component_manager.py      # Main component logic
├── managers/                     # Management modules
│   ├── __init__.py
│   └── resource_manager.py
├── api/                          # API endpoints
│   ├── __init__.py
│   └── endpoints.py
├── config/                       # Component configuration
│   ├── __init__.py
│   └── component-config.yaml
├── tests/                        # Component tests
│   ├── __init__.py
│   ├── test_component.py
│   └── test_integration.py
└── README.md                     # Component documentation
```

**Base Component Implementation:**

```python
# src/email-infrastructure/new-component/core/component_manager.py
from typing import Dict, Any, Optional
from email_infrastructure.core.base_component import BaseComponent
from email_infrastructure.core.config_manager import get_section
from email_infrastructure.core.logger import get_logger

class NewComponentManager(BaseComponent):
    """New component manager implementation."""
    
    def __init__(self, config: Optional[Dict[str, Any]] = None):
        """Initialize the new component manager."""
        self.config = config or get_section('new_component')
        self.logger = get_logger(f"{__name__}.{self.__class__.__name__}")
        super().__init__('new-component')
    
    async def initialize(self) -> bool:
        """Initialize the component."""
        try:
            self.logger.info("Initializing new component")
            
            # Component initialization logic
            await self._setup_resources()
            await self._validate_configuration()
            
            # Register event handlers
            self._register_event_handlers()
            
            self.logger.info("New component initialized successfully")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to initialize new component: {e}")
            return False
    
    async def _setup_resources(self):
        """Set up component resources."""
        # Implementation specific to your component
        pass
    
    async def _validate_configuration(self):
        """Validate component configuration."""
        required_keys = ['api_endpoint', 'timeout', 'retry_attempts']
        for key in required_keys:
            if key not in self.config:
                raise ValueError(f"Missing required configuration: {key}")
    
    def _register_event_handlers(self):
        """Register event handlers for component communication."""
        from email_infrastructure.core.event_bus import EventBus
        
        EventBus.subscribe('system.started', self._on_system_started)
        EventBus.subscribe('system.stopping', self._on_system_stopping)
    
    async def _on_system_started(self, event_data: Dict[str, Any]):
        """Handle system started event."""
        self.logger.info("System started event received")
    
    async def _on_system_stopping(self, event_data: Dict[str, Any]):
        """Handle system stopping event."""
        self.logger.info("System stopping event received")
        await self.cleanup()
    
    async def health_check(self) -> Dict[str, Any]:
        """Perform component health check."""
        try:
            # Implement health check logic
            status = {
                'status': 'healthy',
                'component': 'new-component',
                'timestamp': self.get_current_timestamp(),
                'metrics': {
                    'response_time': 0.123,
                    'error_rate': 0.0,
                    'active_connections': 5
                }
            }
            
            return status
            
        except Exception as e:
            self.logger.error(f"Health check failed: {e}")
            return {
                'status': 'unhealthy',
                'component': 'new-component',
                'error': str(e),
                'timestamp': self.get_current_timestamp()
            }
    
    async def cleanup(self):
        """Clean up component resources."""
        self.logger.info("Cleaning up new component resources")
        # Cleanup logic here
```

### 2. API Endpoint Development

**FastAPI Endpoint Implementation:**

```python
# src/email-infrastructure/new-component/api/endpoints.py
from fastapi import APIRouter, HTTPException, Depends
from typing import Dict, Any, List
from pydantic import BaseModel

from email_infrastructure.api.middleware.auth import get_current_user
from email_infrastructure.api.middleware.rate_limiter import rate_limit
from ..core.component_manager import NewComponentManager

router = APIRouter(prefix="/api/v1/new-component", tags=["new-component"])

class ComponentRequest(BaseModel):
    name: str
    description: str
    config: Dict[str, Any] = {}

class ComponentResponse(BaseModel):
    id: str
    name: str
    status: str
    created_at: str

@router.get("/status")
@rate_limit(requests=60, window=60)  # 60 requests per minute
async def get_component_status():
    """Get component status."""
    try:
        manager = NewComponentManager()
        status = await manager.health_check()
        return {"success": True, "data": status}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.post("/create")
@rate_limit(requests=10, window=60)
async def create_resource(
    request: ComponentRequest,
    current_user = Depends(get_current_user)
):
    """Create a new resource."""
    try:
        manager = NewComponentManager()
        resource = await manager.create_resource(
            name=request.name,
            description=request.description,
            config=request.config
        )
        
        return {
            "success": True,
            "data": ComponentResponse(
                id=resource['id'],
                name=resource['name'],
                status=resource['status'],
                created_at=resource['created_at']
            )
        }
        
    except Exception as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/resources")
async def list_resources(
    limit: int = 100,
    offset: int = 0,
    current_user = Depends(get_current_user)
):
    """List component resources."""
    try:
        manager = NewComponentManager()
        resources = await manager.list_resources(limit=limit, offset=offset)
        
        return {
            "success": True,
            "data": {
                "resources": resources,
                "pagination": {
                    "limit": limit,
                    "offset": offset,
                    "total": len(resources)
                }
            }
        }
        
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
```

### 3. Database Integration

**Database Models:**

```python
# src/email-infrastructure/new-component/models.py
from sqlalchemy import Column, Integer, String, DateTime, Text, Boolean
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.sql import func

from email_infrastructure.core.database import Base

class ComponentResource(Base):
    """Component resource model."""
    __tablename__ = 'component_resources'
    
    id = Column(Integer, primary_key=True)
    name = Column(String(255), nullable=False, unique=True)
    description = Column(Text)
    status = Column(String(50), default='active')
    config = Column(Text)  # JSON configuration
    created_at = Column(DateTime, default=func.now())
    updated_at = Column(DateTime, default=func.now(), onupdate=func.now())
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert model to dictionary."""
        return {
            'id': self.id,
            'name': self.name,
            'description': self.description,
            'status': self.status,
            'config': json.loads(self.config) if self.config else {},
            'created_at': self.created_at.isoformat(),
            'updated_at': self.updated_at.isoformat()
        }
```

**Database Operations:**

```python
# src/email-infrastructure/new-component/core/database_manager.py
from typing import List, Optional, Dict, Any
from sqlalchemy.orm import Session
from email_infrastructure.core.database import get_db_session
from ..models import ComponentResource

class ComponentDatabaseManager:
    """Database operations for component resources."""
    
    def __init__(self):
        self.session: Session = get_db_session()
    
    async def create_resource(self, **kwargs) -> ComponentResource:
        """Create a new component resource."""
        resource = ComponentResource(**kwargs)
        self.session.add(resource)
        await self.session.commit()
        await self.session.refresh(resource)
        return resource
    
    async def get_resource(self, resource_id: int) -> Optional[ComponentResource]:
        """Get resource by ID."""
        return self.session.query(ComponentResource).filter(
            ComponentResource.id == resource_id
        ).first()
    
    async def list_resources(
        self,
        limit: int = 100,
        offset: int = 0,
        status: Optional[str] = None
    ) -> List[ComponentResource]:
        """List component resources."""
        query = self.session.query(ComponentResource)
        
        if status:
            query = query.filter(ComponentResource.status == status)
        
        return query.offset(offset).limit(limit).all()
    
    async def update_resource(
        self,
        resource_id: int,
        **updates
    ) -> Optional[ComponentResource]:
        """Update component resource."""
        resource = await self.get_resource(resource_id)
        if not resource:
            return None
        
        for key, value in updates.items():
            setattr(resource, key, value)
        
        await self.session.commit()
        await self.session.refresh(resource)
        return resource
    
    async def delete_resource(self, resource_id: int) -> bool:
        """Delete component resource."""
        resource = await self.get_resource(resource_id)
        if not resource:
            return False
        
        self.session.delete(resource)
        await self.session.commit()
        return True
```

## Testing Framework

### 1. Unit Testing

**Test Structure:**

```python
# src/email-infrastructure/new-component/tests/test_component.py
import pytest
import asyncio
from unittest.mock import Mock, patch, AsyncMock

from email_infrastructure.new_component.core.component_manager import NewComponentManager

class TestNewComponentManager:
    """Test suite for NewComponentManager."""
    
    @pytest.fixture
    async def component_manager(self):
        """Create component manager instance for testing."""
        config = {
            'api_endpoint': 'https://test.api.com',
            'timeout': 30,
            'retry_attempts': 3
        }
        manager = NewComponentManager(config)
        await manager.initialize()
        yield manager
        await manager.cleanup()
    
    @pytest.mark.asyncio
    async def test_initialization(self, component_manager):
        """Test component initialization."""
        assert component_manager is not None
        assert component_manager.config['timeout'] == 30
    
    @pytest.mark.asyncio
    async def test_health_check(self, component_manager):
        """Test component health check."""
        health_status = await component_manager.health_check()
        
        assert health_status['status'] == 'healthy'
        assert health_status['component'] == 'new-component'
        assert 'timestamp' in health_status
        assert 'metrics' in health_status
    
    @pytest.mark.asyncio
    async def test_create_resource(self, component_manager):
        """Test resource creation."""
        with patch.object(component_manager, '_api_call', new_callable=AsyncMock) as mock_api:
            mock_api.return_value = {
                'id': 'test-123',
                'name': 'test-resource',
                'status': 'created'
            }
            
            resource = await component_manager.create_resource(
                name='test-resource',
                description='Test resource'
            )
            
            assert resource['id'] == 'test-123'
            assert resource['name'] == 'test-resource'
            mock_api.assert_called_once()
    
    @pytest.mark.asyncio
    async def test_error_handling(self, component_manager):
        """Test error handling."""
        with patch.object(component_manager, '_api_call', new_callable=AsyncMock) as mock_api:
            mock_api.side_effect = Exception("API Error")
            
            with pytest.raises(Exception) as exc_info:
                await component_manager.create_resource(name='test')
            
            assert "API Error" in str(exc_info.value)
    
    def test_configuration_validation(self):
        """Test configuration validation."""
        # Test missing required configuration
        with pytest.raises(ValueError) as exc_info:
            NewComponentManager({})
        
        assert "Missing required configuration" in str(exc_info.value)
```

### 2. Integration Testing

**API Integration Tests:**

```python
# src/email-infrastructure/tests/integration/test_new_component_api.py
import pytest
import asyncio
from fastapi.testclient import TestClient
from email_infrastructure.api.main import app

class TestNewComponentAPI:
    """Integration tests for new component API."""
    
    @pytest.fixture
    def client(self):
        """Create test client."""
        return TestClient(app)
    
    @pytest.fixture
    def auth_headers(self):
        """Create authentication headers."""
        return {"Authorization": "Bearer test-api-key"}
    
    def test_get_component_status(self, client, auth_headers):
        """Test component status endpoint."""
        response = client.get("/api/v1/new-component/status", headers=auth_headers)
        
        assert response.status_code == 200
        data = response.json()
        assert data['success'] is True
        assert 'data' in data
        assert data['data']['component'] == 'new-component'
    
    def test_create_resource(self, client, auth_headers):
        """Test resource creation endpoint."""
        payload = {
            "name": "test-resource",
            "description": "Test resource description",
            "config": {"setting1": "value1"}
        }
        
        response = client.post(
            "/api/v1/new-component/create",
            json=payload,
            headers=auth_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data['success'] is True
        assert data['data']['name'] == 'test-resource'
    
    def test_list_resources(self, client, auth_headers):
        """Test resource listing endpoint."""
        response = client.get(
            "/api/v1/new-component/resources?limit=10&offset=0",
            headers=auth_headers
        )
        
        assert response.status_code == 200
        data = response.json()
        assert data['success'] is True
        assert 'resources' in data['data']
        assert 'pagination' in data['data']
    
    def test_rate_limiting(self, client, auth_headers):
        """Test API rate limiting."""
        # Make multiple requests to trigger rate limiting
        for _ in range(65):  # Exceed limit of 60 per minute
            response = client.get("/api/v1/new-component/status", headers=auth_headers)
        
        assert response.status_code == 429  # Too Many Requests
    
    def test_authentication_required(self, client):
        """Test that authentication is required."""
        response = client.get("/api/v1/new-component/status")
        
        assert response.status_code == 401  # Unauthorized
```

### 3. End-to-End Testing

**Complete Workflow Tests:**

```python
# src/email-infrastructure/tests/e2e/test_component_workflow.py
import pytest
import asyncio
from email_infrastructure.new_component.core.component_manager import NewComponentManager
from email_infrastructure.core.event_bus import EventBus

class TestComponentWorkflow:
    """End-to-end workflow tests."""
    
    @pytest.mark.asyncio
    async def test_complete_resource_lifecycle(self):
        """Test complete resource lifecycle."""
        manager = NewComponentManager()
        await manager.initialize()
        
        try:
            # 1. Create resource
            resource = await manager.create_resource(
                name='e2e-test-resource',
                description='End-to-end test resource'
            )
            assert resource['status'] == 'created'
            resource_id = resource['id']
            
            # 2. Retrieve resource
            retrieved = await manager.get_resource(resource_id)
            assert retrieved['name'] == 'e2e-test-resource'
            
            # 3. Update resource
            updated = await manager.update_resource(
                resource_id,
                description='Updated description'
            )
            assert updated['description'] == 'Updated description'
            
            # 4. List resources
            resources = await manager.list_resources()
            resource_names = [r['name'] for r in resources]
            assert 'e2e-test-resource' in resource_names
            
            # 5. Delete resource
            deleted = await manager.delete_resource(resource_id)
            assert deleted is True
            
            # 6. Verify deletion
            retrieved_after_delete = await manager.get_resource(resource_id)
            assert retrieved_after_delete is None
            
        finally:
            await manager.cleanup()
    
    @pytest.mark.asyncio
    async def test_event_communication(self):
        """Test inter-component event communication."""
        manager = NewComponentManager()
        await manager.initialize()
        
        # Set up event listener
        events_received = []
        
        def event_handler(event_data):
            events_received.append(event_data)
        
        EventBus.subscribe('new_component.resource.created', event_handler)
        
        try:
            # Trigger event
            await manager.create_resource(
                name='event-test-resource',
                description='Event test resource'
            )
            
            # Give some time for event processing
            await asyncio.sleep(0.1)
            
            # Verify event was received
            assert len(events_received) > 0
            assert events_received[0]['resource_name'] == 'event-test-resource'
            
        finally:
            EventBus.unsubscribe('new_component.resource.created', event_handler)
            await manager.cleanup()
```

## Code Quality and Standards

### 1. Code Formatting

**Black Configuration:**

```toml
# pyproject.toml
[tool.black]
line-length = 88
target-version = ['py38', 'py39']
include = '\.pyi?$'
extend-exclude = '''
/(
  # directories
  \.eggs
  | \.git
  | \.hg
  | \.mypy_cache
  | \.tox
  | \.venv
  | build
  | dist
)/
'''
```

**isort Configuration:**

```toml
# pyproject.toml
[tool.isort]
profile = "black"
multi_line_output = 3
line_length = 88
known_first_party = ["email_infrastructure"]
sections = ["FUTURE", "STDLIB", "THIRDPARTY", "FIRSTPARTY", "LOCALFOLDER"]
```

### 2. Type Checking

**mypy Configuration:**

```ini
# mypy.ini
[mypy]
python_version = 3.8
warn_return_any = True
warn_unused_configs = True
disallow_untyped_defs = True
disallow_incomplete_defs = True
check_untyped_defs = True
disallow_untyped_decorators = True
no_implicit_optional = True
warn_redundant_casts = True
warn_unused_ignores = True
warn_no_return = True
warn_unreachable = True

[mypy-email_infrastructure.*]
disallow_untyped_defs = True

[mypy-tests.*]
ignore_errors = True
```

**Type Annotations Example:**

```python
from typing import Dict, List, Optional, Union, Any, Awaitable
from dataclasses import dataclass
from enum import Enum

class ResourceStatus(Enum):
    ACTIVE = "active"
    INACTIVE = "inactive"
    PENDING = "pending"
    ERROR = "error"

@dataclass
class ResourceConfig:
    name: str
    description: str
    timeout: int = 30
    retry_attempts: int = 3
    settings: Dict[str, Any] = None

class TypedComponentManager:
    """Type-annotated component manager."""
    
    def __init__(self, config: Optional[ResourceConfig] = None) -> None:
        self.config = config
        self.resources: Dict[str, Any] = {}
    
    async def create_resource(
        self,
        name: str,
        description: str,
        config: Optional[Dict[str, Any]] = None
    ) -> Dict[str, Union[str, int]]:
        """Create a new resource with type annotations."""
        # Implementation
        return {"id": "123", "name": name, "status": "created"}
    
    async def get_resources(
        self,
        status: Optional[ResourceStatus] = None
    ) -> List[Dict[str, Any]]:
        """Get resources with optional status filter."""
        # Implementation
        return []
```

### 3. Documentation Standards

**Docstring Style (Google Style):**

```python
class ComponentManager:
    """Component manager for handling resources.
    
    This class provides comprehensive resource management including creation,
    retrieval, updating, and deletion of component resources. It integrates
    with the unified configuration system and event bus.
    
    Attributes:
        config (Dict[str, Any]): Component configuration
        logger (Logger): Component logger instance
        
    Example:
        >>> manager = ComponentManager()
        >>> await manager.initialize()
        >>> resource = await manager.create_resource(name="test", description="Test resource")
        >>> print(resource['id'])
        'resource-123'
    """
    
    def __init__(self, config: Optional[Dict[str, Any]] = None) -> None:
        """Initialize the component manager.
        
        Args:
            config: Optional configuration dictionary. If not provided,
                   configuration will be loaded from the unified config system.
        
        Raises:
            ValueError: If required configuration keys are missing.
            ConfigurationError: If configuration validation fails.
        """
        pass
    
    async def create_resource(
        self,
        name: str,
        description: str,
        config: Optional[Dict[str, Any]] = None,
        tags: Optional[List[str]] = None
    ) -> Dict[str, Any]:
        """Create a new component resource.
        
        Creates a new resource with the specified parameters and stores it
        in the component's resource registry. The resource will be validated
        before creation and events will be emitted upon successful creation.
        
        Args:
            name: Unique name for the resource (must be alphanumeric)
            description: Human-readable description of the resource
            config: Optional resource-specific configuration
            tags: Optional list of tags for resource categorization
            
        Returns:
            Dict containing the created resource with keys:
            - id (str): Unique resource identifier
            - name (str): Resource name
            - status (str): Current resource status
            - created_at (str): ISO timestamp of creation
            
        Raises:
            ValueError: If name is invalid or already exists
            ResourceCreationError: If resource creation fails
            
        Example:
            >>> resource = await manager.create_resource(
            ...     name="web-server",
            ...     description="Production web server",
            ...     config={"port": 80, "ssl": True},
            ...     tags=["production", "web"]
            ... )
            >>> print(resource['id'])
            'resource-abc123'
        """
        pass
```

## Performance Optimization

### 1. Asynchronous Programming

**Async Best Practices:**

```python
import asyncio
import aiohttp
from typing import List, Dict, Any
from contextlib import asynccontextmanager

class OptimizedComponentManager:
    """Optimized component manager with async patterns."""
    
    def __init__(self):
        self.session: Optional[aiohttp.ClientSession] = None
        self.connection_pool_size = 100
        self.timeout = aiohttp.ClientTimeout(total=30)
    
    async def __aenter__(self):
        """Async context manager entry."""
        connector = aiohttp.TCPConnector(
            limit=self.connection_pool_size,
            limit_per_host=20,
            keepalive_timeout=30
        )
        self.session = aiohttp.ClientSession(
            connector=connector,
            timeout=self.timeout
        )
        return self
    
    async def __aexit__(self, exc_type, exc_val, exc_tb):
        """Async context manager exit."""
        if self.session:
            await self.session.close()
    
    async def batch_create_resources(
        self,
        resources: List[Dict[str, Any]]
    ) -> List[Dict[str, Any]]:
        """Create multiple resources concurrently."""
        semaphore = asyncio.Semaphore(10)  # Limit concurrent requests
        
        async def create_single_resource(resource_data):
            async with semaphore:
                return await self._create_resource_internal(resource_data)
        
        # Execute all creation tasks concurrently
        tasks = [
            create_single_resource(resource)
            for resource in resources
        ]
        
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Filter out exceptions and return successful results
        successful_results = [
            result for result in results
            if not isinstance(result, Exception)
        ]
        
        return successful_results
    
    async def _create_resource_internal(self, resource_data: Dict[str, Any]) -> Dict[str, Any]:
        """Internal resource creation with error handling."""
        try:
            async with self.session.post('/api/resources', json=resource_data) as response:
                response.raise_for_status()
                return await response.json()
        except Exception as e:
            self.logger.error(f"Failed to create resource: {e}")
            raise
```

### 2. Caching Strategies

**Multi-Level Caching:**

```python
import redis
from functools import wraps
from typing import Optional, Any, Callable
import json
import hashlib

class CacheManager:
    """Multi-level caching system."""
    
    def __init__(self):
        self.memory_cache: Dict[str, Any] = {}
        self.redis_client = redis.Redis(host='localhost', port=6379, db=0)
        self.max_memory_cache_size = 1000
    
    def cache_key(self, prefix: str, *args, **kwargs) -> str:
        """Generate cache key from arguments."""
        key_data = f"{prefix}:{json.dumps(args, sort_keys=True)}:{json.dumps(kwargs, sort_keys=True)}"
        return hashlib.md5(key_data.encode()).hexdigest()
    
    async def get(self, key: str) -> Optional[Any]:
        """Get value from cache (memory first, then Redis)."""
        # Try memory cache first
        if key in self.memory_cache:
            return self.memory_cache[key]
        
        # Try Redis cache
        try:
            value = self.redis_client.get(key)
            if value:
                parsed_value = json.loads(value)
                # Store in memory cache for faster access
                self._set_memory_cache(key, parsed_value)
                return parsed_value
        except Exception as e:
            self.logger.warning(f"Redis cache error: {e}")
        
        return None
    
    async def set(
        self,
        key: str,
        value: Any,
        ttl: int = 300,
        memory_cache: bool = True
    ) -> bool:
        """Set value in cache."""
        try:
            # Store in Redis
            serialized_value = json.dumps(value)
            self.redis_client.setex(key, ttl, serialized_value)
            
            # Store in memory cache if requested
            if memory_cache:
                self._set_memory_cache(key, value)
            
            return True
        except Exception as e:
            self.logger.error(f"Cache set error: {e}")
            return False
    
    def _set_memory_cache(self, key: str, value: Any):
        """Set value in memory cache with LRU eviction."""
        if len(self.memory_cache) >= self.max_memory_cache_size:
            # Remove oldest item (simple LRU)
            oldest_key = next(iter(self.memory_cache))
            del self.memory_cache[oldest_key]
        
        self.memory_cache[key] = value

def cached(ttl: int = 300, cache_prefix: str = "default"):
    """Decorator for caching function results."""
    def decorator(func: Callable):
        @wraps(func)
        async def wrapper(*args, **kwargs):
            cache_manager = CacheManager()
            cache_key = cache_manager.cache_key(
                f"{cache_prefix}:{func.__name__}",
                *args,
                **kwargs
            )
            
            # Try to get from cache
            cached_result = await cache_manager.get(cache_key)
            if cached_result is not None:
                return cached_result
            
            # Execute function and cache result
            result = await func(*args, **kwargs)
            await cache_manager.set(cache_key, result, ttl)
            return result
        
        return wrapper
    return decorator

# Usage example
@cached(ttl=600, cache_prefix="dns")
async def get_dns_records(domain: str) -> List[Dict[str, Any]]:
    """Get DNS records with caching."""
    # Expensive operation
    records = await fetch_dns_records_from_api(domain)
    return records
```

### 3. Database Optimization

**Connection Pooling and Query Optimization:**

```python
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker, scoped_session
from sqlalchemy.pool import QueuePool
import asyncio

class OptimizedDatabase:
    """Optimized database manager."""
    
    def __init__(self, database_url: str):
        self.engine = create_engine(
            database_url,
            poolclass=QueuePool,
            pool_size=20,
            max_overflow=30,
            pool_pre_ping=True,
            pool_recycle=3600,
            echo=False  # Set to True for SQL debugging
        )
        self.session_factory = sessionmaker(bind=self.engine)
        self.Session = scoped_session(self.session_factory)
    
    @asynccontextmanager
    async def get_session(self):
        """Get database session with proper cleanup."""
        session = self.Session()
        try:
            yield session
            session.commit()
        except Exception:
            session.rollback()
            raise
        finally:
            session.close()
    
    async def bulk_insert(self, model_class, data: List[Dict]):
        """Optimized bulk insert operation."""
        async with self.get_session() as session:
            session.bulk_insert_mappings(model_class, data)
    
    async def execute_query_with_pagination(
        self,
        query,
        page: int = 1,
        per_page: int = 100
    ) -> Dict[str, Any]:
        """Execute query with optimized pagination."""
        offset = (page - 1) * per_page
        
        async with self.get_session() as session:
            # Get total count efficiently
            count_query = query.statement.with_only_columns([func.count()])
            total = session.execute(count_query).scalar()
            
            # Get paginated results
            results = query.offset(offset).limit(per_page).all()
            
            return {
                'items': [item.to_dict() for item in results],
                'pagination': {
                    'page': page,
                    'per_page': per_page,
                    'total': total,
                    'pages': (total + per_page - 1) // per_page
                }
            }
```

## Deployment and CI/CD

### 1. Docker Development

**Development Dockerfile:**

```dockerfile
# Dockerfile.dev
FROM python:3.9-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Create application user
RUN useradd -m -u 1001 emailinfra

# Set working directory
WORKDIR /app

# Copy requirements first (for better caching)
COPY requirements-dev.txt .
RUN pip install --no-cache-dir -r requirements-dev.txt

# Copy application code
COPY --chown=emailinfra:emailinfra . .

# Install in development mode
RUN pip install -e .

# Switch to non-root user
USER emailinfra

# Expose development port
EXPOSE 8000

# Development command
CMD ["uvicorn", "email_infrastructure.api.main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
```

**Docker Compose for Development:**

```yaml
# docker-compose.dev.yml
version: '3.8'

services:
  api:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "8000:8000"
    volumes:
      - .:/app
      - /app/venv
    environment:
      - EMAIL_INFRA_ENV=development
      - EMAIL_INFRA_LOG_LEVEL=DEBUG
    depends_on:
      - redis
      - postgres
  
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
  
  postgres:
    image: postgres:14-alpine
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_DB=emailinfra_dev
      - POSTGRES_USER=emailinfra
      - POSTGRES_PASSWORD=dev_password
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  redis_data:
  postgres_data:
```

### 2. CI/CD Pipeline

**GitHub Actions Workflow:**

```yaml
# .github/workflows/ci.yml
name: CI/CD Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        python-version: [3.8, 3.9]
    
    services:
      redis:
        image: redis:7
        ports:
          - 6379:6379
      postgres:
        image: postgres:14
        env:
          POSTGRES_PASSWORD: test_password
          POSTGRES_DB: emailinfra_test
        ports:
          - 5432:5432
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up Python ${{ matrix.python-version }}
      uses: actions/setup-python@v4
      with:
        python-version: ${{ matrix.python-version }}
    
    - name: Cache pip dependencies
      uses: actions/cache@v3
      with:
        path: ~/.cache/pip
        key: ${{ runner.os }}-pip-${{ hashFiles('**/requirements*.txt') }}
        restore-keys: |
          ${{ runner.os }}-pip-
    
    - name: Install dependencies
      run: |
        python -m pip install --upgrade pip
        pip install -r requirements-dev.txt
        pip install -e .
    
    - name: Run code quality checks
      run: |
        # Format check
        black --check .
        
        # Import sorting check
        isort --check-only .
        
        # Linting
        flake8 .
        
        # Type checking
        mypy src/email-infrastructure/
    
    - name: Run security checks
      run: |
        # Security audit
        safety check
        
        # Dependency vulnerabilities
        pip-audit
    
    - name: Run tests
      env:
        EMAIL_INFRA_ENV: testing
        DATABASE_URL: postgresql://postgres:test_password@localhost:5432/emailinfra_test
        REDIS_URL: redis://localhost:6379/0
      run: |
        pytest --cov=src/email-infrastructure --cov-report=xml --cov-report=html
    
    - name: Upload coverage reports
      uses: codecov/codecov-action@v3
      with:
        file: ./coverage.xml
    
    - name: Build Docker image
      run: |
        docker build -t emailinfra:${{ github.sha }} .
    
    - name: Run integration tests
      run: |
        docker-compose -f docker-compose.test.yml up -d
        docker-compose -f docker-compose.test.yml exec -T api pytest tests/integration/
        docker-compose -f docker-compose.test.yml down

  deploy:
    needs: test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Deploy to staging
      run: |
        # Add deployment steps here
        echo "Deploying to staging environment"
    
    - name: Run smoke tests
      run: |
        # Add smoke tests here
        echo "Running smoke tests"
```

## Contributing Guidelines

### 1. Development Workflow

**Branch Strategy:**
```bash
# Feature development
git checkout -b feature/new-component-feature
git commit -m "Add new component feature"
git push origin feature/new-component-feature

# Bug fixes
git checkout -b fix/component-bug-fix
git commit -m "Fix component initialization bug"
git push origin fix/component-bug-fix

# Release branches
git checkout -b release/v1.2.0
```

### 2. Commit Message Standards

**Conventional Commits Format:**
```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Examples:**
```
feat(dns): add batch DNS record creation
fix(mailcow): resolve API authentication issue
docs(api): update endpoint documentation
test(monitoring): add integration tests for blacklist monitor
chore(deps): update dependencies to latest versions
```

### 3. Pull Request Process

**PR Checklist:**
- [ ] Code follows project style guidelines
- [ ] Self-review of code completed
- [ ] Tests added for new functionality
- [ ] All tests pass locally
- [ ] Documentation updated
- [ ] Security considerations addressed
- [ ] Performance impact considered
- [ ] Breaking changes documented

## Debugging and Profiling

### 1. Debug Configuration

**Enable Debug Logging:**

```python
import logging
from email_infrastructure.core.logger import setup_debug_logging

# Enable debug logging
setup_debug_logging()

# Component-specific debug logging
logger = logging.getLogger('email_infrastructure.dns')
logger.setLevel(logging.DEBUG)

# Add debug middleware to API
from email_infrastructure.api.middleware.debug import DebugMiddleware
app.add_middleware(DebugMiddleware)
```

### 2. Performance Profiling

**Profiling Code:**

```python
import cProfile
import pstats
from functools import wraps

def profile(func):
    """Decorator for profiling function performance."""
    @wraps(func)
    def wrapper(*args, **kwargs):
        profiler = cProfile.Profile()
        profiler.enable()
        
        try:
            result = func(*args, **kwargs)
        finally:
            profiler.disable()
            stats = pstats.Stats(profiler)
            stats.sort_stats('cumulative')
            stats.print_stats(20)  # Top 20 functions
        
        return result
    return wrapper

# Usage
@profile
async def expensive_operation():
    # Your code here
    pass
```

This developer guide provides a comprehensive foundation for extending and contributing to the Cold Email Infrastructure system. The modular architecture, comprehensive testing framework, and clear development standards ensure maintainable and scalable code development.