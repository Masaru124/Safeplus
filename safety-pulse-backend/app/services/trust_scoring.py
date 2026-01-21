"""
Trust Scoring Service for Safety Pulse

This service handles:
- Trust score calculation based on device activity
- Trust score clamping between safe bounds (0.2-1.0)
- Trust boost for confirmed reports (+0.02)
- Trust penalty for false reports (-0.05)
- Spam reporter down-weighting
- Anomaly detection for abuse protection

Trust Score Bounds:
- MIN_TRUST_SCORE = 0.2: Minimum trust to have any influence
- MAX_TRUST_SCORE = 1.0: Maximum possible trust
"""

import math
import random
from typing import Tuple, Optional, Dict, Any
from sqlalchemy.orm import Session
from datetime import datetime, timedelta, timezone
from app.models import DeviceActivity, SafetySignal, User
import uuid


class TrustScoringService:
    """
    Service for managing trust scores and abuse protection.
    """
    
    # Trust score bounds - enforced for all trust calculations
    MIN_TRUST_SCORE = 0.2  # Minimum trust to have any influence
    MAX_TRUST_SCORE = 1.0  # Maximum possible trust
    
    # Trust adjustments
    TRUST_BOOST_CONFIRMED = 0.02  # Boost for confirmed reports
    TRUST_PENALTY_FALSE = 0.05    # Penalty for false reports
    ANONYMOUS_PENALTY = 0.1       # Penalty for unauthenticated reports
    
    # Spam detection thresholds
    RAPID_SUBMISSION_THRESHOLD = 5   # submissions in time window
    RAPID_SUBMISSION_WINDOW = 60     # seconds
    MAX_REPORTS_PER_HOUR = 20        # Maximum reports per hour per device
    MAX_SAME_LOCATION_REPORTS = 3    # Max reports from same location per hour
    
    def __init__(self, db: Session):
        self.db = db
    
    # ============ Trust Score Bounds ============
    
    @staticmethod
    def clamp_trust_score(score: float) -> float:
        """
        Clamp trust score between safe bounds (0.2-1.0).
        
        This ensures that even users with low trust still have some influence,
        while preventing malicious users from gaming the system with high trust.
        
        Args:
            score: Raw trust score
            
        Returns:
            Clamped trust score between MIN_TRUST_SCORE and MAX_TRUST_SCORE
        """
        return max(TrustScoringService.MIN_TRUST_SCORE, 
                   min(TrustScoringService.MAX_TRUST_SCORE, score))
    
    # ============ Coordinate Blurring ============
    
    @staticmethod
    def blur_coordinates(latitude: float, longitude: float, radius_meters: int = 50) -> Tuple[float, float]:
        """
        Blur coordinates by adding random offset within specified radius.
        This protects reporter privacy while maintaining spatial accuracy.
        
        Args:
            latitude: Original latitude
            longitude: Original longitude
            radius_meters: Blur radius in meters (default 50m)
            
        Returns:
            Tuple of (blurred_lat, blurred_lon)
        """
        # Convert radius to degrees (approximate)
        radius_deg = radius_meters / 111320  # meters per degree at equator

        # Generate random angle and distance
        angle = random.uniform(0, 2 * math.pi)
        distance = random.uniform(0, radius_deg)

        # Calculate offset
        delta_lat = distance * math.cos(angle)
        delta_lon = distance * math.sin(angle) / math.cos(math.radians(latitude))

        blurred_lat = latitude + delta_lat
        blurred_lon = longitude + delta_lon

        return blurred_lat, blurred_lon
    
    # ============ Trust Score Calculation ============
    
    def calculate_trust_score(self, device_hash: str, is_authenticated: bool = False) -> float:
        """
        Calculate trust score for a device based on activity history.
        
        This is the main entry point for trust score calculation.
        
        Args:
            device_hash: Unique identifier for the device
            is_authenticated: Whether the user is authenticated
            
        Returns:
            Trust score between MIN_TRUST_SCORE (0.2) and MAX_TRUST_SCORE (1.0)
        """
        return self.calculate_base_trust_score(device_hash, is_authenticated)
    
    def calculate_base_trust_score(self, device_hash: str, is_authenticated: bool = False) -> float:
        """
        Calculate base trust score for a device based on activity history.
        
        Args:
            device_hash: Unique identifier for the device
            is_authenticated: Whether the user is authenticated
            
        Returns:
            Trust score between MIN_TRUST_SCORE (0.2) and MAX_TRUST_SCORE (1.0)
        """
        device_activity = self.db.query(DeviceActivity).filter(
            DeviceActivity.device_hash == device_hash
        ).first()

        if not device_activity:
            # New device, start with minimum trust for anonymous, higher for authenticated
            if is_authenticated:
                return self.clamp_trust_score(0.6)
            return self.clamp_trust_score(self.MIN_TRUST_SCORE)

        # Start with minimum trust
        trust_score = self.MIN_TRUST_SCORE
        
        # Increase trust based on submission count (up to 0.4 bonus)
        submission_bonus = min(0.4, device_activity.submission_count * 0.02)
        trust_score += submission_bonus
        
        # Authentication bonus (up to 0.15)
        if is_authenticated:
            trust_score += 0.15
        
        # Decrease trust based on anomaly score (anomaly_score is 0.0-1.0)
        anomaly_penalty = device_activity.anomaly_score * 0.3
        trust_score -= anomaly_penalty
        
        return self.clamp_trust_score(trust_score)

    def calculate_verification_based_trust(
        self, 
        true_votes: int, 
        false_votes: int, 
        base_trust_score: float = 0.5
    ) -> float:
        """
        Calculate trust score based on user verification votes.
        
        The trust score is calculated using a Bayesian approach:
        - Start with a prior (base_trust_score)
        - Weight new votes more heavily for low vote counts
        - As vote count increases, trust ratio dominates
        
        Args:
            true_votes: Number of users who voted the report is true/accurate
            false_votes: Number of users who voted the report is false/inaccurate
            base_trust_score: Prior trust score (default 0.5)
            
        Returns:
            Trust score between MIN_TRUST_SCORE and MAX_TRUST_SCORE
        """
        total_votes = true_votes + false_votes
        
        if total_votes == 0:
            # No votes yet, return clamped base trust score
            return self.clamp_trust_score(base_trust_score)
        
        # Calculate the verification ratio (true / total)
        trust_ratio = true_votes / total_votes
        
        # Bayesian-style weighting:
        # - For low vote counts (< 10), blend towards base_trust_score
        # - For high vote counts, trust_ratio dominates
        # - Maximum weight for votes is 0.4 (40% of final score)
        min_votes_for_full_weight = 10
        vote_weight = min(0.4, total_votes / min_votes_for_full_weight * 0.4)
        
        # Combine base trust score with verification ratio
        trust_score = base_trust_score * (1 - vote_weight) + trust_ratio * vote_weight
        
        # Apply severity weighting: higher severity reports need more verification
        # This is handled separately when saving to the signal
        
        # Clamp to bounds
        return self.clamp_trust_score(trust_score)

    def calculate_trust_score_from_signal(self, signal: SafetySignal) -> float:
        """
        Calculate trust score for an existing signal based on its vote counts.
        
        Args:
            signal: SafetySignal instance with true_votes and false_votes
            
        Returns:
            Updated trust score between MIN_TRUST_SCORE and MAX_TRUST_SCORE
        """
        return self.calculate_verification_based_trust(
            true_votes=signal.true_votes or 0,
            false_votes=signal.false_votes or 0,
            base_trust_score=signal.trust_score or 0.5
        )

    # ============ Trust Updates ============
    
    def update_signal_trust_from_vote(
        self, 
        signal_id: str, 
        is_true_vote: bool
    ) -> float:
        """
        Update a signal's trust score after a vote is cast.
        
        Args:
            signal_id: UUID or string ID of the signal
            is_true_vote: True if vote is "true/accurate", False if "false/inaccurate"
            
        Returns:
            The updated trust score (clamped to bounds)
        """
        signal_uuid = uuid.UUID(signal_id) if isinstance(signal_id, str) else signal_id
        
        signal = self.db.query(SafetySignal).filter(
            SafetySignal.id == signal_uuid
        ).first()
        
        if not signal:
            raise ValueError(f"Signal with ID {signal_uuid} not found")
        
        # Update vote counts
        if is_true_vote:
            signal.true_votes = (signal.true_votes or 0) + 1
        else:
            signal.false_votes = (signal.false_votes or 0) + 1
        
        # Calculate new trust score based on votes
        new_trust_score = self.calculate_verification_based_trust(
            true_votes=signal.true_votes or 0,
            false_votes=signal.false_votes or 0,
            base_trust_score=0.5
        )
        
        # Blend with original trust score to avoid drastic changes
        original_weight = 0.6
        new_weight = 0.4
        
        blended_score = signal.trust_score * original_weight + new_trust_score * new_weight
        
        # Clamp to bounds (0.2 - 1.0)
        signal.trust_score = self.clamp_trust_score(blended_score)
        
        self.db.add(signal)
        self.db.commit()
        self.db.refresh(signal)
        
        return signal.trust_score

    def revert_vote_from_signal(self, signal_id: str, was_true_vote: bool) -> float:
        """
        Revert a vote from a signal (for when a user removes their vote).
        
        Args:
            signal_id: UUID or string ID of the signal
            was_true_vote: True if the removed vote was "true", False if "false"
            
        Returns:
            The updated trust score (clamped to bounds)
        """
        signal_uuid = uuid.UUID(signal_id) if isinstance(signal_id, str) else signal_id
        
        signal = self.db.query(SafetySignal).filter(
            SafetySignal.id == signal_uuid
        ).first()
        
        if not signal:
            raise ValueError(f"Signal with ID {signal_uuid} not found")
        
        # Decrease the appropriate vote count
        if was_true_vote:
            signal.true_votes = max(0, (signal.true_votes or 0) - 1)
        else:
            signal.false_votes = max(0, (signal.false_votes or 0) - 1)
        
        # Recalculate trust score
        new_trust_score = self.calculate_verification_based_trust(
            true_votes=signal.true_votes or 0,
            false_votes=signal.false_votes or 0,
            base_trust_score=0.5
        )
        
        # Blend with original trust score
        original_weight = 0.6
        new_weight = 0.4
        
        blended_score = signal.trust_score * original_weight + new_trust_score * new_weight
        signal.trust_score = self.clamp_trust_score(blended_score)
        
        self.db.add(signal)
        self.db.commit()
        self.db.refresh(signal)
        
        return signal.trust_score

    def get_vote_summary(self, signal_id: str) -> dict:
        """
        Get a summary of votes for a signal.
        
        Args:
            signal_id: UUID or string ID of the signal
            
        Returns:
            Dictionary with vote statistics
        """
        signal_uuid = uuid.UUID(signal_id) if isinstance(signal_id, str) else signal_id
        
        signal = self.db.query(SafetySignal).filter(
            SafetySignal.id == signal_uuid
        ).first()
        
        if not signal:
            raise ValueError(f"Signal with ID {signal_uuid} not found")
        
        true_votes = signal.true_votes or 0
        false_votes = signal.false_votes or 0
        total_votes = true_votes + false_votes
        
        trust_ratio = true_votes / total_votes if total_votes > 0 else 0.5
        
        return {
            "signal_id": str(signal_uuid),
            "true_votes": true_votes,
            "false_votes": false_votes,
            "total_votes": total_votes,
            "trust_ratio": trust_ratio,
            "trust_score": signal.trust_score
        }

    # ============ User Trust Score Methods ============

    def update_user_trust_on_verification(
        self,
        user_id: str,
        vote_was_true: bool,
        signal_confidence: float = 0.5
    ) -> float:
        """
        Update a user's trust score when they vote on a report.
        
        This helps track which users consistently provide accurate verifications.
        
        Trust adjustment rules:
        - Confirmed report: +0.02
        - False report: -0.05
        
        Trust is clamped between MIN_TRUST_SCORE (0.2) and MAX_TRUST_SCORE (1.0).
        
        Args:
            user_id: UUID of the user
            vote_was_true: Whether the user's vote matched the eventual consensus
            signal_confidence: The confidence of the signal being voted on
            
        Returns:
            Updated user trust score
        """
        try:
            user_uuid = uuid.UUID(user_id) if isinstance(user_id, str) else user_id
        except ValueError:
            user_uuid = user_id
        
        user = self.db.query(User).filter(User.id == user_uuid).first()
        if not user:
            # Create user with minimum trust if not exists
            user = User(id=user_uuid, trust_score=0.5)
            self.db.add(user)
            self.db.commit()
            self.db.refresh(user)
            return user.trust_score
        
        # Calculate trust adjustment based on vote
        if vote_was_true:
            # User confirmed a report - trust boost
            user.trust_score = user.trust_score + self.TRUST_BOOST_CONFIRMED
            user.reports_confirmed = (user.reports_confirmed or 0) + 1
        else:
            # User flagged a report - trust penalty
            user.trust_score = user.trust_score - self.TRUST_PENALTY_FALSE
            user.reports_flagged = (user.reports_flagged or 0) + 1
        
        # Clamp trust score between bounds
        user.trust_score = self.clamp_trust_score(user.trust_score)
        
        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)
        
        return user.trust_score

    def revert_user_trust_on_verification(
        self,
        user_id: str,
        vote_was_true: bool,
        signal_confidence: float = 0.5
    ) -> float:
        """
        Revert a user's trust score when they remove their vote.
        
        Args:
            user_id: UUID of the user
            vote_was_true: Whether the removed vote was "true"
            signal_confidence: The confidence of the signal
            
        Returns:
            Updated user trust score
        """
        try:
            user_uuid = uuid.UUID(user_id) if isinstance(user_id, str) else user_id
        except ValueError:
            user_uuid = user_id
        
        user = self.db.query(User).filter(User.id == user_uuid).first()
        if not user:
            return self.MIN_TRUST_SCORE
        
        # Reverse the adjustment (smaller than original to prevent gaming)
        adjustment = 0.01
        
        if vote_was_true:
            user.trust_score = max(self.MIN_TRUST_SCORE, user.trust_score - adjustment)
            user.reports_confirmed = max(0, (user.reports_confirmed or 0) - 1)
        else:
            user.trust_score = min(self.MAX_TRUST_SCORE, user.trust_score + adjustment)
            user.reports_flagged = max(0, (user.reports_flagged or 0) - 1)
        
        self.db.add(user)
        self.db.commit()
        self.db.refresh(user)
        
        return user.trust_score

    def get_user_trust_summary(self, user_id: str) -> dict:
        """
        Get a summary of a user's trust statistics.
        
        Args:
            user_id: UUID of the user
            
        Returns:
            Dictionary with trust statistics
        """
        try:
            user_uuid = uuid.UUID(user_id) if isinstance(user_id, str) else user_id
        except ValueError:
            user_uuid = user_id
        
        user = self.db.query(User).filter(User.id == user_uuid).first()
        if not user:
            return {
                "user_id": str(user_id),
                "trust_score": 0.5,
                "reports_confirmed": 0,
                "reports_flagged": 0,
                "total_votes": 0,
                "trust_level": "unknown"
            }
        
        total_votes = (user.reports_confirmed or 0) + (user.reports_flagged or 0)
        
        # Determine trust level
        if user.trust_score >= 0.8:
            trust_level = "high"
        elif user.trust_score >= 0.6:
            trust_level = "medium"
        elif user.trust_score >= self.MIN_TRUST_SCORE:
            trust_level = "low"
        else:
            trust_level = "very_low"
        
        return {
            "user_id": str(user.id),
            "trust_score": user.trust_score,
            "reports_confirmed": user.reports_confirmed or 0,
            "reports_flagged": user.reports_flagged or 0,
            "total_votes": total_votes,
            "trust_level": trust_level
        }
    
    # ============ Abuse Protection & Spam Detection ============
    
    def check_rapid_submission(self, device_hash: str) -> Dict[str, Any]:
        """
        Check if a device is submitting reports too rapidly (potential spam).
        
        Args:
            device_hash: Device identifier
            
        Returns:
            Dictionary with is_suspicious flag and reason
        """
        device_activity = self.db.query(DeviceActivity).filter(
            DeviceActivity.device_hash == device_hash
        ).first()
        
        if not device_activity:
            return {"is_suspicious": False, "reason": None}
        
        # Check last submission time
        if device_activity.last_submission:
            seconds_since_last = (
                datetime.now(timezone.utc) - device_activity.last_submission
            ).total_seconds()
            
            if seconds_since_last < 10:
                return {
                    "is_suspicious": True,
                    "reason": "Rapid submission detected",
                    "seconds_since_last": seconds_since_last
                }
        
        # Check hourly limit
        # This would need hourly tracking - simplified here
        hourly_submissions = device_activity.submission_count
        
        if hourly_submissions > self.MAX_REPORTS_PER_HOUR:
            return {
                "is_suspicious": True,
                "reason": "Excessive reports per hour",
                "count": hourly_submissions
            }
        
        return {"is_suspicious": False, "reason": None}
    
    def update_anomaly_score(
        self, 
        device_hash: str, 
        is_spam: bool = False,
        is_duplicate: bool = False
    ) -> float:
        """
        Update the anomaly score for a device based on suspicious behavior.
        
        Args:
            device_hash: Device identifier
            is_spam: Whether spam was detected
            is_duplicate: Whether a duplicate report was detected
            
        Returns:
            Updated anomaly score
        """
        device_activity = self.db.query(DeviceActivity).filter(
            DeviceActivity.device_hash == device_hash
        ).first()
        
        if not device_activity:
            device_activity = DeviceActivity(device_hash=device_hash)
            self.db.add(device_activity)
        
        # Increase anomaly score for suspicious behavior
        if is_spam:
            device_activity.anomaly_score = min(1.0, device_activity.anomaly_score + 0.3)
        elif is_duplicate:
            device_activity.anomaly_score = min(1.0, device_activity.anomaly_score + 0.1)
        else:
            # Slowly decrease anomaly score for good behavior
            device_activity.anomaly_score = max(0.0, device_activity.anomaly_score - 0.05)
        
        self.db.commit()
        self.db.refresh(device_activity)
        
        return device_activity.anomaly_score
    
    def get_device_info(self, device_hash: str) -> Dict[str, Any]:
        """
        Get device activity information for monitoring.
        
        Args:
            device_hash: Device identifier
            
        Returns:
            Dictionary with device activity stats
        """
        device_activity = self.db.query(DeviceActivity).filter(
            DeviceActivity.device_hash == device_hash
        ).first()
        
        if not device_activity:
            return {
                "device_hash": device_hash,
                "submission_count": 0,
                "anomaly_score": 0.0,
                "status": "new"
            }
        
        # Determine status based on anomaly score
        if device_activity.anomaly_score >= 0.7:
            status = "flagged"
        elif device_activity.anomaly_score >= 0.3:
            status = "watched"
        else:
            status = "normal"
        
        return {
            "device_hash": device_hash,
            "submission_count": device_activity.submission_count,
            "anomaly_score": device_activity.anomaly_score,
            "status": status,
            "last_submission": device_activity.last_submission.isoformat() if device_activity.last_submission else None
        }
    
    def apply_spam_downweight(self, trust_score: float, anomaly_score: float) -> float:
        """
        Apply down-weighting for users with high anomaly scores.
        
        This reduces the influence of potentially spam accounts on pulse calculations.
        
        Args:
            trust_score: Original trust score
            anomaly_score: Device anomaly score (0.0-1.0)
            
        Returns:
            Down-weighted trust score
        """
        if anomaly_score < 0.3:
            # Normal behavior, no penalty
            return trust_score
        
        # Apply penalty proportional to anomaly score
        # Max penalty is 50% reduction for highly anomalous users
        penalty_factor = 1.0 - (anomaly_score * 0.5)
        
        downweighted = trust_score * penalty_factor
        
        return self.clamp_trust_score(downweighted)

