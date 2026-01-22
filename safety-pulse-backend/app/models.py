from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, Enum, JSON, ForeignKey, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
import enum
import uuid
from datetime import datetime

from app.database import Base

class SignalType(enum.Enum):
    followed = "followed"
    suspicious_activity = "suspicious_activity"
    unsafe_area = "unsafe_area"
    harassment = "harassment"
    other = "other"

class ConfidenceLevel(enum.Enum):
    low = "low"
    medium = "medium"
    high = "high"

class ReportStatus(enum.Enum):
    """
    Report lifecycle status.
    
    Status transitions:
    - pending -> verified (when confidence > VERIFY_THRESHOLD)
    - pending -> disputed (when downvotes > DISPUTE_THRESHOLD)
    - pending -> expired (after expiration time)
    - verified -> expired (after expiration time)
    - disputed -> expired (after expiration time)
    - Any status -> deleted (soft delete by owner or admin)
    """
    pending = "pending"
    verified = "verified"
    disputed = "disputed"
    expired = "expired"
    deleted = "deleted"

class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(String(255), unique=True, nullable=False, index=True)
    username = Column(String(100), unique=True, nullable=False, index=True)
    hashed_password = Column(String(255), nullable=False)
    is_active = Column(Boolean, default=True)
    
    # Trust and reputation fields
    trust_score = Column(Float, nullable=False, default=0.5)
    reports_confirmed = Column(Integer, default=0)
    reports_flagged = Column(Integer, default=0)
    
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

class SafetySignal(Base):
    __tablename__ = "safety_signals"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    signal_type = Column(Enum(SignalType), nullable=False)
    severity = Column(Integer, nullable=False)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    geohash = Column(String, nullable=False)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())
    device_hash = Column(String, nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)
    context_tags = Column(JSON, nullable=True)
    trust_score = Column(Float, nullable=False)
    is_valid = Column(Boolean, default=True)
    true_votes = Column(Integer, default=0)
    false_votes = Column(Integer, default=0)
    verifications = relationship("ReportVerification", back_populates="signal", lazy="dynamic")
    
    # ============ Status Lifecycle Fields ============
    # status: Report lifecycle status (pending/verified/disputed/expired/deleted)
    status = Column(Enum(ReportStatus), nullable=False, default=ReportStatus.pending)
    
    # ============ Enhanced Tracking Fields ============
    # severity_weight: Derived weight based on report type and severity
    severity_weight = Column(Float, nullable=False, default=0.5)
    
    # confidence_score: Derived from community verification (0.0-1.0)
    confidence_score = Column(Float, nullable=False, default=0.5)
    
    # last_activity_at: Updated when votes or edits occur
    last_activity_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    
    # expires_at: When this signal should expire (24h from creation by default)
    expires_at = Column(DateTime(timezone=True), nullable=True)
    
    # ============ Abuse & Integrity Fields ============
    # abuse_flags: Internal flags for tracking abusive behavior
    abuse_flags = Column(JSON, nullable=True)
    
    # deleted_by_owner: True if deleted by the report owner (vs auto-removed)
    deleted_by_owner = Column(Boolean, default=False)
    
    # delete_reason: Reason provided for deletion (if any)
    delete_reason = Column(Text, nullable=True)
    
    # delete_cooldown_expires_at: When user can delete another report
    delete_cooldown_expires_at = Column(DateTime(timezone=True), nullable=True)
    
    # vote_window_expires_at: When voting window closes for this report
    vote_window_expires_at = Column(DateTime(timezone=True), nullable=True)
    
    # verified_at: When report was verified
    verified_at = Column(DateTime(timezone=True), nullable=True)
    
    # disputed_at: When report was disputed
    disputed_at = Column(DateTime(timezone=True), nullable=True)
    
    # Helper methods for status transitions
    def can_accept_votes(self) -> bool:
        """Check if this report can still accept votes."""
        if self.status in [ReportStatus.deleted, ReportStatus.expired]:
            return False
        if self.vote_window_expires_at and datetime.utcnow() > self.vote_window_expires_at:
            return False
        return True
    
    def can_be_deleted_by(self, user_id: UUID) -> bool:
        """Check if this report can be deleted by the given user."""
        # Only owner can delete
        if self.user_id != user_id:
            return False
        # Cannot delete verified reports with high confidence
        if self.status == ReportStatus.verified and self.confidence_score >= 0.7:
            return False
        # Check delete cooldown
        if self.delete_cooldown_expires_at and datetime.utcnow() < self.delete_cooldown_expires_at:
            return False
        return True
    
    def is_owned_by(self, user_id: UUID) -> bool:
        """Check if the report is owned by the given user."""
        return self.user_id == user_id

class ReportVerification(Base):
    __tablename__ = "report_verifications"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    signal_id = Column(UUID(as_uuid=True), ForeignKey("safety_signals.id"), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    is_true = Column(Boolean, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    signal = relationship("SafetySignal", back_populates="verifications")
    user = relationship("User")

class PulseTile(Base):
    __tablename__ = "pulse_tiles"

    tile_id = Column(String, primary_key=True)
    center_lat = Column(Float, nullable=False)
    center_lng = Column(Float, nullable=False)
    intensity = Column(Float, nullable=False, default=0.0)  # 0.0-1.0
    radius = Column(Integer, nullable=False, default=200)  # meters
    confidence_level = Column(Enum(ConfidenceLevel), nullable=False)
    dominant_reason = Column(String, nullable=True)  # e.g., "Followed", "Harassment"
    last_updated = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    signal_count = Column(Integer, default=0)
    expires_at = Column(DateTime(timezone=True), nullable=True)

class DeviceActivity(Base):
    __tablename__ = "device_activity"

    device_hash = Column(String, primary_key=True)
    submission_count = Column(Integer, default=0)
    last_submission = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    anomaly_score = Column(Float, default=0.0)

# New Tables for AI/Pattern Detection

class SafetyPattern(Base):
    __tablename__ = "safety_patterns"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    pattern_type = Column(String, nullable=False)  # cluster, hotspot, coldspot, trend
    geohash = Column(String, nullable=False, index=True)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    intensity = Column(Float, nullable=False)  # 0.0-1.0
    report_count = Column(Integer, default=1)
    avg_severity = Column(Float, default=0.0)
    avg_confidence = Column(Float, default=0.5)
    dominant_reason = Column(String, nullable=True)
    radius_m = Column(Float, default=500.0)  # Cluster radius in meters
    confidence_level = Column(Enum(ConfidenceLevel), nullable=False)
    extra_data = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True), nullable=True)

    def is_expired(self):
        if self.expires_at:
            return datetime.utcnow() > self.expires_at
        return False

class AnomalyAlert(Base):
    __tablename__ = "anomaly_alerts"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    alert_type = Column(String, nullable=False)
    geohash = Column(String, nullable=False, index=True)
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    severity = Column(Float, nullable=False)
    message = Column(String, nullable=True)
    extra_data = Column(JSON, nullable=True)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    expires_at = Column(DateTime(timezone=True), nullable=True)

class RealtimeEvent(Base):
    __tablename__ = "realtime_events"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    event_type = Column(String, nullable=False)
    geohash = Column(String, nullable=True, index=True)
    data = Column(JSON, nullable=False)
    is_broadcast = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())

from datetime import datetime

