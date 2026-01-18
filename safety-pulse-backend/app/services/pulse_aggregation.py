import math
from datetime import datetime, timedelta
from typing import List, Dict
from sqlalchemy.orm import Session
from sqlalchemy import func
import pygeohash as pgh
from app.models import SafetySignal, PulseTile, ConfidenceLevel
from app.database import get_db

class PulseAggregationService:
    def __init__(self):
        self.db: Session = next(get_db())

    def aggregate_pulse_tiles(self):
        """Aggregate safety signals into pulse tiles"""
        # Get signals from the last aggregation period (e.g., last hour)
        cutoff_time = datetime.utcnow() - timedelta(hours=1)

        signals = self.db.query(SafetySignal).filter(
            SafetySignal.timestamp > cutoff_time,
            SafetySignal.is_valid == True
        ).all()

        # Group signals by geohash tile
        tile_signals: Dict[str, List[SafetySignal]] = {}
        for signal in signals:
            geohash = pgh.encode(signal.latitude, signal.longitude, precision=6)
            if geohash not in tile_signals:
                tile_signals[geohash] = []
            tile_signals[geohash].append(signal)

        # Calculate pulse score for each tile
        for tile_id, tile_signals_list in tile_signals.items():
            pulse_score = self._calculate_pulse_score(tile_signals_list)
            confidence = self._calculate_confidence(len(tile_signals_list))

            # Update or create pulse tile
            pulse_tile = self.db.query(PulseTile).filter(
                PulseTile.tile_id == tile_id
            ).first()

            if not pulse_tile:
                pulse_tile = PulseTile(tile_id=tile_id)

            pulse_tile.pulse_score = pulse_score
            pulse_tile.confidence_level = confidence
            pulse_tile.signal_count = len(tile_signals_list)
            pulse_tile.last_updated = datetime.utcnow()

            self.db.add(pulse_tile)

        self.db.commit()

    def _calculate_pulse_score(self, signals: List[SafetySignal]) -> int:
        """Calculate Safety Pulse Index (0-100)"""
        if not signals:
            return 0

        total_weight = 0
        weighted_sum = 0

        for signal in signals:
            # Signal type weights
            type_weights = {
                'harassment': 1.0,
                'followed': 0.9,
                'suspicious_activity': 0.8,
                'unsafe_area': 0.7,
                'other': 0.5
            }

            type_weight = type_weights.get(signal.signal_type.value, 0.5)

            # Severity weight (1-5 scale)
            severity_weight = signal.severity / 5.0

            # Trust score weight
            trust_weight = signal.trust_score

            # Recency decay (exponential decay over time)
            hours_old = (datetime.utcnow() - signal.timestamp).total_seconds() / 3600
            recency_decay = math.exp(-hours_old / 24)  # Half-life of 24 hours

            # Combine weights
            signal_weight = type_weight * severity_weight * trust_weight * recency_decay

            weighted_sum += signal_weight * signal.severity
            total_weight += signal_weight

        if total_weight == 0:
            return 0

        # Normalize to 0-100 scale
        avg_severity = weighted_sum / total_weight
        pulse_score = min(100, int(avg_severity * 20))  # Scale 1-5 severity to 0-100

        return pulse_score

    def _calculate_confidence(self, signal_count: int) -> ConfidenceLevel:
        """Calculate confidence level based on data density"""
        if signal_count >= 10:
            return ConfidenceLevel.high
        elif signal_count >= 5:
            return ConfidenceLevel.medium
        else:
            return ConfidenceLevel.low

    def decay_old_tiles(self):
        """Apply decay to tiles with no recent signals"""
        cutoff_time = datetime.utcnow() - timedelta(days=7)

        old_tiles = self.db.query(PulseTile).filter(
            PulseTile.last_updated < cutoff_time
        ).all()

        for tile in old_tiles:
            # Exponential decay
            days_old = (datetime.utcnow() - tile.last_updated).days
            decay_factor = math.exp(-days_old / 30)  # 30-day half-life

            tile.pulse_score = int(tile.pulse_score * decay_factor)

            # If pulse score drops to 0, remove tile
            if tile.pulse_score == 0:
                self.db.delete(tile)
            else:
                self.db.add(tile)

        self.db.commit()

    def get_pulse_tiles_in_radius(self, center_lat: float, center_lon: float,
                                radius_km: float) -> List[PulseTile]:
        """Get pulse tiles within a radius of a point"""
        # Convert radius to approximate degree bounds
        lat_radius = radius_km / 111.0  # 1 degree lat ~ 111km
        lon_radius = radius_km / (111.0 * math.cos(math.radians(center_lat)))

        min_lat = center_lat - lat_radius
        max_lat = center_lat + lat_radius
        min_lon = center_lon - lon_radius
        max_lon = center_lon + lon_radius

        # Get tiles in bounding box
        tiles = self.db.query(PulseTile).filter(
            PulseTile.tile_id.in_(
                self.db.query(SafetySignal.geohash).filter(
                    SafetySignal.latitude.between(min_lat, max_lat),
                    SafetySignal.longitude.between(min_lon, max_lon)
                ).distinct()
            )
        ).all()

        return tiles
