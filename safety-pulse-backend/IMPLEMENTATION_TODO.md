# Implementation TODO - Trust Score from User Reports

## Phase 1: Database Models

- [x] 1.1 Create `ReportVerification` model to track user votes
- [x] 1.2 Update `SafetySignal` model with vote count fields (true_votes, false_votes)
- [x] 1.3 Create Alembic migration for schema changes

## Phase 2: Pydantic Schemas

- [x] 2.1 Create `VoteRequest` schema (true/false vote)
- [x] 2.2 Create `VoteResponse` schema
- [x] 2.3 Update `ReportItem` to include vote counts
- [x] 2.4 Create `VoteSummary` schema for vote statistics

## Phase 3: Trust Scoring Service

- [x] 3.1 Add `calculate_verification_based_trust()` method
- [x] 3.2 Add `update_signal_trust_from_vote()` method
- [x] 3.3 Add `revert_vote_from_signal()` method
- [x] 3.4 Add `get_vote_summary()` method

## Phase 4: API Endpoints

- [x] 4.1 POST `/reports/{signal_id}/vote` - Vote true/false on a report
- [x] 4.2 DELETE `/reports/{signal_id}/vote` - Remove your vote
- [x] 4.3 GET `/reports/{signal_id}/votes` - Get vote summary
- [x] 4.4 GET `/reports/{signal_id}/vote/check` - Check if user voted
- [x] 4.5 Update GET `/reports` to include vote counts

## Phase 5: Testing

- [ ] 5.1 Test voting on reports
- [ ] 5.2 Verify trust score recalculation
- [ ] 5.3 Test edge cases (double voting, removing votes)

## Phase 6: Frontend Integration (Flutter)

- [x] 6.1 Update API service for voting endpoints
- [x] 6.2 Add vote models (VoteResponse, VoteSummary, VoteCheckResponse)
- [x] 6.3 Update SafetyReport model with vote counts and userVote field
