from fastapi import APIRouter, HTTPException, Depends, BackgroundTasks, Header
from sqlalchemy.orm import Session
from app.database import get_db
from app.schemas import ReportRequest, ReportResponse, ReportListResponse, ReportItem
from app.models import SignalType, SafetySignal, DeviceActivity
from app.services.trust_scoring import TrustScoringService
from app.services.pulse_aggregation import PulseAggregationService
import hashlib
from datetime import datetime, timedelta, timezone
import uuid
import pygeohash as pgh

router = APIRouter()

@router.post("/report", response_model=ReportResponse)
async def report_safety_signal(
    request: ReportRequest,
    background_tasks: BackgroundTasks,
    x_device_hash: str = Header(..., alias="X-Device-Hash"),
    db: Session = Depends(get_db)
):
    """Report a safety signal"""

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

    # Calculate trust score
    trust_service = TrustScoringService(db)
    trust_score = trust_service.calculate_trust_score(x_device_hash)

    # Create safety signal
    signal_id = uuid.uuid4()
    signal = SafetySignal(
        id=signal_id,
        signal_type=signal_type,
        severity=request.severity,
        latitude=blurred_lat,
        longitude=blurred_lon,
        geohash=geohash,
        device_hash=x_device_hash,
        context_tags=request.context,
        trust_score=trust_score,
        is_valid=True
    )

    db.add(signal)

    # Update device activity
    device_activity = db.query(DeviceActivity).filter(
        DeviceActivity.device_hash == x_device_hash
    ).first()

    if not device_activity:
        device_activity = DeviceActivity(device_hash=x_device_hash, submission_count=0)

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
    db: Session = Depends(get_db)
):
    """Get safety reports in a given area and time window"""

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
    ).all()

    # Convert to response format
    report_items = [
        ReportItem(
            id=report.id,
            signal_type=report.signal_type.value,
            severity=report.severity,
            latitude=report.latitude,
            longitude=report.longitude,
            created_at=report.timestamp,
            trust_score=report.trust_score
        )
        for report in reports
    ]

    return ReportListResponse(reports=report_items)

async def aggregate_pulse_background(signal_id: uuid.UUID):
    """Background task to aggregate pulse data"""
    # This would be called to update pulse tiles
    # For now, we'll implement it as a simple aggregation
    service = PulseAggregationService()
    service.aggregate_pulse_tiles()
