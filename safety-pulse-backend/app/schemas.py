from pydantic import BaseModel, Field, EmailStr, field_serializer
from typing import Dict, Any, List, Optional
from uuid import UUID
from datetime import datetime
from enum import Enum

# ============ User Schemas ============

class UserCreate(BaseModel):
    """Schema for user registration"""
    email: EmailStr = Field(..., description="User email address")
    username: str = Field(..., min_length=3, max_length=100, description="Username")
    password: str = Field(..., min_length=6, max_length=72, description="Password (6-72 characters)")

class UserLogin(BaseModel):
    """Schema for user login"""
    email: EmailStr = Field(..., description="User email address")
    password: str = Field(..., description="User password")

class UserResponse(BaseModel):
    """Schema for user response"""
    id: UUID
    email: str
    username: str
    is_active: bool
    trust_score: float = 0.5
    reports_confirmed: int = 0
    reports_flagged: int = 0
    created_at: datetime

    class Config:
        from_attributes = True

class Token(BaseModel):
    """Schema for JWT token response"""
    access_token: str
    token_type: str = "bearer"
    user: UserResponse

class TokenData(BaseModel):
    """Schema for token payload"""
    user_id: Optional[UUID] = None
    email: Optional[str] = None

# ============ Report Schemas ============

class ReportRequest(BaseModel):
    signal_type: str = Field(..., description="Type of safety signal")
    severity: int = Field(..., ge=1, le=5, description="Severity level 1-5")
    latitude: float = Field(..., ge=-90, le=90, description="Latitude")
    longitude: float = Field(..., ge=-180, le=180, description="Longitude")
    context: Dict[str, Any] = Field(default_factory=dict, description="Additional context")

class ReportResponse(BaseModel):
    message: str
    signal_id: UUID
    trust_score: float

class ReportItem(BaseModel):
    id: UUID
    signal_type: str
    severity: int
    latitude: float
    longitude: float
    created_at: datetime
    trust_score: float
    user_id: Optional[UUID] = None
    reporter_username: Optional[str] = None
    true_votes: int = 0
    false_votes: int = 0
    user_vote: Optional[bool] = None
    
    # New fields for enhanced tracking
    severity_weight: float = 0.5
    confidence_score: float = 0.5
    last_activity_at: Optional[datetime] = None
    expires_at: Optional[datetime] = None

    class Config:
        from_attributes = True
    
    @field_serializer('created_at')
    @classmethod
    def serialize_datetime(cls, v: datetime) -> str:
        return v.isoformat()
    
    @field_serializer('last_activity_at')
    @classmethod
    def serialize_last_activity(cls, v: Optional[datetime]) -> Optional[str]:
        return v.isoformat() if v else None
    
    @field_serializer('expires_at')
    @classmethod
    def serialize_expires(cls, v: Optional[datetime]) -> Optional[str]:
        return v.isoformat() if v else None

class ReportListResponse(BaseModel):
    reports: List[ReportItem]

# ============ Vote Schemas ============

class VoteRequest(BaseModel):
    is_true: bool = Field(..., description="True if report is accurate")

class VoteResponse(BaseModel):
    message: str
    signal_id: UUID
    is_true: bool
    new_true_votes: int
    new_false_votes: int
    updated_trust_score: float

class VoteSummary(BaseModel):
    signal_id: UUID
    true_votes: int
    false_votes: int
    total_votes: int
    trust_ratio: float
    trust_score: float

class VoteCheckResponse(BaseModel):
    has_voted: bool
    is_true: Optional[bool] = None

# ============ Delete Report Schema ============

class DeleteReportResponse(BaseModel):
    message: str
    deleted_signal_id: UUID
    deleted_at: datetime

    class Config:
        from_attributes = True
    
    @field_serializer('deleted_at')
    @classmethod
    def serialize_datetime(cls, v: datetime) -> str:
        return v.isoformat()

# ============ Pulse Schemas ============

class PulseTileResponse(BaseModel):
    tile_id: str
    pulse_score: int
    confidence: str

class PulseResponse(BaseModel):
    tiles: List[PulseTileResponse]

# New schema for /pulses/active endpoint - single source of truth for map
class PulseActiveResponse(BaseModel):
    """Response for GET /pulses/active - single source of truth for map rendering"""
    lat: float
    lng: float
    radius: int
    intensity: float
    confidence: str
    dominant_reason: Optional[str] = None
    last_updated: datetime

    class Config:
        from_attributes = True
    
    @field_serializer('last_updated')
    @classmethod
    def serialize_datetime(cls, v: datetime) -> str:
        return v.isoformat()

class PulseActiveListResponse(BaseModel):
    """Response containing all active pulses for map rendering"""
    pulses: List[PulseActiveResponse]
    count: int
    generated_at: str

# ============ Health Schemas ============

class HealthResponse(BaseModel):
    status: str
    timestamp: datetime
    version: str

class MetricsResponse(BaseModel):
    total_signals: int
    active_tiles: int
    avg_trust_score: float
    uptime_seconds: float

# ============ Smart Scoring Schemas ============

class SmartScoreResponse(BaseModel):
    signal_id: UUID
    smart_score: float
    base_trust_score: float
    vote_contribution: float
    recency_weight: float
    time_risk_boost: float
    age_decay_factor: float
    severity_factor: float

class TileSafetyScore(BaseModel):
    tile_id: str
    safety_score: float
    risk_level: str
    confidence: str
    signal_count: int
    is_spike: bool
    spike_message: Optional[str] = None

class RiskZoneSummary(BaseModel):
    center_lat: float
    center_lon: float
    radius_km: float
    total_signals: int
    risk_zone_count: int
    overall_risk_score: float
    risk_zones: List[Dict[str, Any]]
    time_risk: Dict[str, Any]

class TimeOfDayRisk(BaseModel):
    current_hour: int
    is_night: bool
    risk_multiplier: float
    risk_level: str

# ============ Pattern Detection Schemas ============

class SpikeDetection(BaseModel):
    id: str
    geohash: str
    latitude: float
    longitude: float
    report_count: int
    spike_intensity: float
    time_window_minutes: int
    actual_time_range_minutes: float
    severity_breakdown: Dict[int, int]
    signal_types: List[str]
    detected_at: str
    message: str

class ClusterDetection(BaseModel):
    id: str
    geohash: str
    latitude: float
    longitude: float
    report_count: int
    avg_severity: float
    avg_trust_score: float
    intensity: float
    signal_types: List[str]
    detected_at: str

class PatternAnalysisResponse(BaseModel):
    analyzed_at: str
    spikes: List[SpikeDetection]
    clusters: List[ClusterDetection]
    anomalies: Dict[str, List[Dict[str, Any]]]
    risk_zones: Dict[str, Any]

# ============ Personalized Alert Schemas ============

class PersonalizedAlert(BaseModel):
    alert_level: str
    risk_score: float
    location_risk: float
    time_risk: float
    spike_risk: float
    nearby_reports: int
    is_night: bool
    message: str

# ============ Real-Time Schemas ============

class RealtimeEventResponse(BaseModel):
    event_type: str
    data: Dict[str, Any]
    timestamp: str

class PollingResponse(BaseModel):
    new_reports: List[Dict[str, Any]]
    pulse_updates: List[Dict[str, Any]]
    spikes: List[Dict[str, Any]]
    server_time: str

class PulseDeltaResponse(BaseModel):
    tiles: List[Dict[str, Any]]
    version: int
    has_updates: bool
    updated_at: str

# ============ SafetyPattern Schemas ============

class SafetyPatternResponse(BaseModel):
    """Schema for SafetyPattern response"""
    id: str
    pattern_type: str  # cluster, hotspot, coldspot, trend
    geohash: str
    latitude: float
    longitude: float
    intensity: float
    report_count: int
    avg_severity: float = 0.0
    avg_confidence: float = 0.5
    dominant_reason: Optional[str] = None
    radius_m: float = 500.0
    confidence_level: str
    created_at: datetime
    expires_at: Optional[datetime] = None

    class Config:
        from_attributes = True
    
    @field_serializer('created_at')
    @classmethod
    def serialize_datetime(cls, v: datetime) -> str:
        return v.isoformat()
    
    @field_serializer('expires_at')
    @classmethod
    def serialize_expires(cls, v: Optional[datetime]) -> Optional[str]:
        return v.isoformat() if v else None

class ConfidenceLevelEnum(str, Enum):
    low = "low"
    medium = "medium"
    high = "high"

class SafetyPatternCreate(BaseModel):
    """Schema for creating a SafetyPattern"""
    pattern_type: str
    geohash: str
    latitude: float
    longitude: float
    intensity: float
    report_count: int = 1
    avg_severity: float = 0.0
    avg_confidence: float = 0.5
    dominant_reason: Optional[str] = None
    radius_m: float = 500.0
    confidence_level: ConfidenceLevelEnum
    expires_at: Optional[datetime] = None

class SafetyPatternListResponse(BaseModel):
    """Response for listing safety patterns"""
    patterns: List[SafetyPatternResponse]
    count: int
    analyzed_at: str

