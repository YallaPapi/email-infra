#!/bin/bash
# Cold Email Infrastructure Dashboard Startup Script

echo "🚀 Starting Cold Email Infrastructure Dashboard..."

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: Python 3 is required but not installed."
    exit 1
fi

# Check if pip is installed
if ! command -v pip &> /dev/null && ! command -v pip3 &> /dev/null; then
    echo "❌ Error: pip is required but not installed."
    exit 1
fi

# Use pip3 if available, otherwise pip
PIP_CMD="pip"
if command -v pip3 &> /dev/null; then
    PIP_CMD="pip3"
fi

# Check if requirements are installed
echo "📦 Checking dependencies..."
if [ -f "requirements.txt" ]; then
    echo "Installing/updating requirements..."
    $PIP_CMD install -r requirements.txt --quiet
    if [ $? -ne 0 ]; then
        echo "❌ Failed to install requirements"
        exit 1
    fi
else
    echo "⚠️  Warning: requirements.txt not found"
fi

# Create logs directory if it doesn't exist
mkdir -p logs

# Set default environment variables if not set
export FLASK_ENV=${FLASK_ENV:-development}
export FLASK_DEBUG=${FLASK_DEBUG:-1}
export FLASK_PORT=${FLASK_PORT:-5000}

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo "⚠️  Warning: .env file not found. Creating a sample .env file..."
    cat > .env << EOF
# Cold Email Infrastructure Dashboard Configuration
DOMAIN=yourdomain.com
SERVER_IP=your.server.ip
ADMIN_EMAIL=admin@yourdomain.com
DMARC_EMAIL=dmarc@yourdomain.com
CLOUDFLARE_API_TOKEN=your_cloudflare_token_here
MAILCOW_API_KEY=your_mailcow_api_key_here
MAILCOW_HOSTNAME=mail.yourdomain.com
SMTP_HOST=mail.yourdomain.com
SMTP_PORT=587
SMTP_USER=your_smtp_user
SMTP_PASSWORD=your_smtp_password
FLASK_SECRET_KEY=change-this-in-production
FLASK_PORT=5000
DKIM_SELECTOR=default
EOF
    echo "📝 Sample .env file created. Please edit it with your actual configuration."
fi

# Load environment variables from .env if it exists
if [ -f ".env" ]; then
    echo "📄 Loading environment variables from .env file..."
    set -a  # automatically export all variables
    source .env
    set +a  # stop automatically export
fi

# Display startup information
echo "🌐 Dashboard will be available at:"
echo "   Local:    http://localhost:${FLASK_PORT}"
echo "   Network:  http://$(hostname -I | awk '{print $1}'):${FLASK_PORT}"
echo ""
echo "📊 Available endpoints:"
echo "   Dashboard:     http://localhost:${FLASK_PORT}/"
echo "   Configuration: http://localhost:${FLASK_PORT}/config"
echo "   Testing:       http://localhost:${FLASK_PORT}/test"
echo "   Monitoring:    http://localhost:${FLASK_PORT}/monitor"
echo ""

# Check if the port is already in use
if lsof -Pi :${FLASK_PORT} -sTCP:LISTEN -t >/dev/null ; then
    echo "⚠️  Warning: Port ${FLASK_PORT} is already in use."
    echo "   Try using a different port with: FLASK_PORT=5001 ./start_dashboard.sh"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create static directories if they don't exist
mkdir -p static/css static/js

echo "✅ Starting dashboard server..."
echo "Press Ctrl+C to stop the server"
echo ""

# Start the Flask application
python3 app.py