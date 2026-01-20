from pydantic import BaseModel, Field, EmailStr, field_serializer
from typing import Dict, Any, List, Optional
from uuid import UUID
from datetime import datetime

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
    user_id: Optional[UUID] = None  # Include reporter info
    reporter_username: Optional[str] = None  # Username of reporter
    # Vote counts for trust score
    true_votes: int = 0
    false_votes: int = 0
    # User's vote on this report (if any)
    user_vote: Optional[bool] = None

    class Config:
        from_attributes = True
    
    @field_serializer('created_at')
    @classmethod
    def serialize_datetime(cls, v: datetime) -> str:
        """Serialize datetime as ISO string"""
        return v.isoformat()

class ReportListResponse(BaseModel):
    reports: List[ReportItem]

# ============ Vote Schemas ============

class VoteRequest(BaseModel):
    """Schema for voting on a report"""
    is_true: bool = Field(..., description="True if report is accurate, False if false report")

class VoteResponse(BaseModel):
    """Response after voting on a report"""
    message: str
    signal_id: UUID
    is_true: bool
    new_true_votes: int
    new_false_votes: int
    updated_trust_score: float

class VoteSummary(BaseModel):
    """Summary of votes on a report"""
    signal_id: UUID
    true_votes: int
    false_votes: int
    total_votes: int
    trust_ratio: float  # true_votes / total_votes
    trust_score: float

class VoteCheckResponse(BaseModel):
    """Response to check if user has voted"""
    has_voted: bool
    is_true: Optional[bool] = None  # The user's vote if they have voted

# ============ Delete Report Schema ============

class DeleteReportResponse(BaseModel):
    """Response after deleting a report"""
    message: str
    deleted_signal_id: UUID
    deleted_at: datetime

    class Config:
        from_attributes = True
    
    @field_serializer('deleted_at')
    @classmethod
    def serialize_datetime(cls, v: datetime) -> str:
        """Serialize datetime as ISO string"""
        return v.isoformat()

# ============ Pulse Schemas ============

class PulseTileResponse(BaseModel):
    tile_id: str
    pulse_score: int
    confidence: str

class PulseResponse(BaseModel):
    tiles: List[PulseTileResponse]

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
