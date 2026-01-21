"""
Expiration Service for Safety Pulse

This service handles:
- Automatic expiration of old safety signals
- Confidence decay for aging reports
- Cleanup of expired patterns and alerts
- Background job scheduling

Time-based decay rules:
- Strong for 30 mins
- Medium for 2 hours
- Weak after 6 hours
- Expire after 24 hours
"""

import math
from datetime import datetime, timedelta
from typing import Dict, List, Any, Optional
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.models import (
    SafetySignal, SafetyPattern, AnomalyAlert, PulseTile, ConfidenceLevel
)


class ExpirationService:
    """
    Service for managing signal expiration and decay.
    
    This implements the time decay system:
    - Reports decay over time
    - Expired reports are marked invalid
    - Patterns and alerts are cleaned up
    """
    
    # Time thresholds (in hours)
    STRONG_WINDOW_HOURS = 0.5  # 30 minutes
    MEDIUM_WINDOW_HOURS = 2.0
    WEAK_WINDOW_HOURS = 6.0
    EXPIRATION_HOURS = 24.0
    
    # Decay half-life (hours)
    DECAY_HALF_LIFE_HOURS = 12.0
    
    def __init__(self, db: Session):
        self.db = db
    
    def get_decay_factor(self, signal: SafetySignal) -> float:
        """
        Calculate the decay factor for a signal based on age.
        
        Returns:
            Factor between 0.0 and 1.0
            1.0 = just created
            0.5 = half-life reached
            0.0 = completely decayed
        """
        age_hours = (datetime.utcnow() - signal.timestamp).total_seconds() / 3600
        
        # Exponential decay
        decay = math.exp(-age_hours / self.DECAY_HALF_LIFE_HOURS)
        
        return max(0.0, decay)
    
    def get_time_category(self, signal: SafetySignal) -> str:
        """
        Get the time category for a signal.
        
        Returns:
            "strong", "medium", "weak", or "expired"
        """
        age_hours = (datetime.utcnow() - signal.timestamp).total_seconds() / 3600
        
        if age_hours <= self.STRONG_WINDOW_HOURS:
            return "strong"
        elif age_hours <= self.MEDIUM_WINDOW_HOURS:
            return "medium"
        elif age_hours <= self.EXPIRATION_HOURS:
            return "weak"
        else:
            return "expired"
    
    def apply_decay_to_signal(self, signal: SafetySignal) -> SafetySignal:
        """
        Apply decay to a signal's confidence score.
        
        Args:
            signal: The SafetySignal to decay
            
        Returns:
            Updated signal with decayed confidence
        """
        decay_factor = self.get_decay_factor(signal)
        
        # Apply decay to confidence score
        if signal.confidence_score:
            signal.confidence_score = signal.confidence_score * decay_factor
        
        # Update severity weight based on decay
        if signal.severity_weight:
            signal.severity_weight = signal.severity_weight * decay_factor
        
        return signal
    
    def check_and_expire_signal(self, signal: SafetySignal) -> bool:
        """
        Check if a signal is expired and mark it as such.
        
        Args:
            signal: The SafetySignal to check
            
        Returns:
            True if signal was expired, False otherwise
        """
        time_category = self.get_time_category(signal)
        
        if time_category == "expired" and signal.is_valid:
            signal.is_valid = False
            signal.expires_at = datetime.utcnow()
            return True
        
        return False
    
    def process_expired_signals(self) -> Dict[str, int]:
        """
        Process all signals and expire old ones.
        
        Returns:
            Dictionary with counts of expired signals
        """
        cutoff_time = datetime.utcnow() - timedelta(hours=self.EXPIRATION_HOURS)
        
        # Find expired signals
        expired_signals = self.db.query(SafetySignal).filter(
            SafetySignal.timestamp < cutoff_time,
            SafetySignal.is_valid == True
        ).all()
        
        expired_count = 0
        for signal in expired_signals:
            signal.is_valid = False
            signal.expires_at = datetime.utcnow()
            self.db.add(signal)
            expired_count += 1
        
        self.db.commit()
        
        return {
            "expired_signals": expired_count
        }
    
    def apply_decay_to_all_signals(self) -> Dict[str, int]:
        """
        Apply decay to all active signals.
        
        This should be called periodically (e.g., every hour).
        
        Returns:
            Dictionary with counts of updated signals
        """
        active_signals = self.db.query(SafetySignal).filter(
            SafetySignal.is_valid == True
        ).all()
        
        updated_count = 0
        for signal in active_signals:
            # Apply decay
            self.apply_decay_to_signal(signal)
            
            # Check if should be expired
            if self.get_time_category(signal) == "expired":
                signal.is_valid = False
                signal.expires_at = datetime.utcnow()
            
            self.db.add(signal)
            updated_count += 1
        
        self.db.commit()
        
        return {
            "updated_signals": updated_count
        }
    
    def cleanup_expired_patterns(self) -> Dict[str, int]:
        """
        Clean up expired safety patterns and alerts.
        
        Patterns and alerts should only be stored temporarily
        to avoid cluttering the database.
        
        Returns:
            Dictionary with counts of deleted patterns
        """
        # Clean up old patterns (older than 7 days)
        pattern_cutoff = datetime.utcnow() - timedelta(days=7)
        old_patterns = self.db.query(SafetyPattern).filter(
            SafetyPattern.created_at < pattern_cutoff
        ).delete()
        
        # Clean up old alerts (older than 24 hours)
        alert_cutoff = datetime.utcnow() - timedelta(hours=24)
        old_alerts = self.db.query(AnomalyAlert).filter(
            AnomalyAlert.created_at < alert_cutoff
        ).delete()
        
        self.db.commit()
        
        return {
            "deleted_patterns": old_patterns,
            "deleted_alerts": old_alerts
        }
    
    def cleanup_empty_tiles(self) -> Dict[str, int]:
        """
        Remove pulse tiles with no recent signals.
        
        Returns:
            Dictionary with counts of deleted tiles
        """
        # Find tiles that haven't been updated in 7 days
        tile_cutoff = datetime.utcnow() - timedelta(days=7)
        
        # Get tiles to delete (no signals in the last 7 days)
        empty_tiles = self.db.query(PulseTile).filter(
            PulseTile.last_updated < tile_cutoff,
            PulseTile.signal_count == 0
        ).delete()
        
        self.db.commit()
        
        return {
            "deleted_tiles": empty_tiles
        }
    
    def run_full_maintenance(self) -> Dict[str, Any]:
        """
        Run all maintenance tasks.
        
        This should be called periodically (e.g., daily).
        
        Returns:
            Dictionary with all maintenance results
        """
        results = {
            "run_at": datetime.utcnow().isoformat(),
            "expired_signals": 0,
            "updated_signals": 0,
            "deleted_patterns": 0,
            "deleted_alerts": 0,
            "deleted_tiles": 0
        }
        
        # Expire old signals
        expire_result = self.process_expired_signals()
        results["expired_signals"] = expire_result["expired_signals"]
        
        # Apply decay to active signals
        decay_result = self.apply_decay_to_all_signals()
        results["updated_signals"] = decay_result["updated_signals"]
        
        # Clean up old patterns and alerts
        cleanup_result = self.cleanup_expired_patterns()
        results["deleted_patterns"] = cleanup_result["deleted_patterns"]
        results["deleted_alerts"] = cleanup_result["deleted_alerts"]
        
        # Clean up empty tiles
        tile_result = self.cleanup_empty_tiles()
        results["deleted_tiles"] = tile_result["deleted_tiles"]
        
        return results
    
    def get_signal_age_info(self, signal: SafetySignal) -> Dict[str, Any]:
        """
        Get detailed age information for a signal.
        
        Returns:
            Dictionary with age details and time category
        """
        age = datetime.utcnow() - signal.timestamp
        age_hours = age.total_seconds() / 3600
        age_minutes = age.total_seconds() / 60
        
        time_category = self.get_time_category(signal)
        decay_factor = self.get_decay_factor(signal)
        
        # Calculate remaining time until next category
        if time_category == "strong":
            remaining_seconds = (self.STRONG_WINDOW_HOURS * 3600) - age.total_seconds()
        elif time_category == "medium":
            remaining_seconds = (self.MEDIUM_WINDOW_HOURS * 3600) - age.total_seconds()
        elif time_category == "weak":
            remaining_seconds = (self.WEAK_WINDOW_HOURS * 3600) - age.total_seconds()
        else:
            remaining_seconds = 0
        
        return {
            "signal_id": str(signal.id),
            "created_at": signal.timestamp.isoformat(),
            "age_hours": round(age_hours, 2),
            "age_minutes": round(age_minutes, 2),
            "time_category": time_category,
            "decay_factor": round(decay_factor, 3),
            "remaining_seconds_until_decay": max(0, remaining_seconds),
            "is_expired": time_category == "expired",
            "is_valid": signal.is_valid
        }


class BackgroundJobService:
    """
    Service for scheduling and running background jobs.
    
    In production, this would integrate with:
    - Celery
    - APScheduler
    - Background tasks
    """
    
    def __init__(self, db: Session):
        self.db = db
        self.expiration_service = ExpirationService(db)
    
    def run_daily_maintenance(self) -> Dict[str, Any]:
        """
        Run daily maintenance tasks.
        
        Should be scheduled to run once per day.
        """
        return self.expiration_service.run_full_maintenance()
    
    def run_hourly_decay(self) -> Dict[str, int]:
        """
        Apply decay to all active signals.
        
        Should be scheduled to run hourly.
        """
        return self.expiration_service.apply_decay_to_all_signals()
    
    def quick_expire_check(self) -> Dict[str, int]:
        """
        Quick check for and expire old signals.
        
        Should be scheduled to run frequently (e.g., every 5 minutes).
        """
        return self.expiration_service.process_expired_signals()

