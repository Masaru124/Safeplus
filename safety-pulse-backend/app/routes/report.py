from fastapi import APIRouter, HTTPException, Depends, BackgroundTasks, status
from sqlalchemy.orm import Session
from sqlalchemy import desc
from app.database import get_db
from app.schemas import (
    ReportRequest, ReportResponse, ReportListResponse, ReportItem,
    VoteRequest, VoteResponse, VoteSummary, VoteCheckResponse, DeleteReportResponse
)
from app.models import SignalType, SafetySignal, DeviceActivity, User, ReportVerification
from app.services.trust_scoring import TrustScoringService
from app.services.pulse_aggregation import PulseAggregationService
from app.dependencies import get_current_user, JWTUser
import hashlib
from datetime import datetime, timedelta, timezone
import uuid
import pygeohash as pgh

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

@router.post("/reports/{signal_id}/vote", response_model=VoteResponse)
async def vote_on_report(
    signal_id: uuid.UUID,
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
    
    # Get the signal
    signal = db.query(SafetySignal).filter(SafetySignal.id == signal_id).first()
    if not signal:
        raise HTTPException(status_code=404, detail="Report not found")
    
    # Check if user already voted - if so, reject the new vote
    existing_vote = db.query(ReportVerification).filter(
        ReportVerification.signal_id == signal_id,
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
        signal_id=signal_id,
        user_id=current_user.user_id,
        is_true=vote_request.is_true
    )
    db.add(verification)
    
    # Update trust score based on the new vote
    updated_trust_score = trust_service.update_signal_trust_from_vote(
        signal_id=str(signal_id),
        is_true_vote=vote_request.is_true
    )
    
    db.commit()
    
    # Refresh to get updated counts
    db.refresh(signal)
    
    return VoteResponse(
        message="Vote recorded successfully",
        signal_id=signal_id,
        is_true=vote_request.is_true,
        new_true_votes=signal.true_votes or 0,
        new_false_votes=signal.false_votes or 0,
        updated_trust_score=updated_trust_score
    )

@router.delete("/reports/{signal_id}/vote", response_model=VoteResponse)
async def remove_vote(
    signal_id: uuid.UUID,
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Remove your vote from a report.
    """
    
    # Get the vote
    vote = db.query(ReportVerification).filter(
        ReportVerification.signal_id == signal_id,
        ReportVerification.user_id == current_user.user_id
    ).first()
    
    if not vote:
        raise HTTPException(status_code=404, detail="Vote not found")
    
    # Get the signal
    signal = db.query(SafetySignal).filter(SafetySignal.id == signal_id).first()
    if not signal:
        raise HTTPException(status_code=404, detail="Report not found")
    
    # Revert the vote and update trust score
    trust_service = TrustScoringService(db)
    updated_trust_score = trust_service.revert_vote_from_signal(
        signal_id=str(signal_id),
        was_true_vote=vote.is_true
    )
    
    # Delete the vote
    db.delete(vote)
    db.commit()
    
    # Refresh to get updated counts
    db.refresh(signal)
    
    return VoteResponse(
        message="Vote removed successfully",
        signal_id=signal_id,
        is_true=vote.is_true,
        new_true_votes=signal.true_votes or 0,
        new_false_votes=signal.false_votes or 0,
        updated_trust_score=updated_trust_score
    )

@router.get("/reports/{signal_id}/votes", response_model=VoteSummary)
async def get_vote_summary(
    signal_id: uuid.UUID,
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get the vote summary for a report.
    """
    
    trust_service = TrustScoringService(db)
    
    try:
        summary = trust_service.get_vote_summary(str(signal_id))
        return VoteSummary(**summary)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

@router.get("/reports/{signal_id}/vote/check", response_model=VoteCheckResponse)
async def check_user_vote(
    signal_id: uuid.UUID,
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Check if the current user has voted on a report.
    """
    
    vote = db.query(ReportVerification).filter(
        ReportVerification.signal_id == signal_id,
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

