from fastapi import APIRouter, HTTPException, Depends, BackgroundTasks, status, Query
from sqlalchemy.orm import Session
from sqlalchemy import desc, and_
from app.database import get_db
from app.schemas import (
    ReportRequest, ReportResponse, ReportListResponse, ReportItem,
    VoteRequest, VoteResponse, VoteSummary, VoteCheckResponse, DeleteReportResponse
)
from app.models import SignalType, SafetySignal, DeviceActivity, User, ReportVerification
from app.services.trust_scoring import TrustScoringService
from app.services.pulse_aggregation import PulseAggregationService
from app.services.realtime import RealtimeService, connection_manager
from app.dependencies import get_current_user, JWTUser
import hashlib
from datetime import datetime, timedelta, timezone
from typing import List, Optional
from uuid import UUID
from pydantic import BaseModel, field_serializer
import pygeohash as pgh
import uuid

router = APIRouter()

@router.post("/report", response_model=ReportResponse)
async def report_safety_signal(
    request: ReportRequest,
    background_tasks: BackgroundTasks,
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Report a safety signal (requires authentication).
    
    The report will be linked to your user account.
    """

    # Validate signal type
    try:
        signal_type = SignalType(request.signal_type)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid signal type")

    # Validate severity
    if not 1 <= request.severity <= 5:
        raise HTTPException(status_code=400, detail="Severity must be between 1 and 5")

    # Blur coordinates (50m minimum radius)
    blurred_lat, blurred_lon = TrustScoringService.blur_coordinates(
        request.latitude, request.longitude, radius_meters=50
    )

    # Generate geohash
    geohash = pgh.encode(blurred_lat, blurred_lon, precision=6)

    # Calculate trust score with user boost for authenticated users
    trust_service = TrustScoringService(db)
    trust_score = trust_service.calculate_trust_score(
        device_hash=str(current_user.user_id),
        is_authenticated=True
    )

    # Create safety signal with user_id
    signal_id = uuid.uuid4()
    signal = SafetySignal(
        id=signal_id,
        signal_type=signal_type,
        severity=request.severity,
        latitude=blurred_lat,
        longitude=blurred_lon,
        geohash=geohash,
        device_hash=str(current_user.user_id),  # Use user_id as device hash for auth users
        user_id=current_user.user_id,  # Link to authenticated user
        context_tags=request.context,
        trust_score=trust_score,
        is_valid=True
    )

    db.add(signal)

    # Update device activity (using user_id as identifier for auth users)
    device_hash = str(current_user.user_id)
    device_activity = db.query(DeviceActivity).filter(
        DeviceActivity.device_hash == device_hash
    ).first()

    if not device_activity:
        device_activity = DeviceActivity(device_hash=device_hash, submission_count=0)

    device_activity.submission_count += 1
    device_activity.last_submission = datetime.now(timezone.utc)
    db.add(device_activity)

    db.commit()

    # Queue background aggregation
    background_tasks.add_task(aggregate_pulse_background, signal_id)

    return ReportResponse(
        message="Safety signal reported successfully",
        signal_id=signal_id,
        trust_score=trust_score
    )

@router.get("/reports", response_model=ReportListResponse)
async def get_reports(
    lat: float,
    lng: float,
    radius: float = 10.0,
    time_window: str = "24h",
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get safety reports in a given area and time window.
    Requires authentication.
    """

    # Validate parameters
    if not -90 <= lat <= 90:
        raise HTTPException(status_code=400, detail="Invalid latitude")
    if not -180 <= lng <= 180:
        raise HTTPException(status_code=400, detail="Invalid longitude")
    if radius <= 0 or radius > 100:
        raise HTTPException(status_code=400, detail="Invalid radius")

    # Parse time window
    time_deltas = {
        "1h": timedelta(hours=1),
        "24h": timedelta(hours=24),
        "7d": timedelta(days=7)
    }
    if time_window not in time_deltas:
        raise HTTPException(status_code=400, detail="Invalid time window")
    time_delta = time_deltas[time_window]

    # Calculate bounding box for the area (approximate radius in degrees)
    # For simplicity, using a rough approximation: 1 degree ≈ 111km
    lat_range = radius / 111.0  # km to degrees
    lng_range = radius / (111.0 * abs(lat))  # adjust for latitude

    min_lat = lat - lat_range
    max_lat = lat + lat_range
    min_lng = lng - lng_range
    max_lng = lng + lng_range

    # Get reports within time window and bounding box
    cutoff_time = datetime.now(timezone.utc) - time_delta
    reports = db.query(SafetySignal).filter(
        SafetySignal.latitude.between(min_lat, max_lat),
        SafetySignal.longitude.between(min_lng, max_lng),
        SafetySignal.timestamp >= cutoff_time,
        SafetySignal.is_valid == True
    ).order_by(desc(SafetySignal.timestamp)).limit(100).all()

    # Convert to response format with reporter info and votes
    report_items = []
    for report in reports:
        # Get reporter username if available
        reporter_username = None
        if report.user_id:
            user = db.query(User).filter(User.id == report.user_id).first()
            if user:
                reporter_username = user.username
        
        # Check if current user has voted on this report
        user_vote = None
        user_verification = db.query(ReportVerification).filter(
            ReportVerification.signal_id == report.id,
            ReportVerification.user_id == current_user.user_id
        ).first()
        if user_verification:
            user_vote = user_verification.is_true
        
        report_items.append(
            ReportItem(
                id=report.id,
                signal_type=report.signal_type.value,
                severity=report.severity,
                latitude=report.latitude,
                longitude=report.longitude,
                created_at=report.timestamp,
                trust_score=report.trust_score,
                user_id=report.user_id,
                reporter_username=reporter_username,
                true_votes=report.true_votes or 0,
                false_votes=report.false_votes or 0,
                user_vote=user_vote
            )
        )

    return ReportListResponse(reports=report_items)


class PulseReportResponse(BaseModel):
    """Response model for a single report in the pulse context"""
    report_id: UUID
    created_at: datetime
    feeling_level: str  # "Calm", "Caution", "Moderate", "Unsafe"
    reason: str  # "Followed", "Poor lighting", "Suspicious activity", "Other"
    description: Optional[str] = None  # Max 120 chars
    has_user_voted: bool
    is_user_report: bool
    user_vote: Optional[bool] = None  # True=accurate, False=false

    class Config:
        from_attributes = True
    
    @field_serializer('created_at')
    @classmethod
    def serialize_datetime(cls, v: datetime) -> str:
        return v.isoformat()


class PulseReportListResponse(BaseModel):
    """Response for GET /reports/by-pulse"""
    reports: List[PulseReportResponse]
    count: int
    pulse_lat: float
    pulse_lng: float
    generated_at: str


@router.get("/reports/by-pulse", response_model=PulseReportListResponse)
async def get_reports_by_pulse(
    lat: float = Query(..., description="Pulse center latitude", ge=-90, le=90),
    lng: float = Query(..., description="Pulse center longitude", ge=-180, le=180),
    radius: float = Query(500, description="Search radius in meters", ge=50, le=5000),
    time_window_hours: int = Query(2, description="Only show reports from last N hours", ge=1, le=24),
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get reports for a specific pulse location.
    
    This endpoint is used when a user taps on a safety pulse and wants to see
    the underlying reports. It returns:
    - Reports within the pulse radius
    - Limited to recent reports (default 2 hours)
    - With voting status for the current user
    
    NOTE: No personal data is exposed. Reporter usernames are NOT included.
    """
    
    # Calculate time cutoff
    cutoff_time = datetime.now(timezone.utc) - timedelta(hours=time_window_hours)
    
    # Convert radius from meters to approximate degrees (1 degree ≈ 111km)
    radius_deg = radius / 111000.0
    
    # Calculate bounding box
    min_lat = lat - radius_deg
    max_lat = lat + radius_deg
    min_lng = lng - radius_deg
    max_lng = lng + radius_deg
    
    # Get reports within the pulse area and time window
    reports = db.query(SafetySignal).filter(
        and_(
            SafetySignal.latitude.between(min_lat, max_lat),
            SafetySignal.longitude.between(min_lng, max_lng),
            SafetySignal.timestamp >= cutoff_time,
            SafetySignal.is_valid == True
        )
    ).order_by(desc(SafetySignal.timestamp)).limit(50).all()
    
    # Build response with voting status
    report_responses = []
    for report in reports:
        # Check if current user has voted on this report
        user_verification = db.query(ReportVerification).filter(
            ReportVerification.signal_id == report.id,
            ReportVerification.user_id == current_user.user_id
        ).first()
        
        user_vote = None
        has_voted = False
        if user_verification:
            has_voted = True
            user_vote = user_verification.is_true
        
        # Determine if this is the user's own report
        is_user_report = report.user_id == current_user.user_id
        
        # Map severity to feeling level
        feeling_level = _get_feeling_level(report.severity)
        
        # Format reason from signal type
        reason = _format_reason(report.signal_type.value)
        
        # Get description from context (max 120 chars)
        description = None
        if report.context_tags and 'description' in report.context_tags:
            desc_text = report.context_tags['description']
            if desc_text and len(desc_text) > 0:
                description = desc_text[:120] if len(desc_text) > 120 else desc_text
        
        report_responses.append(
            PulseReportResponse(
                report_id=report.id,
                created_at=report.timestamp,
                feeling_level=feeling_level,
                reason=reason,
                description=description,
                has_user_voted=has_voted,
                is_user_report=is_user_report,
                user_vote=user_vote
            )
        )
    
    return PulseReportListResponse(
        reports=report_responses,
        count=len(report_responses),
        pulse_lat=lat,
        pulse_lng=lng,
        generated_at=datetime.now(timezone.utc).isoformat()
    )


def _get_feeling_level(severity: int) -> str:
    """Map severity (1-5) to feeling level"""
    if severity >= 5:
        return "Very Unsafe"
    elif severity >= 4:
        return "Unsafe"
    elif severity >= 3:
        return "Moderate"
    elif severity >= 2:
        return "Caution"
    else:
        return "Calm"


def _format_reason(signal_type: str) -> str:
    """Format signal type to human-readable reason"""
    reason_map = {
        "followed": "Followed",
        "suspicious_activity": "Suspicious activity",
        "unsafe_area": "Unsafe area",
        "harassment": "Harassment",
        "other": "Other"
    }
    return reason_map.get(signal_type, "Other")


def _get_confidence_level(trust_score: float) -> str:
    """Map trust score to confidence level"""
    if trust_score >= 0.7:
        return "HIGH"
    elif trust_score >= 0.4:
        return "MEDIUM"
    else:
        return "LOW"


@router.post("/reports/{signal_id}/vote", response_model=VoteResponse)
async def vote_on_report(
    signal_id: str,
    vote_request: VoteRequest,
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Vote on whether a report is accurate (true) or not (false).
    
    - is_true=True: Vote that the report is accurate/legitimate
    - is_true=False: Vote that the report is false/inaccurate
    
    IMPORTANT: Users can only vote ONCE per report.
    If you want to change your vote, you must first delete your existing vote.
    """
    
    # Try to parse as UUID first, then fallback to numeric string search
    signal_uuid = None
    try:
        signal_uuid = uuid.UUID(signal_id)
    except ValueError:
        # Handle numeric string IDs (e.g., timestamp-based from frontend)
        pass
    
    # Get the signal - try UUID first, then by string ID
    signal = None
    if signal_uuid:
        signal = db.query(SafetySignal).filter(SafetySignal.id == signal_uuid).first()
    
    if not signal:
        # Try searching by string representation of UUID
        signal = db.query(SafetySignal).filter(
            SafetySignal.id == signal_id
        ).first()
    
    if not signal:
        raise HTTPException(status_code=404, detail="Report not found")
    
    # Check if user already voted - if so, reject the new vote
    existing_vote = db.query(ReportVerification).filter(
        ReportVerification.signal_id == signal.id,
        ReportVerification.user_id == current_user.user_id
    ).first()
    
    if existing_vote:
        raise HTTPException(
            status_code=400,
            detail="You have already voted on this report. Delete your vote first if you want to change it."
        )
    
    trust_service = TrustScoringService(db)
    
    # Create new vote
    verification = ReportVerification(
        signal_id=signal.id,
        user_id=current_user.user_id,
        is_true=vote_request.is_true
    )
    db.add(verification)
    
    # Update trust score based on the new vote
    updated_trust_score = trust_service.update_signal_trust_from_vote(
        signal_id=str(signal.id),
        is_true_vote=vote_request.is_true
    )
    
    db.commit()
    
    # Refresh to get updated counts
    db.refresh(signal)
    
    # Emit real-time events
    from app.services.realtime import connection_manager, EventType
    from datetime import datetime
    
    # VOTE_CAST event - update vote counts in real-time
    vote_cast_message = {
        "event_type": "vote_cast",
        "data": {
            "signal_id": str(signal.id),
            "true_votes": signal.true_votes or 0,
            "false_votes": signal.false_votes or 0,
            "trust_score": updated_trust_score,
            "voter_id": str(current_user.user_id),
        },
        "timestamp": datetime.utcnow().isoformat()
    }
    await connection_manager.broadcast_to_subscriptions(
        vote_cast_message,
        ["global", "report_updates"]
    )
    
    # PULSE_UPDATED event - pulse confidence may have changed
    pulse_update_message = {
        "event_type": "pulse_updated",
        "data": {
            "signal_id": str(signal.id),
            "geohash": signal.geohash,
            "latitude": signal.latitude,
            "longitude": signal.longitude,
            "intensity": updated_trust_score,
            "confidence": _get_confidence_level(updated_trust_score),
        },
        "timestamp": datetime.utcnow().isoformat()
    }
    await connection_manager.broadcast_to_subscriptions(
        pulse_update_message,
        ["global", "pulse_updates"]
    )
    
    return VoteResponse(
        message="Vote recorded successfully",
        signal_id=signal.id,
        is_true=vote_request.is_true,
        new_true_votes=signal.true_votes or 0,
        new_false_votes=signal.false_votes or 0,
        updated_trust_score=updated_trust_score
    )

@router.delete("/reports/{signal_id}/vote", response_model=VoteResponse)
async def remove_vote(
    signal_id: str,
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Remove your vote from a report.
    """
    
    # Validate signal_id is a valid UUID
    try:
        signal_uuid = uuid.UUID(signal_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid signal ID format: '{signal_id}'. Expected a valid UUID."
        )
    
    # Get the vote
    vote = db.query(ReportVerification).filter(
        ReportVerification.signal_id == signal_uuid,
        ReportVerification.user_id == current_user.user_id
    ).first()
    
    if not vote:
        raise HTTPException(status_code=404, detail="Vote not found")
    
    # Get the signal
    signal = db.query(SafetySignal).filter(SafetySignal.id == signal_uuid).first()
    if not signal:
        raise HTTPException(status_code=404, detail="Report not found")
    
    # Revert the vote and update trust score
    trust_service = TrustScoringService(db)
    updated_trust_score = trust_service.revert_vote_from_signal(
        signal_id=str(signal_uuid),
        was_true_vote=vote.is_true
    )
    
    # Delete the vote
    db.delete(vote)
    db.commit()
    
    # Refresh to get updated counts
    db.refresh(signal)
    
    return VoteResponse(
        message="Vote removed successfully",
        signal_id=signal_uuid,
        is_true=vote.is_true,
        new_true_votes=signal.true_votes or 0,
        new_false_votes=signal.false_votes or 0,
        updated_trust_score=updated_trust_score
    )

@router.get("/reports/{signal_id}/votes", response_model=VoteSummary)
async def get_vote_summary(
    signal_id: str,
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get the vote summary for a report.
    """
    
    # Validate signal_id is a valid UUID
    try:
        signal_uuid = uuid.UUID(signal_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid signal ID format: '{signal_id}'. Expected a valid UUID."
        )
    
    trust_service = TrustScoringService(db)
    
    try:
        summary = trust_service.get_vote_summary(str(signal_uuid))
        return VoteSummary(**summary)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

@router.get("/reports/{signal_id}/vote/check", response_model=VoteCheckResponse)
async def check_user_vote(
    signal_id: str,
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Check if the current user has voted on a report.
    """
    
    # Validate signal_id is a valid UUID
    try:
        signal_uuid = uuid.UUID(signal_id)
    except ValueError:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid signal ID format: '{signal_id}'. Expected a valid UUID."
        )
    
    vote = db.query(ReportVerification).filter(
        ReportVerification.signal_id == signal_uuid,
        ReportVerification.user_id == current_user.user_id
    ).first()
    
    if vote:
        return VoteCheckResponse(has_voted=True, is_true=vote.is_true)
    else:
        return VoteCheckResponse(has_voted=False)


async def aggregate_pulse_background(signal_id: uuid.UUID):
    """Background task to aggregate pulse data"""
    # This would be called to update pulse tiles
    # For now, we'll implement it as a simple aggregation
    service = PulseAggregationService()
    service.aggregate_pulse_tiles()


# ============ New Features ============

@router.delete("/reports/{signal_id}", response_model=DeleteReportResponse)
async def delete_report(
    signal_id: uuid.UUID,
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Delete your own report.
    
    Only the report owner can delete their report.
    This will also delete all verifications (votes) associated with the report.
    """
    
    # Get the signal
    signal = db.query(SafetySignal).filter(SafetySignal.id == signal_id).first()
    if not signal:
        raise HTTPException(status_code=404, detail="Report not found")
    
    # Check if user is the owner of the report
    if signal.user_id != current_user.user_id:
        raise HTTPException(
            status_code=403, 
            detail="You can only delete your own reports"
        )
    
    # Store info for response before deletion
    deleted_signal_id = signal.id
    deleted_at = datetime.now(timezone.utc)
    
    # Delete all verifications (votes) associated with this report
    db.query(ReportVerification).filter(
        ReportVerification.signal_id == signal_id
    ).delete()
    
    # Delete the report
    db.delete(signal)
    db.commit()
    
    return DeleteReportResponse(
        message="Report deleted successfully",
        deleted_signal_id=deleted_signal_id,
        deleted_at=deleted_at
    )

