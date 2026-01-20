from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, Enum, JSON, ForeignKey
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
from sqlalchemy.orm import relationship
import enum
import uuid

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

class User(Base):
    __tablename__ = "users"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    email = Column(String(255), unique=True, nullable=False, index=True)
    username = Column(String(100), unique=True, nullable=False, index=True)
    hashed_password = Column(String(255), nullable=False)
    is_active = Column(Boolean, default=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())

class SafetySignal(Base):
    __tablename__ = "safety_signals"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    signal_type = Column(Enum(SignalType), nullable=False)
    severity = Column(Integer, nullable=False)  # 1-5
    latitude = Column(Float, nullable=False)
    longitude = Column(Float, nullable=False)
    geohash = Column(String, nullable=False)
    timestamp = Column(DateTime(timezone=True), server_default=func.now())
    device_hash = Column(String, nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=True)  # Link to authenticated user
    context_tags = Column(JSON, nullable=True)
    trust_score = Column(Float, nullable=False)
    is_valid = Column(Boolean, default=True)
    # Vote tracking for trust score calculation
    true_votes = Column(Integer, default=0)
    false_votes = Column(Integer, default=0)
    # Relationships
    verifications = relationship("ReportVerification", back_populates="signal", lazy="dynamic")

class ReportVerification(Base):
    __tablename__ = "report_verifications"

    id = Column(UUID(as_uuid=True), primary_key=True, default=uuid.uuid4)
    signal_id = Column(UUID(as_uuid=True), ForeignKey("safety_signals.id"), nullable=False)
    user_id = Column(UUID(as_uuid=True), ForeignKey("users.id"), nullable=False)
    is_true = Column(Boolean, nullable=False)  # True = report is accurate, False = report is false
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    
    # Relationships
    signal = relationship("SafetySignal", back_populates="verifications")
    user = relationship("User")

class PulseTile(Base):
    __tablename__ = "pulse_tiles"

    tile_id = Column(String, primary_key=True)
    pulse_score = Column(Integer, nullable=False)  # 0-100
    confidence_level = Column(Enum(ConfidenceLevel), nullable=False)
    last_updated = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    signal_count = Column(Integer, default=0)

class DeviceActivity(Base):
    __tablename__ = "device_activity"

    device_hash = Column(String, primary_key=True)
    submission_count = Column(Integer, default=0)
    last_submission = Column(DateTime(timezone=True), server_default=func.now(), onupdate=func.now())
    anomaly_score = Column(Float, default=0.0)

