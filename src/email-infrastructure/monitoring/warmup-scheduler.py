#!/usr/bin/env python3
"""
IP Warmup Scheduler - Gradual IP warmup automation with progressive volume scaling
Manages the progressive scaling of email volume from 10 to 500+ emails per day
"""

import sys
import os
import json
import logging
import asyncio
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from typing import Dict, List, Optional, Tuple
from enum import Enum
import sqlite3
import smtplib
from email.mime.text import MimeText
from email.mime.multipart import MimeMultipart
import random
import time

# Add parent directory to path for imports
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

class WarmupPhase(Enum):
    INITIALIZATION = "initialization"
    GRADUAL_RAMP = "gradual_ramp"
    SUSTAINED_VOLUME = "sustained_volume"
    REPUTATION_BUILDING = "reputation_building"
    MAINTENANCE = "maintenance"

@dataclass
class WarmupSchedule:
    day: int
    target_volume: int
    phase: WarmupPhase
    success_rate_target: float
    reputation_score_target: float
    mailbox_distribution: Dict[str, int]
    time_distribution: Dict[str, int]  # Hour -> count
    content_variation_required: int

@dataclass
class IPWarmupConfig:
    ip_address: str
    domain: str
    smtp_host: str
    smtp_port: int
    username: str
    password: str
    start_date: datetime
    target_daily_volume: int
    warmup_duration_days: int
    success_rate_threshold: float
    blacklist_check_frequency: int
    reputation_check_frequency: int

class WarmupScheduler:
    def __init__(self, config_path: str = None):
        self.config_path = config_path or os.path.join(os.path.dirname(__file__), 'config/warmup_config.json')
        self.db_path = os.path.join(os.path.dirname(__file__), 'logs/warmup_scheduler.db')
        
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(os.path.join(os.path.dirname(__file__), 'logs/warmup_scheduler.log')),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
        # Initialize database
        self._init_database()
        
        # Load configuration
        self.config = self._load_config()
        
        # Generate warmup schedule
        self.schedule = self._generate_warmup_schedule()
        
        self.logger.info(f"Warmup Scheduler initialized for IP: {self.config.ip_address}")

    def _init_database(self):
        """Initialize SQLite database for tracking warmup progress"""
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Create tables
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS warmup_sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ip_address TEXT NOT NULL,
                start_date DATE NOT NULL,
                current_day INTEGER DEFAULT 1,
                current_phase TEXT DEFAULT 'initialization',
                total_sent INTEGER DEFAULT 0,
                total_delivered INTEGER DEFAULT 0,
                total_bounced INTEGER DEFAULT 0,
                success_rate REAL DEFAULT 0.0,
                reputation_score REAL DEFAULT 0.0,
                status TEXT DEFAULT 'active',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS daily_stats (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER,
                day INTEGER,
                date DATE,
                target_volume INTEGER,
                actual_sent INTEGER DEFAULT 0,
                delivered INTEGER DEFAULT 0,
                bounced INTEGER DEFAULT 0,
                success_rate REAL DEFAULT 0.0,
                reputation_score REAL DEFAULT 0.0,
                phase TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (session_id) REFERENCES warmup_sessions (id)
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS email_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                session_id INTEGER,
                day INTEGER,
                recipient_type TEXT,
                recipient_address TEXT,
                subject TEXT,
                sent_at TIMESTAMP,
                delivery_status TEXT,
                bounce_reason TEXT,
                response_time REAL,
                FOREIGN KEY (session_id) REFERENCES warmup_sessions (id)
            )
        ''')
        
        conn.commit()
        conn.close()

    def _load_config(self) -> IPWarmupConfig:
        """Load warmup configuration from file"""
        if not os.path.exists(self.config_path):
            # Create default config
            default_config = {
                "ip_address": "192.168.1.100",
                "domain": "example.com",
                "smtp_host": "localhost",
                "smtp_port": 587,
                "username": "warmup@example.com",
                "password": "password",
                "start_date": datetime.now().isoformat(),
                "target_daily_volume": 500,
                "warmup_duration_days": 45,
                "success_rate_threshold": 95.0,
                "blacklist_check_frequency": 6,
                "reputation_check_frequency": 12
            }
            
            os.makedirs(os.path.dirname(self.config_path), exist_ok=True)
            with open(self.config_path, 'w') as f:
                json.dump(default_config, f, indent=2, default=str)
            
            self.logger.info(f"Created default config at: {self.config_path}")
        
        with open(self.config_path, 'r') as f:
            config_data = json.load(f)
        
        return IPWarmupConfig(
            ip_address=config_data['ip_address'],
            domain=config_data['domain'],
            smtp_host=config_data['smtp_host'],
            smtp_port=config_data['smtp_port'],
            username=config_data['username'],
            password=config_data['password'],
            start_date=datetime.fromisoformat(config_data['start_date']),
            target_daily_volume=config_data['target_daily_volume'],
            warmup_duration_days=config_data['warmup_duration_days'],
            success_rate_threshold=config_data['success_rate_threshold'],
            blacklist_check_frequency=config_data['blacklist_check_frequency'],
            reputation_check_frequency=config_data['reputation_check_frequency']
        )

    def _generate_warmup_schedule(self) -> List[WarmupSchedule]:
        """Generate complete warmup schedule with progressive volume scaling"""
        schedule = []
        
        # Phase 1: Initialization (Days 1-7) - 10-50 emails/day
        for day in range(1, 8):
            target_volume = min(10 + (day - 1) * 5, 50)
            schedule.append(WarmupSchedule(
                day=day,
                target_volume=target_volume,
                phase=WarmupPhase.INITIALIZATION,
                success_rate_target=98.0,
                reputation_score_target=7.0,
                mailbox_distribution=self._calculate_mailbox_distribution(target_volume, 'initialization'),
                time_distribution=self._calculate_time_distribution(target_volume, 'business_hours'),
                content_variation_required=min(3, target_volume // 10 + 1)
            ))
        
        # Phase 2: Gradual Ramp (Days 8-21) - 50-200 emails/day
        for day in range(8, 22):
            target_volume = min(50 + (day - 8) * 12, 200)
            schedule.append(WarmupSchedule(
                day=day,
                target_volume=target_volume,
                phase=WarmupPhase.GRADUAL_RAMP,
                success_rate_target=97.0,
                reputation_score_target=7.5,
                mailbox_distribution=self._calculate_mailbox_distribution(target_volume, 'gradual_ramp'),
                time_distribution=self._calculate_time_distribution(target_volume, 'extended_hours'),
                content_variation_required=min(5, target_volume // 20 + 1)
            ))
        
        # Phase 3: Sustained Volume (Days 22-35) - 200-400 emails/day
        for day in range(22, 36):
            target_volume = min(200 + (day - 22) * 15, 400)
            schedule.append(WarmupSchedule(
                day=day,
                target_volume=target_volume,
                phase=WarmupPhase.SUSTAINED_VOLUME,
                success_rate_target=96.0,
                reputation_score_target=8.0,
                mailbox_distribution=self._calculate_mailbox_distribution(target_volume, 'sustained_volume'),
                time_distribution=self._calculate_time_distribution(target_volume, 'full_day'),
                content_variation_required=min(8, target_volume // 30 + 1)
            ))
        
        # Phase 4: Reputation Building (Days 36-45) - 400-500+ emails/day
        for day in range(36, self.config.warmup_duration_days + 1):
            target_volume = min(400 + (day - 36) * 12, self.config.target_daily_volume)
            schedule.append(WarmupSchedule(
                day=day,
                target_volume=target_volume,
                phase=WarmupPhase.REPUTATION_BUILDING,
                success_rate_target=95.0,
                reputation_score_target=8.5,
                mailbox_distribution=self._calculate_mailbox_distribution(target_volume, 'reputation_building'),
                time_distribution=self._calculate_time_distribution(target_volume, 'full_day'),
                content_variation_required=min(10, target_volume // 40 + 1)
            ))
        
        return schedule

    def _calculate_mailbox_distribution(self, volume: int, phase: str) -> Dict[str, int]:
        """Calculate distribution across different mailbox providers"""
        if phase == 'initialization':
            # Conservative approach - focus on major providers
            return {
                'gmail': int(volume * 0.4),
                'outlook': int(volume * 0.3),
                'yahoo': int(volume * 0.2),
                'other': int(volume * 0.1)
            }
        elif phase == 'gradual_ramp':
            return {
                'gmail': int(volume * 0.35),
                'outlook': int(volume * 0.30),
                'yahoo': int(volume * 0.20),
                'apple': int(volume * 0.10),
                'other': int(volume * 0.05)
            }
        else:
            # Full distribution for later phases
            return {
                'gmail': int(volume * 0.35),
                'outlook': int(volume * 0.25),
                'yahoo': int(volume * 0.15),
                'apple': int(volume * 0.10),
                'protonmail': int(volume * 0.05),
                'zoho': int(volume * 0.05),
                'other': int(volume * 0.05)
            }

    def _calculate_time_distribution(self, volume: int, pattern: str) -> Dict[str, int]:
        """Calculate distribution across hours of the day"""
        distribution = {}
        
        if pattern == 'business_hours':
            # 9 AM - 5 PM
            hours = list(range(9, 18))
            emails_per_hour = volume // len(hours)
            remainder = volume % len(hours)
            
            for i, hour in enumerate(hours):
                distribution[str(hour)] = emails_per_hour + (1 if i < remainder else 0)
                
        elif pattern == 'extended_hours':
            # 8 AM - 8 PM
            hours = list(range(8, 21))
            # Peak hours get more emails
            peak_hours = [10, 11, 14, 15, 16]
            
            base_per_hour = volume // (len(hours) + len(peak_hours))  # Extra for peak hours
            
            for hour in hours:
                multiplier = 2 if hour in peak_hours else 1
                distribution[str(hour)] = base_per_hour * multiplier
                
            # Distribute remainder
            remainder = volume - sum(distribution.values())
            for i in range(remainder):
                hour = hours[i % len(hours)]
                distribution[str(hour)] += 1
                
        else:  # full_day
            # 6 AM - 10 PM with natural distribution
            hours = list(range(6, 23))
            
            # Weight distribution based on typical email patterns
            weights = {
                6: 0.5, 7: 0.8, 8: 1.2, 9: 1.5, 10: 1.8, 11: 1.8,
                12: 1.2, 13: 1.0, 14: 1.5, 15: 1.8, 16: 1.8, 17: 1.5,
                18: 1.0, 19: 0.8, 20: 0.6, 21: 0.4, 22: 0.3
            }
            
            total_weight = sum(weights.values())
            
            for hour in hours:
                distribution[str(hour)] = int(volume * weights[hour] / total_weight)
            
            # Distribute remainder
            remainder = volume - sum(distribution.values())
            priority_hours = ['10', '11', '15', '16']  # Peak hours
            for i in range(remainder):
                hour = priority_hours[i % len(priority_hours)]
                distribution[hour] += 1
        
        return distribution

    async def start_warmup(self) -> int:
        """Start a new warmup session"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Check for existing active session
        cursor.execute(
            "SELECT id FROM warmup_sessions WHERE ip_address = ? AND status = 'active'",
            (self.config.ip_address,)
        )
        
        if cursor.fetchone():
            self.logger.warning(f"Active warmup session already exists for IP: {self.config.ip_address}")
            return None
        
        # Create new session
        cursor.execute('''
            INSERT INTO warmup_sessions (ip_address, start_date, current_phase)
            VALUES (?, ?, ?)
        ''', (self.config.ip_address, self.config.start_date.date(), 'initialization'))
        
        session_id = cursor.lastrowid
        
        # Create daily stats entries
        for day_schedule in self.schedule:
            target_date = self.config.start_date + timedelta(days=day_schedule.day - 1)
            cursor.execute('''
                INSERT INTO daily_stats (session_id, day, date, target_volume, phase)
                VALUES (?, ?, ?, ?, ?)
            ''', (
                session_id,
                day_schedule.day,
                target_date.date(),
                day_schedule.target_volume,
                day_schedule.phase.value
            ))
        
        conn.commit()
        conn.close()
        
        self.logger.info(f"Started new warmup session (ID: {session_id}) for IP: {self.config.ip_address}")
        return session_id

    async def execute_daily_schedule(self, session_id: int, day: int):
        """Execute the warmup schedule for a specific day"""
        if day > len(self.schedule):
            self.logger.error(f"Day {day} exceeds warmup schedule length")
            return
        
        day_schedule = self.schedule[day - 1]
        self.logger.info(f"Executing warmup schedule for day {day} - Target: {day_schedule.target_volume} emails")
        
        # Get current stats
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        sent_count = 0
        delivered_count = 0
        bounced_count = 0
        
        # Execute time-distributed sending
        for hour_str, email_count in day_schedule.time_distribution.items():
            if email_count == 0:
                continue
                
            hour = int(hour_str)
            current_time = datetime.now().replace(hour=hour, minute=0, second=0, microsecond=0)
            
            self.logger.info(f"Scheduled {email_count} emails for {hour}:00")
            
            # Send emails for this hour
            for i in range(email_count):
                try:
                    # Simulate email sending with realistic delays
                    send_delay = random.uniform(30, 300)  # 30 seconds to 5 minutes between emails
                    
                    recipient_type, recipient_address = self._select_recipient(day_schedule.mailbox_distribution)
                    subject, content = self._generate_email_content(day_schedule.content_variation_required)
                    
                    # Log the email attempt
                    send_time = datetime.now()
                    cursor.execute('''
                        INSERT INTO email_log (session_id, day, recipient_type, recipient_address, subject, sent_at)
                        VALUES (?, ?, ?, ?, ?, ?)
                    ''', (session_id, day, recipient_type, recipient_address, subject, send_time))
                    
                    # Simulate sending (replace with actual SMTP in production)
                    success, response_time = await self._send_email(recipient_address, subject, content)
                    
                    if success:
                        delivered_count += 1
                        cursor.execute('''
                            UPDATE email_log SET delivery_status = 'delivered', response_time = ?
                            WHERE id = ?
                        ''', (response_time, cursor.lastrowid))
                    else:
                        bounced_count += 1
                        cursor.execute('''
                            UPDATE email_log SET delivery_status = 'bounced', bounce_reason = 'SMTP Error'
                            WHERE id = ?
                        ''', (cursor.lastrowid,))
                    
                    sent_count += 1
                    
                    # Commit after each email for safety
                    conn.commit()
                    
                    # Wait before next email
                    await asyncio.sleep(send_delay)
                    
                except Exception as e:
                    self.logger.error(f"Error sending email {i+1} for hour {hour}: {str(e)}")
                    bounced_count += 1
        
        # Update daily stats
        success_rate = (delivered_count / sent_count * 100) if sent_count > 0 else 0
        
        cursor.execute('''
            UPDATE daily_stats 
            SET actual_sent = ?, delivered = ?, bounced = ?, success_rate = ?
            WHERE session_id = ? AND day = ?
        ''', (sent_count, delivered_count, bounced_count, success_rate, session_id, day))
        
        # Update session totals
        cursor.execute('''
            UPDATE warmup_sessions 
            SET current_day = ?, total_sent = total_sent + ?, 
                total_delivered = total_delivered + ?, total_bounced = total_bounced + ?,
                success_rate = CASE 
                    WHEN (total_sent + ?) > 0 
                    THEN ((total_delivered + ?) * 100.0 / (total_sent + ?))
                    ELSE 0 
                END,
                current_phase = ?, updated_at = CURRENT_TIMESTAMP
            WHERE id = ?
        ''', (
            day, sent_count, delivered_count, bounced_count, 
            sent_count, delivered_count, sent_count,
            day_schedule.phase.value, session_id
        ))
        
        conn.commit()
        conn.close()
        
        self.logger.info(f"Day {day} completed: {sent_count} sent, {delivered_count} delivered, {success_rate:.2f}% success rate")

    def _select_recipient(self, distribution: Dict[str, int]) -> Tuple[str, str]:
        """Select a recipient based on mailbox provider distribution"""
        # Create weighted list
        weighted_providers = []
        for provider, count in distribution.items():
            weighted_providers.extend([provider] * count)
        
        if not weighted_providers:
            return 'other', 'test@example.com'
            
        provider = random.choice(weighted_providers)
        
        # Generate recipient address based on provider
        domains = {
            'gmail': 'gmail.com',
            'outlook': 'outlook.com',
            'yahoo': 'yahoo.com',
            'apple': 'icloud.com',
            'protonmail': 'protonmail.com',
            'zoho': 'zoho.com',
            'other': 'example.org'
        }
        
        username = f"warmup{random.randint(1000, 9999)}"
        domain = domains.get(provider, 'example.com')
        
        return provider, f"{username}@{domain}"

    def _generate_email_content(self, variation_count: int) -> Tuple[str, str]:
        """Generate varied email content to avoid spam filters"""
        subjects = [
            "Welcome to our newsletter",
            "Your account information",
            "Monthly update from our team",
            "Important notification",
            "Thank you for your interest",
            "Upcoming events and updates",
            "Weekly digest",
            "Account verification required",
            "New features available",
            "Service maintenance notice"
        ]
        
        templates = [
            "Hello,\n\nThank you for subscribing to our service. We're excited to have you on board!\n\nBest regards,\nThe Team",
            "Hi there,\n\nThis is a friendly reminder about your account. Please let us know if you have any questions.\n\nThanks,\nSupport Team",
            "Dear Subscriber,\n\nWe wanted to share some exciting updates with you. Stay tuned for more!\n\nWarm regards,\nMarketing Team",
            "Hello,\n\nWe hope you're enjoying our service. Your feedback is important to us.\n\nSincerely,\nCustomer Success"
        ]
        
        subject = random.choice(subjects)
        content = random.choice(templates)
        
        # Add slight variations to avoid duplicate content
        variation_suffix = f" #{random.randint(1, variation_count)}"
        subject += variation_suffix
        
        return subject, content

    async def _send_email(self, recipient: str, subject: str, content: str) -> Tuple[bool, float]:
        """Send an email and return success status and response time"""
        start_time = time.time()
        
        try:
            # In production, replace this with actual SMTP sending
            # For warmup testing, we simulate various response scenarios
            
            # Simulate network delay
            await asyncio.sleep(random.uniform(0.1, 2.0))
            
            # Simulate success/failure rates based on warmup stage
            success_probability = 0.95  # Adjust based on warmup progress
            success = random.random() < success_probability
            
            response_time = time.time() - start_time
            return success, response_time
            
        except Exception as e:
            self.logger.error(f"SMTP error sending to {recipient}: {str(e)}")
            response_time = time.time() - start_time
            return False, response_time

    def get_session_status(self, session_id: int) -> Dict:
        """Get current status of warmup session"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Get session info
        cursor.execute('''
            SELECT * FROM warmup_sessions WHERE id = ?
        ''', (session_id,))
        
        session = cursor.fetchone()
        if not session:
            return {"error": "Session not found"}
        
        # Get daily progress
        cursor.execute('''
            SELECT day, target_volume, actual_sent, delivered, bounced, success_rate, phase
            FROM daily_stats WHERE session_id = ? ORDER BY day
        ''', (session_id,))
        
        daily_stats = cursor.fetchall()
        
        conn.close()
        
        return {
            "session_id": session_id,
            "ip_address": session[1],
            "start_date": session[2],
            "current_day": session[3],
            "current_phase": session[4],
            "total_sent": session[5],
            "total_delivered": session[6],
            "total_bounced": session[7],
            "success_rate": session[8],
            "reputation_score": session[9],
            "status": session[10],
            "daily_progress": [
                {
                    "day": row[0],
                    "target_volume": row[1],
                    "actual_sent": row[2],
                    "delivered": row[3],
                    "bounced": row[4],
                    "success_rate": row[5],
                    "phase": row[6]
                } for row in daily_stats
            ]
        }

    def generate_schedule_report(self) -> str:
        """Generate a detailed warmup schedule report"""
        report_path = os.path.join(os.path.dirname(__file__), 'reports/warmup_schedule.json')
        os.makedirs(os.path.dirname(report_path), exist_ok=True)
        
        schedule_data = {
            "ip_address": self.config.ip_address,
            "domain": self.config.domain,
            "warmup_duration": self.config.warmup_duration_days,
            "target_daily_volume": self.config.target_daily_volume,
            "schedule": [asdict(day_schedule) for day_schedule in self.schedule]
        }
        
        with open(report_path, 'w') as f:
            json.dump(schedule_data, f, indent=2, default=str)
        
        self.logger.info(f"Schedule report generated: {report_path}")
        return report_path

async def main():
    """Main function for CLI usage"""
    import argparse
    
    parser = argparse.ArgumentParser(description="IP Warmup Scheduler")
    parser.add_argument('--config', help='Config file path')
    parser.add_argument('--start', action='store_true', help='Start new warmup session')
    parser.add_argument('--execute-day', type=int, help='Execute specific day schedule')
    parser.add_argument('--session-id', type=int, help='Session ID for operations')
    parser.add_argument('--status', action='store_true', help='Show session status')
    parser.add_argument('--generate-schedule', action='store_true', help='Generate schedule report')
    
    args = parser.parse_args()
    
    scheduler = WarmupScheduler(args.config)
    
    if args.start:
        session_id = await scheduler.start_warmup()
        print(f"Started warmup session: {session_id}")
        
    elif args.execute_day and args.session_id:
        await scheduler.execute_daily_schedule(args.session_id, args.execute_day)
        
    elif args.status and args.session_id:
        status = scheduler.get_session_status(args.session_id)
        print(json.dumps(status, indent=2, default=str))
        
    elif args.generate_schedule:
        report_path = scheduler.generate_schedule_report()
        print(f"Schedule report generated: {report_path}")
        
    else:
        parser.print_help()

if __name__ == "__main__":
    asyncio.run(main())