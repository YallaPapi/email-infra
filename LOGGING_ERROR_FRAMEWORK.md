# Standardized Logging and Error Handling Framework

## Overview

This framework consolidates the 20+ separate logging implementations and inconsistent error handling patterns found across the cold email infrastructure into a unified, standardized system. Currently, each component implements its own logging configuration and error handling, leading to maintenance overhead and inconsistent behavior.

## Current Problems Identified

### Logging Duplication:
**Found identical patterns across 20+ files:**
```python
# Repeated in every component:
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/component.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)
```

### Error Handling Inconsistencies:
**Found 3+ different error patterns:**
```python
# Pattern 1 (most common):
except Exception as e:
    logger.error(f"Operation failed: {e}")
    raise

# Pattern 2 (some files):
except requests.RequestException as e:
    if retry_count < max_retries:
        # retry logic
    raise CustomError(f"API failed: {e}")

# Pattern 3 (inconsistent):
try:
    # operation
except:
    # Silent failure or basic print
```

### Custom Exception Chaos:
- `CloudflareAPIError`
- `MailcowAPIError` 
- Various unnamed exception classes
- Inconsistent error message formats
- No error categorization or handling strategies

## Unified Framework Architecture

### Directory Structure
```
/src/common/logging/
├── __init__.py                      # Public logging API
├── logger.py                        # Main logger factory
├── formatters.py                    # Log formatters (JSON, structured, etc.)
├── handlers.py                      # Custom log handlers
├── filters.py                       # Log filters and processors
└── config.py                        # Logging configuration management

/src/common/exceptions/
├── __init__.py                      # Public exception API
├── base.py                          # Base exception hierarchy
├── infrastructure.py                # Infrastructure-specific exceptions
├── api.py                          # API-related exceptions
├── validation.py                    # Data validation exceptions
├── handlers.py                      # Exception handlers and processors
└── formatters.py                    # Error message formatters
```

## Unified Logging System

### Main Logger Factory (`logging/logger.py`)
```python
#!/usr/bin/env python3
"""
Unified Logger Factory
Centralized logging system for the entire infrastructure
"""

import logging
import logging.handlers
import os
import sys
from typing import Dict, Any, Optional, List, Union
from pathlib import Path
from datetime import datetime
import json

from .formatters import JSONFormatter, StructuredFormatter, ColoredFormatter
from .handlers import AsyncRotatingFileHandler, MetricsHandler
from .filters import SensitiveDataFilter, ComponentFilter
from ..config import get_value

class LoggerFactory:
    """Factory for creating standardized loggers"""
    
    _loggers: Dict[str, logging.Logger] = {}
    _configured: bool = False
    
    @classmethod
    def get_logger(cls, name: str, component: str = None) -> logging.Logger:
        """
        Get or create a logger with standardized configuration
        
        Args:
            name: Logger name (typically __name__)
            component: Component name for categorization (dns, email, api, etc.)
            
        Returns:
            Configured logger instance
        """
        if not cls._configured:
            cls._setup_root_logging()
        
        # Create unique logger key
        logger_key = f"{component}.{name}" if component else name
        
        if logger_key not in cls._loggers:
            logger = logging.getLogger(logger_key)
            cls._configure_logger(logger, component)
            cls._loggers[logger_key] = logger
        
        return cls._loggers[logger_key]
    
    @classmethod
    def _setup_root_logging(cls):
        """Setup root logging configuration"""
        # Get logging configuration
        log_config = get_value('logging', {})
        
        # Configure root logger
        root_logger = logging.getLogger()
        root_logger.setLevel(getattr(logging, log_config.get('level', 'INFO')))
        
        # Remove default handlers to avoid duplication
        root_logger.handlers.clear()
        
        # Setup handlers based on configuration
        handlers = cls._create_handlers(log_config.get('handlers', []))
        
        for handler in handlers:
            root_logger.addHandler(handler)
        
        cls._configured = True
    
    @classmethod
    def _configure_logger(cls, logger: logging.Logger, component: str = None):
        """Configure individual logger"""
        # Add component-specific filters
        if component:
            logger.addFilter(ComponentFilter(component))
        
        # Add sensitive data filter
        logger.addFilter(SensitiveDataFilter())
        
        # Set logger-specific configuration if available
        log_config = get_value('logging', {})
        logger_configs = log_config.get('loggers', {})
        
        if component and component in logger_configs:
            config = logger_configs[component]
            logger.setLevel(getattr(logging, config.get('level', 'INFO')))
            
            # Add component-specific handlers if configured
            if 'handlers' in config:
                for handler_name in config['handlers']:
                    handler = cls._get_handler_by_name(handler_name)
                    if handler:
                        logger.addHandler(handler)
    
    @classmethod
    def _create_handlers(cls, handler_configs: List[Dict]) -> List[logging.Handler]:
        """Create logging handlers from configuration"""
        handlers = []
        
        for config in handler_configs:
            handler_type = config.get('type', 'console')
            
            try:
                if handler_type == 'console':
                    handler = cls._create_console_handler(config)
                elif handler_type == 'file':
                    handler = cls._create_file_handler(config)
                elif handler_type == 'rotating_file':
                    handler = cls._create_rotating_file_handler(config)
                elif handler_type == 'json':
                    handler = cls._create_json_handler(config)
                elif handler_type == 'syslog':
                    handler = cls._create_syslog_handler(config)
                elif handler_type == 'metrics':
                    handler = cls._create_metrics_handler(config)
                else:
                    logging.warning(f"Unknown handler type: {handler_type}")
                    continue
                
                handlers.append(handler)
                
            except Exception as e:
                logging.error(f"Failed to create handler {handler_type}: {e}")
        
        return handlers
    
    @classmethod
    def _create_console_handler(cls, config: Dict) -> logging.StreamHandler:
        """Create console handler"""
        handler = logging.StreamHandler(sys.stdout)
        
        # Use colored formatter for console output
        formatter = ColoredFormatter(
            config.get('format', '%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        )
        handler.setFormatter(formatter)
        
        level = config.get('level')
        if level:
            handler.setLevel(getattr(logging, level))
        
        return handler
    
    @classmethod
    def _create_file_handler(cls, config: Dict) -> logging.FileHandler:
        """Create basic file handler"""
        filename = config.get('filename', '/var/log/email-infrastructure.log')
        
        # Ensure directory exists
        os.makedirs(os.path.dirname(filename), exist_ok=True)
        
        handler = logging.FileHandler(filename, encoding='utf-8')
        
        # Use structured formatter for file output
        formatter = StructuredFormatter(
            config.get('format', '%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        )
        handler.setFormatter(formatter)
        
        level = config.get('level')
        if level:
            handler.setLevel(getattr(logging, level))
        
        return handler
    
    @classmethod
    def _create_rotating_file_handler(cls, config: Dict) -> logging.handlers.RotatingFileHandler:
        """Create rotating file handler"""
        filename = config.get('filename', '/var/log/email-infrastructure.log')
        max_size = cls._parse_size(config.get('max_size', '10MB'))
        backup_count = config.get('backup_count', 5)
        
        # Ensure directory exists
        os.makedirs(os.path.dirname(filename), exist_ok=True)
        
        handler = logging.handlers.RotatingFileHandler(
            filename,
            maxBytes=max_size,
            backupCount=backup_count,
            encoding='utf-8'
        )
        
        formatter = StructuredFormatter(
            config.get('format', '%(asctime)s - %(name)s - %(levelname)s - %(message)s')
        )
        handler.setFormatter(formatter)
        
        level = config.get('level')
        if level:
            handler.setLevel(getattr(logging, level))
        
        return handler
    
    @classmethod
    def _create_json_handler(cls, config: Dict) -> logging.FileHandler:
        """Create JSON log handler"""
        filename = config.get('filename', '/var/log/email-infrastructure.json')
        
        # Ensure directory exists
        os.makedirs(os.path.dirname(filename), exist_ok=True)
        
        handler = logging.FileHandler(filename, encoding='utf-8')
        handler.setFormatter(JSONFormatter())
        
        level = config.get('level')
        if level:
            handler.setLevel(getattr(logging, level))
        
        return handler
    
    @classmethod
    def _create_syslog_handler(cls, config: Dict) -> logging.handlers.SysLogHandler:
        """Create syslog handler"""
        address = config.get('address', ('localhost', 514))
        facility = getattr(
            logging.handlers.SysLogHandler,
            f"LOG_{config.get('facility', 'USER').upper()}"
        )
        
        handler = logging.handlers.SysLogHandler(address=address, facility=facility)
        
        formatter = StructuredFormatter(
            '%(name)s[%(process)d]: %(levelname)s - %(message)s'
        )
        handler.setFormatter(formatter)
        
        level = config.get('level')
        if level:
            handler.setLevel(getattr(logging, level))
        
        return handler
    
    @classmethod
    def _create_metrics_handler(cls, config: Dict) -> 'MetricsHandler':
        """Create metrics collection handler"""
        return MetricsHandler(
            metrics_endpoint=config.get('endpoint'),
            component_name=config.get('component', 'email-infrastructure')
        )
    
    @staticmethod
    def _parse_size(size_str: str) -> int:
        """Parse size string (e.g., '10MB') to bytes"""
        size_str = size_str.upper()
        multipliers = {
            'B': 1,
            'K': 1024, 'KB': 1024,
            'M': 1024**2, 'MB': 1024**2,
            'G': 1024**3, 'GB': 1024**3,
            'T': 1024**4, 'TB': 1024**4
        }
        
        for suffix, multiplier in multipliers.items():
            if size_str.endswith(suffix):
                return int(size_str[:-len(suffix)]) * multiplier
        
        # If no suffix, assume bytes
        return int(size_str)

# Convenience function for getting loggers
def get_logger(name: str = None, component: str = None) -> logging.Logger:
    """
    Get a logger with standardized configuration
    
    Args:
        name: Logger name (defaults to caller's module)
        component: Component category (dns, email, api, monitoring, etc.)
    
    Returns:
        Configured logger instance
    
    Example:
        from src.common.logging import get_logger
        logger = get_logger(__name__, 'dns')
    """
    if name is None:
        # Get caller's module name
        import inspect
        frame = inspect.currentframe().f_back
        name = frame.f_globals.get('__name__', 'unknown')
    
    return LoggerFactory.get_logger(name, component)
```

### Log Formatters (`logging/formatters.py`)
```python
#!/usr/bin/env python3
"""
Log Formatters
Various formatting options for different output types
"""

import json
import logging
from datetime import datetime
from typing import Dict, Any

class JSONFormatter(logging.Formatter):
    """JSON formatter for structured logging"""
    
    def format(self, record: logging.LogRecord) -> str:
        log_entry = {
            'timestamp': datetime.fromtimestamp(record.created).isoformat(),
            'level': record.levelname,
            'logger': record.name,
            'message': record.getMessage(),
            'module': record.module,
            'function': record.funcName,
            'line': record.lineno,
            'process': record.process,
            'thread': record.thread,
        }
        
        # Add component information if available
        if hasattr(record, 'component'):
            log_entry['component'] = record.component
        
        # Add request ID for tracing if available
        if hasattr(record, 'request_id'):
            log_entry['request_id'] = record.request_id
        
        # Add extra fields
        if hasattr(record, 'extra'):
            log_entry['extra'] = record.extra
        
        # Add exception information
        if record.exc_info:
            log_entry['exception'] = {
                'type': record.exc_info[0].__name__ if record.exc_info[0] else None,
                'message': str(record.exc_info[1]) if record.exc_info[1] else None,
                'traceback': self.formatException(record.exc_info)
            }
        
        return json.dumps(log_entry, ensure_ascii=False)

class StructuredFormatter(logging.Formatter):
    """Enhanced structured formatter with additional context"""
    
    def format(self, record: logging.LogRecord) -> str:
        # Add component prefix if available
        prefix = ""
        if hasattr(record, 'component'):
            prefix = f"[{record.component}] "
        
        # Format base message
        message = super().format(record)
        
        # Add request ID if available
        if hasattr(record, 'request_id'):
            message += f" [req_id={record.request_id}]"
        
        # Add performance metrics if available
        if hasattr(record, 'duration'):
            message += f" [duration={record.duration:.3f}s]"
        
        return f"{prefix}{message}"

class ColoredFormatter(logging.Formatter):
    """Colored console formatter for better readability"""
    
    COLORS = {
        logging.DEBUG: '\033[36m',      # Cyan
        logging.INFO: '\033[32m',       # Green
        logging.WARNING: '\033[33m',    # Yellow
        logging.ERROR: '\033[31m',      # Red
        logging.CRITICAL: '\033[35m',   # Magenta
    }
    RESET = '\033[0m'
    
    def format(self, record: logging.LogRecord) -> str:
        # Add color to level name
        color = self.COLORS.get(record.levelno, '')
        record.levelname = f"{color}{record.levelname}{self.RESET}"
        
        # Add component coloring if available
        if hasattr(record, 'component'):
            record.component = f"\033[34m[{record.component}]\033[0m"
        
        return super().format(record)
```

## Unified Exception System

### Base Exception Hierarchy (`exceptions/base.py`)
```python
#!/usr/bin/env python3
"""
Base Exception Hierarchy
Standardized exception classes for the entire infrastructure
"""

import traceback
from typing import Dict, Any, Optional, List
from datetime import datetime
from enum import Enum

class ErrorSeverity(Enum):
    """Error severity levels"""
    LOW = "low"
    MEDIUM = "medium"
    HIGH = "high"
    CRITICAL = "critical"

class ErrorCategory(Enum):
    """Error categories for better organization"""
    CONFIGURATION = "configuration"
    NETWORK = "network"
    API = "api"
    DATABASE = "database"
    VALIDATION = "validation"
    AUTHENTICATION = "authentication"
    PERMISSION = "permission"
    RESOURCE = "resource"
    BUSINESS_LOGIC = "business_logic"

class BaseInfrastructureError(Exception):
    """
    Base exception class for all infrastructure errors
    Provides structured error information and context
    """
    
    def __init__(self, 
                 message: str,
                 error_code: str = None,
                 category: ErrorCategory = None,
                 severity: ErrorSeverity = ErrorSeverity.MEDIUM,
                 context: Dict[str, Any] = None,
                 cause: Exception = None,
                 suggestions: List[str] = None,
                 component: str = None):
        super().__init__(message)
        
        self.message = message
        self.error_code = error_code or self.__class__.__name__
        self.category = category or ErrorCategory.BUSINESS_LOGIC
        self.severity = severity
        self.context = context or {}
        self.cause = cause
        self.suggestions = suggestions or []
        self.component = component
        self.timestamp = datetime.utcnow()
        
        # Capture stack trace
        self.stack_trace = traceback.format_exc()
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert exception to dictionary for logging/serialization"""
        return {
            'error_code': self.error_code,
            'message': self.message,
            'category': self.category.value,
            'severity': self.severity.value,
            'component': self.component,
            'context': self.context,
            'suggestions': self.suggestions,
            'timestamp': self.timestamp.isoformat(),
            'cause': str(self.cause) if self.cause else None,
            'stack_trace': self.stack_trace
        }
    
    def add_context(self, key: str, value: Any):
        """Add context information to the error"""
        self.context[key] = value
        return self
    
    def add_suggestion(self, suggestion: str):
        """Add a suggestion for resolving the error"""
        self.suggestions.append(suggestion)
        return self
    
    def __str__(self) -> str:
        return f"[{self.error_code}] {self.message}"

class ConfigurationError(BaseInfrastructureError):
    """Configuration-related errors"""
    
    def __init__(self, message: str, **kwargs):
        super().__init__(
            message, 
            category=ErrorCategory.CONFIGURATION,
            **kwargs
        )

class NetworkError(BaseInfrastructureError):
    """Network-related errors"""
    
    def __init__(self, message: str, **kwargs):
        super().__init__(
            message,
            category=ErrorCategory.NETWORK,
            **kwargs
        )

class ValidationError(BaseInfrastructureError):
    """Data validation errors"""
    
    def __init__(self, message: str, field: str = None, value: Any = None, **kwargs):
        context = kwargs.pop('context', {})
        if field:
            context['field'] = field
        if value is not None:
            context['value'] = str(value)
        
        super().__init__(
            message,
            category=ErrorCategory.VALIDATION,
            context=context,
            **kwargs
        )

class AuthenticationError(BaseInfrastructureError):
    """Authentication-related errors"""
    
    def __init__(self, message: str = "Authentication failed", **kwargs):
        super().__init__(
            message,
            category=ErrorCategory.AUTHENTICATION,
            severity=ErrorSeverity.HIGH,
            **kwargs
        )

class PermissionError(BaseInfrastructureError):
    """Permission/authorization errors"""
    
    def __init__(self, message: str = "Permission denied", resource: str = None, **kwargs):
        context = kwargs.pop('context', {})
        if resource:
            context['resource'] = resource
            
        super().__init__(
            message,
            category=ErrorCategory.PERMISSION,
            context=context,
            **kwargs
        )

class ResourceError(BaseInfrastructureError):
    """Resource-related errors (not found, unavailable, etc.)"""
    
    def __init__(self, message: str, resource_type: str = None, resource_id: str = None, **kwargs):
        context = kwargs.pop('context', {})
        if resource_type:
            context['resource_type'] = resource_type
        if resource_id:
            context['resource_id'] = resource_id
            
        super().__init__(
            message,
            category=ErrorCategory.RESOURCE,
            context=context,
            **kwargs
        )
```

### API-Specific Exceptions (`exceptions/api.py`)
```python
#!/usr/bin/env python3
"""
API-Specific Exceptions
Standardized exceptions for API operations
"""

from .base import BaseInfrastructureError, ErrorCategory, ErrorSeverity

class APIError(BaseInfrastructureError):
    """Base API error"""
    
    def __init__(self, message: str, status_code: int = None, response_data: dict = None, **kwargs):
        context = kwargs.pop('context', {})
        if status_code:
            context['status_code'] = status_code
        if response_data:
            context['response_data'] = response_data
            
        super().__init__(
            message,
            category=ErrorCategory.API,
            context=context,
            **kwargs
        )

class RateLimitError(APIError):
    """Rate limit exceeded error"""
    
    def __init__(self, message: str = "Rate limit exceeded", retry_after: int = None, **kwargs):
        context = kwargs.pop('context', {})
        if retry_after:
            context['retry_after'] = retry_after
            
        super().__init__(
            message,
            error_code="RATE_LIMIT_EXCEEDED",
            context=context,
            suggestions=["Wait before retrying", "Implement backoff strategy"],
            **kwargs
        )

class CloudflareError(APIError):
    """Cloudflare API specific error"""
    
    def __init__(self, message: str, cloudflare_error_code: int = None, **kwargs):
        context = kwargs.pop('context', {})
        if cloudflare_error_code:
            context['cloudflare_error_code'] = cloudflare_error_code
            
        super().__init__(
            message,
            component="cloudflare",
            context=context,
            **kwargs
        )

class MailcowError(APIError):
    """Mailcow API specific error"""
    
    def __init__(self, message: str, **kwargs):
        super().__init__(
            message,
            component="mailcow",
            **kwargs
        )
```

### Exception Handler (`exceptions/handlers.py`)
```python
#!/usr/bin/env python3
"""
Exception Handlers
Centralized exception handling and processing
"""

import logging
from typing import Callable, Any, Optional, Dict
from functools import wraps

from .base import BaseInfrastructureError, ErrorSeverity
from ..logging import get_logger

class ExceptionHandler:
    """Centralized exception handling"""
    
    def __init__(self, component: str = None):
        self.component = component
        self.logger = get_logger(__name__, component)
        self.error_callbacks: Dict[type, Callable] = {}
    
    def handle_exception(self, 
                        exception: Exception, 
                        context: Dict[str, Any] = None,
                        reraise: bool = True):
        """
        Handle exception with logging and optional callbacks
        
        Args:
            exception: The exception to handle
            context: Additional context information
            reraise: Whether to reraise the exception after handling
        """
        # Add component context if available
        if isinstance(exception, BaseInfrastructureError):
            if not exception.component and self.component:
                exception.component = self.component
            
            if context:
                for key, value in context.items():
                    exception.add_context(key, value)
        
        # Log the exception
        self._log_exception(exception)
        
        # Call registered callbacks
        exception_type = type(exception)
        if exception_type in self.error_callbacks:
            try:
                self.error_callbacks[exception_type](exception)
            except Exception as callback_error:
                self.logger.error(f"Error in exception callback: {callback_error}")
        
        # Reraise if requested
        if reraise:
            raise exception
    
    def register_callback(self, exception_type: type, callback: Callable):
        """Register a callback for specific exception types"""
        self.error_callbacks[exception_type] = callback
    
    def _log_exception(self, exception: Exception):
        """Log exception with appropriate level and details"""
        if isinstance(exception, BaseInfrastructureError):
            # Use severity to determine log level
            if exception.severity == ErrorSeverity.CRITICAL:
                log_level = logging.CRITICAL
            elif exception.severity == ErrorSeverity.HIGH:
                log_level = logging.ERROR
            elif exception.severity == ErrorSeverity.MEDIUM:
                log_level = logging.WARNING
            else:
                log_level = logging.INFO
            
            # Create structured log entry
            self.logger.log(
                log_level,
                f"Infrastructure Error: {exception.message}",
                extra={
                    'error_details': exception.to_dict(),
                    'component': exception.component
                }
            )
        else:
            # Standard exception logging
            self.logger.error(f"Unhandled exception: {str(exception)}", exc_info=True)

# Global exception handler instance
_global_handler = ExceptionHandler()

def handle_exceptions(component: str = None, reraise: bool = True):
    """
    Decorator for automatic exception handling
    
    Args:
        component: Component name for context
        reraise: Whether to reraise exceptions after handling
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        def wrapper(*args, **kwargs):
            try:
                return func(*args, **kwargs)
            except Exception as e:
                context = {
                    'function': func.__name__,
                    'module': func.__module__,
                    'args_count': len(args),
                    'kwargs_keys': list(kwargs.keys())
                }
                
                handler = ExceptionHandler(component)
                handler.handle_exception(e, context, reraise)
                
                if not reraise:
                    return None
        
        return wrapper
    return decorator

def handle_async_exceptions(component: str = None, reraise: bool = True):
    """
    Decorator for automatic exception handling in async functions
    """
    def decorator(func: Callable) -> Callable:
        @wraps(func)
        async def wrapper(*args, **kwargs):
            try:
                return await func(*args, **kwargs)
            except Exception as e:
                context = {
                    'function': func.__name__,
                    'module': func.__module__,
                    'args_count': len(args),
                    'kwargs_keys': list(kwargs.keys())
                }
                
                handler = ExceptionHandler(component)
                handler.handle_exception(e, context, reraise)
                
                if not reraise:
                    return None
        
        return wrapper
    return decorator
```

## Usage Examples

### Standardized Logging
```python
from src.common.logging import get_logger

# Get component-specific logger
logger = get_logger(__name__, 'dns')

# Standard logging
logger.info("DNS record created successfully")
logger.warning("Rate limit approaching", extra={'rate_usage': 0.8})
logger.error("API request failed", extra={
    'endpoint': '/zones',
    'status_code': 500,
    'duration': 2.5
})

# Structured logging with context
logger.info("Processing domain", extra={
    'domain': 'YOUR_DOMAIN.com',
    'record_count': 15,
    'request_id': 'req_123'
})
```

### Standardized Exception Handling
```python
from src.common.exceptions import CloudflareError, ValidationError
from src.common.exceptions.handlers import handle_exceptions

@handle_exceptions(component='dns')
async def create_dns_record(domain: str, record_data: dict):
    # Validation
    if not domain:
        raise ValidationError("Domain is required", field='domain')
    
    # API call
    try:
        response = await cloudflare_client.post('/dns_records', data=record_data)
    except Exception as e:
        raise CloudflareError(
            "Failed to create DNS record",
            context={'domain': domain, 'record_type': record_data.get('type')}
        ).add_suggestion("Check DNS record format").add_suggestion("Verify API permissions")

# Usage with automatic exception handling
try:
    await create_dns_record("YOUR_DOMAIN.com", {"type": "A", "name": "mail", "content": "192.168.1.100"})
except BaseInfrastructureError as e:
    # All context and suggestions are automatically logged
    print(f"Error: {e.message}")
    print(f"Suggestions: {', '.join(e.suggestions)}")
```

### Migration Benefits

### Before Standardization:
- **20+ duplicate logging configurations**
- **Inconsistent log formats** across components
- **Multiple custom exception classes** with no hierarchy
- **No error context** or suggestions
- **Scattered error handling** patterns
- **No centralized error tracking**

### After Standardization:
- **Single logging factory** with component categorization
- **Consistent structured logging** with JSON/colored/plain formats
- **Hierarchical exception system** with context and suggestions
- **Centralized error handling** with automatic logging
- **Performance metrics** integration in logging
- **Sensitive data filtering** built-in
- **Request tracing** capabilities

### Development Benefits:
- **Reduced configuration overhead** by ~90%
- **Consistent debugging experience** across all components
- **Better error diagnostics** with context and suggestions
- **Automatic performance tracking**
- **Centralized log aggregation** ready
- **Type-safe exception handling**

This framework eliminates the logging and error handling duplication found across the codebase while providing a robust, standardized foundation for all components in the cold email infrastructure.