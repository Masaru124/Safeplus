"""
Pulse API Routes for Safety Pulse

These routes provide:
- GET /pulses/active - Single source of truth for map rendering
- GET /pulse - Legacy pulse data (for backwards compatibility)
"""

from fastapi import APIRouter, Query, HTTPException, Depends, BackgroundTasks
from typing import List, Optional
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import PulseTile
from app.schemas import (
    PulseTileResponse, PulseResponse, PulseActiveResponse, PulseActiveListResponse
)
from app.services.pulse_aggregation import PulseAggregationService, PulseDecayService
from app.services.realtime import connection_manager, RealtimeService, WebSocketMessage, EventType
from app.dependencies import get_current_user, JWTUser
from datetime import datetime, timezone

router = APIRouter()

# In-memory cache for local development
cache = {}


@router.get("/pulses/active", response_model=PulseActiveListResponse)
async def get_active_pulses(
    lat: Optional[float] = Query(None, description="Center latitude for filtering"),
    lng: Optional[float] = Query(None, description="Center longitude for filtering"),
    radius: Optional[float] = Query(None, description="Radius in kilometers for filtering"),
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get all active pulse tiles for map rendering.
    
    This is the SINGLE source of truth for map rendering.
    Frontend must NEVER fetch raw signals for map rendering.
    
    Returns pulses with:
    - lat, lng: Center coordinates
    - radius: Danger radius in meters
    - intensity: 0.0-1.0 danger intensity
    - confidence: HIGH/MEDIUM/LOW
    - dominant_reason: Primary safety concern
    - last_updated: When pulse was last updated
    
    Optional filtering by location and radius.
    """
    
    try:
        # Validate filtering parameters
        if (lat is not None) != (lng is not None):
            raise HTTPException(
                status_code=400, 
                detail="Both lat and lng must be provided for filtering"
            )
        
        if radius is not None and (lat is None or lng is None):
            raise HTTPException(
                status_code=400,
                detail="lat and lng must be provided when radius is specified"
            )
        
        if radius is not None and (radius <= 0 or radius > 100):
            raise HTTPException(
                status_code=400,
                detail="Radius must be between 0 and 100 kilometers"
            )
        
        # Get pulses based on filtering
        if lat is not None and lng is not None and radius is not None:
            # Filter by location and radius
            pulses = db.query(PulseTile).filter(
                (PulseTile.expires_at == None) | (PulseTile.expires_at > datetime.now(timezone.utc))
            ).all()
            # Filter by radius manually
            filtered_pulses = []
            for pulse in pulses:
                # Simple distance calculation
                dist = ((pulse.center_lat - lat)**2 + (pulse.center_lng - lng)**2)**0.5
                # Approximate: 1 degree ≈ 111km
                if dist * 111 <= radius:
                    filtered_pulses.append(pulse)
            pulses = filtered_pulses
        else:
            # Get all active pulses
            pulses = db.query(PulseTile).filter(
                (PulseTile.expires_at == None) | (PulseTile.expires_at > datetime.now(timezone.utc))
            ).all()
        
        # Convert to response format
        pulse_responses = []
        for pulse in pulses:
            try:
                confidence_str = pulse.confidence_level.value.upper() if pulse.confidence_level else "LOW"
            except AttributeError:
                confidence_str = "LOW"
            
            pulse_responses.append(
                PulseActiveResponse(
                    lat=pulse.center_lat,
                    lng=pulse.center_lng,
                    radius=pulse.radius or 200,
                    intensity=pulse.intensity or 0.0,
                    confidence=confidence_str,
                    dominant_reason=pulse.dominant_reason,
                    last_updated=pulse.last_updated or datetime.now(timezone.utc)
                )
            )
        
        return PulseActiveListResponse(
            pulses=pulse_responses,
            count=len(pulse_responses),
            generated_at=datetime.now(timezone.utc).isoformat()
        )
    
    except HTTPException:
        raise
    except Exception as e:
        import traceback
        traceback.print_exc()
        raise HTTPException(
            status_code=500,
            detail=f"Internal server error: {str(e)}"
        )


@router.post("/pulses/refresh")
async def refresh_pulses(
    background_tasks: BackgroundTasks,
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Trigger a manual refresh of all pulse tiles.
    
    This aggregates recent reports into pulse tiles and emits
    WebSocket events for real-time updates.
    """
    service = PulseAggregationService(db)
    decay_service = PulseDecayService(db)
    
    # Run aggregation
    updated_tiles = service.aggregate_pulse_tiles()
    
    # Run decay
    decay_result = decay_service.decay_pulses()
    
    # Emit real-time updates
    realtime_service = RealtimeService(db)
    for tile in updated_tiles:
        await realtime_service.notify_pulse_update(
            tile_id=tile.tile_id,
            intensity=tile.intensity,
            confidence=tile.confidence_level.value
        )
    
    return {
        "message": f"Refreshed {len(updated_tiles)} pulse tiles",
        "updated_tiles": len(updated_tiles),
        "decayed_tiles": decay_result["updated_pulses"],
        "expired_tiles": decay_result["deleted_pulses"]
    }


@router.get("/pulse", response_model=PulseResponse)
async def get_safety_pulse(
    lat: float = Query(..., description="Latitude of center point"),
    lng: float = Query(..., description="Longitude of center point"),
    radius: float = Query(10.0, description="Radius in kilometers"),
    time_window: str = Query("24h", description="Time window (e.g., 1h, 24h, 7d)"),
    current_user: JWTUser = Depends(get_current_user)
):
    """
    Get safety pulse heatmap data (legacy endpoint).
    
    Note: For new implementations, use GET /pulses/active instead.
    This endpoint is kept for backwards compatibility.
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
        "1h": 1,
        "24h": 24,
        "7d": 168
    }
    if time_window not in time_deltas:
        raise HTTPException(status_code=400, detail="Invalid time window")
    
    # Create cache key
    cache_key = f"pulse:{lat:.4f}:{lng:.4f}:{radius}:{time_window}"
    
    # Check cache first (5 minute cache)
    cached_data = cache.get(cache_key)
    if cached_data and (datetime.now() - cached_data['timestamp']).seconds < 300:
        return PulseResponse(**cached_data['data'])
    
    # Get pulse tiles from service
    service = PulseAggregationService()
    tiles = service.get_pulses_in_radius(lat, lng, radius)
    
    # Filter by time window (approximate based on last_updated)
    cutoff_time = datetime.now() - cache[cache_key]['timestamp'] if False else None
    
    # Convert to response format
    tile_responses = []
    for tile in tiles:
        tile_responses.append(
            PulseTileResponse(
                tile_id=tile.tile_id,
                pulse_score=int(tile.intensity * 100),
                confidence=tile.confidence_level.value
            )
        )
    
    response = PulseResponse(tiles=tile_responses)
    
    # Cache for 5 minutes
    cache[cache_key] = {
        'data': response.dict(),
        'timestamp': datetime.now()
    }
    
    return response


@router.get("/pulses/stats")
async def get_pulse_stats(
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get statistics about current pulse state.
    
    Useful for monitoring and debugging.
    """
    service = PulseAggregationService(db)
    active_pulses = service.get_active_pulses()
    
    # Calculate stats
    total_pulses = len(active_pulses)
    avg_intensity = sum(p.intensity for p in active_pulses) / total_pulses if total_pulses > 0 else 0
    high_confidence = sum(1 for p in active_pulses if p.confidence_level.value == 'high')
    
    # Count by confidence level
    confidence_counts = {'high': 0, 'medium': 0, 'low': 0}
    for pulse in active_pulses:
        confidence_counts[pulse.confidence_level.value] += 1
    
    # Count by dominant reason
    reason_counts: dict = {}
    for pulse in active_pulses:
        reason = pulse.dominant_reason or 'Unknown'
        reason_counts[reason] = reason_counts.get(reason, 0) + 1
    
    return {
        "total_active_pulses": total_pulses,
        "average_intensity": round(avg_intensity, 3),
        "high_confidence_count": high_confidence,
        "confidence_distribution": confidence_counts,
        "reason_distribution": reason_counts,
        "server_time": datetime.now(timezone.utc).isoformat()
    }

