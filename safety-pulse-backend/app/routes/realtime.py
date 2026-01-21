"""
Real-Time API Routes for Safety Pulse

These routes provide:
- WebSocket connection handling
- Polling endpoints for updates
- Pulse delta for version-based updates
"""

from fastapi import APIRouter, HTTPException, Depends, Query, WebSocket, WebSocketDisconnect
from sqlalchemy.orm import Session
from datetime import datetime, timedelta
from typing import Optional

from app.database import get_db
from app.schemas import PollingResponse, PulseDeltaResponse, RealtimeEventResponse
from app.services.realtime import (
    connection_manager, RealtimeService, PollingService
)
from app.dependencies import get_current_user, JWTUser

router = APIRouter()


# ============ WebSocket Endpoints ============

@router.websocket("/ws/realtime")
async def websocket_realtime(websocket: WebSocket):
    """
    WebSocket endpoint for real-time safety updates.
    
    Clients can subscribe to:
    - Global updates (new reports, votes, deletions)
    - Pulse updates (tile score changes)
    - Alerts (spikes, anomalies)
    
    Message types from client:
    - ping: Keep connection alive
    - subscribe: Subscribe to additional topics
    - unsubscribe: Unsubscribe from topics
    - location_update: Update client location for targeted alerts
    - request_pulse: Request pulse data for an area
    
    Message types to client:
    - new_report: New safety report submitted
    - vote_update: Vote count changed
    - pulse_update: Tile score changed
    - spike_detected: Safety spike detected
    - location_alert: Personalized alert for location
    """
    await websocket.accept()
    
    # Default subscription
    subscription = "global"
    
    try:
        while True:
            data = await websocket.receive_json()
            message_type = data.get("type")
            
            if message_type == "ping":
                await websocket.send_json({"type": "pong", "server_time": datetime.utcnow().isoformat()})
            
            elif message_type == "subscribe":
                topics = data.get("topics", [])
                for topic in topics:
                    await connection_manager.disconnect(websocket, subscription)
                    await connection_manager.connect(websocket, topic)
                    subscription = topic
            
            elif message_type == "location_update":
                lat = data.get("latitude")
                lng = data.get("longitude")
                if lat and lng:
                    from app.services.pattern_detection import PatternDetectionService
                    db = next(get_db())
                    try:
                        pattern_service = PatternDetectionService(db)
                        alert = pattern_service.get_personalized_alert(lat, lng, datetime.utcnow().hour)
                        await websocket.send_json({
                            "type": "location_alert",
                            "data": alert
                        })
                    finally:
                        db.close()
            
            elif message_type == "request_pulse":
                lat = data.get("latitude")
                lng = data.get("longitude")
                radius = data.get("radius", 10.0)
                if lat and lng:
                    from app.services.pulse_aggregation import PulseAggregationService
                    db = next(get_db())
                    try:
                        service = PulseAggregationService()
                        tiles = service.get_pulse_tiles_in_radius(lat, lng, radius)
                        await websocket.send_json({
                            "type": "pulse_data",
                            "data": {
                                "tiles": [
                                    {
                                        "tile_id": t.tile_id,
                                        "pulse_score": t.pulse_score,
                                        "confidence": t.confidence_level.value
                                    }
                                    for t in tiles
                                ]
                            }
                        })
                    finally:
                        db.close()
            
    except WebSocketDisconnect:
        await connection_manager.disconnect(websocket, subscription)


@router.websocket("/ws/pulse")
async def websocket_pulse(websocket: WebSocket):
    """
    WebSocket endpoint specifically for pulse updates.
    
    Only receives pulse tile updates.
    """
    await connection_manager.connect(websocket, "pulse_updates")
    
    try:
        while True:
            # Wait for any message (keep connection alive)
            await websocket.receive_json()
    except WebSocketDisconnect:
        await connection_manager.disconnect(websocket, "pulse_updates")


@router.websocket("/ws/alerts")
async def websocket_alerts(websocket: WebSocket):
    """
    WebSocket endpoint specifically for alerts.
    
    Receives:
    - Spike detections
    - Anomaly alerts
    - Personalized location alerts
    """
    await connection_manager.connect(websocket, "alerts")
    
    try:
        while True:
            await websocket.receive_json()
    except WebSocketDisconnect:
        await connection_manager.disconnect(websocket, "alerts")


# ============ Polling Endpoints ============

@router.get("/realtime/updates", response_model=PollingResponse)
async def get_updates(
    lat: float = Query(..., description="Center latitude"),
    lng: float = Query(..., description="Center longitude"),
    radius: float = Query(10.0, description="Radius in kilometers", le=100),
    since: Optional[str] = Query(None, description="ISO timestamp to get updates since"),
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Polling endpoint for safety updates.
    
    Returns all new reports, pulse updates, and spikes since the given timestamp.
    This is a fallback for clients that don't support WebSockets.
    """
    if not -90 <= lat <= 90:
        raise HTTPException(status_code=400, detail="Invalid latitude")
    if not -180 <= lng <= 180:
        raise HTTPException(status_code=400, detail="Invalid longitude")
    
    last_update = None
    if since:
        try:
            last_update = datetime.fromisoformat(since.replace('Z', '+00:00'))
        except ValueError:
            raise HTTPException(status_code=400, detail="Invalid timestamp format")
    
    polling_service = PollingService(db)
    updates = await polling_service.get_updates_since(lat, lng, radius, last_update)
    
    return PollingResponse(**updates)


@router.get("/realtime/pulse-delta", response_model=PulseDeltaResponse)
async def get_pulse_delta(
    lat: float = Query(..., description="Center latitude"),
    lng: float = Query(..., description="Center longitude"),
    radius: float = Query(10.0, description="Radius in kilometers", le=100),
    version: Optional[int] = Query(None, description="Last known version number"),
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Efficient pulse update using version-based delta.
    
    Instead of returning all data, this returns only tiles that have changed
    since the client's last version.
    
    The version is a Unix timestamp of the latest report in the area.
    Clients should cache this version and pass it on subsequent requests.
    """
    if not -90 <= lat <= 90:
        raise HTTPException(status_code=400, detail="Invalid latitude")
    if not -180 <= lng <= 180:
        raise HTTPException(status_code=400, detail="Invalid longitude")
    
    polling_service = PollingService(db)
    delta = await polling_service.get_pulse_delta(lat, lng, radius, version)
    
    return PulseDeltaResponse(**delta)


@router.get("/realtime/events")
async def get_recent_events(
    limit: int = Query(50, description="Maximum number of events", le=100),
    event_type: Optional[str] = Query(None, description="Filter by event type"),
    current_user: JWTUser = Depends(get_current_user),
    db: Session = Depends(get_db)
):
    """
    Get recent real-time events.
    
    Returns the most recent events in the system.
    Useful for clients that just connected and want to catch up.
    """
    from app.models import RealtimeEvent
    
    query = db.query(RealtimeEvent)
    
    if event_type:
        query = query.filter(RealtimeEvent.event_type == event_type)
    
    events = query.order_by(
        RealtimeEvent.created_at.desc()
    ).limit(limit).all()
    
    return {
        "events": [
            RealtimeEventResponse(
                event_type=e.event_type,
                data=e.data,
                timestamp=e.created_at.isoformat()
            )
            for e in events
        ],
        "count": len(events)
    }


# ============ Subscription Management ============

@router.post("/realtime/subscribe")
async def subscribe_to_topics(
    topics: list[str],
    current_user: JWTUser = Depends(get_current_user)
):
    """
    Subscribe to specific real-time topics.
    
    Topics:
    - pulse_updates: Receive tile score updates
    - report_updates: Receive new report notifications
    - alerts: Receive spike and anomaly alerts
    """
    valid_topics = ["pulse_updates", "report_updates", "alerts"]
    
    for topic in topics:
        if topic not in valid_topics:
            raise HTTPException(
                status_code=400,
                detail=f"Invalid topic: {topic}. Valid topics: {valid_topics}"
            )
    
    return {
        "message": f"Subscribed to {len(topics)} topics",
        "topics": topics
    }


# ============ Connection Status ============

@router.get("/realtime/status")
async def get_realtime_status(
    current_user: JWTUser = Depends(get_current_user)
):
    """
    Get real-time system status.
    
    Returns connection counts and system health.
    """
    return {
        "status": "healthy",
        "websocket_connections": {
            "global": len(connection_manager._connections.get("global", set())),
            "pulse_updates": len(connection_manager._connections.get("pulse_updates", set())),
            "report_updates": len(connection_manager._connections.get("report_updates", set())),
            "alerts": len(connection_manager._connections.get("alerts", set()))
        },
        "redis_connected": connection_manager._redis is not None,
        "server_time": datetime.utcnow().isoformat()
    }

