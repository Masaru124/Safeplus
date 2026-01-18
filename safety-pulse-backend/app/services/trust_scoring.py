import math
import random
from typing import Tuple
from sqlalchemy.orm import Session
from app.models import DeviceActivity

class TrustScoringService:
    def __init__(self, db: Session):
        self.db = db

    @staticmethod
    def blur_coordinates(latitude: float, longitude: float, radius_meters: int = 50) -> Tuple[float, float]:
        """
        Blur coordinates by adding random offset within specified radius
        """
        # Convert radius to degrees (approximate)
        radius_deg = radius_meters / 111320  # meters per degree at equator

        # Generate random angle and distance
        angle = random.uniform(0, 2 * math.pi)
        distance = random.uniform(0, radius_deg)

        # Calculate offset
        delta_lat = distance * math.cos(angle)
        delta_lon = distance * math.sin(angle) / math.cos(math.radians(latitude))

        blurred_lat = latitude + delta_lat
        blurred_lon = longitude + delta_lon

        return blurred_lat, blurred_lon

    def calculate_trust_score(self, device_hash: str) -> float:
        """
        Calculate trust score for a device based on activity history
        Returns a score between 0.0 and 1.0
        """
        device_activity = self.db.query(DeviceActivity).filter(
            DeviceActivity.device_hash == device_hash
        ).first()

        if not device_activity:
            # New device, start with moderate trust
            return 0.5

        # Base trust score starts at 0.5
        trust_score = 0.5

        # Increase trust based on submission count (up to 0.3 bonus)
        submission_bonus = min(0.3, device_activity.submission_count * 0.01)
        trust_score += submission_bonus

        # Decrease trust based on anomaly score (anomaly_score is 0.0-1.0, higher is worse)
        anomaly_penalty = device_activity.anomaly_score * 0.4
        trust_score -= anomaly_penalty

        # Ensure score stays within 0.0-1.0 bounds
        trust_score = max(0.0, min(1.0, trust_score))

        return trust_score
