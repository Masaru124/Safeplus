"""
Smart Scoring Service for Safety Pulse

This service provides intelligent safety scoring that simulates "AI" using
heuristic logic without requiring actual machine learning.

The scoring formula:
    score = (true_votes - false_votes)
            + recent_reports_weight
            + time_of_day_risk
            - report_age_decay

This makes the safety pulse feel "intelligent" by considering:
- Community verification (votes)
- Recency (recent reports matter more)
- Time of day (night hours = higher risk)
- Report age (older reports decay in importance)
"""

import math
from datetime import datetime, timedelta
from typing import Optional, Dict, Any
from sqlalchemy.orm import Session
from sqlalchemy import func

from app.models import SafetySignal, DeviceActivity


class SmartScoringService:
    """
    Intelligent scoring service that provides "AI-like" safety assessment
    without requiring actual machine learning models.
    """
    
    # Configuration constants
    RECENT_WINDOW_HOURS = 24  # Reports within this window get weight boost
    RECENT_WINDOW_WEIGHT = 0.3  # Maximum weight for recent reports
    
    # Night hours for risk boost (10 PM - 6 AM)
    NIGHT_START_HOUR = 22  # 10 PM
    NIGHT_END_HOUR = 6    # 6 AM
    
    # Time decay constants
    DECAY_HALF_LIFE_HOURS = 72  # Score halves every 3 days
    
    # Spike detection thresholds
    SPIKE_REPORT_COUNT = 10
    SPIKE_TIME_WINDOW_MINUTES = 30
    
    def __init__(self, db: Session):
        self.db = db
    
    def calculate_smart_score(
        self,
        signal: SafetySignal,
        include_votes: bool = True,
        include_time_risk: bool = True,
        include_recency: bool = True,
        include_spike_boost: bool = True,
        persist: bool = False  # New parameter to persist score
    ) -> float:
        """
        Calculate an intelligent safety score for a signal.
        
        Args:
            signal: The SafetySignal to score
            include_votes: Include community verification score
            include_time_risk: Include time-of-day risk boost
            include_recency: Include recent reports weight
            include_spike_boost: Include spike detection boost
            persist: Whether to persist the score to the database
            
        Returns:
            Smart score between 0.0 and 1.0
        """
        # Start with base trust score
        base_score = signal.trust_score
        
        # 1. Community Verification Score
        vote_score = 0.5  # Neutral starting point
        if include_votes and signal.true_votes and signal.false_votes:
            true_votes = signal.true_votes
            false_votes = signal.false_votes
            total_votes = true_votes + false_votes
            
            if total_votes > 0:
                trust_ratio = true_votes / total_votes
                # Bayesian-style blend towards neutral for low vote counts
                vote_weight = min(0.4, total_votes / 10 * 0.4)
                vote_score = 0.5 * (1 - vote_weight) + trust_ratio * vote_weight
        
        # 2. Recency Weight
        recency_weight = 0.5  # Neutral
        if include_recency:
            age_hours = (datetime.utcnow() - signal.timestamp).total_seconds() / 3600
            if age_hours < self.RECENT_WINDOW_HOURS:
                recency_weight = 1.0 - (age_hours / self.RECENT_WINDOW_HOURS) * 0.3
            else:
                recency_weight = 0.7
        
        # 3. Time of Day Risk
        time_risk = 0.0
        if include_time_risk:
            current_hour = datetime.utcnow().hour
            # Check if current time is in night hours (considering midnight wrap)
            is_night = (
                current_hour >= self.NIGHT_START_HOUR or 
                current_hour < self.NIGHT_END_HOUR
            )
            if is_night:
                time_risk = 0.15  # 15% boost for night hours
        
        # 4. Report Age Decay
        age_decay = 1.0
        age_hours = (datetime.utcnow() - signal.timestamp).total_seconds() / 3600
        age_decay = math.exp(-age_hours / self.DECAY_HALF_LIFE_HOURS)
        
        # 5. Spike Detection Boost
        spike_boost = 0.0
        if include_spike_boost and self._is_in_spike_window(signal):
            spike_boost = 0.2  # 20% boost for spike areas
        
        # 6. Severity Weight
        severity_weight = signal.severity / 5.0  # 0.2 to 1.0
        
        # Combine all factors
        final_score = (
            base_score * 0.3 +
            vote_score * 0.25 +
            recency_weight * 0.15 +
            (0.5 + time_risk) * 0.1 +
            age_decay * 0.1 +
            (0.5 + spike_boost) * 0.1
        ) * severity_weight * 2  # Apply severity and scale to 0-1
        
        # Ensure bounds
        final_score = max(0.0, min(1.0, final_score))
        
        # Persist the score if requested
        if persist:
            signal.confidence_score = final_score
            signal.severity_weight = severity_weight
            signal.last_activity_at = datetime.utcnow()
            self.db.add(signal)
            self.db.commit()
        
        return final_score
    
    def calculate_tile_safety_score(
        self,
        tile_id: str,
        signals: list[SafetySignal]
    ) -> Dict[str, Any]:
        """
        Calculate comprehensive safety score for a geographic tile.
        
        Args:
            tile_id: The geohash tile identifier
            signals: List of signals in this tile
            
        Returns:
            Dictionary with safety metrics
        """
        if not signals:
            return {
                "tile_id": tile_id,
                "safety_score": 0.5,
                "risk_level": "unknown",
                "confidence": "low",
                "signal_count": 0,
                "is_spike": False,
                "spike_message": None
            }
        
        # Calculate base score from individual signals
        total_score = 0.0
        for signal in signals:
            score = self.calculate_smart_score(signal)
            total_score += score
        
        avg_score = total_score / len(signals)
        
        # Apply signal density boost
        density_boost = min(0.2, len(signals) * 0.02)
        avg_score = min(1.0, avg_score + density_boost)
        
        # Determine risk level
        if avg_score >= 0.7:
            risk_level = "high"
        elif avg_score >= 0.5:
            risk_level = "medium"
        elif avg_score >= 0.3:
            risk_level = "low"
        else:
            risk_level = "safe"
        
        # Confidence based on signal count
        if len(signals) >= 10:
            confidence = "high"
        elif len(signals) >= 5:
            confidence = "medium"
        else:
            confidence = "low"
        
        # Check for spike
        is_spike, spike_message = self._detect_spike(tile_id, signals)
        spike_boost = 0.15 if is_spike else 0.0
        
        return {
            "tile_id": tile_id,
            "safety_score": min(1.0, avg_score + spike_boost),
            "risk_level": risk_level,
            "confidence": confidence,
            "signal_count": len(signals),
            "is_spike": is_spike,
            "spike_message": spike_message
        }
    
    def _is_in_spike_window(self, signal: SafetySignal) -> bool:
        """Check if signal is part of a recent spike"""
        cutoff_time = datetime.utcnow() - timedelta(
            minutes=self.SPIKE_TIME_WINDOW_MINUTES
        )
        
        # Count signals in the same tile within the time window
        count = self.db.query(SafetySignal).filter(
            SafetySignal.geohash == signal.geohash,
            SafetySignal.timestamp > cutoff_time,
            SafetySignal.is_valid == True
        ).count()
        
        return count >= self.SPIKE_REPORT_COUNT
    
    def _detect_spike(
        self,
        tile_id: str,
        signals: list[SafetySignal]
    ) -> tuple[bool, Optional[str]]:
        """
        Detect if a tile is experiencing a spike in reports.
        
        Returns:
            Tuple of (is_spike, message)
        """
        if len(signals) < self.SPIKE_REPORT_COUNT:
            return False, None
        
        # Find the time range of signals
        timestamps = [s.timestamp for s in signals]
        min_time = min(timestamps)
        max_time = max(timestamps)
        time_range_minutes = (max_time - min_time).total_seconds() / 60
        
        if time_range_minutes <= self.SPIKE_TIME_WINDOW_MINUTES:
            message = (
                f"Spike detected: {len(signals)} reports in "
                f"{int(time_range_minutes)} minutes"
            )
            return True, message
        
        return False, None
    
    def get_time_of_day_risk(self) -> Dict[str, Any]:
        """
        Get current time-based risk assessment.
        
        Returns:
            Dictionary with time risk information
        """
        current_hour = datetime.utcnow().hour
        is_night = (
            current_hour >= self.NIGHT_START_HOUR or 
            current_hour < self.NIGHT_END_HOUR
        )
        
        # Calculate risk multiplier
        if is_night:
            risk_multiplier = 1.3  # 30% higher risk at night
            risk_level = "elevated"
        else:
            risk_multiplier = 1.0
            risk_level = "normal"
        
        return {
            "current_hour": current_hour,
            "is_night": is_night,
            "risk_multiplier": risk_multiplier,
            "risk_level": risk_level
        }
    
    def get_risk_zone_summary(
        self,
        center_lat: float,
        center_lon: float,
        radius_km: float = 10.0
    ) -> Dict[str, Any]:
        """
        Get a summary of risk zones in a given area.
        
        Args:
            center_lat: Center latitude
            center_lon: Center longitude
            radius_km: Search radius in kilometers
            
        Returns:
            Dictionary with risk zone information
        """
        # Import here to avoid circular imports
        import pygeohash as pgh
        from sqlalchemy import and_, or_
        
        # Calculate bounding box
        lat_range = radius_km / 111.0
        lon_range = radius_km / (111.0 * abs(center_lat))
        
        min_lat = center_lat - lat_range
        max_lat = center_lat + lat_range
        min_lon = center_lon - lon_range
        max_lon = center_lon + lon_range
        
        # Get signals in the area
        signals = self.db.query(SafetySignal).filter(
            SafetySignal.latitude.between(min_lat, max_lat),
            SafetySignal.longitude.between(min_lon, max_lon),
            SafetySignal.is_valid == True
        ).all()
        
        # Group by geohash (6 char precision ~ 1.2km x 0.6km tiles)
        tile_signals = {}
        for signal in signals:
            tile_id = pgh.encode(signal.latitude, signal.longitude, precision=6)
            if tile_id not in tile_signals:
                tile_signals[tile_id] = []
            tile_signals[tile_id].append(signal)
        
        # Calculate safety score for each tile
        risk_zones = []
        for tile_id, tile_signals_list in tile_signals.items():
            tile_score = self.calculate_tile_safety_score(tile_id, tile_signals_list)
            if tile_score["risk_level"] in ["high", "medium"]:
                risk_zones.append({
                    "tile_id": tile_id,
                    "risk_level": tile_score["risk_level"],
                    "safety_score": tile_score["safety_score"],
                    "signal_count": tile_score["signal_count"],
                    "is_spike": tile_score["is_spike"],
                    "message": tile_score["spike_message"]
                })
        
        # Sort by safety score (highest risk first)
        risk_zones.sort(key=lambda x: x["safety_score"], reverse=True)
        
        # Overall assessment
        avg_score = sum(z["safety_score"] for z in risk_zones) / len(risk_zones) if risk_zones else 0.5
        
        return {
            "center_lat": center_lat,
            "center_lon": center_lon,
            "radius_km": radius_km,
            "total_signals": len(signals),
            "risk_zone_count": len(risk_zones),
            "overall_risk_score": avg_score,
            "risk_zones": risk_zones[:10],  # Top 10 risk zones
            "time_risk": self.get_time_of_day_risk()
        }


class SpikeDetectionService:
    """
    Service for detecting spikes in safety reports.
    """
    
    SPIKE_REPORT_COUNT = 10
    SPIKE_TIME_WINDOW_MINUTES = 30
    
    def __init__(self, db: Session):
        self.db = db
    
    def detect_spikes(self) -> list[Dict[str, Any]]:
        """
        Detect all spikes in the current time window.
        
        Returns:
            List of spike detections with details
        """
        from sqlalchemy import func
        import pygeohash as pgh
        
        cutoff_time = datetime.utcnow() - timedelta(
            minutes=self.SPIKE_TIME_WINDOW_MINUTES
        )
        
        # Get geohashes with signal counts in the time window
        tile_counts = self.db.query(
            SafetySignal.geohash,
            func.count(SafetySignal.id).label('count')
        ).filter(
            SafetySignal.timestamp > cutoff_time,
            SafetySignal.is_valid == True
        ).group_by(SafetySignal.geohash).having(
            func.count(SafetySignal.id) >= self.SPIKE_REPORT_COUNT
        ).all()
        
        spikes = []
        for geohash, count in tile_counts:
            # Get the signals for this tile
            signals = self.db.query(SafetySignal).filter(
                SafetySignal.geohash == geohash,
                SafetySignal.timestamp > cutoff_time,
                SafetySignal.is_valid == True
            ).all()
            
            if signals:
                # Get centroid of the spike
                avg_lat = sum(s.latitude for s in signals) / len(signals)
                avg_lon = sum(s.longitude for s in signals) / len(signals)
                
                # Get severity breakdown
                severity_breakdown = {}
                for s in signals:
                    severity = s.severity
                    if severity not in severity_breakdown:
                        severity_breakdown[severity] = 0
                    severity_breakdown[severity] += 1
                
                spikes.append({
                    "geohash": geohash,
                    "report_count": count,
                    "latitude": avg_lat,
                    "longitude": avg_lon,
                    "detected_at": datetime.utcnow(),
                    "time_window_minutes": self.SPIKE_TIME_WINDOW_MINUTES,
                    "severity_breakdown": severity_breakdown,
                    "signal_types": list(set(s.signal_type.value for s in signals))
                })
        
        return spikes


class AnomalyDetectionService:
    """
    Service for detecting anomalous patterns in reports.
    """
    
    # Thresholds for anomaly detection
    SPAM_REPORT_THRESHOLD = 5  # Reports from same device in short time
    SPAM_TIME_WINDOW_MINUTES = 10
    SUSPICIOUS_DEVICE_THRESHOLD = 0.3  # Low trust score threshold
    
    def __init__(self, db: Session):
        self.db = db
    
    def detect_anomalies(self) -> Dict[str, Any]:
        """
        Detect various types of anomalies in the report data.
        
        Returns:
            Dictionary with detected anomalies
        """
        anomalies = {
            "spam_reports": self._detect_spam_reports(),
            "suspicious_devices": self._detect_suspicious_devices(),
            "rapid_reports": self._detect_rapid_reports()
        }
        
        return anomalies
    
    def _detect_spam_reports(self) -> list[Dict[str, Any]]:
        """Detect devices that are submitting too many reports (potential spam)"""
        cutoff_time = datetime.utcnow() - timedelta(
            minutes=self.SPAM_TIME_WINDOW_MINUTES
        )
        
        # Get devices with report counts
        device_counts = self.db.query(
            SafetySignal.device_hash,
            func.count(SafetySignal.id).label('count')
        ).filter(
            SafetySignal.timestamp > cutoff_time
        ).group_by(SafetySignal.device_hash).having(
            func.count(SafetySignal.id) >= self.SPAM_REPORT_THRESHOLD
        ).all()
        
        spam_devices = []
        for device_hash, count in device_counts:
            # Get the device activity record
            device_activity = self.db.query(DeviceActivity).filter(
                DeviceActivity.device_hash == device_hash
            ).first()
            
            spam_devices.append({
                "device_hash": device_hash[:8] + "...",  # Partial hash for privacy
                "report_count": count,
                "time_window_minutes": self.SPAM_TIME_WINDOW_MINUTES,
                "anomaly_score": min(1.0, count / 10),
                "is_known_device": device_activity is not None,
                "submission_count": device_activity.submission_count if device_activity else 0
            })
        
        return spam_devices
    
    def _detect_suspicious_devices(self) -> list[Dict[str, Any]]:
        """Detect devices with consistently low trust scores"""
        devices = self.db.query(DeviceActivity).filter(
            DeviceActivity.anomaly_score >= self.SUSPICIOUS_DEVICE_THRESHOLD
        ).all()
        
        suspicious = []
        for device in devices:
            suspicious.append({
                "device_hash": device.device_hash[:8] + "...",
                "anomaly_score": device.anomaly_score,
                "submission_count": device.submission_count,
                "last_submission": device.last_submission.isoformat() if device.last_submission else None
            })
        
        return suspicious
    
    def _detect_rapid_reports(self) -> list[Dict[str, Any]]:
        """Detect rapid-fire report patterns"""
        # This would look for reports with nearly identical timestamps
        # and locations, which could indicate automated spamming
        cutoff_time = datetime.utcnow() - timedelta(hours=1)
        
        # Find reports with identical locations (within geohash precision)
        rapid_reports = self.db.query(
            SafetySignal.geohash,
            func.count(SafetySignal.id).label('count'),
            func.min(SafetySignal.timestamp).label('first_report'),
            func.max(SafetySignal.timestamp).label('last_report')
        ).filter(
            SafetySignal.timestamp > cutoff_time
        ).group_by(SafetySignal.geohash).having(
            func.count(SafetySignal.id) > 3
        ).all()
        
        patterns = []
        for geohash, count, first_report, last_report in rapid_reports:
            if first_report and last_report:
                time_span = (last_report - first_report).total_seconds()
                if time_span < 300:  # Within 5 minutes
                    patterns.append({
                        "geohash": geohash,
                        "report_count": count,
                        "time_span_seconds": time_span,
                        "is_rapid": True
                    })
        
        return patterns

