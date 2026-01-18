from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from sqlalchemy import func
from app.database import get_db
from app.models import SafetySignal, PulseTile, DeviceActivity
from app.schemas import HealthResponse, MetricsResponse
from datetime import datetime

router = APIRouter()

@router.get("/health", response_model=HealthResponse)
async def health_check():
    """Health check endpoint"""
    return HealthResponse(
        status="healthy",
        timestamp=datetime.utcnow(),
        version="1.0.0"
    )

@router.get("/metrics", response_model=MetricsResponse)
async def get_metrics(db: Session = Depends(get_db)):
    """System metrics endpoint"""
    total_signals = db.query(func.count(SafetySignal.id)).scalar()
    active_tiles = db.query(func.count(PulseTile.tile_id)).scalar()
    avg_trust_score = db.query(func.avg(SafetySignal.trust_score)).scalar() or 0.0

    # Calculate uptime (simplified - in production use proper tracking)
    uptime_seconds = 3600  # Placeholder - would track actual uptime

    return MetricsResponse(
        total_signals=total_signals,
        active_tiles=active_tiles,
        avg_trust_score=round(avg_trust_score, 2),
        uptime_seconds=uptime_seconds
    )
