#!/usr/bin/env python3
"""
Warmup Campaigns System - Inter-mailbox exchanges and conversation simulation
Creates realistic email conversations between warmup mailboxes to build reputation
"""

import sys
import os
import json
import logging
import asyncio
import random
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from typing import Dict, List, Optional, Tuple, Any
from enum import Enum
import sqlite3
import smtplib
import imaplib
import email
from email.mime.text import MimeText
from email.mime.multipart import MimeMultipart
from email.header import decode_header
import time
import hashlib

# Add parent directory to path for imports
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

class CampaignType(Enum):
    WELCOME_SERIES = "welcome_series"
    NEWSLETTER = "newsletter"
    CONVERSATION = "conversation"
    NOTIFICATION = "notification"
    SURVEY = "survey"
    PRODUCT_UPDATE = "product_update"
    ENGAGEMENT = "engagement"

class InteractionType(Enum):
    SEND_ONLY = "send_only"
    SEND_REPLY = "send_reply"
    FORWARD = "forward"
    CONVERSATION_CHAIN = "conversation_chain"

@dataclass
class WarmupMailbox:
    email: str
    password: str
    smtp_host: str
    smtp_port: int
    imap_host: str
    imap_port: int
    provider: str
    is_active: bool = True
    reputation_score: float = 0.0
    last_activity: datetime = None

@dataclass
class CampaignTemplate:
    name: str
    campaign_type: CampaignType
    subject_templates: List[str]
    content_templates: List[str]
    interaction_type: InteractionType
    reply_probability: float
    forward_probability: float
    engagement_actions: List[str]
    timing_pattern: str
    target_audience: List[str]

@dataclass
class ConversationFlow:
    id: str
    participants: List[str]
    message_count: int
    current_sender: str
    last_message_time: datetime
    topic: str
    interaction_history: List[Dict]
    status: str = "active"

class WarmupCampaigns:
    def __init__(self, config_path: str = None):
        self.config_path = config_path or os.path.join(os.path.dirname(__file__), 'config/campaigns_config.json')
        self.db_path = os.path.join(os.path.dirname(__file__), 'logs/warmup_campaigns.db')
        
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(os.path.join(os.path.dirname(__file__), 'logs/warmup_campaigns.log')),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
        # Initialize database
        self._init_database()
        
        # Load configuration
        self.config = self._load_config()
        
        # Load mailboxes and templates
        self.mailboxes = self._load_mailboxes()
        self.templates = self._load_campaign_templates()
        
        # Active conversations
        self.active_conversations: Dict[str, ConversationFlow] = {}
        
        self.logger.info(f"Warmup Campaigns initialized with {len(self.mailboxes)} mailboxes")

    def _init_database(self):
        """Initialize SQLite database for campaign tracking"""
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Create tables
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS campaigns (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                campaign_type TEXT NOT NULL,
                start_date DATE NOT NULL,
                end_date DATE,
                target_interactions INTEGER,
                actual_interactions INTEGER DEFAULT 0,
                success_rate REAL DEFAULT 0.0,
                status TEXT DEFAULT 'active',
                config_json TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS campaign_interactions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                campaign_id INTEGER,
                sender_email TEXT,
                recipient_email TEXT,
                subject TEXT,
                interaction_type TEXT,
                message_id TEXT,
                parent_message_id TEXT,
                sent_at TIMESTAMP,
                delivered BOOLEAN DEFAULT FALSE,
                opened BOOLEAN DEFAULT FALSE,
                replied BOOLEAN DEFAULT FALSE,
                forwarded BOOLEAN DEFAULT FALSE,
                marked_spam BOOLEAN DEFAULT FALSE,
                bounce_reason TEXT,
                FOREIGN KEY (campaign_id) REFERENCES campaigns (id)
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS conversation_flows (
                id TEXT PRIMARY KEY,
                participants_json TEXT,
                message_count INTEGER DEFAULT 0,
                current_sender TEXT,
                last_message_time TIMESTAMP,
                topic TEXT,
                interaction_history_json TEXT,
                status TEXT DEFAULT 'active',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS mailbox_activity (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                email TEXT,
                activity_type TEXT,
                timestamp TIMESTAMP,
                success BOOLEAN,
                details TEXT,
                reputation_impact REAL DEFAULT 0.0
            )
        ''')
        
        conn.commit()
        conn.close()

    def _load_config(self) -> Dict:
        """Load campaign configuration"""
        if not os.path.exists(self.config_path):
            default_config = {
                "daily_interaction_target": 100,
                "conversation_probability": 0.3,
                "reply_delay_range": [300, 3600],  # 5 minutes to 1 hour
                "max_conversation_length": 5,
                "engagement_simulation": True,
                "spam_avoidance": {
                    "content_variation_ratio": 0.8,
                    "timing_randomization": 0.3,
                    "subject_line_entropy": 0.7
                }
            }
            
            os.makedirs(os.path.dirname(self.config_path), exist_ok=True)
            with open(self.config_path, 'w') as f:
                json.dump(default_config, f, indent=2)
        
        with open(self.config_path, 'r') as f:
            return json.load(f)

    def _load_mailboxes(self) -> List[WarmupMailbox]:
        """Load warmup mailboxes configuration"""
        mailboxes_path = os.path.join(os.path.dirname(self.config_path), 'warmup_mailboxes.json')
        
        if not os.path.exists(mailboxes_path):
            # Create sample mailboxes configuration
            sample_mailboxes = [
                {
                    "email": "warmup1@gmail.com",
                    "password": "app_password_1",
                    "smtp_host": "smtp.gmail.com",
                    "smtp_port": 587,
                    "imap_host": "imap.gmail.com",
                    "imap_port": 993,
                    "provider": "gmail"
                },
                {
                    "email": "warmup2@outlook.com",
                    "password": "app_password_2",
                    "smtp_host": "smtp-mail.outlook.com",
                    "smtp_port": 587,
                    "imap_host": "outlook.office365.com",
                    "imap_port": 993,
                    "provider": "outlook"
                },
                {
                    "email": "warmup3@yahoo.com",
                    "password": "app_password_3",
                    "smtp_host": "smtp.mail.yahoo.com",
                    "smtp_port": 587,
                    "imap_host": "imap.mail.yahoo.com",
                    "imap_port": 993,
                    "provider": "yahoo"
                }
            ]
            
            with open(mailboxes_path, 'w') as f:
                json.dump(sample_mailboxes, f, indent=2)
                
            self.logger.info(f"Created sample mailboxes config at: {mailboxes_path}")
        
        with open(mailboxes_path, 'r') as f:
            mailbox_data = json.load(f)
        
        mailboxes = []
        for mb_data in mailbox_data:
            mailboxes.append(WarmupMailbox(
                email=mb_data['email'],
                password=mb_data['password'],
                smtp_host=mb_data['smtp_host'],
                smtp_port=mb_data['smtp_port'],
                imap_host=mb_data['imap_host'],
                imap_port=mb_data['imap_port'],
                provider=mb_data['provider'],
                is_active=mb_data.get('is_active', True),
                reputation_score=mb_data.get('reputation_score', 0.0),
                last_activity=datetime.fromisoformat(mb_data['last_activity']) if mb_data.get('last_activity') else None
            ))
        
        return mailboxes

    def _load_campaign_templates(self) -> List[CampaignTemplate]:
        """Load campaign templates for different types of interactions"""
        return [
            CampaignTemplate(
                name="Welcome Series",
                campaign_type=CampaignType.WELCOME_SERIES,
                subject_templates=[
                    "Welcome to {company}!",
                    "Getting started with {service}",
                    "Your account is ready",
                    "Next steps for {user_name}"
                ],
                content_templates=[
                    "Welcome aboard! We're excited to have you join our community.",
                    "Thank you for signing up. Here's what you can expect next.",
                    "Your journey with us begins here. Let's get you set up.",
                    "We're here to help you get the most out of {service}."
                ],
                interaction_type=InteractionType.SEND_REPLY,
                reply_probability=0.4,
                forward_probability=0.1,
                engagement_actions=["open", "click", "reply"],
                timing_pattern="immediate",
                target_audience=["new_users"]
            ),
            
            CampaignTemplate(
                name="Newsletter",
                campaign_type=CampaignType.NEWSLETTER,
                subject_templates=[
                    "{company} Weekly Update - {date}",
                    "This week in {industry}",
                    "Your {frequency} digest",
                    "What's new at {company}"
                ],
                content_templates=[
                    "Here are the highlights from this week...",
                    "We've been busy working on exciting new features...",
                    "Check out what's trending in our community...",
                    "Don't miss these important updates..."
                ],
                interaction_type=InteractionType.SEND_ONLY,
                reply_probability=0.05,
                forward_probability=0.15,
                engagement_actions=["open", "click", "forward"],
                timing_pattern="weekly",
                target_audience=["subscribers"]
            ),
            
            CampaignTemplate(
                name="Conversation Starter",
                campaign_type=CampaignType.CONVERSATION,
                subject_templates=[
                    "Quick question about {topic}",
                    "Thoughts on {subject}?",
                    "Following up on {previous_topic}",
                    "Your input needed on {project}"
                ],
                content_templates=[
                    "Hi {name}, I wanted to get your thoughts on...",
                    "Hope you're doing well! Quick question about...",
                    "Following up on our previous conversation about...",
                    "Would love to hear your perspective on..."
                ],
                interaction_type=InteractionType.CONVERSATION_CHAIN,
                reply_probability=0.7,
                forward_probability=0.05,
                engagement_actions=["open", "reply", "engage"],
                timing_pattern="business_hours",
                target_audience=["contacts", "colleagues"]
            ),
            
            CampaignTemplate(
                name="Product Update",
                campaign_type=CampaignType.PRODUCT_UPDATE,
                subject_templates=[
                    "New feature: {feature_name}",
                    "{product} Update - {version}",
                    "You asked for it, we built it",
                    "Exciting improvements to {product}"
                ],
                content_templates=[
                    "We're excited to announce a new feature...",
                    "Based on your feedback, we've improved...",
                    "Here's what's new in the latest update...",
                    "We've been working hard to bring you..."
                ],
                interaction_type=InteractionType.SEND_REPLY,
                reply_probability=0.2,
                forward_probability=0.1,
                engagement_actions=["open", "click", "try_feature"],
                timing_pattern="product_release",
                target_audience=["users", "beta_testers"]
            )
        ]

    async def create_campaign(self, template_name: str, target_interactions: int = 50) -> int:
        """Create a new warmup campaign"""
        template = next((t for t in self.templates if t.name == template_name), None)
        if not template:
            raise ValueError(f"Template '{template_name}' not found")
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO campaigns (name, campaign_type, start_date, target_interactions, config_json)
            VALUES (?, ?, ?, ?, ?)
        ''', (
            template.name,
            template.campaign_type.value,
            datetime.now().date(),
            target_interactions,
            json.dumps(asdict(template), default=str)
        ))
        
        campaign_id = cursor.lastrowid
        conn.commit()
        conn.close()
        
        self.logger.info(f"Created campaign '{template.name}' (ID: {campaign_id})")
        return campaign_id

    async def execute_campaign(self, campaign_id: int):
        """Execute a warmup campaign with realistic interactions"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Get campaign details
        cursor.execute("SELECT * FROM campaigns WHERE id = ?", (campaign_id,))
        campaign_row = cursor.fetchone()
        
        if not campaign_row:
            self.logger.error(f"Campaign {campaign_id} not found")
            return
        
        campaign_config = json.loads(campaign_row[7])  # config_json column
        template = CampaignTemplate(**campaign_config)
        
        target_interactions = campaign_row[4]
        
        self.logger.info(f"Executing campaign: {template.name} (Target: {target_interactions} interactions)")
        
        interactions_executed = 0
        
        while interactions_executed < target_interactions:
            # Select random sender and recipient
            sender = random.choice([mb for mb in self.mailboxes if mb.is_active])
            recipient = random.choice([mb for mb in self.mailboxes if mb.is_active and mb.email != sender.email])
            
            try:
                # Generate message content
                subject = self._generate_subject(template)
                content = self._generate_content(template, sender.email, recipient.email)
                
                # Send message
                message_id = await self._send_campaign_message(
                    sender, recipient, subject, content, campaign_id
                )
                
                # Handle interaction type
                if template.interaction_type == InteractionType.SEND_REPLY:
                    if random.random() < template.reply_probability:
                        # Schedule reply
                        await self._schedule_reply(recipient, sender, subject, message_id, campaign_id)
                
                elif template.interaction_type == InteractionType.CONVERSATION_CHAIN:
                    # Start or continue conversation
                    await self._manage_conversation(sender, recipient, subject, message_id, campaign_id)
                
                # Simulate engagement actions
                await self._simulate_engagement(message_id, template.engagement_actions)
                
                interactions_executed += 1
                
                # Update campaign progress
                cursor.execute('''
                    UPDATE campaigns SET actual_interactions = ? WHERE id = ?
                ''', (interactions_executed, campaign_id))
                conn.commit()
                
                # Random delay between interactions
                delay = random.uniform(60, 600)  # 1-10 minutes
                await asyncio.sleep(delay)
                
            except Exception as e:
                self.logger.error(f"Error in campaign execution: {str(e)}")
                continue
        
        # Mark campaign as completed
        success_rate = (interactions_executed / target_interactions) * 100
        cursor.execute('''
            UPDATE campaigns 
            SET status = 'completed', success_rate = ?
            WHERE id = ?
        ''', (success_rate, campaign_id))
        
        conn.commit()
        conn.close()
        
        self.logger.info(f"Campaign {campaign_id} completed: {interactions_executed}/{target_interactions} interactions")

    def _generate_subject(self, template: CampaignTemplate) -> str:
        """Generate subject line from template"""
        subject_template = random.choice(template.subject_templates)
        
        # Replace placeholders
        replacements = {
            'company': 'TechCorp',
            'service': 'CloudService',
            'user_name': f'User{random.randint(100, 999)}',
            'date': datetime.now().strftime('%B %d, %Y'),
            'industry': 'Technology',
            'frequency': 'Weekly',
            'topic': random.choice(['project planning', 'quarterly review', 'team updates', 'market analysis']),
            'subject': random.choice(['new features', 'user feedback', 'performance metrics', 'roadmap planning']),
            'previous_topic': 'our last meeting',
            'project': 'Q4 Initiative',
            'feature_name': f'Feature{random.randint(10, 99)}',
            'product': 'Platform',
            'version': f'v{random.randint(1, 10)}.{random.randint(0, 9)}'
        }
        
        for placeholder, value in replacements.items():
            subject_template = subject_template.replace(f'{{{placeholder}}}', value)
        
        return subject_template

    def _generate_content(self, template: CampaignTemplate, sender_email: str, recipient_email: str) -> str:
        """Generate email content from template"""
        content_template = random.choice(template.content_templates)
        
        # Extract names from email addresses
        sender_name = sender_email.split('@')[0].title()
        recipient_name = recipient_email.split('@')[0].title()
        
        replacements = {
            'name': recipient_name,
            'company': 'TechCorp',
            'service': 'CloudService',
            'product': 'Platform'
        }
        
        for placeholder, value in replacements.items():
            content_template = content_template.replace(f'{{{placeholder}}}', value)
        
        # Add signature
        signature = f"\n\nBest regards,\n{sender_name}"
        
        return content_template + signature

    async def _send_campaign_message(self, sender: WarmupMailbox, recipient: WarmupMailbox, 
                                   subject: str, content: str, campaign_id: int) -> str:
        """Send campaign message and log interaction"""
        try:
            # Generate unique message ID
            message_id = f"<{hashlib.md5((subject + str(time.time())).encode()).hexdigest()}@{sender.email.split('@')[1]}>"
            
            # Create message
            msg = MimeMultipart()
            msg['From'] = sender.email
            msg['To'] = recipient.email
            msg['Subject'] = subject
            msg['Message-ID'] = message_id
            
            msg.attach(MimeText(content, 'plain'))
            
            # Send via SMTP (simulated for warmup)
            # In production, replace with actual SMTP sending
            await asyncio.sleep(random.uniform(0.5, 2.0))  # Simulate send time
            
            # Log interaction
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute('''
                INSERT INTO campaign_interactions 
                (campaign_id, sender_email, recipient_email, subject, interaction_type, message_id, sent_at, delivered)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                campaign_id, sender.email, recipient.email, subject, 
                'send', message_id, datetime.now(), True
            ))
            
            conn.commit()
            conn.close()
            
            # Update mailbox activity
            await self._log_mailbox_activity(sender.email, 'send', True, f"Sent to {recipient.email}")
            
            self.logger.debug(f"Sent message: {sender.email} -> {recipient.email}")
            return message_id
            
        except Exception as e:
            self.logger.error(f"Failed to send message: {str(e)}")
            await self._log_mailbox_activity(sender.email, 'send', False, str(e))
            return None

    async def _schedule_reply(self, sender: WarmupMailbox, recipient: WarmupMailbox, 
                            original_subject: str, parent_message_id: str, campaign_id: int):
        """Schedule a reply to create conversation flow"""
        # Calculate reply delay
        min_delay, max_delay = self.config['reply_delay_range']
        reply_delay = random.uniform(min_delay, max_delay)
        
        # Generate reply content
        reply_templates = [
            "Thank you for reaching out. I'll look into this.",
            "This looks great! Thanks for sharing.",
            "I have a few questions about this. Can we discuss?",
            "Thanks for the update. Very helpful information.",
            "Sounds good. Let me know if you need anything else.",
            "I appreciate you following up on this.",
            "This is exactly what I was looking for. Thank you!"
        ]
        
        reply_content = random.choice(reply_templates)
        reply_subject = f"Re: {original_subject}"
        
        # Wait for reply delay
        await asyncio.sleep(reply_delay)
        
        # Send reply
        try:
            message_id = f"<reply-{hashlib.md5((reply_subject + str(time.time())).encode()).hexdigest()}@{sender.email.split('@')[1]}>"
            
            # Log reply interaction
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            cursor.execute('''
                INSERT INTO campaign_interactions 
                (campaign_id, sender_email, recipient_email, subject, interaction_type, message_id, parent_message_id, sent_at, delivered)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            ''', (
                campaign_id, sender.email, recipient.email, reply_subject,
                'reply', message_id, parent_message_id, datetime.now(), True
            ))
            
            conn.commit()
            conn.close()
            
            await self._log_mailbox_activity(sender.email, 'reply', True, f"Replied to {recipient.email}")
            
            self.logger.debug(f"Sent reply: {sender.email} -> {recipient.email}")
            
        except Exception as e:
            self.logger.error(f"Failed to send reply: {str(e)}")

    async def _manage_conversation(self, sender: WarmupMailbox, recipient: WarmupMailbox,
                                 subject: str, message_id: str, campaign_id: int):
        """Manage ongoing conversation chains"""
        conversation_key = f"{min(sender.email, recipient.email)}_{max(sender.email, recipient.email)}"
        
        if conversation_key not in self.active_conversations:
            # Start new conversation
            conversation = ConversationFlow(
                id=conversation_key,
                participants=[sender.email, recipient.email],
                message_count=1,
                current_sender=sender.email,
                last_message_time=datetime.now(),
                topic=subject,
                interaction_history=[{
                    'sender': sender.email,
                    'recipient': recipient.email,
                    'subject': subject,
                    'message_id': message_id,
                    'timestamp': datetime.now().isoformat()
                }],
                status="active"
            )
            
            self.active_conversations[conversation_key] = conversation
            await self._save_conversation(conversation)
            
        else:
            # Continue existing conversation
            conversation = self.active_conversations[conversation_key]
            
            if conversation.message_count < self.config['max_conversation_length']:
                # Schedule continuation
                if random.random() < 0.6:  # 60% chance to continue
                    await self._continue_conversation(conversation, campaign_id)

    async def _continue_conversation(self, conversation: ConversationFlow, campaign_id: int):
        """Continue an existing conversation"""
        # Determine next sender (alternate between participants)
        current_idx = conversation.participants.index(conversation.current_sender)
        next_sender_email = conversation.participants[1 - current_idx]
        recipient_email = conversation.current_sender
        
        # Find sender and recipient mailbox objects
        sender = next((mb for mb in self.mailboxes if mb.email == next_sender_email), None)
        recipient = next((mb for mb in self.mailboxes if mb.email == recipient_email), None)
        
        if not sender or not recipient:
            return
        
        # Generate continuation content
        continuation_templates = [
            "That makes sense. What about {aspect}?",
            "Good point! I was also thinking about {related_topic}.",
            "Thanks for clarifying. One more question: {question}?",
            "I agree with your approach. Should we {action}?",
            "Interesting perspective. How do you think {scenario}?",
            "Let me know when you have time to discuss this further.",
            "I'll look into that and get back to you."
        ]
        
        content = random.choice(continuation_templates).format(
            aspect="the implementation details",
            related_topic="the timeline",
            question="how should we prioritize this",
            action="move forward with this plan",
            scenario="this would impact the project"
        )
        
        subject = f"Re: {conversation.topic}"
        
        # Wait for realistic delay
        delay = random.uniform(300, 1800)  # 5-30 minutes
        await asyncio.sleep(delay)
        
        # Send continuation message
        message_id = await self._send_campaign_message(sender, recipient, subject, content, campaign_id)
        
        # Update conversation
        conversation.message_count += 1
        conversation.current_sender = next_sender_email
        conversation.last_message_time = datetime.now()
        conversation.interaction_history.append({
            'sender': next_sender_email,
            'recipient': recipient_email,
            'subject': subject,
            'message_id': message_id,
            'timestamp': datetime.now().isoformat()
        })
        
        await self._save_conversation(conversation)

    async def _save_conversation(self, conversation: ConversationFlow):
        """Save conversation to database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT OR REPLACE INTO conversation_flows
            (id, participants_json, message_count, current_sender, last_message_time, 
             topic, interaction_history_json, status, updated_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            conversation.id,
            json.dumps(conversation.participants),
            conversation.message_count,
            conversation.current_sender,
            conversation.last_message_time,
            conversation.topic,
            json.dumps(conversation.interaction_history, default=str),
            conversation.status,
            datetime.now()
        ))
        
        conn.commit()
        conn.close()

    async def _simulate_engagement(self, message_id: str, engagement_actions: List[str]):
        """Simulate realistic engagement actions on messages"""
        for action in engagement_actions:
            # Simulate different engagement probabilities
            probabilities = {
                'open': 0.8,
                'click': 0.3,
                'reply': 0.1,
                'forward': 0.05,
                'engage': 0.4,
                'try_feature': 0.2
            }
            
            if random.random() < probabilities.get(action, 0.1):
                # Simulate engagement delay
                delay = random.uniform(30, 300)  # 30 seconds to 5 minutes
                await asyncio.sleep(delay)
                
                # Log engagement
                await self._log_engagement(message_id, action, True)

    async def _log_engagement(self, message_id: str, action: str, success: bool):
        """Log engagement activity"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Update the corresponding interaction record
        column_map = {
            'open': 'opened',
            'reply': 'replied',
            'forward': 'forwarded'
        }
        
        if action in column_map:
            cursor.execute(f'''
                UPDATE campaign_interactions 
                SET {column_map[action]} = ? 
                WHERE message_id = ?
            ''', (success, message_id))
            
            conn.commit()
        
        conn.close()

    async def _log_mailbox_activity(self, email: str, activity_type: str, 
                                  success: bool, details: str, reputation_impact: float = 0.0):
        """Log mailbox activity for reputation tracking"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO mailbox_activity 
            (email, activity_type, timestamp, success, details, reputation_impact)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (email, activity_type, datetime.now(), success, details, reputation_impact))
        
        conn.commit()
        conn.close()

    def get_campaign_stats(self, campaign_id: int) -> Dict:
        """Get campaign statistics"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Get campaign info
        cursor.execute("SELECT * FROM campaigns WHERE id = ?", (campaign_id,))
        campaign = cursor.fetchone()
        
        if not campaign:
            return {"error": "Campaign not found"}
        
        # Get interaction stats
        cursor.execute('''
            SELECT 
                COUNT(*) as total_interactions,
                SUM(CASE WHEN delivered = 1 THEN 1 ELSE 0 END) as delivered,
                SUM(CASE WHEN opened = 1 THEN 1 ELSE 0 END) as opened,
                SUM(CASE WHEN replied = 1 THEN 1 ELSE 0 END) as replied,
                SUM(CASE WHEN forwarded = 1 THEN 1 ELSE 0 END) as forwarded,
                SUM(CASE WHEN marked_spam = 1 THEN 1 ELSE 0 END) as spam
            FROM campaign_interactions 
            WHERE campaign_id = ?
        ''', (campaign_id,))
        
        stats = cursor.fetchone()
        
        # Get conversation stats
        cursor.execute('''
            SELECT COUNT(*) as active_conversations
            FROM conversation_flows 
            WHERE status = 'active' AND interaction_history_json LIKE ?
        ''', (f'%campaign_{campaign_id}%',))
        
        conversations = cursor.fetchone()[0]
        
        conn.close()
        
        return {
            "campaign_id": campaign_id,
            "name": campaign[1],
            "type": campaign[2],
            "start_date": campaign[3],
            "target_interactions": campaign[4],
            "actual_interactions": campaign[5],
            "status": campaign[8],
            "interactions": {
                "total": stats[0],
                "delivered": stats[1],
                "opened": stats[2],
                "replied": stats[3],
                "forwarded": stats[4],
                "marked_spam": stats[5]
            },
            "engagement_rates": {
                "delivery_rate": (stats[1] / stats[0] * 100) if stats[0] > 0 else 0,
                "open_rate": (stats[2] / stats[1] * 100) if stats[1] > 0 else 0,
                "reply_rate": (stats[3] / stats[1] * 100) if stats[1] > 0 else 0,
                "forward_rate": (stats[4] / stats[1] * 100) if stats[1] > 0 else 0,
                "spam_rate": (stats[5] / stats[1] * 100) if stats[1] > 0 else 0
            },
            "conversations": {
                "active": conversations
            }
        }

    def get_mailbox_reputation(self, email: str) -> Dict:
        """Get mailbox reputation metrics"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Get recent activity
        cursor.execute('''
            SELECT 
                activity_type,
                COUNT(*) as count,
                AVG(CASE WHEN success = 1 THEN 1.0 ELSE 0.0 END) as success_rate,
                SUM(reputation_impact) as reputation_impact
            FROM mailbox_activity 
            WHERE email = ? AND timestamp > datetime('now', '-30 days')
            GROUP BY activity_type
        ''', (email,))
        
        activities = cursor.fetchall()
        
        conn.close()
        
        reputation_data = {
            "email": email,
            "overall_score": 0.0,
            "activity_breakdown": {},
            "total_interactions": 0,
            "success_rate": 0.0
        }
        
        total_count = 0
        total_success = 0
        
        for activity in activities:
            activity_type, count, success_rate, impact = activity
            reputation_data["activity_breakdown"][activity_type] = {
                "count": count,
                "success_rate": success_rate * 100,
                "reputation_impact": impact
            }
            total_count += count
            total_success += count * success_rate
        
        if total_count > 0:
            reputation_data["total_interactions"] = total_count
            reputation_data["success_rate"] = (total_success / total_count) * 100
            reputation_data["overall_score"] = min(10.0, max(0.0, 5.0 + (reputation_data["success_rate"] - 50) / 10))
        
        return reputation_data

async def main():
    """Main function for CLI usage"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Warmup Campaigns Manager")
    parser.add_argument('--config', help='Config file path')
    parser.add_argument('--create-campaign', help='Create campaign from template')
    parser.add_argument('--execute-campaign', type=int, help='Execute campaign by ID')
    parser.add_argument('--target-interactions', type=int, default=50, help='Target interactions for campaign')
    parser.add_argument('--campaign-stats', type=int, help='Get campaign statistics')
    parser.add_argument('--mailbox-reputation', help='Get mailbox reputation')
    
    args = parser.parse_args()
    
    campaigns = WarmupCampaigns(args.config)
    
    if args.create_campaign:
        campaign_id = await campaigns.create_campaign(args.create_campaign, args.target_interactions)
        print(f"Created campaign ID: {campaign_id}")
        
    elif args.execute_campaign:
        await campaigns.execute_campaign(args.execute_campaign)
        
    elif args.campaign_stats:
        stats = campaigns.get_campaign_stats(args.campaign_stats)
        print(json.dumps(stats, indent=2, default=str))
        
    elif args.mailbox_reputation:
        reputation = campaigns.get_mailbox_reputation(args.mailbox_reputation)
        print(json.dumps(reputation, indent=2))
        
    else:
        parser.print_help()

if __name__ == "__main__":
    asyncio.run(main())