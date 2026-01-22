"""
Report Lifecycle Service for Safety Pulse

This service handles:
- Report status transitions (pending -> verified/disputed/expired)
- Vote window enforcement
- Voting thresholds for verification/dispute
- Ownership checks and delete safety
- Abuse detection and integrity protection

Voting Thresholds:
- VERIFY_THRESHOLD: Confidence > 0.7 triggers verified status
- DISPUTE_THRESHOLD: > 30% downvotes with minimum 3 votes triggers disputed status
- VOTE_WINDOW_HOURS: Reports accept votes for 72 hours
- DELETE_COOLDOWN_HOURS: Users must wait 1 hour between deletions

Status Transitions:
- pending -> verified (when confidence > VERIFY_THRESHOLD)
- pending -> disputed (when downvotes > DISPUTE_THRESHOLD)
- pending -> expired (after VOTE_WINDOW_HOURS)
- Any status -> deleted (soft delete by owner)
"""

import math
from datetime import datetime, timedelta, timezone
from typing import Optional, Dict, Any, Tuple
from sqlalchemy.orm import Session
from sqlalchemy import and_
from uuid import UUID

from app.models import (
    SafetySignal, ReportVerification, ReportStatus, 
    User, DeviceActivity, PulseTile
)
from app.services.trust_scoring import TrustScoringService


# ============ Configuration Constants ============

# Vote thresholds
VERIFY_THRESHOLD = 0.7  # Confidence > 70% triggers verified status
DISPUTE_THRESHOLD = 0.3  # > 30% downvotes triggers disputed status
MIN_VOTES_FOR_STATUS_UPDATE = 3  # Minimum votes before status changes

# Time windows
VOTE_WINDOW_HOURS = 72  # Reports accept votes for 72 hours
DELETE_COOLDOWN_HOURS = 1  # Users wait 1 hour between deletions
EXPIRATION_HOURS = 24  # Reports expire after 24 hours by default

# Confidence calculation weights
VOTE_WEIGHT = 0.4  # Weight of votes in confidence calculation
TRUST_WEIGHT = 0.3  # Weight of reporter trust in confidence
RECENCY_WEIGHT = 0.2  # Weight of recency in confidence
SEVERITY_WEIGHT = 0.1  # Weight of severity in confidence


class ReportLifecycleService:
    """
    Service for managing report lifecycle, voting, and status transitions.
    """
    
    def __init__(self, db: Session):
        self.db = db
        self.trust_service = TrustScoringService(db)
    
    # ============ Vote Window Management ============
    
    def get_vote_window_expires_at(self) -> datetime:
        """Get the expiration time for vote windows."""
        return datetime.now(timezone.utc) + timedelta(hours=VOTE_WINDOW_HOURS)
    
    def can_accept_votes(self, signal: SafetySignal) -> bool:
        """
        Check if a report can still accept votes.
        
        Returns False if:
        - Report is deleted or expired
        - Vote window has closed
        """
        if signal.status in [ReportStatus.deleted, ReportStatus.expired]:
            return False
        
        if signal.vote_window_expires_at:
            if datetime.now(timezone.utc) > signal.vote_window_expires_at:
                return False
        
        return True
    
    def check_vote_window(self, signal: SafetySignal) -> Tuple[bool, str]:
        """
        Check if a vote can be accepted for this report.
        
        Returns:
            Tuple of (can_vote, reason_if_no)
        """
        if not self.can_accept_votes(signal):
            if signal.status == ReportStatus.deleted:
                return False, "Cannot vote on a deleted report"
            elif signal.status == ReportStatus.expired:
                return False, "Voting window has expired for this report"
            else:
                return False, "Voting window has closed"
        
        return True, ""
    
    # ============ Vote Validation ============
    
    def has_user_voted(self, signal_id: UUID, user_id: UUID) -> bool:
        """Check if a user has already voted on a report."""
        vote = self.db.query(ReportVerification).filter(
            and_(
                ReportVerification.signal_id == signal_id,
                ReportVerification.user_id == user_id
            )
        ).first()
        return vote is not None
    
    def check_vote_permission(
        self, 
        signal: SafetySignal, 
        user_id: UUID
    ) -> Tuple[bool, str]:
        """
        Check if a user can vote on a report.
        
        Returns:
            Tuple of (can_vote, reason_if_no)
        """
        # Check if user already voted
        if self.has_user_voted(signal.id, user_id):
            return False, "You have already voted on this report"
        
        # Check vote window
        can_vote, reason = self.check_vote_window(signal)
        if not can_vote:
            return False, reason
        
        # Check ownership - users cannot vote on their own reports
        if signal.user_id == user_id:
            return False, "You cannot vote on your own report"
        
        return True, ""
    
    # ============ Confidence Calculation ============
    
    def calculate_confidence(
        self, 
        signal: SafetySignal,
        true_votes: int,
        false_votes: int
    ) -> float:
        """
        Calculate report confidence score (0.0-1.0).
        
        Confidence is based on:
        - Vote ratio (weighted by total votes)
        - Reporter trust score
        - Report recency
        - Severity of the report
        """
        total_votes = true_votes + false_votes
        
        # Base confidence from vote ratio (Bayesian-style)
        if total_votes == 0:
            vote_confidence = 0.5  # Neutral start
        else:
            trust_ratio = true_votes / total_votes
            # More votes = more weight on actual ratio
            vote_weight = min(0.5, total_votes / 20.0)
            vote_confidence = 0.5 * (1 - vote_weight) + trust_ratio * vote_weight
        
        # Reporter trust contribution
        trust_contribution = signal.trust_score * TRUST_WEIGHT
        
        # Recency contribution (more recent = higher confidence)
        hours_since = (datetime.now(timezone.utc) - signal.timestamp).total_seconds() / 3600
        recency_contribution = max(0, 1 - hours_since / 48) * RECENCY_WEIGHT  # Decays over 48h
        
        # Severity contribution (higher severity = slightly more weight)
        severity_contribution = (signal.severity / 5.0) * SEVERITY_WEIGHT
        
        # Combine contributions
        confidence = (
            vote_confidence * VOTE_WEIGHT +
            trust_contribution +
            recency_contribution +
            severity_contribution
        )
        
        return max(0.0, min(1.0, confidence))
    
    # ============ Status Updates ============
    
    def update_status_from_votes(self, signal: SafetySignal) -> ReportStatus:
        """
        Update report status based on current votes and confidence.
        
        Status transitions:
        - pending -> verified (confidence > VERIFY_THRESHOLD with MIN_VOTES)
        - pending -> disputed (downvote ratio > DISPUTE_THRESHOLD with MIN_VOTES)
        - No other automatic transitions (only deletion or expiration)
        """
        true_votes = signal.true_votes or 0
        false_votes = signal.false_votes or 0
        total_votes = true_votes + false_votes
        
        # Calculate current confidence
        confidence = self.calculate_confidence(signal, true_votes, false_votes)
        signal.confidence_score = confidence
        
        # Only update status if we have enough votes
        if total_votes < MIN_VOTES_FOR_STATUS_UPDATE:
            return signal.status
        
        # Check for verification
        if signal.status == ReportStatus.pending and confidence >= VERIFY_THRESHOLD:
            signal.status = ReportStatus.verified
            signal.verified_at = datetime.now(timezone.utc)
            return ReportStatus.verified
        
        # Check for dispute
        if signal.status == ReportStatus.pending:
            downvote_ratio = false_votes / total_votes
            if downvote_ratio >= DISPUTE_THRESHOLD:
                signal.status = ReportStatus.disputed
                signal.disputed_at = datetime.now(timezone.utc)
                return ReportStatus.disputed
        
        return signal.status
    
    def check_and_expire_report(self, signal: SafetySignal) -> bool:
        """
        Check if a report should be expired and update status.
        
        Returns True if report was expired.
        """
        # Check explicit expiration time
        if signal.expires_at and datetime.now(timezone.utc) > signal.expires_at:
            if signal.status not in [ReportStatus.deleted]:
                signal.status = ReportStatus.expired
                return True
        
        # Check vote window expiration
        if signal.vote_window_expires_at:
            if datetime.now(timezone.utc) > signal.vote_window_expires_at:
                if signal.status == ReportStatus.pending:
                    signal.status = ReportStatus.expired
                    return True
        
        return False
    
    # ============ Voting Operations ============
    
    def process_vote(
        self,
        signal: SafetySignal,
        user_id: UUID,
        is_true: bool
    ) -> Tuple[bool, str, float]:
        """
        Process a vote on a report.
        
        Returns:
            Tuple of (success, error_message, updated_trust_score)
        """
        # Check permissions
        can_vote, reason = self.check_vote_permission(signal, user_id)
        if not can_vote:
            return False, reason, signal.trust_score
        
        # Create vote
        verification = ReportVerification(
            signal_id=signal.id,
            user_id=user_id,
            is_true=is_true
        )
        self.db.add(verification)
        
        # Update vote counts
        if is_true:
            signal.true_votes = (signal.true_votes or 0) + 1
        else:
            signal.false_votes = (signal.false_votes or 0) + 1
        
        # Update last activity
        signal.last_activity_at = datetime.now(timezone.utc)
        
        # Update trust score from vote
        updated_trust_score = self.trust_service.update_signal_trust_from_vote(
            signal_id=str(signal.id),
            is_true_vote=is_true
        )
        
        # Update status based on new votes
        self.update_status_from_votes(signal)
        
        self.db.commit()
        self.db.refresh(signal)
        
        return True, "", updated_trust_score
    
    def remove_vote(self, signal: SafetySignal, user_id: UUID) -> Tuple[bool, str, float]:
        """
        Remove a user's vote from a report.
        
        Returns:
            Tuple of (success, error_message, updated_trust_score)
        """
        # Find the vote
        vote = self.db.query(ReportVerification).filter(
            and_(
                ReportVerification.signal_id == signal.id,
                ReportVerification.user_id == user_id
            )
        ).first()
        
        if not vote:
            return False, "Vote not found", signal.trust_score
        
        was_true = vote.is_true
        
        # Revert vote counts
        if was_true:
            signal.true_votes = max(0, (signal.true_votes or 0) - 1)
        else:
            signal.false_votes = max(0, (signal.false_votes or 0) - 1)
        
        # Delete the vote
        self.db.delete(vote)
        
        # Update trust score
        updated_trust_score = self.trust_service.revert_vote_from_signal(
            signal_id=str(signal.id),
            was_true_vote=was_true
        )
        
        # Update confidence
        signal.confidence_score = self.calculate_confidence(
            signal, 
            signal.true_votes or 0, 
            signal.false_votes or 0
        )
        
        # Revert status if needed (pending only)
        if signal.status in [ReportStatus.verified, ReportStatus.disputed]:
            if signal.true_votes + signal.false_votes < MIN_VOTES_FOR_STATUS_UPDATE:
                signal.status = ReportStatus.pending
                signal.verified_at = None
                signal.disputed_at = None
        
        signal.last_activity_at = datetime.now(timezone.utc)
        
        self.db.commit()
        self.db.refresh(signal)
        
        return True, "", updated_trust_score
    
    # ============ Delete Operations ============
    
    def get_delete_cooldown_expires_at(self) -> datetime:
        """Get when the user's delete cooldown expires."""
        return datetime.now(timezone.utc) + timedelta(hours=DELETE_COOLDOWN_HOURS)
    
    def check_delete_permission(
        self, 
        signal: SafetySignal, 
        user_id: UUID
    ) -> Tuple[bool, str]:
        """
        Check if a user can delete a report.
        
        Returns:
            Tuple of (can_delete, reason_if_no)
        """
        # Check ownership
        if signal.user_id != user_id:
            return False, "Only the report owner can delete this report"
        
        # Cannot delete verified reports with high confidence
        if signal.status == ReportStatus.verified and signal.confidence_score >= 0.7:
            return False, "Verified reports with high community confidence cannot be deleted"
        
        # Check delete cooldown
        if signal.delete_cooldown_expires_at:
            if datetime.now(timezone.utc) < signal.delete_cooldown_expires_at:
                remaining = int((signal.delete_cooldown_expires_at - datetime.now(timezone.utc)).total_seconds())
                minutes_left = remaining // 60
                return False, f"Please wait {minutes_left} minutes before deleting another report"
        
        return True, ""
    
    def soft_delete_report(
        self,
        signal: SafetySignal,
        user_id: UUID,
        reason: Optional[str] = None
    ) -> Tuple[bool, str]:
        """
        Soft delete a report (marks as deleted, preserves audit trail).
        
        Returns:
            Tuple of (success, error_message)
        """
        # Check permissions
        can_delete, reason_msg = self.check_delete_permission(signal, user_id)
        if not can_delete:
            return False, reason_msg
        
        # Mark as deleted
        signal.status = ReportStatus.deleted
        signal.is_valid = False
        signal.deleted_by_owner = True
        signal.delete_reason = reason
        signal.delete_cooldown_expires_at = self.get_delete_cooldown_expires_at()
        signal.last_activity_at = datetime.now(timezone.utc)
        
        self.db.commit()
        
        return True, ""
    
    # ============ Abuse Detection ============
    
    def check_abuse_flags(
        self, 
        signal: SafetySignal, 
        device_hash: str
    ) -> Dict[str, Any]:
        """
        Check and update abuse flags for a report/device.
        
        Returns:
            Dictionary with abuse detection results
        """
        result = {
            "is_suspicious": False,
            "reasons": [],
            "action_taken": None
        }
        
        # Check for rapid submission
        device_activity = self.db.query(DeviceActivity).filter(
            DeviceActivity.device_hash == device_hash
        ).first()
        
        if device_activity:
            # Check submission rate
            if device_activity.submission_count > 20:
                result["is_suspicious"] = True
                result["reasons"].append("High submission rate")
            
            # Check anomaly score
            if device_activity.anomaly_score > 0.7:
                result["is_suspicious"] = True
                result["reasons"].append("High anomaly score")
        
        # Update abuse flags if suspicious
        if result["is_suspicious"]:
            if signal.abuse_flags is None:
                signal.abuse_flags = {}
            
            signal.abuse_flags["detected_at"] = datetime.now(timezone.utc).isoformat()
            signal.abuse_flags["reasons"] = result["reasons"]
            
            # Apply trust penalty for suspicious reports
            signal.trust_score = max(0.2, signal.trust_score * 0.8)
            result["action_taken"] = "trust_penalty_applied"
            
            self.db.commit()
        
        return result
    
    # ============ Report Creation ============
    
    def create_report(
        self,
        signal_type: str,
        severity: int,
        latitude: float,
        longitude: float,
        geohash: str,
        device_hash: str,
        user_id: Optional[UUID],
        context_tags: Optional[Dict[str, Any]],
        trust_score: float
    ) -> SafetySignal:
        """
        Create a new safety report with proper initialization.
        """
        signal = SafetySignal(
            signal_type=signal_type,
            severity=severity,
            latitude=latitude,
            longitude=longitude,
            geohash=geohash,
            device_hash=device_hash,
            user_id=user_id,
            context_tags=context_tags,
            trust_score=trust_score,
            is_valid=True,
            status=ReportStatus.pending,
            vote_window_expires_at=self.get_vote_window_expires_at(),
            expires_at=datetime.now(timezone.utc) + timedelta(hours=EXPIRATION_HOURS),
            confidence_score=0.5,
            severity_weight=severity / 5.0
        )
        
        self.db.add(signal)
        self.db.commit()
        self.db.refresh(signal)
        
        return signal
    
    # ============ Query Helpers ============
    
    def get_active_reports_for_status_update(self) -> list:
        """
        Get all reports that need status updates based on votes.
        
        Returns reports that:
        - Are in pending status
        - Have received votes since last status update
        - Are within vote window
        """
        cutoff_time = datetime.now(timezone.utc) - timedelta(hours=VOTE_WINDOW_HOURS)
        
        return self.db.query(SafetySignal).filter(
            and_(
                SafetySignal.status == ReportStatus.pending,
                SafetySignal.timestamp > cutoff_time,
                SafetySignal.is_valid == True,
                SafetySignal.vote_window_expires_at > datetime.now(timezone.utc)
            )
        ).all()
    
    def get_reports_for_expiration(self) -> list:
        """
        Get reports that should be expired.
        
        Returns reports that:
        - Have expired vote windows
        - Have explicit expiration times in the past
        """
        now = datetime.now(timezone.utc)
        
        # Expire reports with closed vote windows
        window_expired = self.db.query(SafetySignal).filter(
            and_(
                SafetySignal.status == ReportStatus.pending,
                SafetySignal.vote_window_expires_at < now,
                SafetySignal.is_valid == True
            )
        ).all()
        
        # Expire reports past their explicit expiration
        explicit_expired = self.db.query(SafetySignal).filter(
            and_(
                SafetySignal.expires_at != None,
                SafetySignal.expires_at < now,
                SafetySignal.status != ReportStatus.deleted,
                SafetySignal.is_valid == True
            )
        ).all()
        
        # Combine unique reports
        all_expired = list(set(window_expired + explicit_expired))
        return all_expired
    
    def expire_reports_batch(self) -> Dict[str, int]:
        """
        Batch expire reports that have passed their expiration time.
        
        Returns:
            Dictionary with count of expired reports
        """
        reports_to_expire = self.get_reports_for_expiration()
        
        expired_count = 0
        for signal in reports_to_expire:
            if self.check_and_expire_report(signal):
                expired_count += 1
        
        if expired_count > 0:
            self.db.commit()
        
        return {"expired_reports": expired_count}
    
    def update_status_batch(self) -> Dict[str, int]:
        """
        Batch update report statuses based on votes.
        
        Returns:
            Dictionary with counts of status updates
        """
        reports_to_update = self.get_active_reports_for_status_update()
        
        verified_count = 0
        disputed_count = 0
        
        for signal in reports_to_update:
            old_status = signal.status
            new_status = self.update_status_from_votes(signal)
            
            if old_status != new_status:
                if new_status == ReportStatus.verified:
                    verified_count += 1
                elif new_status == ReportStatus.disputed:
                    disputed_count += 1
        
        if verified_count > 0 or disputed_count > 0:
            self.db.commit()
        
        return {
            "verified_reports": verified_count,
            "disputed_reports": disputed_count
        }

