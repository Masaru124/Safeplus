from pydantic import BaseModel, Field
from typing import Dict, Any, List
from uuid import UUID
from datetime import datetime

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

class PulseTileResponse(BaseModel):
    tile_id: str
    pulse_score: int
    confidence: str

class PulseResponse(BaseModel):
    tiles: List[PulseTileResponse]

class HealthResponse(BaseModel):
    status: str
    timestamp: datetime
    version: str

class MetricsResponse(BaseModel):
    total_signals: int
    active_tiles: int
    avg_trust_score: float
    uptime_seconds: float

class ReportItem(BaseModel):
    id: UUID
    signal_type: str
    severity: int
    latitude: float
    longitude: float
    created_at: datetime
    trust_score: float

class ReportListResponse(BaseModel):
    reports: List[ReportItem]
