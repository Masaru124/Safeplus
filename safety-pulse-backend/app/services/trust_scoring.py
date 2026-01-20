import math
import random
from typing import Tuple, Optional
from sqlalchemy.orm import Session
from app.models import DeviceActivity, SafetySignal
import uuid

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

    def calculate_trust_score(self, device_hash: str, is_authenticated: bool = False) -> float:
        """
        Calculate trust score for a device based on activity history
        Returns a score between 0.0 and 1.0
        
        Args:
            device_hash: Unique identifier for the device
            is_authenticated: Whether the user is authenticated (gives trust boost)
        """
        device_activity = self.db.query(DeviceActivity).filter(
            DeviceActivity.device_hash == device_hash
        ).first()

        if not device_activity:
            # New device, start with moderate trust
            if is_authenticated:
                return 0.6  # Higher trust for authenticated new users
            return 0.5

        # Base trust score starts at 0.5
        trust_score = 0.5

        # Increase trust based on submission count (up to 0.3 bonus)
        submission_bonus = min(0.3, device_activity.submission_count * 0.01)
        trust_score += submission_bonus

        # Authentication bonus (up to 0.1)
        if is_authenticated:
            trust_score += 0.1

        # Decrease trust based on anomaly score (anomaly_score is 0.0-1.0, higher is worse)
        anomaly_penalty = device_activity.anomaly_score * 0.4
        trust_score -= anomaly_penalty

        # Ensure score stays within 0.0-1.0 bounds
        trust_score = max(0.0, min(1.0, trust_score))

        return trust_score

    def calculate_verification_based_trust(
        self, 
        true_votes: int, 
        false_votes: int, 
        base_trust_score: float = 0.5
    ) -> float:
        """
        Calculate trust score based on user verification votes.
        
        The trust score is calculated using a Bayesian approach:
        - Start with a prior (base_trust_score)
        - Weight new votes more heavily for low vote counts
        - As vote count increases, trust ratio dominates
        
        Args:
            true_votes: Number of users who voted the report is true/accurate
            false_votes: Number of users who voted the report is false/inaccurate
            base_trust_score: Prior trust score (default 0.5)
            
        Returns:
            Trust score between 0.0 and 1.0
        """
        total_votes = true_votes + false_votes
        
        if total_votes == 0:
            # No votes yet, return base trust score
            return base_trust_score
        
        # Calculate the verification ratio (true / total)
        trust_ratio = true_votes / total_votes
        
        # Bayesian-style weighting:
        # - For low vote counts (< 10), blend towards base_trust_score
        # - For high vote counts, trust_ratio dominates
        # - Maximum weight for votes is 0.3 (30% of final score)
        min_votes_for_full_weight = 10
        vote_weight = min(0.3, total_votes / min_votes_for_full_weight * 0.3)
        
        # Combine base trust score with verification ratio
        # More votes = verification ratio has more influence
        trust_score = base_trust_score * (1 - vote_weight) + trust_ratio * vote_weight
        
        # Apply severity weighting: higher severity reports need more verification
        # This is handled separately when saving to the signal
        
        # Ensure score stays within 0.0-1.0 bounds
        trust_score = max(0.0, min(1.0, trust_score))
        
        return trust_score

    def calculate_trust_score_from_signal(self, signal: SafetySignal) -> float:
        """
        Calculate trust score for an existing signal based on its vote counts.
        
        Args:
            signal: SafetySignal instance with true_votes and false_votes
            
        Returns:
            Updated trust score between 0.0 and 1.0
        """
        return self.calculate_verification_based_trust(
            true_votes=signal.true_votes or 0,
            false_votes=signal.false_votes or 0,
            base_trust_score=signal.trust_score or 0.5
        )

    def update_signal_trust_from_vote(
        self, 
        signal_id: str, 
        is_true_vote: bool
    ) -> float:
        """
        Update a signal's trust score after a vote is cast.
        
        Args:
            signal_id: UUID or string ID of the signal
            is_true_vote: True if vote is "true/accurate", False if "false/inaccurate"
            
        Returns:
            The updated trust score
        """
        # Import here to avoid circular imports
        from sqlalchemy import text
        
        # Convert string UUID to Python uuid.UUID object for database query
        signal_uuid = uuid.UUID(signal_id) if isinstance(signal_id, str) else signal_id
        
        # Get the signal
        signal = self.db.query(SafetySignal).filter(
            SafetySignal.id == signal_uuid
        ).first()
        
        if not signal:
            raise ValueError(f"Signal with ID {signal_uuid} not found")
        
        # Update vote counts based on the vote
        if is_true_vote:
            signal.true_votes = (signal.true_votes or 0) + 1
        else:
            signal.false_votes = (signal.false_votes or 0) + 1
        
        # Calculate new trust score based on votes
        new_trust_score = self.calculate_verification_based_trust(
            true_votes=signal.true_votes or 0,
            false_votes=signal.false_votes or 0,
            base_trust_score=0.5  # Start fresh for vote-based scoring
        )
        
        # Blend with original trust score to avoid drastic changes
        # New votes contribute up to 40% of the final trust score
        original_weight = 0.6
        new_weight = 0.4
        
        blended_score = signal.trust_score * original_weight + new_trust_score * new_weight
        
        # Ensure score stays within bounds
        signal.trust_score = max(0.0, min(1.0, blended_score))
        
        self.db.add(signal)
        self.db.commit()
        self.db.refresh(signal)
        
        return signal.trust_score

    def revert_vote_from_signal(self, signal_id: str, was_true_vote: bool) -> float:
        """
        Revert a vote from a signal (for when a user removes their vote).
        
        Args:
            signal_id: UUID or string ID of the signal
            was_true_vote: True if the removed vote was "true", False if "false"
            
        Returns:
            The updated trust score
        """
        # Convert string UUID to Python uuid.UUID object for database query
        signal_uuid = uuid.UUID(signal_id) if isinstance(signal_id, str) else signal_id
        
        signal = self.db.query(SafetySignal).filter(
            SafetySignal.id == signal_uuid
        ).first()
        
        if not signal:
            raise ValueError(f"Signal with ID {signal_uuid} not found")
        
        # Decrease the appropriate vote count
        if was_true_vote:
            signal.true_votes = max(0, (signal.true_votes or 0) - 1)
        else:
            signal.false_votes = max(0, (signal.false_votes or 0) - 1)
        
        # Recalculate trust score
        new_trust_score = self.calculate_verification_based_trust(
            true_votes=signal.true_votes or 0,
            false_votes=signal.false_votes or 0,
            base_trust_score=0.5
        )
        
        # Blend with original trust score
        original_weight = 0.6
        new_weight = 0.4
        
        blended_score = signal.trust_score * original_weight + new_trust_score * new_weight
        signal.trust_score = max(0.0, min(1.0, blended_score))
        
        self.db.add(signal)
        self.db.commit()
        self.db.refresh(signal)
        
        return signal.trust_score

    def get_vote_summary(self, signal_id: str) -> dict:
        """
        Get a summary of votes for a signal.
        
        Args:
            signal_id: UUID or string ID of the signal
            
        Returns:
            Dictionary with vote statistics
        """
        # Convert string UUID to Python uuid.UUID object for database query
        signal_uuid = uuid.UUID(signal_id) if isinstance(signal_id, str) else signal_id
        
        signal = self.db.query(SafetySignal).filter(
            SafetySignal.id == signal_uuid
        ).first()
        
        if not signal:
            raise ValueError(f"Signal with ID {signal_uuid} not found")
        
        true_votes = signal.true_votes or 0
        false_votes = signal.false_votes or 0
        total_votes = true_votes + false_votes
        
        trust_ratio = true_votes / total_votes if total_votes > 0 else 0.5
        
        return {
            "signal_id": str(signal_uuid),
            "true_votes": true_votes,
            "false_votes": false_votes,
            "total_votes": total_votes,
            "trust_ratio": trust_ratio,
            "trust_score": signal.trust_score
        }

