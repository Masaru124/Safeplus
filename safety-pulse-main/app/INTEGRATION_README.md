# Safety Pulse - Frontend-Backend Integration

This document describes the integration between the Flutter frontend and FastAPI backend.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Mobile App                        │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │ SafetyMap   │  │ SafetyProvider│  │ ReportDialog       │  │
│  └──────┬──────┘  └──────┬───────┘  └────────────────────┘  │
│         │                │                                    │
│         └────────────────┴────────────────────────────────┐  │
│                        API Service                         │  │
│                     (api_service.dart)                     │  │
└─────────────────────────────┬───────────────────────────────┘
                              │ HTTP Requests
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   FastAPI Backend                            │
│  ┌─────────────┐  ┌──────────────┐  ┌────────────────────┐  │
│  │ POST /report│  │ GET /reports │  │ GET /pulse          │  │
│  └─────────────┘  └──────────────┘  └────────────────────┘  │
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ▼
                    ┌─────────────────┐
                    │   SQLite DB     │
                    └─────────────────┘
```

## Quick Start

### 1. Start the Backend

```bash
cd safety-pulse-backend
# Using Python directly
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

# Or using Docker
docker-compose up -d
```

The backend will be available at `http://localhost:8000`

### 2. Start the Frontend

```bash
cd safety-pulse-main/app
flutter pub get
flutter run
```

## API Endpoints

### POST /api/v1/report

Submit a new safety signal.

**Request:**

```json
{
  "signal_type": "followed",
  "severity": 5,
  "latitude": 40.7484,
  "longitude": -73.9857,
  "context": {
    "category": "Followed",
    "description": "Someone followed me"
  }
}
```

**Response:**

```json
{
  "message": "Safety signal reported successfully",
  "signal_id": "550e8400-e29b-41d4-a716-446655440000",
  "trust_score": 0.85
}
```

### GET /api/v1/reports

Get safety reports in a given area and time window.

**Query Parameters:**

- `lat` (required): Latitude of center point
- `lng` (required): Longitude of center point
- `radius` (optional): Radius in kilometers (default: 10.0)
- `time_window` (optional): Time window - "1h", "24h", or "7d" (default: "24h")

**Response:**

```json
{
  "reports": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "signal_type": "followed",
      "severity": 5,
      "latitude": 40.7484,
      "longitude": -73.9857,
      "created_at": "2024-01-15T10:30:00Z",
      "trust_score": 0.85
    }
  ]
}
```

### GET /api/v1/pulse

Get pulse heatmap data for an area.

**Query Parameters:**

- `lat` (required): Latitude of center point
- `lng` (required): Longitude of center point
- `radius` (optional): Radius in kilometers (default: 10.0)
- `time_window` (optional): Time window (default: "24h")

### GET /health

Health check endpoint.

**Response:**

```json
{
  "status": "healthy",
  "timestamp": "2024-01-15T10:30:00Z",
  "version": "1.0.0"
}
```

## Signal Types

The backend supports the following signal types:

- `followed` - Being followed by someone
- `suspicious_activity` - Suspicious activity observed
- `harassment` - Harassment incident
- `unsafe_area` - Area feels unsafe
- `other` - Other safety concerns

## Flutter Integration Details

### API Service (`lib/services/api_service.dart`)

The API service handles all communication with the backend:

```dart
// Submit a report
final response = await apiService.submitReport(
  signalType: 'followed',
  severity: 5,
  latitude: 40.7484,
  longitude: -73.9857,
  context: {'category': 'Followed'},
);

// Fetch reports
final reports = await apiService.fetchReports(
  lat: 40.7484,
  lng: -73.9857,
  radius: 10.0,
  timeWindow: '24h',
);
```

### SafetyProvider (`lib/providers/safety_provider.dart`)

The SafetyProvider manages state and integrates with the API:

```dart
// Initialize reports (tries API, falls back to mock data)
provider.initializeReports();

// Add a new report (submits to API, saves locally if offline)
provider.addReport(report);

// Refresh data from API
await provider.refreshReports();

// Set user location
provider.setUserLocation(MapLocation(
  latitude: 40.7484,
  longitude: -73.9857,
));
```

### Category Mapping

Flutter categories are mapped to backend signal types:

| Flutter Category    | Backend Signal Type | Severity |
| ------------------- | ------------------- | -------- |
| Felt unsafe here    | other               | 3        |
| Followed            | followed            | 5        |
| Poor lighting       | other               | 2        |
| Suspicious activity | suspicious_activity | 4        |
| Harassment          | harassment          | 5        |
| Feels safe          | other               | 1        |

## Offline Support

The app supports offline functionality:

1. **Report Submission**: Reports are saved locally if the API is unavailable
2. **Data Fetching**: Falls back to mock data if the backend is not reachable
3. **Error Handling**: Users are notified of connectivity issues via SnackBar

## Configuration

### Backend URL

The frontend connects to `http://localhost:8000` by default. To change this:

Edit `lib/services/api_service.dart`:

```dart
static const String baseUrl = 'http://your-production-url:8000';
```

### CORS Configuration

The backend is configured to accept requests from any origin. For production, update `app/main.py`:

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["https://your-frontend.com"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

## Testing

### Backend Tests

```bash
cd safety-pulse-backend
python -m pytest test_api.py -v
```

### Manual API Testing

```bash
# Check health
curl http://localhost:8000/health

# Submit a report
curl -X POST http://localhost:8000/api/v1/report \
  -H "Content-Type: application/json" \
  -H "X-Device-Hash: test-device-hash" \
  -d '{"signal_type": "followed", "severity": 5, "latitude": 40.7484, "longitude": -73.9857}'

# Get reports
curl "http://localhost:8000/api/v1/reports?lat=40.7484&lng=-73.9857&radius=10"
```

## Troubleshooting

### Backend not starting

- Check if port 8000 is already in use
- Ensure all dependencies are installed: `pip install -r requirements.txt`

### Frontend API errors

- Verify backend is running at `http://localhost:8000`
- Check console logs for error messages
- Ensure CORS is properly configured on the backend

### Flutter build errors

- Run `flutter pub get` to update dependencies
- Ensure Flutter SDK version is compatible (SDK ^3.8.1)
