"""
Pattern Detection Service for Safety Pulse

This service implements pattern detection without requiring actual ML:
- Spike detection (10+ reports in 30 min)
- Location clustering
- Time-based anomaly detection
- Spam report detection
- User trust weighting

These patterns make the safety pulse feel "intelligent".
"""

import math
from datetime import datetime, timedelta
from typing import List, Dict, Optional, Any
from sqlalchemy.orm import Session
from sqlalchemy import func, and_, or_
import pygeohash as pgh
import uuid

from app.models import SafetySignal, DeviceActivity, User, ReportVerification, SafetyPattern, AnomalyAlert


class PatternDetectionService:
    """
    Service for detecting patterns in safety reports.
    
    This provides "AI-like" pattern detection using heuristic logic:
    - Cluster reports by location
    - Detect spikes in short time windows
    - Flag anomalous patterns
    - Calculate risk scores for zones
    """
    
    # Configuration
    SPIKE_REPORT_COUNT = 10
    SPIKE_TIME_WINDOW_MINUTES = 30
    
    CLUSTER_RADIUS_KM = 1.0  # For grouping nearby reports
    
    SPAM_REPORT_THRESHOLD = 5
    SPAM_TIME_WINDOW_MINUTES = 10
    
    REPORT_DECAY_DAYS = 7  # Older reports have less weight
    
    def __init__(self, db: Session):
        self.db = db
    
    def run_full_pattern_analysis(self) -> Dict[str, Any]:
        """
        Run complete pattern analysis on all recent data.
        
        Returns:
            Dictionary with all pattern analysis results
        """
        results = {
            "analyzed_at": datetime.utcnow().isoformat(),
            "spikes": self.detect_spikes(),
            "clusters": self.detect_clusters(),
            "anomalies": self.detect_anomalies(),
            "risk_zones": self.calculate_risk_zones()
        }
        
        return results
    
    def detect_spikes(self) -> List[Dict[str, Any]]:
        """
        Detect spikes: areas with unusually high report counts in short time windows.
        
        Example: "10 people report unsafe here in 30 min → spike"
        """
        cutoff_time = datetime.utcnow() - timedelta(
            minutes=self.SPIKE_TIME_WINDOW_MINUTES
        )
        
        # Get geohashes with signal counts in the time window
        # Use 6-char precision (~1.2km x 0.6km tiles)
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
            # Get the signals for this spike
            signals = self.db.query(SafetySignal).filter(
                SafetySignal.geohash == geohash,
                SafetySignal.timestamp > cutoff_time,
                SafetySignal.is_valid == True
            ).all()
            
            if signals:
                # Get centroid of the spike
                avg_lat = sum(s.latitude for s in signals) / len(signals)
                avg_lon = sum(s.longitude for s in signals) / len(signals)
                
                # Calculate spike intensity (0-1)
                spike_intensity = min(1.0, count / 20)
                
                # Get severity breakdown
                severity_breakdown = {}
                for s in signals:
                    severity = s.severity
                    if severity not in severity_breakdown:
                        severity_breakdown[severity] = 0
                    severity_breakdown[severity] += 1
                
                # Get time range
                timestamps = [s.timestamp for s in signals]
                time_range = (max(timestamps) - min(timestamps)).total_seconds() / 60
                
                spikes.append({
                    "id": str(uuid.uuid4()),
                    "geohash": geohash,
                    "latitude": avg_lat,
                    "longitude": avg_lon,
                    "report_count": count,
                    "spike_intensity": spike_intensity,
                    "time_window_minutes": self.SPIKE_TIME_WINDOW_MINUTES,
                    "actual_time_range_minutes": round(time_range, 2),
                    "severity_breakdown": severity_breakdown,
                    "signal_types": list(set(s.signal_type.value for s in signals)),
                    "detected_at": datetime.utcnow().isoformat(),
                    "message": f"Spike detected: {count} reports in {int(time_range)} minutes"
                })
        
        return spikes
    
    def detect_clusters(self) -> List[Dict[str, Any]]:
        """
        Detect clusters: groups of related safety reports.
        
        This groups reports by location to identify problem areas.
        """
        # Get recent signals (last 24 hours)
        cutoff_time = datetime.utcnow() - timedelta(hours=24)
        
        signals = self.db.query(SafetySignal).filter(
            SafetySignal.timestamp > cutoff_time,
            SafetySignal.is_valid == True
        ).all()
        
        if not signals:
            return []
        
        # Group by geohash (7-char precision ~ 150m x 150m)
        tile_signals: Dict[str, List[SafetySignal]] = {}
        for signal in signals:
            tile_id = pgh.encode(signal.latitude, signal.longitude, precision=7)
            if tile_id not in tile_signals:
                tile_signals[tile_id] = []
            tile_signals[tile_id].append(signal)
        
        # Find clusters with multiple reports
        clusters = []
        for tile_id, tile_signals_list in tile_signals.items():
            if len(tile_signals_list) >= 2:  # At least 2 reports to form a cluster
                # Calculate cluster metrics
                avg_severity = sum(s.severity for s in tile_signals_list) / len(tile_signals_list)
                avg_trust = sum(s.trust_score for s in tile_signals_list) / len(tile_signals_list)
                
                # Get the centroid
                avg_lat = sum(s.latitude for s in tile_signals_list) / len(tile_signals_list)
                avg_lon = sum(s.longitude for s in tile_signals_list) / len(tile_signals_list)
                
                # Calculate cluster intensity
                intensity = min(1.0, len(tile_signals_list) / 10) * (avg_severity / 5)
                
                clusters.append({
                    "id": str(uuid.uuid4()),
                    "geohash": tile_id,
                    "latitude": avg_lat,
                    "longitude": avg_lon,
                    "report_count": len(tile_signals_list),
                    "avg_severity": round(avg_severity, 2),
                    "avg_trust_score": round(avg_trust, 2),
                    "intensity": round(intensity, 2),
                    "signal_types": list(set(s.signal_type.value for s in tile_signals_list)),
                    "detected_at": datetime.utcnow().isoformat()
                })
        
        # Sort by intensity (highest first)
        clusters.sort(key=lambda x: x["intensity"], reverse=True)
        
        return clusters[:50]  # Limit to top 50 clusters
    
    def detect_anomalies(self) -> Dict[str, List[Dict[str, Any]]]:
        """
        Detect anomalies in the report data.
        
        Types of anomalies:
        - Spam reports (too many from same device)
        - Suspicious patterns (rapid reports)
        - Unusual hours (reports at odd times)
        - Low trust score accumulation
        """
        anomalies = {
            "spam_devices": self._detect_spam_devices(),
            "rapid_reports": self._detect_rapid_reports(),
            "low_trust_patterns": self._detect_low_trust_patterns()
        }
        
        return anomalies
    
    def _detect_spam_devices(self) -> List[Dict[str, Any]]:
        """Detect devices submitting too many reports"""
        cutoff_time = datetime.utcnow() - timedelta(
            minutes=self.SPAM_TIME_WINDOW_MINUTES
        )
        
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
            device_activity = self.db.query(DeviceActivity).filter(
                DeviceActivity.device_hash == device_hash
            ).first()
            
            # Calculate spam score
            spam_score = min(1.0, count / 10)
            
            # Get recent reports from this device
            recent_reports = self.db.query(SafetySignal).filter(
                SafetySignal.device_hash == device_hash,
                SafetySignal.timestamp > cutoff_time
            ).all()
            
            # Check if all reports have similar severity (potential auto-spam)
            severities = set(s.severity for s in recent_reports)
            pattern_score = 0.8 if len(severities) == 1 else 0.3
            
            spam_devices.append({
                "device_hash": device_hash[:12] + "...",
                "report_count": count,
                "time_window_minutes": self.SPAM_TIME_WINDOW_MINUTES,
                "spam_score": spam_score,
                "pattern_score": pattern_score,
                "severity_pattern": list(severities),
                "is_known_device": device_activity is not None,
                "total_submissions": device_activity.submission_count if device_activity else 0,
                "action_recommended": "down-rank" if spam_score > 0.5 else "monitor"
            })
            
            # Update device anomaly score
            if device_activity:
                device_activity.anomaly_score = spam_score
                self.db.add(device_activity)
        
        self.db.commit()
        
        return spam_devices
    
    def _detect_rapid_reports(self) -> List[Dict[str, Any]]:
        """Detect rapid-fire report patterns"""
        cutoff_time = datetime.utcnow() - timedelta(hours=1)
        
        # Find reports with identical locations (within geohash precision)
        location_counts = self.db.query(
            SafetySignal.geohash,
            func.count(SafetySignal.id).label('count'),
            func.min(SafetySignal.timestamp).label('first_report'),
            func.max(SafetySignal.timestamp).label('last_report')
        ).filter(
            SafetySignal.timestamp > cutoff_time
        ).group_by(SafetySignal.geohash).having(
            func.count(SafetySignal.id) > 3
        ).all()
        
        rapid_patterns = []
        for geohash, count, first_report, last_report in location_counts:
            if first_report and last_report:
                time_span = (last_report - first_report).total_seconds()
                reports_per_minute = count / (time_span / 60) if time_span > 0 else count
                
                if reports_per_minute >= 1:  # More than 1 report per minute
                    # Get centroid
                    signals = self.db.query(SafetySignal).filter(
                        SafetySignal.geohash == geohash,
                        SafetySignal.timestamp > cutoff_time
                    ).all()
                    
                    if signals:
                        avg_lat = sum(s.latitude for s in signals) / len(signals)
                        avg_lon = sum(s.longitude for s in signals) / len(signals)
                        
                        rapid_patterns.append({
                            "geohash": geohash,
                            "report_count": count,
                            "time_span_seconds": time_span,
                            "reports_per_minute": round(reports_per_minute, 2),
                            "latitude": avg_lat,
                            "longitude": avg_lon,
                            "is_rapid": True,
                            "action_recommended": "flag" if reports_per_minute > 5 else "monitor"
                        })
        
        return rapid_patterns
    
    def _detect_low_trust_patterns(self) -> List[Dict[str, Any]]:
        """Detect patterns of consistently low trust scores"""
        cutoff_time = datetime.utcnow() - timedelta(days=7)
        
        # Find devices with low average trust scores
        device_stats = self.db.query(
            SafetySignal.device_hash,
            func.avg(SafetySignal.trust_score).label('avg_trust'),
            func.count(SafetySignal.id).label('count')
        ).filter(
            SafetySignal.timestamp > cutoff_time
        ).group_by(SafetySignal.device_hash).having(
            func.count(SafetySignal.id) >= 3
        ).all()
        
        low_trust_patterns = []
        for device_hash, avg_trust, count in device_stats:
            if avg_trust and avg_trust < 0.3:  # Low trust threshold
                low_trust_patterns.append({
                    "device_hash": device_hash[:12] + "...",
                    "avg_trust_score": round(avg_trust, 3),
                    "report_count": count,
                    "action_recommended": "down-rank" if avg_trust < 0.2 else "flag"
                })
        
        return low_trust_patterns
    
    def calculate_risk_zones(self) -> Dict[str, Any]:
        """
        Calculate risk zones based on aggregated safety data.
        
        This identifies areas with elevated risk scores.
        """
        # Get recent signals (last 24 hours)
        cutoff_time = datetime.utcnow() - timedelta(hours=24)
        
        signals = self.db.query(SafetySignal).filter(
            SafetySignal.timestamp > cutoff_time,
            SafetySignal.is_valid == True
        ).all()
        
        if not signals:
            return {
                "total_zones": 0,
                "high_risk_zones": [],
                "medium_risk_zones": [],
                "message": "No recent data"
            }
        
        # Group by geohash (6-char precision ~ 1.2km x 0.6km tiles)
        tile_signals: Dict[str, List[SafetySignal]] = {}
        for signal in signals:
            tile_id = pgh.encode(signal.latitude, signal.longitude, precision=6)
            if tile_id not in tile_signals:
                tile_signals[tile_id] = []
            tile_signals[tile_id].append(signal)
        
        # Calculate risk for each tile
        high_risk = []
        medium_risk = []
        
        for tile_id, tile_signals_list in tile_signals.items():
            # Calculate risk metrics
            total_severity = sum(s.severity * s.trust_score for s in tile_signals_list)
            total_weight = sum(s.trust_score for s in tile_signals_list)
            
            if total_weight > 0:
                risk_score = (total_severity / total_weight) / 5  # Normalize to 0-1
                
                # Apply time decay
                newest_signal = max(s.timestamp for s in tile_signals_list)
                hours_old = (datetime.utcnow() - newest_signal).total_seconds() / 3600
                decay_factor = math.exp(-hours_old / 24)
                risk_score *= decay_factor
                
                # Get centroid
                avg_lat = sum(s.latitude for s in tile_signals_list) / len(tile_signals_list)
                avg_lon = sum(s.longitude for s in tile_signals_list) / len(tile_signals_list)
                
                zone_info = {
                    "geohash": tile_id,
                    "latitude": round(avg_lat, 6),
                    "longitude": round(avg_lon, 6),
                    "risk_score": round(risk_score, 3),
                    "report_count": len(tile_signals_list),
                    "avg_severity": round(sum(s.severity for s in tile_signals_list) / len(tile_signals_list), 2),
                    "signal_types": list(set(s.signal_type.value for s in tile_signals_list))
                }
                
                if risk_score >= 0.6:
                    high_risk.append(zone_info)
                elif risk_score >= 0.4:
                    medium_risk.append(zone_info)
        
        # Sort by risk score
        high_risk.sort(key=lambda x: x["risk_score"], reverse=True)
        medium_risk.sort(key=lambda x: x["risk_score"], reverse=True)
        
        return {
            "total_zones": len(high_risk) + len(medium_risk),
            "high_risk_zones": high_risk[:10],
            "medium_risk_zones": medium_risk[:10],
            "message": f"Found {len(high_risk)} high-risk and {len(medium_risk)} medium-risk zones"
        }
    
    def get_personalized_alert(
        self,
        latitude: float,
        longitude: float,
        current_hour: int
    ) -> Dict[str, Any]:
        """
        Generate personalized safety alert for a location and time.
        
        This combines multiple factors to give intelligent advice:
        - Location risk score
        - Time of day risk
        - Recent spike detection
        """
        # Get nearby signals
        radius_km = 2.0
        lat_range = radius_km / 111.0
        lon_range = radius_km / (111.0 * abs(latitude))
        
        cutoff_time = datetime.utcnow() - timedelta(hours=24)
        
        nearby_signals = self.db.query(SafetySignal).filter(
            SafetySignal.latitude.between(latitude - lat_range, latitude + lat_range),
            SafetySignal.longitude.between(longitude - lon_range, longitude + lon_range),
            SafetySignal.timestamp > cutoff_time,
            SafetySignal.is_valid == True
        ).all()
        
        # Calculate location risk
        if nearby_signals:
            avg_severity = sum(s.severity for s in nearby_signals) / len(nearby_signals)
            location_risk = min(1.0, avg_severity / 5)
        else:
            location_risk = 0.0
        
        # Time of day risk
        is_night = current_hour >= 22 or current_hour < 6
        time_risk = 0.3 if is_night else 0.0
        
        # Check for nearby spikes
        tile_id = pgh.encode(latitude, longitude, precision=6)
        spike_cutoff = datetime.utcnow() - timedelta(minutes=30)
        spike_count = self.db.query(SafetySignal).filter(
            SafetySignal.geohash == tile_id,
            SafetySignal.timestamp > spike_cutoff
        ).count()
        
        spike_risk = 0.4 if spike_count >= 10 else 0.0
        
        # Combined risk score
        combined_risk = min(1.0, location_risk + time_risk + spike_risk)
        
        # Generate alert message
        if combined_risk >= 0.7:
            alert_level = "high"
            message = "⚠️ This area has elevated safety concerns. Exercise caution."
        elif combined_risk >= 0.4:
            alert_level = "medium"
            if is_night:
                message = "🌙 Nighttime in this area. Stay alert."
            else:
                message = "ℹ️ Some safety incidents reported here recently."
        else:
            alert_level = "low"
            message = "✅ This area appears relatively safe."
        
        return {
            "alert_level": alert_level,
            "risk_score": round(combined_risk, 3),
            "location_risk": round(location_risk, 3),
            "time_risk": round(time_risk, 3),
            "spike_risk": round(spike_risk, 3),
            "nearby_reports": len(nearby_signals),
            "is_night": is_night,
            "message": message
        }


class BackgroundJobService:
    """
    Service for running background pattern detection jobs.
    """
    
    def __init__(self, db: Session):
        self.db = db
        self.pattern_service = PatternDetectionService(db)
    
    def run_periodic_analysis(self):
        """
        Run periodic pattern analysis and store results.
        This would typically be called by a scheduler (e.g., APScheduler).
        """
        # Run pattern analysis
        results = self.pattern_service.run_full_pattern_analysis()
        
        # Store high-risk spikes as alerts
        for spike in results.get("spikes", []):
            if spike.get("spike_intensity", 0) > 0.5:
                # Check if alert already exists
                existing = self.db.query(AnomalyAlert).filter(
                    AnomalyAlert.geohash == spike["geohash"],
                    AnomalyAlert.alert_type == "spike",
                    AnomalyAlert.is_active == True
                ).first()
                
                if not existing:
                    alert = AnomalyAlert(
                        alert_type="spike",
                        geohash=spike["geohash"],
                        latitude=spike["latitude"],
                        longitude=spike["longitude"],
                        severity=spike["spike_intensity"],
                        message=spike["message"],
                        extra_data={"spike_data": spike}
                    )
                    self.db.add(alert)
        
        # Store patterns
        for cluster in results.get("clusters", []):
            if cluster.get("intensity", 0) > 0.5:
                pattern = SafetyPattern(
                    pattern_type="cluster",
                    geohash=cluster["geohash"],
                    latitude=cluster["latitude"],
                    longitude=cluster["longitude"],
                    intensity=cluster["intensity"],
                    extra_data={"cluster_data": cluster}
                )
                self.db.add(pattern)
        
        # Clean up old alerts
        old_alerts = self.db.query(AnomalyAlert).filter(
            AnomalyAlert.created_at < datetime.utcnow() - timedelta(hours=24)
        ).all()
        
        for alert in old_alerts:
            alert.is_active = False
        
        self.db.commit()
        
        return results

