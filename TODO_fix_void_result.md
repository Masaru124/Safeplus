# TODO: Fix use_of_void_result errors in safety_map.dart

## Task

Remove incorrect `unawaited()` wrappers from `async void` method calls in safety_map.dart

## Issues Identified

- Line 154: `unawaited()` used with `voteOnReport()` (async void)
- Line 190: `unawaited()` used with `voteOnReport()` (async void)
- Line 230: `unawaited()` used with `removeVote()` (async void)

## Fixes Required

- [x] Remove `unawaited()` from line 154 (voteOnReport call)
- [x] Remove `unawaited()` from line 190 (voteOnReport call)
- [x] Remove `unawaited()` from line 230 (removeVote call)
- [x] Verify no lint errors remain

## Summary

Fixed all 3 `use_of_void_result` errors by removing incorrect `unawaited()` wrappers from calls to `async void` methods (`voteOnReport()` and `removeVote()`). Since these methods return `void` (not `Future<void>`), the `unawaited()` wrapper was unnecessary and caused the lint errors.

## Backend UUID Fix (Additional Issue Found)

Fixed SQLAlchemy `AttributeError: 'str' object has no attribute 'hex'` error in `safety-pulse-backend/app/services/trust_scoring.py`.

**Root Cause:** The `SafetySignal.id` column is defined as `UUID(as_uuid=True)` which expects a Python `uuid.UUID` object. When a string UUID was passed, SQLAlchemy tried to convert it but failed because strings don't have a `.hex` method.

**Fix Applied:**

- Added `import uuid` to trust_scoring.py
- Fixed `update_signal_trust_from_vote()`: `signal_uuid = uuid.UUID(signal_id)`
- Fixed `revert_vote_from_signal()`: `signal_uuid = uuid.UUID(signal_id)`
- Fixed `get_vote_summary()`: `signal_uuid = uuid.UUID(signal_id)`

All three methods now properly convert string UUIDs to Python `uuid.UUID` objects for database queries.

## New Features (Completed)

### 1. One Vote Per User ✅

- [x] Modify voting endpoint to reject votes if user has already voted
- Users must delete their vote first before voting again

### 2. Delete Own Reports ✅

- [x] Add new endpoint: `DELETE /api/v1/reports/{signal_id}`
- [x] Only the report owner can delete their report
- [x] Also delete all verifications (votes) associated with the report
- [x] Return success message with report details

### Frontend Integration ✅

- [x] Add delete report method to api_service.dart
- [x] Add delete option in safety_map.dart report details dialog

## Files Modified

### Backend:

- `safety-pulse-backend/app/services/trust_scoring.py` - UUID conversion fix
- `safety-pulse-backend/app/routes/report.py` - One-vote restriction + delete endpoint
- `safety-pulse-backend/app/schemas.py` - DeleteResponse schema

### Frontend:

- `safety-pulse-main/app/lib/widgets/safety_map.dart` - Removed unawaited(), added delete button
- `safety-pulse-main/app/lib/services/api_service.dart` - DeleteReportResponse + deleteReport()
- `safety-pulse-main/app/lib/providers/safety_provider.dart` - deleteReport() method
- `safety-pulse-main/app/lib/models/safety.dart` - userId field + isOwnedBy() method
- `safety-pulse-main/app/lib/providers/auth_provider.dart` - userId getter
