"""
Intelligence API Routes for Safety Pulse

These routes provide:
- Smart scoring endpoints
- Pattern detection endpoints
- Risk zone analysis
- Personalized alerts
"""

from fastapi import APIRouter, HTTPException, Depends, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from datetime import datetime

from app.database import get_db
from app.schemas import (
    SmartScoreResponse, TileSafetyScore, RiskZoneSummary, TimeOfDayRisk,
    PatternAnalysisResponse, PersonalizedAlert,
    SpikeDetection, ClusterDetection
)
from app.services.smart_scoring import SmartScoringService, SpikeDetectionService
from app.services.pattern_detection import PatternDetectionService
from app.dependencies import get_current_user, JWTUser
from app.models import SafetySignal

router = APIRouter()

# ============ Smart Scoring Endpoints ============

@router.get("/intelligence/score/{signal_id}")
async def get_smart_score(
    signal_id: str,
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get the intelligent safety score for a specific report.
    
    The smart score considers:
    - Community verification (votes)
    - Recency (recent reports matter more)
    - Time of day (night hours = higher risk)
    - Report age (decay over time)
    - Severity weighting
    """
    import uuid
    
    try:
        signal_uuid = uuid.UUID(signal_id)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid signal ID format")
    
    signal = db.query(SafetySignal).filter(SafetySignal.id == signal_uuid).first()
    if not signal:
        raise HTTPException(status_code=404, detail="Signal not found")
    
    scoring_service = SmartScoringService(db)
    smart_score = scoring_service.calculate_smart_score(signal)
    
    # Calculate individual components for transparency
    # Vote contribution
    if signal.true_votes and signal.false_votes:
        total = signal.true_votes + signal.false_votes
        vote_contribution = 0.5 * (1 - min(0.4, total / 10 * 0.4)) + (signal.true_votes / total) * min(0.4, total / 10 * 0.4)
    else:
        vote_contribution = 0.5
    
    # Recency weight
    age_hours = (datetime.utcnow() - signal.timestamp).total_seconds() / 3600
    if age_hours < 24:
        recency_weight = 1.0 - (age_hours / 24) * 0.3
    else:
        recency_weight = 0.7
    
    # Time of day risk
    current_hour = datetime.utcnow().hour
    is_night = current_hour >= 22 or current_hour < 6
    time_risk_boost = 0.15 if is_night else 0.0
    
    # Age decay
    age_decay = 1.0
    decay_half_life = 72  # hours
    age_decay = 2.71828 ** (-age_hours / decay_half_life)
    
    # Severity factor
    severity_factor = signal.severity / 5.0
    
    return SmartScoreResponse(
        signal_id=signal.id,
        smart_score=smart_score,
        base_trust_score=signal.trust_score,
        vote_contribution=vote_contribution,
        recency_weight=recency_weight,
        time_risk_boost=time_risk_boost,
        age_decay_factor=age_decay,
        severity_factor=severity_factor
    )


@router.get("/intelligence/tile-score/{tile_id}")
async def get_tile_safety_score(
    tile_id: str,
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get the safety score for a specific geographic tile.
    """
    import pygeohash as pgh
    
    # Decode geohash to get center coordinates
    try:
        coords = pgh.decode(tile_id)
        center_lat = coords[0]
        center_lon = coords[1]
    except Exception:
        raise HTTPException(status_code=400, detail="Invalid geohash format")
    
    # Get signals in this tile
    signals = db.query(SafetySignal).filter(
        SafetySignal.geohash == tile_id,
        SafetySignal.is_valid == True
    ).all()
    
    scoring_service = SmartScoringService(db)
    tile_score = scoring_service.calculate_tile_safety_score(tile_id, signals)
    
    return TileSafetyScore(
        tile_id=tile_score["tile_id"],
        safety_score=tile_score["safety_score"],
        risk_level=tile_score["risk_level"],
        confidence=tile_score["confidence"],
        signal_count=tile_score["signal_count"],
        is_spike=tile_score["is_spike"],
        spike_message=tile_score["spike_message"]
    )


@router.get("/intelligence/risk-zones", response_model=RiskZoneSummary)
async def get_risk_zones(
    lat: float = Query(..., description="Center latitude"),
    lng: float = Query(..., description="Center longitude"),
    radius: float = Query(10.0, description="Radius in kilometers", le=100),
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get a summary of risk zones in an area.
    
    Returns all detected risk zones with their safety scores.
    """
    if not -90 <= lat <= 90:
        raise HTTPException(status_code=400, detail="Invalid latitude")
    if not -180 <= lng <= 180:
        raise HTTPException(status_code=400, detail="Invalid longitude")
    
    scoring_service = SmartScoringService(db)
    summary = scoring_service.get_risk_zone_summary(lat, lng, radius)
    
    return RiskZoneSummary(**summary)


@router.get("/intelligence/time-risk", response_model=TimeOfDayRisk)
async def get_time_of_day_risk(
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get the current time-based risk assessment.
    
    Returns risk information based on the current time of day.
    Night hours (10 PM - 6 AM) have elevated risk scores.
    """
    scoring_service = SmartScoringService(db)
    return TimeOfDayRisk(**scoring_service.get_time_of_day_risk())


# ============ Pattern Detection Endpoints ============

@router.get("/intelligence/patterns", response_model=PatternAnalysisResponse)
async def get_pattern_analysis(
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get comprehensive pattern analysis for the current data.
    
    Returns:
    - Spikes: Areas with unusually high report counts
    - Clusters: Groups of related safety reports
    - Anomalies: Detected suspicious patterns
    - Risk Zones: Areas with elevated risk scores
    """
    pattern_service = PatternDetectionService(db)
    results = pattern_service.run_full_pattern_analysis()
    
    # Convert to response format
    return PatternAnalysisResponse(
        analyzed_at=results["analyzed_at"],
        spikes=[SpikeDetection(**s) for s in results["spikes"]],
        clusters=[ClusterDetection(**c) for c in results["clusters"]],
        anomalies=results["anomalies"],
        risk_zones=results["risk_zones"]
    )


@router.get("/intelligence/spikes")
async def get_spikes(
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get detected spikes in the system.
    
    A spike is defined as 10+ reports in a 30-minute window.
    """
    spike_service = SpikeDetectionService(db)
    spikes = spike_service.detect_spikes()
    
    return {
        "spikes": spikes,
        "count": len(spikes),
        "detected_at": datetime.utcnow().isoformat()
    }


@router.get("/intelligence/clusters")
async def get_clusters(
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get detected clusters of safety reports.
    
    Clusters are groups of 2+ reports in the same geographic area.
    """
    pattern_service = PatternDetectionService(db)
    clusters = pattern_service.detect_clusters()
    
    return {
        "clusters": clusters,
        "count": len(clusters),
        "detected_at": datetime.utcnow().isoformat()
    }


@router.get("/intelligence/anomalies")
async def get_anomalies(
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get detected anomalies in the system.
    
    Types of anomalies:
    - Spam devices: Devices submitting too many reports
    - Rapid reports: Unusually fast report sequences
    - Low trust patterns: Devices with consistently low trust scores
    """
    pattern_service = PatternDetectionService(db)
    anomalies = pattern_service.detect_anomalies()
    
    return {
        "anomalies": anomalies,
        "detected_at": datetime.utcnow().isoformat()
    }


# ============ Personalized Alert Endpoints ============

@router.get("/intelligence/alert", response_model=PersonalizedAlert)
async def get_personalized_alert(
    lat: float = Query(..., description="Latitude"),
    lng: float = Query(..., description="Longitude"),
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get a personalized safety alert for a specific location.
    
    This combines location risk, time of day, and spike detection
    to provide intelligent safety advice.
    """
    if not -90 <= lat <= 90:
        raise HTTPException(status_code=400, detail="Invalid latitude")
    if not -180 <= lng <= 180:
        raise HTTPException(status_code=400, detail="Invalid longitude")
    
    pattern_service = PatternDetectionService(db)
    alert = pattern_service.get_personalized_alert(
        lat, lng, datetime.utcnow().hour
    )
    
    return PersonalizedAlert(**alert)

