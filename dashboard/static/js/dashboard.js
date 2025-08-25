/**
 * Cold Email Infrastructure Dashboard JavaScript
 * Enhanced functionality for the dashboard interface
 */

class Dashboard {
    constructor() {
        this.isOnline = true;
        this.refreshIntervals = {};
        this.charts = {};
        this.notifications = [];
        this.init();
    }

    init() {
        this.setupEventListeners();
        this.initializeToasts();
        this.checkConnectionStatus();
        this.loadUserPreferences();
    }

    setupEventListeners() {
        // Global error handler
        window.addEventListener('error', (e) => {
            this.showToast('error', 'JavaScript Error', e.message);
        });

        // Connection status
        window.addEventListener('online', () => {
            this.isOnline = true;
            this.showToast('success', 'Connection Restored', 'Internet connection is back');
        });

        window.addEventListener('offline', () => {
            this.isOnline = false;
            this.showToast('warning', 'Connection Lost', 'No internet connection');
        });

        // Copy to clipboard functionality
        document.addEventListener('click', (e) => {
            if (e.target.classList.contains('copy-btn') || e.target.closest('.copy-btn')) {
                this.handleCopyClick(e);
            }
        });

        // Form validation
        document.addEventListener('submit', (e) => {
            if (e.target.classList.contains('needs-validation')) {
                this.handleFormValidation(e);
            }
        });
    }

    // Toast Notification System
    initializeToasts() {
        if (!document.querySelector('.toast-container')) {
            const container = document.createElement('div');
            container.className = 'toast-container';
            document.body.appendChild(container);
        }
    }

    showToast(type, title, message, duration = 5000) {
        const toastContainer = document.querySelector('.toast-container');
        const toastId = 'toast-' + Date.now();
        
        const iconMap = {
            success: 'fas fa-check-circle',
            error: 'fas fa-exclamation-circle',
            warning: 'fas fa-exclamation-triangle',
            info: 'fas fa-info-circle'
        };

        const colorMap = {
            success: 'text-success',
            error: 'text-danger',
            warning: 'text-warning',
            info: 'text-info'
        };

        const toastHTML = `
            <div class="toast toast-enhanced" id="${toastId}" role="alert" data-bs-autohide="true" data-bs-delay="${duration}">
                <div class="toast-header">
                    <i class="${iconMap[type]} ${colorMap[type]} me-2"></i>
                    <strong class="me-auto">${title}</strong>
                    <small class="text-light">${new Date().toLocaleTimeString()}</small>
                    <button type="button" class="btn-close btn-close-white" data-bs-dismiss="toast"></button>
                </div>
                <div class="toast-body">
                    ${message}
                </div>
            </div>
        `;

        toastContainer.insertAdjacentHTML('beforeend', toastHTML);
        
        const toastElement = document.getElementById(toastId);
        const toast = new bootstrap.Toast(toastElement);
        toast.show();

        // Clean up after toast is hidden
        toastElement.addEventListener('hidden.bs.toast', () => {
            toastElement.remove();
        });

        this.notifications.push({
            type, title, message, timestamp: new Date()
        });
    }

    // Connection Status Checker
    async checkConnectionStatus() {
        try {
            const response = await fetch('/api/status');
            if (response.ok) {
                this.updateConnectionIndicator(true);
            } else {
                this.updateConnectionIndicator(false);
            }
        } catch (error) {
            this.updateConnectionIndicator(false);
        }

        // Check every 30 seconds
        setTimeout(() => this.checkConnectionStatus(), 30000);
    }

    updateConnectionIndicator(isConnected) {
        const indicators = document.querySelectorAll('.connection-indicator');
        indicators.forEach(indicator => {
            if (isConnected) {
                indicator.className = 'connection-indicator text-success';
                indicator.innerHTML = '<i class="fas fa-circle"></i> Connected';
            } else {
                indicator.className = 'connection-indicator text-danger';
                indicator.innerHTML = '<i class="fas fa-circle"></i> Disconnected';
            }
        });
    }

    // Copy to Clipboard
    async handleCopyClick(e) {
        e.preventDefault();
        const button = e.target.closest('.copy-btn');
        const targetSelector = button.dataset.target;
        let textToCopy;

        if (targetSelector) {
            const targetElement = document.querySelector(targetSelector);
            textToCopy = targetElement ? targetElement.textContent : button.dataset.text;
        } else {
            textToCopy = button.dataset.text || button.previousElementSibling?.textContent;
        }

        if (!textToCopy) return;

        try {
            await navigator.clipboard.writeText(textToCopy);
            
            // Visual feedback
            const originalHTML = button.innerHTML;
            button.innerHTML = '<i class="fas fa-check"></i> Copied!';
            button.classList.add('btn-success');
            
            setTimeout(() => {
                button.innerHTML = originalHTML;
                button.classList.remove('btn-success');
            }, 2000);
            
            this.showToast('success', 'Copied!', 'Text copied to clipboard');
        } catch (error) {
            this.showToast('error', 'Copy Failed', 'Could not copy to clipboard');
        }
    }

    // Form Validation
    handleFormValidation(e) {
        const form = e.target;
        
        if (!form.checkValidity()) {
            e.preventDefault();
            e.stopPropagation();
            
            // Find first invalid field and focus it
            const firstInvalid = form.querySelector(':invalid');
            if (firstInvalid) {
                firstInvalid.focus();
                this.showToast('warning', 'Form Validation', 'Please fill in all required fields correctly');
            }
        }
        
        form.classList.add('was-validated');
    }

    // Loading States
    showLoading(elementId, message = 'Loading...') {
        const element = document.getElementById(elementId);
        if (!element) return;

        const overlay = document.createElement('div');
        overlay.className = 'loading-overlay';
        overlay.innerHTML = `
            <div class="text-center">
                <div class="spinner-enhanced"></div>
                <div class="mt-2">${message}</div>
            </div>
        `;
        
        element.style.position = 'relative';
        element.appendChild(overlay);
    }

    hideLoading(elementId) {
        const element = document.getElementById(elementId);
        if (!element) return;

        const overlay = element.querySelector('.loading-overlay');
        if (overlay) {
            overlay.remove();
        }
    }

    // API Helper
    async apiCall(url, options = {}) {
        const defaultOptions = {
            headers: {
                'Content-Type': 'application/json',
            }
        };

        const mergedOptions = { ...defaultOptions, ...options };
        
        try {
            const response = await fetch(url, mergedOptions);
            
            if (!response.ok) {
                throw new Error(`HTTP error! status: ${response.status}`);
            }
            
            return await response.json();
        } catch (error) {
            console.error('API call failed:', error);
            this.showToast('error', 'API Error', error.message);
            throw error;
        }
    }

    // Local Storage Helpers
    saveUserPreference(key, value) {
        try {
            localStorage.setItem(`dashboard_${key}`, JSON.stringify(value));
        } catch (error) {
            console.warn('Could not save user preference:', error);
        }
    }

    getUserPreference(key, defaultValue = null) {
        try {
            const stored = localStorage.getItem(`dashboard_${key}`);
            return stored ? JSON.parse(stored) : defaultValue;
        } catch (error) {
            console.warn('Could not load user preference:', error);
            return defaultValue;
        }
    }

    loadUserPreferences() {
        // Load saved preferences
        const darkMode = this.getUserPreference('darkMode', false);
        if (darkMode) {
            document.body.classList.add('dark-mode');
        }

        // Auto-refresh settings
        const autoRefresh = this.getUserPreference('autoRefresh', true);
        if (autoRefresh) {
            this.enableAutoRefresh();
        }
    }

    // Auto-refresh functionality
    enableAutoRefresh(interval = 30000) {
        this.refreshIntervals.main = setInterval(() => {
            if (this.isOnline && document.visibilityState === 'visible') {
                this.refreshDashboard();
            }
        }, interval);
    }

    disableAutoRefresh() {
        Object.values(this.refreshIntervals).forEach(interval => {
            clearInterval(interval);
        });
        this.refreshIntervals = {};
    }

    async refreshDashboard() {
        try {
            // Dispatch custom event for other components to listen to
            document.dispatchEvent(new CustomEvent('dashboard:refresh'));
        } catch (error) {
            console.error('Dashboard refresh failed:', error);
        }
    }

    // Chart Helpers
    createChart(canvasId, config) {
        const ctx = document.getElementById(canvasId);
        if (!ctx) return null;

        // Destroy existing chart if it exists
        if (this.charts[canvasId]) {
            this.charts[canvasId].destroy();
        }

        // Create new chart
        this.charts[canvasId] = new Chart(ctx.getContext('2d'), config);
        return this.charts[canvasId];
    }

    updateChart(canvasId, data) {
        const chart = this.charts[canvasId];
        if (!chart) return;

        // Update chart data
        if (data.labels) {
            chart.data.labels = data.labels;
        }
        
        if (data.datasets) {
            chart.data.datasets = data.datasets;
        }

        chart.update();
    }

    // Utility Functions
    formatBytes(bytes, decimals = 2) {
        if (bytes === 0) return '0 Bytes';
        
        const k = 1024;
        const dm = decimals < 0 ? 0 : decimals;
        const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
        
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        
        return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
    }

    formatDuration(seconds) {
        const days = Math.floor(seconds / 86400);
        const hours = Math.floor((seconds % 86400) / 3600);
        const minutes = Math.floor((seconds % 3600) / 60);
        
        if (days > 0) {
            return `${days}d ${hours}h ${minutes}m`;
        } else if (hours > 0) {
            return `${hours}h ${minutes}m`;
        } else {
            return `${minutes}m`;
        }
    }

    formatNumber(num) {
        if (num >= 1000000) {
            return (num / 1000000).toFixed(1) + 'M';
        } else if (num >= 1000) {
            return (num / 1000).toFixed(1) + 'K';
        } else {
            return num.toString();
        }
    }

    // Animation Helpers
    animateValue(element, start, end, duration = 1000, suffix = '') {
        const startTime = performance.now();
        
        const animate = (currentTime) => {
            const elapsed = currentTime - startTime;
            const progress = Math.min(elapsed / duration, 1);
            
            const easeOut = 1 - Math.pow(1 - progress, 3);
            const current = start + (end - start) * easeOut;
            
            element.textContent = Math.floor(current) + suffix;
            
            if (progress < 1) {
                requestAnimationFrame(animate);
            }
        };
        
        requestAnimationFrame(animate);
    }

    // Cleanup
    destroy() {
        // Clear all intervals
        this.disableAutoRefresh();
        
        // Destroy all charts
        Object.values(this.charts).forEach(chart => {
            if (chart && typeof chart.destroy === 'function') {
                chart.destroy();
            }
        });
        
        // Clear notifications
        this.notifications = [];
    }
}

// Status Badge Helper
class StatusBadge {
    static create(status, text = '') {
        const badge = document.createElement('span');
        badge.className = `badge badge-${status} status-badge`;
        
        const icon = this.getIcon(status);
        badge.innerHTML = `<i class="${icon}"></i> ${text || status.toUpperCase()}`;
        
        return badge;
    }

    static getIcon(status) {
        const icons = {
            success: 'fas fa-check-circle',
            warning: 'fas fa-exclamation-triangle',
            error: 'fas fa-times-circle',
            info: 'fas fa-info-circle',
            pending: 'fas fa-clock'
        };
        
        return icons[status] || 'fas fa-circle';
    }
}

// Real-time Data Updater
class RealTimeUpdater {
    constructor(endpoint, updateCallback, interval = 5000) {
        this.endpoint = endpoint;
        this.updateCallback = updateCallback;
        this.interval = interval;
        this.isRunning = false;
        this.timeoutId = null;
    }

    start() {
        if (this.isRunning) return;
        
        this.isRunning = true;
        this.update();
    }

    stop() {
        this.isRunning = false;
        if (this.timeoutId) {
            clearTimeout(this.timeoutId);
        }
    }

    async update() {
        if (!this.isRunning) return;

        try {
            const response = await fetch(this.endpoint);
            if (response.ok) {
                const data = await response.json();
                this.updateCallback(data);
            }
        } catch (error) {
            console.warn('Real-time update failed:', error);
        }

        if (this.isRunning) {
            this.timeoutId = setTimeout(() => this.update(), this.interval);
        }
    }
}

// Initialize dashboard when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    window.dashboard = new Dashboard();
    
    // Add connection indicator to navbar
    const navbar = document.querySelector('.navbar');
    if (navbar) {
        const indicator = document.createElement('div');
        indicator.className = 'connection-indicator text-success ms-3';
        indicator.innerHTML = '<i class="fas fa-circle"></i> Connected';
        navbar.querySelector('.navbar-nav').appendChild(indicator);
    }
});

// Export for use in other modules
window.Dashboard = Dashboard;
window.StatusBadge = StatusBadge;
window.RealTimeUpdater = RealTimeUpdater;