# Cold Email Infrastructure Dashboard

A comprehensive web dashboard for testing and monitoring your cold email infrastructure setup.

## Features

### Testing Interface (`/test`)
- **Email Sending Test**: Send test emails with custom recipients, subjects, and content
- **SMTP Connection Test**: Verify SMTP server connectivity and authentication
- **DNS Record Validation**: Check SPF, DKIM, DMARC, and MX records
- **Blacklist Status Checker**: Monitor IP and domain blacklist status
- **Email Warmup Campaign**: Start and manage email warmup processes

### Monitoring Dashboard (`/monitor`)
- **Real-time System Metrics**: CPU, memory, disk, and network monitoring
- **Email Delivery Statistics**: Track success rates and delivery metrics
- **Queue Management**: Monitor and control email queues
- **Error Logs**: View and filter system logs
- **Performance Graphs**: Visual representation of system performance
- **Alert Configuration**: Set up custom alerts and thresholds

### Configuration Management (`/config`)
- **Environment Variables**: Manage system configuration
- **API Keys**: Configure third-party service credentials
- **SMTP Settings**: Set up mail server connections

## Installation

1. Install Python dependencies:
```bash
pip install -r requirements.txt
```

2. Set up environment variables (create `.env` file):
```env
DOMAIN=yourdomain.com
SERVER_IP=your.server.ip
ADMIN_EMAIL=admin@yourdomain.com
CLOUDFLARE_API_TOKEN=your_cloudflare_token
MAILCOW_API_KEY=your_mailcow_key
SMTP_HOST=mail.yourdomain.com
SMTP_PORT=587
SMTP_USER=your_smtp_user
SMTP_PASSWORD=your_smtp_password
FLASK_SECRET_KEY=your_secret_key
```

3. Run the dashboard:
```bash
python app.py
```

The dashboard will be available at `http://localhost:5000`

## API Endpoints

### Testing APIs
- `POST /api/test-email` - Send test email
- `POST /api/test-smtp` - Test SMTP connection
- `POST /api/test-dns` - Validate DNS records
- `POST /api/test-blacklist` - Check blacklist status
- `POST /api/start-warmup` - Start warmup campaign
- `GET /api/warmup-status` - Get warmup status

### Monitoring APIs
- `GET /api/metrics/system` - System resource metrics
- `GET /api/metrics/delivery` - Email delivery statistics
- `GET /api/metrics/queue` - Queue status and metrics
- `GET /api/logs` - System logs
- `GET /api/alerts` - System alerts

### Queue Management
- `POST /api/queue/pause` - Pause email queue
- `POST /api/queue/resume` - Resume email queue

## Features Overview

### Visual Testing Interface
- Bootstrap 5 responsive design
- Real-time status updates using AJAX
- Loading spinners and progress indicators
- Modal dialogs for detailed results
- Copy-to-clipboard functionality
- Color-coded status indicators

### Real-time Monitoring
- Live system metrics with charts
- Email delivery tracking
- Queue monitoring with pause/resume controls
- Error log viewing with filtering
- Performance graphs and statistics
- Configurable alerts

### User-Friendly Design
- Professional dashboard appearance
- Intuitive navigation
- Mobile-responsive layout
- Dark mode support
- Toast notifications
- Form validation

## Technology Stack

- **Backend**: Flask (Python)
- **Frontend**: Bootstrap 5, JavaScript, Chart.js
- **Monitoring**: psutil for system metrics
- **Email**: smtplib for SMTP testing
- **DNS**: dnspython for DNS validation
- **Styling**: Custom CSS with gradients and animations

## Security Notes

- Change the default `FLASK_SECRET_KEY` in production
- Use HTTPS in production environments
- Secure API endpoints with proper authentication
- Keep sensitive configuration in environment variables
- Regular security updates for dependencies

## Development

The dashboard is designed for easy extension:

- Add new test functions in `app.py`
- Create new templates in `templates/`
- Add custom styles in `static/css/`
- Extend JavaScript functionality in `static/js/`

## Support

For issues or questions, refer to the main project documentation or create an issue in the project repository.