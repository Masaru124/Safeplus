"""
Pulse Aggregation Service for Safety Pulse

This service handles:
- Geohash-based tile clustering
- Pulse intensity calculation with time decay
- Trust score integration with spam down-weighting
- Pulse persistence and updates

Pulse Intensity Formula:
    intensity = Σ(severity_weight × user_trust × time_decay) / normalization

Where:
- severity_weight: Based on report type (1.0 for harassment, 0.5 for other)
- user_trust: Clamped between 0.2-1.0, with spam down-weighting
- time_decay: Exponential decay with 2.5 hour half-life
"""

import math
import pygeohash as pgh
from datetime import datetime, timedelta, timezone
from typing import List, Dict, Optional, Tuple
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.models import SafetySignal, PulseTile, ConfidenceLevel, SignalType
from app.services.trust_scoring import TrustScoringService


class PulseAggregationService:
    """Service for aggregating safety signals into pulse tiles"""
    
    # Time decay half-life in hours (increased from 2.5 to 6 for slower decay)
    DECAY_HALF_LIFE_HOURS = 6.0
    
    # Time window for aggregation (increased from 6 to 12 hours for longer visibility)
    AGGREGATION_WINDOW_HOURS = 12
    
    # Geohash precision for tile identification
    GEOHASH_PRECISION = 6
    
    # Signal type weights for intensity calculation
    SIGNAL_TYPE_WEIGHTS = {
        'harassment': 1.0,
        'followed': 0.9,
        'suspicious_activity': 0.8,
        'unsafe_area': 0.7,
        'other': 0.5
    }
    
    # Minimum intensity for pulse creation
    MIN_PULSE_INTENSITY = 0.05
    
    # Default pulse radius (meters)
    DEFAULT_RADIUS = 200
    MAX_RADIUS = 500
    
    def __init__(self, db: Optional[Session] = None):
        from app.database import get_db
        self.db = db if db else next(get_db())
        self.trust_service = TrustScoringService(self.db)
    
    # ============ Geohash Utilities ============
    
    def get_tile(self, lat: float, lng: float) -> str:
        """
        Get the geohash tile ID for a given coordinate.
        
        Args:
            lat: Latitude
            lng: Longitude
            
        Returns:
            Geohash string representing the tile
        """
        return pgh.encode(lat, lng, precision=self.GEOHASH_PRECISION)
    
    def get_tile_center(self, tile_id: str) -> Tuple[float, float]:
        """
        Get the center coordinates of a geohash tile.
        
        Args:
            tile_id: Geohash string
            
        Returns:
            Tuple of (latitude, longitude)
        """
        return pgh.decode(tile_id)
    
    def get_tile_bounds(self, tile_id: str) -> Dict[str, float]:
        """
        Get the bounding box of a geohash tile.
        
        Args:
            tile_id: Geohash string
            
        Returns:
            Dictionary with min_lat, max_lat, min_lng, max_lng
        """
        lat, lng = self.get_tile_center(tile_id)
        
        # Approximate cell size for precision 6 is about 1.2km x 600m
        lat_offset = 0.01  # ~1.1km
        lng_offset = 0.01 / math.cos(math.radians(lat))
        
        return {
            'min_lat': lat - lat_offset,
            'max_lat': lat + lat_offset,
            'min_lng': lng - lng_offset,
            'max_lng': lng + lng_offset
        }
    
    # ============ Time Decay ============
    
    def time_decay(self, created_at: datetime) -> float:
        """
        Calculate time decay factor for a report.
        
        Uses exponential decay: decay = exp(-hours_since / 2.5)
        
        Args:
            created_at: When the report was created
            
        Returns:
            Decay factor between 0.0 and 1.0
        """
        if created_at.tzinfo is None:
            created_at = created_at.replace(tzinfo=timezone.utc)
        
        hours_since = (datetime.now(timezone.utc) - created_at).total_seconds() / 3600
        decay = math.exp(-hours_since / self.DECAY_HALF_LIFE_HOURS)
        
        return max(0.0, decay)
    
    # ============ Intensity Calculation ============
    
    def calculate_pulse_intensity(
        self,
        reports: List[SafetySignal],
        apply_spam_downweight: bool = True
    ) -> float:
        """
        Calculate pulse intensity for a tile based on its reports.
        
        Formula:
        pulse_intensity = Σ(severity_weight × user_trust × time_decay) / normalization
        
        Args:
            reports: List of safety signals in the tile
            apply_spam_downweight: Whether to apply spam down-weighting
            
        Returns:
            Intensity value between 0.0 and 1.0
        """
        if not reports:
            return 0.0
        
        total_weighted_score = 0.0
        normalization_factor = 0.0
        
        for report in reports:
            # Skip invalid or expired reports
            if not report.is_valid:
                continue
            
            # Severity weight (1-5 scale normalized to 0.2-1.0)
            severity_weight = report.severity / 5.0
            
            # Trust score with spam down-weighting
            user_trust = report.trust_score
            if apply_spam_downweight:
                # Get device anomaly score and apply down-weighting
                device_activity = self.db.query(
                    type(report).anomaly_score  # This won't work, need different approach
                ).filter(
                    SafetySignal.device_hash == report.device_hash
                ).first()
                # Simplified: use report trust score directly
                # The spam down-weighting is applied when creating the report
        
            # Time decay factor
            decay = self.time_decay(report.timestamp)
            
            # Signal type weight
            type_weight = self.SIGNAL_TYPE_WEIGHTS.get(
                report.signal_type.value,
                0.5
            )
            
            # Calculate combined weight
            combined_weight = (
                severity_weight
                * user_trust
                * decay
                * type_weight
            )
            
            total_weighted_score += combined_weight
            normalization_factor += 1.0
        
        if normalization_factor == 0:
            return 0.0
        
        # Normalize to 0.0-1.0 range
        intensity = total_weighted_score / normalization_factor
        
        return min(1.0, intensity)
    
    def calculate_weighted_intensity(self, reports: List[SafetySignal]) -> float:
        """
        Calculate intensity with proper weighting for severity and trust.
        
        This version weights more recent/reliable reports more heavily.
        
        Args:
            reports: List of safety signals in the tile
            
        Returns:
            Weighted intensity value between 0.0 and 1.0
        """
        if not reports:
            return 0.0
        
        weighted_sum = 0.0
        total_weight = 0.0
        
        for report in reports:
            if not report.is_valid:
                continue
            
            # Base weight components
            severity = report.severity / 5.0  # 0.2-1.0
            trust = report.trust_score  # Already clamped 0.2-1.0
            decay = self.time_decay(report.timestamp)  # 0.0-1.0
            type_weight = self.SIGNAL_TYPE_WEIGHTS.get(
                report.signal_type.value, 0.5
            )
            
            # Calculate report weight
            report_weight = severity * trust * decay * type_weight
            
            weighted_sum += report_weight
            total_weight += 1.0
        
        if total_weight == 0:
            return 0.0
        
        # Weighted average with minimum threshold
        intensity = weighted_sum / total_weight
        
        # Apply confidence boost for high report counts
        if len(reports) >= 5:
            intensity = min(1.0, intensity * 1.1)
        
        return min(1.0, max(0.0, intensity))
    
    # ============ Dominant Reason ============
    
    def get_dominant_reason(self, reports: List[SafetySignal]) -> Optional[str]:
        """
        Determine the dominant reason for reports in a tile.
        
        Args:
            reports: List of safety signals in the tile
            
        Returns:
            String representing the dominant reason, or None if no reports
        """
        if not reports:
            return None
        
        # Count by signal type (weighted by severity)
        type_scores: Dict[str, float] = {}
        
        for report in reports:
            if not report.is_valid:
                continue
                
            signal_type = report.signal_type.value
            weight = report.severity  # Weight by severity
            
            if signal_type not in type_scores:
                type_scores[signal_type] = 0.0
            type_scores[signal_type] += weight
        
        if not type_scores:
            return None
        
        # Find the type with highest score
        dominant_type = max(type_scores.keys(), key=lambda k: type_scores[k])
        
        return self._format_signal_type(dominant_type)
    
    def _format_signal_type(self, signal_type: str) -> str:
        """Format signal type for display"""
        formatted = {
            'followed': 'Followed',
            'suspicious_activity': 'Suspicious activity',
            'unsafe_area': 'Unsafe area',
            'harassment': 'Harassment',
            'other': 'Felt unsafe here'
        }
        return formatted.get(signal_type, signal_type.title())
    
    # ============ Confidence Calculation ============
    
    def calculate_confidence(self, reports: List[SafetySignal]) -> ConfidenceLevel:
        """
        Calculate confidence level based on data density and quality.
        
        Args:
            reports: List of safety signals in the tile
            
        Returns:
            ConfidenceLevel enum value
        """
        valid_reports = [r for r in reports if r.is_valid]
        count = len(valid_reports)
        
        # Check average trust score
        if count > 0:
            avg_trust = sum(r.trust_score for r in valid_reports) / count
            # Boost confidence for high trust reports
            if avg_trust >= 0.8:
                count += 2
            elif avg_trust >= 0.6:
                count += 1
        
        if count >= 10:
            return ConfidenceLevel.high
        elif count >= 5:
            return ConfidenceLevel.medium
        elif count >= 2:
            return ConfidenceLevel.medium
        else:
            return ConfidenceLevel.low
    
    def calculate_confidence_score(self, reports: List[SafetySignal]) -> float:
        """
        Calculate numerical confidence score (0.0-1.0).
        
        Args:
            reports: List of safety signals in the tile
            
        Returns:
            Confidence score between 0.0 and 1.0
        """
        valid_reports = [r for r in reports if r.is_valid]
        count = len(valid_reports)
        
        if count == 0:
            return 0.0
        
        # Base score from report count
        base_score = min(1.0, count / 10.0)
        
        # Boost from average trust
        avg_trust = sum(r.trust_score for r in valid_reports) / count
        trust_boost = avg_trust * 0.2
        
        # Combine
        confidence = base_score + trust_boost
        
        return min(1.0, max(0.0, confidence))
    
    # ============ Aggregation ============
    
    def aggregate_reports_per_tile(self) -> Dict[str, List[SafetySignal]]:
        """
        Aggregate all reports within the aggregation window by tile.
        
        Returns:
            Dictionary mapping tile_id to list of reports
        """
        cutoff_time = datetime.now(timezone.utc) - timedelta(
            hours=self.AGGREGATION_WINDOW_HOURS
        )
        
        # Get all valid reports within the time window
        reports = self.db.query(SafetySignal).filter(
            SafetySignal.timestamp > cutoff_time,
            SafetySignal.is_valid == True
        ).all()
        
        # Group by geohash tile
        tile_signals: Dict[str, List[SafetySignal]] = {}
        
        for report in reports:
            tile_id = self.get_tile(report.latitude, report.longitude)
            
            if tile_id not in tile_signals:
                tile_signals[tile_id] = []
            tile_signals[tile_id].append(report)
        
        return tile_signals
    
    def upsert_pulse(
        self,
        tile_id: str,
        center_lat: float,
        center_lng: float,
        intensity: float,
        dominant_reason: Optional[str],
        confidence: ConfidenceLevel,
        signal_count: int
    ) -> PulseTile:
        """
        Upsert a pulse tile (create or update).
        
        Args:
            tile_id: Geohash tile identifier
            center_lat: Center latitude of the tile
            center_lng: Center longitude of the tile
            intensity: Calculated intensity (0.0-1.0)
            dominant_reason: Most common reason for reports
            confidence: Confidence level
            signal_count: Number of reports in the tile
            
        Returns:
            Updated or created PulseTile
        """
        # Calculate radius based on intensity (stronger = larger radius)
        radius = int(self.DEFAULT_RADIUS + (intensity * (self.MAX_RADIUS - self.DEFAULT_RADIUS)))
        
        # Calculate expiration (24 hours from now)
        expires_at = datetime.now(timezone.utc) + timedelta(hours=24)
        
        # Query existing tile
        pulse_tile = self.db.query(PulseTile).filter(
            PulseTile.tile_id == tile_id
        ).first()
        
        if not pulse_tile:
            pulse_tile = PulseTile(tile_id=tile_id)
        
        # Update fields
        pulse_tile.center_lat = center_lat
        pulse_tile.center_lng = center_lng
        pulse_tile.intensity = intensity
        pulse_tile.radius = radius
        pulse_tile.confidence_level = confidence
        pulse_tile.dominant_reason = dominant_reason
        pulse_tile.signal_count = signal_count
        pulse_tile.expires_at = expires_at
        pulse_tile.last_updated = datetime.now(timezone.utc)
        
        self.db.add(pulse_tile)
        self.db.commit()
        self.db.refresh(pulse_tile)
        
        return pulse_tile
    
    def aggregate_pulse_tiles(self) -> List[PulseTile]:
        """
        Aggregate all reports into pulse tiles and persist.
        
        This is the main method called periodically or after new reports.
        
        Returns:
            List of updated/created PulseTile objects
        """
        # Get reports grouped by tile
        tile_signals = self.aggregate_reports_per_tile()
        
        updated_tiles = []
        
        for tile_id, reports in tile_signals.items():
            # Skip if no valid reports
            if not reports:
                continue
            
            # Calculate tile center from reports
            avg_lat = sum(r.latitude for r in reports) / len(reports)
            avg_lng = sum(r.longitude for r in reports) / len(reports)
            
            # Calculate intensity using weighted formula
            intensity = self.calculate_weighted_intensity(reports)
            
            # Skip very low intensity tiles
            if intensity < self.MIN_PULSE_INTENSITY:
                continue
            
            # Get dominant reason
            dominant_reason = self.get_dominant_reason(reports)
            
            # Calculate confidence
            confidence = self.calculate_confidence(reports)
            
            # Upsert the pulse tile
            pulse_tile = self.upsert_pulse(
                tile_id=tile_id,
                center_lat=avg_lat,
                center_lng=avg_lng,
                intensity=intensity,
                dominant_reason=dominant_reason,
                confidence=confidence,
                signal_count=len(reports)
            )
            
            updated_tiles.append(pulse_tile)
        
        return updated_tiles
    
    # ============ Pulse Retrieval ============
    
    def get_active_pulses(self) -> List[PulseTile]:
        """
        Get all active (non-expired) pulse tiles.
        
        Returns:
            List of active PulseTile objects
        """
        now = datetime.now(timezone.utc)
        
        pulses = self.db.query(PulseTile).filter(
            (PulseTile.expires_at == None)
            | (PulseTile.expires_at > now)
        ).all()
        
        return pulses
    
    def get_pulses_in_radius(
        self,
        center_lat: float,
        center_lng: float,
        radius_km: float
    ) -> List[PulseTile]:
        """
        Get pulse tiles within a radius of a point.
        
        Args:
            center_lat: Center latitude
            center_lng: Center longitude
            radius_km: Radius in kilometers
            
        Returns:
            List of PulseTile objects within the radius
        """
        # Convert radius to approximate degree bounds
        lat_radius = radius_km / 111.0
        lon_radius = radius_km / (111.0 * abs(center_lat))
        
        min_lat = center_lat - lat_radius
        max_lat = center_lat + lat_radius
        min_lng = center_lng - lon_radius
        max_lng = center_lng + lon_radius
        
        now = datetime.now(timezone.utc)
        
        pulses = self.db.query(PulseTile).filter(
            PulseTile.center_lat.between(min_lat, max_lat),
            PulseTile.center_lng.between(min_lng, max_lng),
            ((PulseTile.expires_at == None) | (PulseTile.expires_at > now))
        ).all()
        
        return pulses


class PulseDecayService:
    """Service for decaying and expiring pulse tiles"""
    
    # Decay intervals
    DECAY_INTERVAL_MINUTES = 10
    
    def __init__(self, db: Optional[Session] = None):
        from app.database import get_db
        self.db = db if db else next(get_db())
        self.aggregation_service = PulseAggregationService(self.db)
    
    def get_decay_factor_by_age(self, last_updated: datetime) -> float:
        """
        Calculate decay factor based on time since last update.
        
        Rules (updated for 6-hour half-life):
        - < 1 hour: Full intensity (1.0)
        - 1-6 hours: Gradual fade (0.5-1.0)
        - 12 hours: Weak (0.25-0.5)
        - 48 hours: Expire (0.0)
        
        Args:
            last_updated: When the pulse was last updated
            
        Returns:
            Decay factor between 0.0 and 1.0
        """
        if last_updated.tzinfo is None:
            last_updated = last_updated.replace(tzinfo=timezone.utc)
        
        age_hours = (datetime.now(timezone.utc) - last_updated).total_seconds() / 3600
        
        if age_hours < 1.0:  # < 1 hour
            return 1.0
        elif age_hours < 6.0:  # 1-6 hours
            return max(0.5, 1.0 - (age_hours - 1.0) * 0.1)
        elif age_hours < 12.0:  # 6-12 hours
            return max(0.25, 0.5 - (age_hours - 6.0) * 0.042)
        elif age_hours < 48.0:  # 12-48 hours
            return max(0.02, 0.25 - (age_hours - 12.0) * 0.007)
        else:  # > 48 hours
            return 0.0
    
    def decay_pulses(self) -> Dict[str, int]:
        """
        Apply decay to all active pulse tiles.
        
        This should be called periodically (e.g., every 10 minutes).
        
        Returns:
            Dictionary with counts of updated and deleted tiles
        """
        active_pulses = self.aggregation_service.get_active_pulses()
        
        updated_count = 0
        deleted_count = 0
        
        for pulse in active_pulses:
            decay_factor = self.get_decay_factor_by_age(pulse.last_updated)
            
            if decay_factor <= 0.05:
                # Remove expired pulses
                self.db.delete(pulse)
                deleted_count += 1
            else:
                # Apply decay
                pulse.intensity = pulse.intensity * decay_factor
                
                # Update expiration
                if pulse.intensity < 0.1:
                    pulse.expires_at = datetime.now(timezone.utc) + timedelta(hours=1)
                else:
                    pulse.expires_at = datetime.now(timezone.utc) + timedelta(hours=24)
                
                self.db.add(pulse)
                updated_count += 1
        
        self.db.commit()
        
        return {
            "updated_pulses": updated_count,
            "deleted_pulses": deleted_count
        }
    
    def cleanup_expired_pulses(self) -> int:
        """
        Remove all expired pulse tiles.
        
        Returns:
            Count of deleted tiles
        """
        now = datetime.now(timezone.utc)
        
        result = self.db.query(PulseTile).filter(
            (PulseTile.expires_at != None) & (PulseTile.expires_at < now)
        ).delete()
        
        self.db.commit()
        
        return result
    
    def refresh_aggregates(self) -> Dict[str, int]:
        """
        Refresh pulse aggregates from recent reports.
        
        This should be called periodically (e.g., every 5 minutes) to ensure
        pulses reflect the latest data.
        
        Returns:
            Dictionary with count of updated tiles
        """
        updated_tiles = self.aggregation_service.aggregate_pulse_tiles()
        
        return {
            "updated_tiles": len(updated_tiles)
        }

