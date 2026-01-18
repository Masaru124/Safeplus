from fastapi import APIRouter, Query, HTTPException
from typing import List
from app.schemas import PulseTileResponse, PulseResponse
from app.services.pulse_aggregation import PulseAggregationService
import redis
import json
from datetime import datetime, timedelta

router = APIRouter()

# In-memory cache for local development
cache = {}

@router.get("/pulse", response_model=PulseResponse)
async def get_safety_pulse(
    lat: float = Query(..., description="Latitude of center point"),
    lng: float = Query(..., description="Longitude of center point"),
    radius: float = Query(10.0, description="Radius in kilometers"),
    time_window: str = Query("24h", description="Time window (e.g., 1h, 24h, 7d)")
):
    """Get safety pulse heatmap data"""

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

    # Create cache key
    cache_key = f"pulse:{lat:.4f}:{lng:.4f}:{radius}:{time_window}"

    # Check cache first
    cached_data = cache.get(cache_key)
    if cached_data and datetime.utcnow() - cached_data['timestamp'] < timedelta(minutes=5):
        return PulseResponse(**cached_data['data'])

    # Get pulse tiles from service
    service = PulseAggregationService()
    tiles = service.get_pulse_tiles_in_radius(lat, lng, radius)

    # Filter by time window
    cutoff_time = datetime.utcnow() - time_delta
    filtered_tiles = [
        tile for tile in tiles
        if tile.last_updated > cutoff_time
    ]

    # Convert to response format
    tile_responses = [
        PulseTileResponse(
            tile_id=tile.tile_id,
            pulse_score=tile.pulse_score,
            confidence=tile.confidence_level.value
        )
        for tile in filtered_tiles
    ]

    response = PulseResponse(tiles=tile_responses)

    # Cache for 5 minutes
    cache[cache_key] = {
        'data': response.dict(),
        'timestamp': datetime.utcnow()
    }

    return response
