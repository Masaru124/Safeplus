from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, Enum, JSON
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.sql import func
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
    context_tags = Column(JSON, nullable=True)
    trust_score = Column(Float, nullable=False)
    is_valid = Column(Boolean, default=True)

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
