#!/usr/bin/env python3
"""
Warmup Progress Tracker - Analytics and progress tracking for IP warmup
Provides comprehensive tracking, analytics, and visualization of warmup progress
"""

import sys
import os
import json
import logging
import asyncio
import sqlite3
from datetime import datetime, timedelta
from dataclasses import dataclass, asdict
from typing import Dict, List, Optional, Tuple, Any
from enum import Enum
import matplotlib.pyplot as plt
import matplotlib.dates as mdates
import pandas as pd
import numpy as np
from io import BytesIO
import base64

# Add parent directory to path for imports
sys.path.append(os.path.join(os.path.dirname(__file__), '..'))

class MetricType(Enum):
    DELIVERY_RATE = "delivery_rate"
    BOUNCE_RATE = "bounce_rate"
    SPAM_RATE = "spam_rate"
    REPUTATION_SCORE = "reputation_score"
    VOLUME_SCALING = "volume_scaling"
    ENGAGEMENT_RATE = "engagement_rate"
    BLACKLIST_STATUS = "blacklist_status"

@dataclass
class WarmupMetric:
    timestamp: datetime
    metric_type: MetricType
    value: float
    target_value: float
    ip_address: str
    domain: str
    phase: str
    details: Dict = None

@dataclass
class ProgressSnapshot:
    day: int
    date: datetime
    phase: str
    target_volume: int
    actual_volume: int
    delivery_rate: float
    bounce_rate: float
    spam_rate: float
    reputation_score: float
    blacklist_count: int
    engagement_metrics: Dict
    compliance_status: str

@dataclass
class WarmupGoal:
    metric_type: MetricType
    target_value: float
    current_value: float
    progress_percentage: float
    deadline: datetime
    status: str  # "on_track", "at_risk", "behind", "completed"

class WarmupTracker:
    def __init__(self, config_path: str = None):
        self.config_path = config_path or os.path.join(os.path.dirname(__file__), 'config/tracker_config.json')
        self.db_path = os.path.join(os.path.dirname(__file__), 'logs/warmup_tracker.db')
        
        # Setup logging
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(os.path.join(os.path.dirname(__file__), 'logs/warmup_tracker.log')),
                logging.StreamHandler()
            ]
        )
        self.logger = logging.getLogger(__name__)
        
        # Initialize database
        self._init_database()
        
        # Load configuration
        self.config = self._load_config()
        
        # Initialize metrics collection
        self.metrics_cache = []
        
        self.logger.info("Warmup Tracker initialized")

    def _init_database(self):
        """Initialize SQLite database for metrics tracking"""
        os.makedirs(os.path.dirname(self.db_path), exist_ok=True)
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Create tables
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS warmup_metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp TIMESTAMP NOT NULL,
                metric_type TEXT NOT NULL,
                value REAL NOT NULL,
                target_value REAL,
                ip_address TEXT,
                domain TEXT,
                phase TEXT,
                details_json TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS progress_snapshots (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ip_address TEXT NOT NULL,
                day INTEGER NOT NULL,
                date DATE NOT NULL,
                phase TEXT,
                target_volume INTEGER,
                actual_volume INTEGER,
                delivery_rate REAL,
                bounce_rate REAL,
                spam_rate REAL,
                reputation_score REAL,
                blacklist_count INTEGER,
                engagement_metrics_json TEXT,
                compliance_status TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                UNIQUE(ip_address, day)
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS warmup_goals (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                ip_address TEXT NOT NULL,
                metric_type TEXT NOT NULL,
                target_value REAL NOT NULL,
                current_value REAL DEFAULT 0.0,
                progress_percentage REAL DEFAULT 0.0,
                deadline DATE,
                status TEXT DEFAULT 'pending',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS analytics_reports (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                report_type TEXT NOT NULL,
                ip_address TEXT,
                date_range TEXT,
                report_data_json TEXT,
                chart_data_base64 TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Create indexes for performance
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_metrics_timestamp ON warmup_metrics(timestamp)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_metrics_ip ON warmup_metrics(ip_address)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_snapshots_date ON progress_snapshots(date)')
        cursor.execute('CREATE INDEX IF NOT EXISTS idx_snapshots_ip ON progress_snapshots(ip_address)')
        
        conn.commit()
        conn.close()

    def _load_config(self) -> Dict:
        """Load tracker configuration"""
        if not os.path.exists(self.config_path):
            default_config = {
                "tracking_interval": 3600,  # 1 hour
                "metrics_retention_days": 90,
                "snapshot_frequency": "daily",
                "alert_thresholds": {
                    "delivery_rate_min": 95.0,
                    "bounce_rate_max": 3.0,
                    "spam_rate_max": 0.5,
                    "reputation_score_min": 7.0
                },
                "visualization_settings": {
                    "chart_width": 12,
                    "chart_height": 8,
                    "color_scheme": "viridis",
                    "show_targets": True
                },
                "reporting": {
                    "daily_report": True,
                    "weekly_summary": True,
                    "phase_completion_report": True
                }
            }
            
            os.makedirs(os.path.dirname(self.config_path), exist_ok=True)
            with open(self.config_path, 'w') as f:
                json.dump(default_config, f, indent=2)
        
        with open(self.config_path, 'r') as f:
            return json.load(f)

    async def record_metric(self, metric: WarmupMetric):
        """Record a single warmup metric"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO warmup_metrics 
            (timestamp, metric_type, value, target_value, ip_address, domain, phase, details_json)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            metric.timestamp,
            metric.metric_type.value,
            metric.value,
            metric.target_value,
            metric.ip_address,
            metric.domain,
            metric.phase,
            json.dumps(metric.details) if metric.details else None
        ))
        
        conn.commit()
        conn.close()
        
        self.logger.debug(f"Recorded metric: {metric.metric_type.value} = {metric.value}")

    async def create_progress_snapshot(self, ip_address: str, day: int) -> ProgressSnapshot:
        """Create a comprehensive progress snapshot for a specific day"""
        # Collect metrics from various sources
        snapshot_data = await self._collect_snapshot_data(ip_address, day)
        
        snapshot = ProgressSnapshot(
            day=day,
            date=datetime.now().date(),
            phase=snapshot_data.get('phase', 'unknown'),
            target_volume=snapshot_data.get('target_volume', 0),
            actual_volume=snapshot_data.get('actual_volume', 0),
            delivery_rate=snapshot_data.get('delivery_rate', 0.0),
            bounce_rate=snapshot_data.get('bounce_rate', 0.0),
            spam_rate=snapshot_data.get('spam_rate', 0.0),
            reputation_score=snapshot_data.get('reputation_score', 0.0),
            blacklist_count=snapshot_data.get('blacklist_count', 0),
            engagement_metrics=snapshot_data.get('engagement_metrics', {}),
            compliance_status=self._assess_compliance(snapshot_data)
        )
        
        # Save to database
        await self._save_progress_snapshot(ip_address, snapshot)
        
        return snapshot

    async def _collect_snapshot_data(self, ip_address: str, day: int) -> Dict:
        """Collect data from all sources for snapshot"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Get data from warmup scheduler
        scheduler_db = os.path.join(os.path.dirname(__file__), 'logs/warmup_scheduler.db')
        if os.path.exists(scheduler_db):
            scheduler_conn = sqlite3.connect(scheduler_db)
            scheduler_cursor = scheduler_conn.cursor()
            
            scheduler_cursor.execute('''
                SELECT target_volume, actual_sent, delivered, bounced, success_rate
                FROM daily_stats 
                WHERE day = ? AND session_id IN (
                    SELECT id FROM warmup_sessions WHERE ip_address = ?
                )
            ''', (day, ip_address))
            
            scheduler_data = scheduler_cursor.fetchone()
            scheduler_conn.close()
        else:
            scheduler_data = None
        
        # Get campaign metrics
        campaigns_db = os.path.join(os.path.dirname(__file__), 'logs/warmup_campaigns.db')
        engagement_metrics = {}
        
        if os.path.exists(campaigns_db):
            campaigns_conn = sqlite3.connect(campaigns_db)
            campaigns_cursor = campaigns_conn.cursor()
            
            campaigns_cursor.execute('''
                SELECT 
                    AVG(CASE WHEN opened = 1 THEN 100.0 ELSE 0.0 END) as open_rate,
                    AVG(CASE WHEN replied = 1 THEN 100.0 ELSE 0.0 END) as reply_rate,
                    AVG(CASE WHEN forwarded = 1 THEN 100.0 ELSE 0.0 END) as forward_rate
                FROM campaign_interactions 
                WHERE DATE(sent_at) = DATE('now', '-{} days')
            '''.format(day - 1))
            
            engagement_data = campaigns_cursor.fetchone()
            if engagement_data:
                engagement_metrics = {
                    'open_rate': engagement_data[0] or 0.0,
                    'reply_rate': engagement_data[1] or 0.0,
                    'forward_rate': engagement_data[2] or 0.0
                }
            campaigns_conn.close()
        
        # Get blacklist data
        blacklist_db = os.path.join(os.path.dirname(__file__), 'logs/blacklist_monitor.db')
        blacklist_count = 0
        
        if os.path.exists(blacklist_db):
            blacklist_conn = sqlite3.connect(blacklist_db)
            blacklist_cursor = blacklist_conn.cursor()
            
            blacklist_cursor.execute('''
                SELECT COUNT(*) FROM blacklist_checks 
                WHERE ip_address = ? AND is_blacklisted = 1 AND DATE(check_time) = DATE('now', '-{} days')
            '''.format(day - 1), (ip_address,))
            
            blacklist_count = blacklist_cursor.fetchone()[0]
            blacklist_conn.close()
        
        # Get reputation score
        reputation_db = os.path.join(os.path.dirname(__file__), 'logs/reputation_tracker.db')
        reputation_score = 0.0
        
        if os.path.exists(reputation_db):
            reputation_conn = sqlite3.connect(reputation_db)
            reputation_cursor = reputation_conn.cursor()
            
            reputation_cursor.execute('''
                SELECT AVG(score) FROM reputation_scores 
                WHERE ip_address = ? AND DATE(timestamp) = DATE('now', '-{} days')
            '''.format(day - 1), (ip_address,))
            
            rep_data = reputation_cursor.fetchone()
            reputation_score = rep_data[0] if rep_data[0] else 0.0
            reputation_conn.close()
        
        conn.close()
        
        # Compile snapshot data
        if scheduler_data:
            target_volume, actual_sent, delivered, bounced, success_rate = scheduler_data
            return {
                'phase': self._get_phase_for_day(day),
                'target_volume': target_volume,
                'actual_volume': actual_sent,
                'delivery_rate': success_rate,
                'bounce_rate': (bounced / actual_sent * 100) if actual_sent > 0 else 0.0,
                'spam_rate': 0.0,  # Calculate from deliverability monitor
                'reputation_score': reputation_score,
                'blacklist_count': blacklist_count,
                'engagement_metrics': engagement_metrics
            }
        else:
            return {
                'phase': self._get_phase_for_day(day),
                'target_volume': 0,
                'actual_volume': 0,
                'delivery_rate': 0.0,
                'bounce_rate': 0.0,
                'spam_rate': 0.0,
                'reputation_score': reputation_score,
                'blacklist_count': blacklist_count,
                'engagement_metrics': engagement_metrics
            }

    def _get_phase_for_day(self, day: int) -> str:
        """Get warmup phase for a given day"""
        if day <= 7:
            return "initialization"
        elif day <= 21:
            return "gradual_ramp"
        elif day <= 35:
            return "sustained_volume"
        else:
            return "reputation_building"

    def _assess_compliance(self, data: Dict) -> str:
        """Assess compliance status based on thresholds"""
        thresholds = self.config['alert_thresholds']
        
        issues = []
        
        if data['delivery_rate'] < thresholds['delivery_rate_min']:
            issues.append('low_delivery_rate')
        
        if data['bounce_rate'] > thresholds['bounce_rate_max']:
            issues.append('high_bounce_rate')
        
        if data['spam_rate'] > thresholds['spam_rate_max']:
            issues.append('high_spam_rate')
        
        if data['reputation_score'] < thresholds['reputation_score_min']:
            issues.append('low_reputation_score')
        
        if data['blacklist_count'] > 0:
            issues.append('blacklisted')
        
        if not issues:
            return 'compliant'
        elif len(issues) <= 2:
            return 'warning'
        else:
            return 'critical'

    async def _save_progress_snapshot(self, ip_address: str, snapshot: ProgressSnapshot):
        """Save progress snapshot to database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT OR REPLACE INTO progress_snapshots
            (ip_address, day, date, phase, target_volume, actual_volume, 
             delivery_rate, bounce_rate, spam_rate, reputation_score, 
             blacklist_count, engagement_metrics_json, compliance_status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            ip_address, snapshot.day, snapshot.date, snapshot.phase,
            snapshot.target_volume, snapshot.actual_volume,
            snapshot.delivery_rate, snapshot.bounce_rate, snapshot.spam_rate,
            snapshot.reputation_score, snapshot.blacklist_count,
            json.dumps(snapshot.engagement_metrics),
            snapshot.compliance_status
        ))
        
        conn.commit()
        conn.close()

    async def set_warmup_goal(self, ip_address: str, metric_type: MetricType, 
                            target_value: float, deadline: datetime = None) -> int:
        """Set a warmup goal for tracking"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO warmup_goals (ip_address, metric_type, target_value, deadline)
            VALUES (?, ?, ?, ?)
        ''', (ip_address, metric_type.value, target_value, deadline))
        
        goal_id = cursor.lastrowid
        conn.commit()
        conn.close()
        
        self.logger.info(f"Set warmup goal: {metric_type.value} = {target_value} for IP {ip_address}")
        return goal_id

    async def update_goal_progress(self, ip_address: str):
        """Update progress for all goals for an IP"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Get all goals for IP
        cursor.execute('''
            SELECT id, metric_type, target_value, deadline FROM warmup_goals 
            WHERE ip_address = ? AND status != 'completed'
        ''', (ip_address,))
        
        goals = cursor.fetchall()
        
        for goal_id, metric_type, target_value, deadline in goals:
            # Get current value for metric
            current_value = await self._get_current_metric_value(ip_address, metric_type)
            
            # Calculate progress
            progress_percentage = min(100.0, (current_value / target_value) * 100)
            
            # Determine status
            status = self._determine_goal_status(current_value, target_value, deadline)
            
            # Update goal
            cursor.execute('''
                UPDATE warmup_goals 
                SET current_value = ?, progress_percentage = ?, status = ?, updated_at = ?
                WHERE id = ?
            ''', (current_value, progress_percentage, status, datetime.now(), goal_id))
        
        conn.commit()
        conn.close()

    async def _get_current_metric_value(self, ip_address: str, metric_type: str) -> float:
        """Get current value for a specific metric"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT value FROM warmup_metrics 
            WHERE ip_address = ? AND metric_type = ? 
            ORDER BY timestamp DESC LIMIT 1
        ''', (ip_address, metric_type))
        
        result = cursor.fetchone()
        conn.close()
        
        return result[0] if result else 0.0

    def _determine_goal_status(self, current_value: float, target_value: float, deadline: datetime) -> str:
        """Determine goal status based on progress and timeline"""
        if current_value >= target_value:
            return 'completed'
        
        if deadline:
            days_remaining = (deadline - datetime.now()).days
            progress_percentage = (current_value / target_value) * 100
            
            if days_remaining <= 0:
                return 'overdue'
            elif progress_percentage < 50 and days_remaining < 7:
                return 'at_risk'
            elif progress_percentage < 80 and days_remaining < 3:
                return 'behind'
            else:
                return 'on_track'
        
        return 'pending'

    async def generate_progress_report(self, ip_address: str, days: int = 30) -> Dict:
        """Generate comprehensive progress report"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Get progress snapshots
        cursor.execute('''
            SELECT * FROM progress_snapshots 
            WHERE ip_address = ? AND date >= DATE('now', '-{} days')
            ORDER BY date ASC
        '''.format(days), (ip_address,))
        
        snapshots = cursor.fetchall()
        
        # Get goals
        cursor.execute('''
            SELECT metric_type, target_value, current_value, progress_percentage, status
            FROM warmup_goals WHERE ip_address = ?
        ''', (ip_address,))
        
        goals = cursor.fetchall()
        
        conn.close()
        
        # Calculate trends and insights
        report = {
            "ip_address": ip_address,
            "report_date": datetime.now().isoformat(),
            "period_days": days,
            "summary": self._calculate_summary_metrics(snapshots),
            "trends": self._calculate_trends(snapshots),
            "goals": [
                {
                    "metric_type": goal[0],
                    "target_value": goal[1],
                    "current_value": goal[2],
                    "progress_percentage": goal[3],
                    "status": goal[4]
                } for goal in goals
            ],
            "insights": self._generate_insights(snapshots),
            "recommendations": self._generate_recommendations(snapshots)
        }
        
        # Save report
        await self._save_report('progress_report', ip_address, f"last_{days}_days", report)
        
        return report

    def _calculate_summary_metrics(self, snapshots: List) -> Dict:
        """Calculate summary metrics from snapshots"""
        if not snapshots:
            return {"error": "No data available"}
        
        # Convert to DataFrame for easier analysis
        df = pd.DataFrame(snapshots, columns=[
            'id', 'ip_address', 'day', 'date', 'phase', 'target_volume', 'actual_volume',
            'delivery_rate', 'bounce_rate', 'spam_rate', 'reputation_score',
            'blacklist_count', 'engagement_metrics_json', 'compliance_status', 'created_at'
        ])
        
        return {
            "total_days": len(snapshots),
            "current_phase": snapshots[-1][4],  # phase
            "avg_delivery_rate": float(df['delivery_rate'].mean()),
            "avg_bounce_rate": float(df['bounce_rate'].mean()),
            "avg_spam_rate": float(df['spam_rate'].mean()),
            "avg_reputation_score": float(df['reputation_score'].mean()),
            "total_volume_sent": int(df['actual_volume'].sum()),
            "compliance_distribution": df['compliance_status'].value_counts().to_dict(),
            "blacklist_incidents": int(df['blacklist_count'].sum())
        }

    def _calculate_trends(self, snapshots: List) -> Dict:
        """Calculate trends from snapshot data"""
        if len(snapshots) < 2:
            return {"error": "Insufficient data for trend analysis"}
        
        df = pd.DataFrame(snapshots, columns=[
            'id', 'ip_address', 'day', 'date', 'phase', 'target_volume', 'actual_volume',
            'delivery_rate', 'bounce_rate', 'spam_rate', 'reputation_score',
            'blacklist_count', 'engagement_metrics_json', 'compliance_status', 'created_at'
        ])
        
        # Calculate trends (simple linear regression slopes)
        trends = {}
        metrics = ['delivery_rate', 'bounce_rate', 'spam_rate', 'reputation_score', 'actual_volume']
        
        for metric in metrics:
            if df[metric].nunique() > 1:  # Ensure variation in data
                x = np.arange(len(df))
                y = df[metric].values
                slope = np.polyfit(x, y, 1)[0]
                trends[metric] = {
                    "trend": "improving" if slope > 0 else "declining" if slope < 0 else "stable",
                    "slope": float(slope),
                    "change_percentage": float(((y[-1] - y[0]) / y[0] * 100) if y[0] != 0 else 0)
                }
            else:
                trends[metric] = {"trend": "stable", "slope": 0.0, "change_percentage": 0.0}
        
        return trends

    def _generate_insights(self, snapshots: List) -> List[str]:
        """Generate insights from warmup data"""
        insights = []
        
        if not snapshots:
            return ["No data available for analysis"]
        
        df = pd.DataFrame(snapshots, columns=[
            'id', 'ip_address', 'day', 'date', 'phase', 'target_volume', 'actual_volume',
            'delivery_rate', 'bounce_rate', 'spam_rate', 'reputation_score',
            'blacklist_count', 'engagement_metrics_json', 'compliance_status', 'created_at'
        ])
        
        # Volume scaling analysis
        avg_actual_vs_target = (df['actual_volume'] / df['target_volume']).mean() if df['target_volume'].sum() > 0 else 0
        if avg_actual_vs_target < 0.8:
            insights.append("Volume targets are consistently not being met. Consider adjusting the warmup schedule.")
        elif avg_actual_vs_target > 1.2:
            insights.append("Consistently exceeding volume targets. This may indicate aggressive scaling.")
        
        # Delivery rate analysis
        avg_delivery_rate = df['delivery_rate'].mean()
        if avg_delivery_rate < 90:
            insights.append("Low average delivery rate indicates potential reputation issues.")
        elif avg_delivery_rate > 98:
            insights.append("Excellent delivery rates indicate good IP reputation building.")
        
        # Bounce rate analysis
        avg_bounce_rate = df['bounce_rate'].mean()
        if avg_bounce_rate > 5:
            insights.append("High bounce rate may indicate list quality issues or overly aggressive sending.")
        
        # Compliance analysis
        compliance_issues = (df['compliance_status'] != 'compliant').sum()
        if compliance_issues > len(df) * 0.3:
            insights.append("Frequent compliance issues detected. Review warmup strategy.")
        
        # Phase progression analysis
        phases = df['phase'].unique()
        if len(phases) == 1 and len(df) > 14:
            insights.append("Extended time in single phase. Consider advancing warmup progression.")
        
        return insights

    def _generate_recommendations(self, snapshots: List) -> List[str]:
        """Generate actionable recommendations"""
        recommendations = []
        
        if not snapshots:
            return ["Insufficient data for recommendations"]
        
        df = pd.DataFrame(snapshots, columns=[
            'id', 'ip_address', 'day', 'date', 'phase', 'target_volume', 'actual_volume',
            'delivery_rate', 'bounce_rate', 'spam_rate', 'reputation_score',
            'blacklist_count', 'engagement_metrics_json', 'compliance_status', 'created_at'
        ])
        
        # Latest metrics
        latest = df.iloc[-1]
        
        if latest['delivery_rate'] < 95:
            recommendations.append("Reduce sending volume and focus on list hygiene to improve delivery rates.")
        
        if latest['bounce_rate'] > 3:
            recommendations.append("Implement stricter email validation and remove hard bounces immediately.")
        
        if latest['reputation_score'] < 7:
            recommendations.append("Increase engagement-focused campaigns and reduce promotional content.")
        
        if latest['blacklist_count'] > 0:
            recommendations.append("Address blacklist issues immediately and implement IP monitoring.")
        
        # Volume recommendations
        volume_trend = (df['actual_volume'].iloc[-1] - df['actual_volume'].iloc[0]) / len(df)
        if volume_trend < 5 and len(df) > 7:
            recommendations.append("Consider more aggressive volume scaling if metrics remain healthy.")
        elif volume_trend > 20:
            recommendations.append("Slow down volume increases to maintain reputation stability.")
        
        return recommendations

    async def _save_report(self, report_type: str, ip_address: str, date_range: str, report_data: Dict):
        """Save report to database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO analytics_reports (report_type, ip_address, date_range, report_data_json)
            VALUES (?, ?, ?, ?)
        ''', (report_type, ip_address, date_range, json.dumps(report_data, default=str)))
        
        conn.commit()
        conn.close()

    async def create_visualization(self, ip_address: str, metric_types: List[MetricType], 
                                 days: int = 30) -> str:
        """Create visualization charts for warmup metrics"""
        conn = sqlite3.connect(self.db_path)
        
        # Get data for visualization
        query = '''
            SELECT timestamp, metric_type, value, target_value, phase
            FROM warmup_metrics
            WHERE ip_address = ? AND metric_type IN ({}) 
            AND timestamp >= datetime('now', '-{} days')
            ORDER BY timestamp ASC
        '''.format(','.join(['?' for _ in metric_types]), days)
        
        params = [ip_address] + [mt.value for mt in metric_types]
        df = pd.read_sql_query(query, conn, params=params)
        conn.close()
        
        if df.empty:
            return None
        
        # Create visualization
        fig, axes = plt.subplots(len(metric_types), 1, figsize=(12, 6 * len(metric_types)))
        if len(metric_types) == 1:
            axes = [axes]
        
        for i, metric_type in enumerate(metric_types):
            metric_data = df[df['metric_type'] == metric_type.value]
            
            if not metric_data.empty:
                # Convert timestamp to datetime
                metric_data['timestamp'] = pd.to_datetime(metric_data['timestamp'])
                
                # Plot actual values
                axes[i].plot(metric_data['timestamp'], metric_data['value'], 
                           label=f'Actual {metric_type.value}', marker='o')
                
                # Plot target values if available
                if 'target_value' in metric_data.columns and metric_data['target_value'].notna().any():
                    axes[i].plot(metric_data['timestamp'], metric_data['target_value'], 
                               label=f'Target {metric_type.value}', linestyle='--', alpha=0.7)
                
                axes[i].set_title(f'{metric_type.value.title()} Over Time')
                axes[i].set_xlabel('Date')
                axes[i].set_ylabel('Value')
                axes[i].legend()
                axes[i].grid(True, alpha=0.3)
                
                # Format x-axis
                axes[i].xaxis.set_major_formatter(mdates.DateFormatter('%m/%d'))
                axes[i].xaxis.set_major_locator(mdates.DayLocator(interval=max(1, days // 10)))
        
        plt.tight_layout()
        
        # Save to base64 string
        buffer = BytesIO()
        plt.savefig(buffer, format='png', dpi=150, bbox_inches='tight')
        buffer.seek(0)
        
        chart_base64 = base64.b64encode(buffer.getvalue()).decode()
        
        plt.close(fig)
        buffer.close()
        
        # Save chart to database
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO analytics_reports (report_type, ip_address, date_range, chart_data_base64)
            VALUES (?, ?, ?, ?)
        ''', ('visualization', ip_address, f'last_{days}_days', chart_base64))
        
        conn.commit()
        conn.close()
        
        # Save chart to file
        chart_path = os.path.join(os.path.dirname(__file__), 'reports', f'warmup_chart_{ip_address}_{days}d.png')
        os.makedirs(os.path.dirname(chart_path), exist_ok=True)
        
        with open(chart_path, 'wb') as f:
            f.write(base64.b64decode(chart_base64))
        
        return chart_path

    def get_real_time_status(self, ip_address: str) -> Dict:
        """Get real-time warmup status"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Get latest snapshot
        cursor.execute('''
            SELECT * FROM progress_snapshots 
            WHERE ip_address = ? ORDER BY date DESC LIMIT 1
        ''', (ip_address,))
        
        snapshot = cursor.fetchone()
        
        # Get active goals
        cursor.execute('''
            SELECT metric_type, target_value, current_value, progress_percentage, status
            FROM warmup_goals WHERE ip_address = ? AND status != 'completed'
        ''', (ip_address,))
        
        goals = cursor.fetchall()
        
        # Get recent metrics
        cursor.execute('''
            SELECT metric_type, value, timestamp FROM warmup_metrics 
            WHERE ip_address = ? AND timestamp >= datetime('now', '-1 day')
            ORDER BY timestamp DESC
        ''', (ip_address,))
        
        recent_metrics = cursor.fetchall()
        
        conn.close()
        
        if not snapshot:
            return {"error": "No progress data found"}
        
        return {
            "ip_address": ip_address,
            "current_day": snapshot[2],
            "current_phase": snapshot[4],
            "delivery_rate": snapshot[7],
            "bounce_rate": snapshot[8],
            "reputation_score": snapshot[10],
            "compliance_status": snapshot[13],
            "active_goals": len(goals),
            "goals_on_track": len([g for g in goals if g[4] == 'on_track']),
            "recent_metrics_count": len(recent_metrics),
            "last_update": snapshot[14]  # created_at
        }

async def main():
    """Main function for CLI usage"""
    import argparse
    
    parser = argparse.ArgumentParser(description="Warmup Progress Tracker")
    parser.add_argument('--config', help='Config file path')
    parser.add_argument('--snapshot', help='Create progress snapshot for IP')
    parser.add_argument('--day', type=int, help='Day number for snapshot')
    parser.add_argument('--report', help='Generate progress report for IP')
    parser.add_argument('--days', type=int, default=30, help='Days to include in report')
    parser.add_argument('--status', help='Get real-time status for IP')
    parser.add_argument('--visualize', help='Create visualization for IP')
    parser.add_argument('--metrics', nargs='+', help='Metric types to visualize')
    parser.add_argument('--set-goal', nargs=3, help='Set goal: IP METRIC_TYPE TARGET_VALUE')
    
    args = parser.parse_args()
    
    tracker = WarmupTracker(args.config)
    
    if args.snapshot:
        day = args.day or 1
        snapshot = await tracker.create_progress_snapshot(args.snapshot, day)
        print(f"Created snapshot for day {day}")
        print(json.dumps(asdict(snapshot), indent=2, default=str))
        
    elif args.report:
        report = await tracker.generate_progress_report(args.report, args.days)
        print(json.dumps(report, indent=2, default=str))
        
    elif args.status:
        status = tracker.get_real_time_status(args.status)
        print(json.dumps(status, indent=2, default=str))
        
    elif args.visualize:
        metric_types = [MetricType(m) for m in args.metrics] if args.metrics else [MetricType.DELIVERY_RATE]
        chart_path = await tracker.create_visualization(args.visualize, metric_types, args.days)
        print(f"Chart saved to: {chart_path}")
        
    elif args.set_goal:
        ip, metric_type, target_value = args.set_goal
        goal_id = await tracker.set_warmup_goal(ip, MetricType(metric_type), float(target_value))
        print(f"Set goal ID: {goal_id}")
        
    else:
        parser.print_help()

if __name__ == "__main__":
    asyncio.run(main())