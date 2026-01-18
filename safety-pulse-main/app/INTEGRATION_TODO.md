# Frontend-Backend Integration Plan

## Tasks

### 1. Add HTTP Package

- [x] Add `http` dependency to pubspec.yaml
- [x] Add `crypto` package for device hashing

### 2. Create API Service Layer

- [x] Create `lib/services/api_service.dart` for API communication
- [x] Implement report submission endpoint
- [x] Implement pulse data fetching
- [x] Add device hash generation
- [x] Handle UUID parsing for backend responses

### 3. Update SafetyProvider

- [x] Integrate API service with SafetyProvider
- [x] Replace mock data with real API calls
- [x] Add error handling
- [x] Add loading states
- [x] Add refresh functionality

### 4. Update Models

- [x] Add `fromBackendJson` factory method to SafetyReport

### 5. Update Main App

- [x] Add refresh button to app bar
- [x] Add loading indicator
- [x] Show error messages via SnackBar

## ✅ All Tasks Completed

## API Endpoints

- Base URL: `http://localhost:8000` (or production URL)
- POST /api/v1/report - Submit safety signal
- GET /api/v1/reports - Get safety reports in area
- GET /api/v1/pulse - Get pulse heatmap data
- GET /health - Health check

## Category Mapping

Flutter categories → Backend signal types:

- "Felt unsafe here" → "other"
- "Followed" → "followed"
- "Poor lighting" → "other"
- "Suspicious activity" → "suspicious_activity"
- "Harassment" → "harassment"
- "Feels safe" → "other"
