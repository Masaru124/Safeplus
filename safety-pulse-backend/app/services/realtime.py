"""
Real-Time Service for Safety Pulse

This service provides real-time updates using:
- WebSocket connections (Socket.IO)
- Server-Sent Events (SSE)
- Periodic polling endpoints
- Redis Pub/Sub for multi-instance support
"""

import json
import asyncio
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Set, Any, Callable
from dataclasses import dataclass, field
from enum import Enum

from sqlalchemy.orm import Session
from sqlalchemy import text

import redis.asyncio as aioredis

from app.models import SafetySignal, PulseTile


class EventType(str, Enum):
    """Types of real-time events"""
    NEW_REPORT = "new_report"
    REPORT_UPDATE = "report_update"
    REPORT_DELETE = "report_delete"
    VOTE_UPDATE = "vote_update"
    PULSE_UPDATE = "pulse_update"
    SPIKE_DETECTED = "spike_detected"
    ANOMALY_ALERT = "anomaly_alert"
    LOCATION_ALERT = "location_alert"


@dataclass
class WebSocketMessage:
    """Message format for WebSocket events"""
    event_type: EventType
    data: Dict[str, Any]
    timestamp: str = field(default_factory=lambda: datetime.utcnow().isoformat())
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "event_type": self.event_type.value,
            "data": self.data,
            "timestamp": self.timestamp
        }
    
    def to_json(self) -> str:
        return json.dumps(self.to_dict())


class ConnectionManager:
    """
    Manages WebSocket connections and broadcasts.
    
    In production, this would use Redis Pub/Sub for multi-instance support.
    For now, it uses in-memory storage.
    """
    
    def __init__(self):
        # Active connections organized by subscription type
        self._connections: Dict[str, Set] = {
            "global": set(),  # All connections
            "pulse_updates": set(),  # Pulse/tile updates
            "report_updates": set(),  # New reports
            "alerts": set(),  # Alerts and spikes
        }
        
        # Redis connection for pub/sub (optional, for production)
        self._redis: Optional[aioredis.Redis] = None
        self._pubsub = None
    
    async def connect(self, websocket, subscription: str = "global"):
        """Register a new WebSocket connection"""
        await websocket.accept()
        if subscription not in self._connections:
            self._connections[subscription] = set()
        self._connections[subscription].add(websocket)
    
    async def disconnect(self, websocket, subscription: str = "global"):
        """Unregister a WebSocket connection"""
        if subscription in self._connections:
            self._connections[subscription].discard(websocket)
    
    async def broadcast(self, message: WebSocketMessage, subscription: str = "global"):
        """Broadcast a message to all connections in a subscription"""
        if subscription not in self._connections:
            return
        
        disconnected = []
        for connection in self._connections[subscription]:
            try:
                await connection.send_json(message.to_dict())
            except Exception:
                disconnected.append(connection)
        
        # Clean up disconnected clients
        for conn in disconnected:
            self._connections[subscription].discard(conn)
    
    async def broadcast_to_subscriptions(
        self,
        message: WebSocketMessage,
        subscriptions: List[str]
    ):
        """Broadcast a message to multiple subscriptions"""
        for subscription in subscriptions:
            await self.broadcast(message, subscription)
    
    # ============ Redis Pub/Sub Integration ============
    
    async def init_redis(self, redis_url: str = "redis://localhost:6379"):
        """Initialize Redis connection for multi-instance pub/sub"""
        try:
            self._redis = aioredis.from_url(redis_url)
            self._pubsub = self._redis.pubsub()
            return True
        except Exception:
            return False
    
    async def publish_event(self, message: WebSocketMessage):
        """Publish event to Redis for cross-instance broadcasting"""
        if self._redis:
            await self._redis.publish(
                "safety_pulse_events",
                message.to_json()
            )
    
    async def subscribe_to_events(self, callback: Callable[[WebSocketMessage], None]):
        """Subscribe to Redis events in background"""
        if self._pubsub:
            await self._pubsub.subscribe("safety_pulse_events")
            async for message in self._pubsub.listen():
                if message["type"] == "message":
                    try:
                        data = json.loads(message["data"])
                        ws_message = WebSocketMessage(
                            event_type=EventType(data["event_type"]),
                            data=data["data"],
                            timestamp=data.get("timestamp", datetime.utcnow().isoformat())
                        )
                        await callback(ws_message)
                    except Exception:
                        pass


# Global connection manager
connection_manager = ConnectionManager()


class RealtimeService:
    """
    Service for managing real-time safety updates.
    """
    
    def __init__(self, db: Session):
        self.db = db
        self.manager = connection_manager
    
    async def notify_new_report(self, signal: SafetySignal):
        """Broadcast new report to all connected clients"""
        message = WebSocketMessage(
            event_type=EventType.NEW_REPORT,
            data={
                "signal_id": str(signal.id),
                "signal_type": signal.signal_type.value,
                "severity": signal.severity,
                "latitude": signal.latitude,
                "longitude": signal.longitude,
                "geohash": signal.geohash,
                "trust_score": signal.trust_score,
                "timestamp": signal.timestamp.isoformat()
            }
        )
        
        # Broadcast to all subscriptions
        await self.manager.broadcast_to_subscriptions(
            message,
            ["global", "report_updates"]
        )
        
        # Also publish to Redis if available
        await self.manager.publish_event(message)
    
    async def notify_vote_update(
        self,
        signal_id: str,
        true_votes: int,
        false_votes: int,
        new_trust_score: float
    ):
        """Broadcast vote update"""
        message = WebSocketMessage(
            event_type=EventType.VOTE_UPDATE,
            data={
                "signal_id": signal_id,
                "true_votes": true_votes,
                "false_votes": false_votes,
                "trust_score": new_trust_score
            }
        )
        
        await self.manager.broadcast(message, "report_updates")
        await self.manager.publish_event(message)
    
    async def notify_report_delete(self, signal_id: str):
        """Broadcast report deletion"""
        message = WebSocketMessage(
            event_type=EventType.REPORT_DELETE,
            data={"signal_id": signal_id}
        )
        
        await self.manager.broadcast_to_subscriptions(
            message,
            ["global", "report_updates"]
        )
        await self.manager.publish_event(message)
    
    async def notify_pulse_update(
        self,
        tile_id: str,
        intensity: float,
        confidence: str,
        radius: Optional[int] = None,
        dominant_reason: Optional[str] = None
    ):
        """Broadcast pulse tile update with full data"""
        message = WebSocketMessage(
            event_type=EventType.PULSE_UPDATE,
            data={
                "tile_id": tile_id,
                "intensity": intensity,
                "confidence": confidence,
                "radius": radius,
                "dominant_reason": dominant_reason,
                "timestamp": datetime.utcnow().isoformat()
            }
        )
        
        await self.manager.broadcast(message, "pulse_updates")
        await self.manager.publish_event(message)
    
    async def notify_spike_detected(
        self,
        geohash: str,
        latitude: float,
        longitude: float,
        report_count: int
    ):
        """Broadcast spike detection alert"""
        message = WebSocketMessage(
            event_type=EventType.SPIKE_DETECTED,
            data={
                "geohash": geohash,
                "latitude": latitude,
                "longitude": longitude,
                "report_count": report_count,
                "message": f"⚠️ Safety spike detected: {report_count} reports nearby"
            }
        )
        
        await self.manager.broadcast_to_subscriptions(
            message,
            ["global", "alerts"]
        )
        await self.manager.publish_event(message)
    
    async def notify_location_alert(
        self,
        latitude: float,
        longitude: float,
        alert_level: str,
        message: str
    ):
        """Broadcast location-specific alert"""
        message_obj = WebSocketMessage(
            event_type=EventType.LOCATION_ALERT,
            data={
                "latitude": latitude,
                "longitude": longitude,
                "alert_level": alert_level,
                "message": message
            }
        )
        
        await self.manager.broadcast(message_obj, "alerts")
        await self.manager.publish_event(message_obj)


class PollingService:
    """
    Service for handling periodic polling requests.
    This provides a fallback for clients that don't support WebSockets.
    """
    
    def __init__(self, db: Session):
        self.db = db
        self._last_updates: Dict[str, datetime] = {}
    
    async def get_updates_since(
        self,
        lat: float,
        lng: float,
        radius_km: float,
        last_update: Optional[datetime] = None
    ) -> Dict[str, Any]:
        """
        Get all updates since a given timestamp.
        
        Args:
            lat: Center latitude
            lng: Center longitude
            radius_km: Search radius
            last_update: Only get updates after this time
            
        Returns:
            Dictionary with new reports, updates, and deletions
        """
        if last_update is None:
            last_update = datetime.utcnow() - timedelta(hours=24)
        
        # Calculate bounding box
        lat_range = radius_km / 111.0
        lon_range = radius_km / (111.0 * abs(lat))
        
        # Get new reports
        new_reports = self.db.query(SafetySignal).filter(
            SafetySignal.latitude.between(lat - lat_range, lat + lat_range),
            SafetySignal.longitude.between(lng - lon_range, lng + lon_range),
            SafetySignal.timestamp > last_update,
            SafetySignal.is_valid == True
        ).order_by(SafetySignal.timestamp).all()
        
        # Get updated pulse tiles
        pulse_updates = self.db.query(PulseTile).filter(
            PulseTile.last_updated > last_update
        ).all()
        
        # Get recent spikes
        from app.services.pattern_detection import PatternDetectionService
        pattern_service = PatternDetectionService(self.db)
        spikes = pattern_service.detect_spikes()
        
        return {
            "new_reports": [
                {
                    "id": str(r.id),
                    "signal_type": r.signal_type.value,
                    "severity": r.severity,
                    "latitude": r.latitude,
                    "longitude": r.longitude,
                    "trust_score": r.trust_score,
                    "timestamp": r.timestamp.isoformat()
                }
                for r in new_reports
            ],
            "pulse_updates": [
                {
                    "tile_id": t.tile_id,
                    "pulse_score": t.pulse_score,
                    "confidence": t.confidence_level.value,
                    "timestamp": t.last_updated.isoformat()
                }
                for t in pulse_updates
            ],
            "spikes": spikes,
            "server_time": datetime.utcnow().isoformat()
        }
    
    async def get_pulse_delta(
        self,
        lat: float,
        lng: float,
        radius_km: float,
        version: Optional[int] = None
    ) -> Dict[str, Any]:
        """
        Get pulse updates using version-based delta.
        
        This is more efficient than timestamp-based polling.
        
        Args:
            lat: Center latitude
            lng: Center longitude
            radius_km: Search radius
            version: Last known version number
            
        Returns:
            Dictionary with current pulse data and new version
        """
        # Get current pulse tiles
        lat_range = radius_km / 111.0
        lon_range = radius_km / (111.0 * abs(lat))
        
        # Get the latest report timestamp as a version marker
        latest_report = self.db.query(SafetySignal).filter(
            SafetySignal.latitude.between(lat - lat_range, lat + lat_range),
            SafetySignal.longitude.between(lng - lon_range, lng + lon_range),
            SafetySignal.is_valid == True
        ).order_by(SafetySignal.timestamp.desc()).first()
        
        if not latest_report:
            return {
                "tiles": [],
                "version": 0,
                "has_updates": False
            }
        
        # Calculate a version number based on recent activity
        current_version = int(latest_report.timestamp.timestamp())
        
        # Get tiles in the area
        tiles = self.db.query(PulseTile).all()
        
        tile_data = [
            {
                "tile_id": t.tile_id,
                "pulse_score": t.pulse_score,
                "confidence": t.confidence_level.value,
                "signal_count": t.signal_count
            }
            for t in tiles
        ]
        
        has_updates = version is None or current_version > version
        
        return {
            "tiles": tile_data,
            "version": current_version,
            "has_updates": has_updates,
            "updated_at": datetime.utcnow().isoformat()
        }


class WebSocketHandler:
    """
    Handler for WebSocket connections and messages.
    """
    
    @staticmethod
    async def handle_connection(websocket, subscription: str = "global"):
        """Handle a WebSocket connection"""
        await connection_manager.connect(websocket, subscription)
        
        try:
            while True:
                # Wait for messages from client
                data = await websocket.receive_json()
                
                # Handle different message types
                await WebSocketHandler._handle_message(
                    websocket,
                    data,
                    subscription
                )
        except Exception:
            pass
        finally:
            await connection_manager.disconnect(websocket, subscription)
    
    @staticmethod
    async def _handle_message(
        websocket,
        data: Dict[str, Any],
        subscription: str
    ):
        """Handle incoming WebSocket messages"""
        message_type = data.get("type")
        
        if message_type == "ping":
            # Respond to ping with pong
            await websocket.send_json({"type": "pong"})
        
        elif message_type == "subscribe":
            # Subscribe to additional topics
            topics = data.get("topics", [])
            for topic in topics:
                await connection_manager.disconnect(websocket, subscription)
                await connection_manager.connect(websocket, topic)
        
        elif message_type == "unsubscribe":
            # Unsubscribe from topics
            topics = data.get("topics", [])
            for topic in topics:
                await connection_manager.disconnect(websocket, topic)
        
        elif message_type == "location_update":
            # Client updated their location
            lat = data.get("latitude")
            lng = data.get("longitude")
            if lat and lng:
                # Send nearby alerts for this location
                await WebSocketHandler._send_location_alerts(
                    websocket,
                    lat,
                    lng
                )
        
        elif message_type == "request_pulse":
            # Client requested pulse data for an area
            lat = data.get("latitude")
            lng = data.get("longitude")
            radius = data.get("radius", 10.0)
            if lat and lng:
                await WebSocketHandler._send_pulse_data(
                    websocket,
                    lat,
                    lng,
                    radius
                )
    
    @staticmethod
    async def _send_location_alerts(
        websocket,
        lat: float,
        lng: float
    ):
        """Send alerts for a specific location"""
        from app.services.pattern_detection import PatternDetectionService
        
        db = Session()
        try:
            pattern_service = PatternDetectionService(db)
            alert = pattern_service.get_personalized_alert(
                lat, lng, datetime.utcnow().hour
            )
            
            await websocket.send_json({
                "type": "location_alert",
                "data": alert
            })
        finally:
            db.close()
    
    @staticmethod
    async def _send_pulse_data(
        websocket,
        lat: float,
        lng: float,
        radius_km: float
    ):
        """Send pulse data for an area"""
        from app.services.pulse_aggregation import PulseAggregationService
        
        db = Session()
        try:
            service = PulseAggregationService()
            tiles = service.get_pulse_tiles_in_radius(lat, lng, radius_km)
            
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

