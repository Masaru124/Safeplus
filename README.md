# 🚨 Safety Pulse

<div align="center">

![Safety Pulse](https://img.shields.io/badge/Safety-Pulse-blue?style=for-the-badge)
![Flutter](https://img.shields.io/badge/Flutter-3.8+-blue?style=flat-square&logo=flutter)
![FastAPI](https://img.shields.io/badge/FastAPI-2.0+-green?style=flat-square&logo=fastapi)
![Python](https://img.shields.io/badge/Python-3.10+-yellow?style=flat-square&logo=python)

**Community-powered safety awareness platform**

[Features](#-features) • [Quick Start](#-quick-start) • [Architecture](#-architecture) • [Contributing](#-contributing) • [API Docs](#-api-documentation)

</div>

---

## 🎯 About Safety Pulse

Safety Pulse is an open-source community safety platform that helps people share and view safety information about locations. Unlike crime maps that track incidents, Safety Pulse focuses on **feelings and perceptions of safety** - letting people report how a place _felt_ to them.

The platform aggregates anonymous reports to create "Safety Pulses" - visual indicators of collective sentiment that help others make informed decisions about their surroundings.

### Why Safety Pulse?

- **🛡️ Community-Driven**: Real reports from real people, weighted by trust scores
- **🔒 Privacy-First**: Reports are anonymous and coordinates are blurred (50m radius)
- **⏰ Time-Aware**: Safety pulses decay over time - recent reports matter more
- **🤖 Smart Detection**: Automatic spike and pattern detection for anomaly alerts
- **🌍 Cross-Platform**: Native mobile apps (iOS/Android) + web support

---

## ✨ Features

### For Users

| Feature                  | Description                                                            |
| ------------------------ | ---------------------------------------------------------------------- |
| 📍 **Interactive Map**   | View safety pulses on a beautiful, privacy-respecting map interface    |
| 📝 **Quick Reporting**   | Tap anywhere to report how a location felt to you                      |
| ⭐ **Severity Levels**   | Report from "Felt Safe" to "Felt Unsafe" with intensity slider         |
| 🔐 **Anonymous Reports** | Your identity is protected with device hashing and coordinate blurring |
| 📊 **Trust Scoring**     | Community verification builds trust over time                          |
| 🔔 **Real-time Updates** | Live pulse updates via WebSocket connections                           |

### For Contributors

| Feature                   | Description                                          |
| ------------------------- | ---------------------------------------------------- |
| 🧠 **Pattern Detection**  | Detect spikes, clusters, and anomalies automatically |
| ⚖️ **Trust System**       | Bayesian trust scoring with spam detection           |
| 📈 **Analytics**          | Risk zone calculation and hotspot identification     |
| 🛡️ **Abuse Protection**   | Rate limiting, anomaly tracking, and down-weighting  |
| 🔄 **Background Workers** | Automated pulse aggregation and decay                |

---

## 🚀 Quick Start

### Prerequisites

- **Backend**: Python 3.10+, Redis
- **Frontend**: Flutter 3.8+, Dart 3.0+
- **Optional**: Docker & Docker Compose

### Option 1: Docker Compose (Recommended)

```bash
# Clone and navigate to project
git clone https://github.com/your-org/safety-pulse.git
cd safety-pulse

# Start all services
docker-compose up -d

# Backend will be at http://localhost:8000
# API docs at http://localhost:8000/docs
```

### Option 2: Manual Setup

#### Backend Setup

```bash
cd safety-pulse-backend

# Create virtual environment
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate

# Install dependencies
pip install -r requirements.txt

# Start the server
python -m uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

#### Frontend Setup

```bash
cd safety-pulse-main/app

# Get dependencies
flutter pub get

# Run on your device/emulator
flutter run
```

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Safety Pulse System                        │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────────┐      ┌──────────────────────────┐ │
│  │   Flutter Mobile     │      │    FastAPI Backend       │ │
│  │       App 📱         │◄────►│       🖥️ Server          │ │
│  └──────────┬───────────┘      └─────────────┬────────────┘ │
│             │                                │               │
│       flutter_map                     SQLite/PostgreSQL      │
│       geolocator                            │               │
│       provider                              │               │
│                                            ▼               │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Redis (Caching & Real-time)             │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

| Component      | Technology                       | Purpose                                   |
| -------------- | -------------------------------- | ----------------------------------------- |
| **Mobile App** | Flutter                          | Cross-platform UI with maps and reporting |
| **REST API**   | FastAPI                          | Report submission, pulse queries, auth    |
| **Database**   | SQLite (dev) / PostgreSQL (prod) | Persistent storage                        |
| **Real-time**  | Redis + WebSockets               | Live updates and caching                  |
| **Auth**       | JWT + Device Hashing             | Secure, anonymous authentication          |

### API Endpoints

| Endpoint                          | Method    | Description                       |
| --------------------------------- | --------- | --------------------------------- |
| `/api/v1/report`                  | POST      | Submit a safety report            |
| `/api/v1/reports`                 | GET       | Query reports by location/radius  |
| `/api/v1/pulse`                   | GET       | Get aggregated pulse heatmap data |
| `/api/v1/realtime/ws`             | WebSocket | Real-time pulse updates           |
| `/api/v1/intelligence/patterns`   | GET       | Get detected patterns & spikes    |
| `/api/v1/intelligence/risk-zones` | GET       | Get high-risk zones               |
| `/auth/register`                  | POST      | User registration                 |
| `/auth/login`                     | POST      | User login                        |

---

## 📂 Project Structure

```
safety/
├── README.md                    # This file
├── .gitignore
│
├── safety-pulse-backend/        # FastAPI Backend
│   ├── app/
│   │   ├── main.py             # Application entry point
│   │   ├── models.py           # SQLAlchemy models
│   │   ├── schemas.py          # Pydantic schemas
│   │   ├── database.py         # Database configuration
│   │   ├── dependencies.py     # FastAPI dependencies
│   │   ├── routes/             # API route handlers
│   │   │   ├── auth.py         # Authentication routes
│   │   │   ├── report.py       # Report submission
│   │   │   ├── pulse.py        # Pulse aggregation
│   │   │   ├── realtime.py     # WebSocket handlers
│   │   │   ├── intelligence.py # Pattern detection
│   │   │   └── health.py       # Health checks
│   │   ├── services/           # Business logic
│   │   │   ├── trust_scoring.py      # Trust score calculation
│   │   │   ├── pattern_detection.py  # Spike/cluster detection
│   │   │   ├── pulse_aggregation.py  # Tile aggregation
│   │   │   ├── smart_scoring.py      # Risk calculations
│   │   │   └── realtime.py           # WebSocket management
│   │   └── middleware/         # Custom middleware
│   │       └── rate_limiter.py # Rate limiting
│   ├── requirements.txt
│   ├── Dockerfile
│   └── docker-compose.yml
│
└── safety-pulse-main/app/      # Flutter Frontend
    ├── lib/
    │   ├── main.dart           # App entry point
    │   ├── models/
    │   │   ├── safety.dart     # Safety report models
    │   │   └── user.dart       # User models
    │   ├── providers/
    │   │   ├── auth_provider.dart    # Auth state management
    │   │   └── safety_provider.dart  # Safety data management
    │   ├── screens/
    │   │   ├── onboarding_screen.dart
    │   │   └── report_list_screen.dart
    │   ├── services/
    │   │   ├── api_service.dart      # HTTP client
    │   │   └── realtime_service.dart # WebSocket client
    │   ├── widgets/
    │   │   ├── safety_map.dart       # Interactive map
    │   │   ├── pulse_visualization.dart
    │   │   ├── report_card.dart
    │   │   └── ...
    │   └── utils/
    │       └── safety_utils.dart
    ├── pubspec.yaml
    ├── android/                 # Android configuration
    ├── ios/                     # iOS configuration
    ├── web/                     # Web configuration
    └── test/                    # Unit tests
```

---

## 🤝 Contributing

We welcome contributions! Here's how you can help build Safety Pulse:

### First-Time Contributors

1. **Fork the repository** on GitHub
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/YOUR-USERNAME/safety-pulse.git
   cd safety-pulse
   ```
3. **Create a feature branch**:
   ```bash
   git checkout -b feature/amazing-new-feature
   ```
4. **Make your changes** and commit:
   ```bash
   git commit -m "Add amazing new feature"
   ```
5. **Push to GitHub** and submit a Pull Request

### Areas Where We Need Help

| Priority  | Area              | Description                                |
| --------- | ----------------- | ------------------------------------------ |
| 🔴 High   | **Mobile App**    | New features, UI improvements, bug fixes   |
| 🟡 Medium | **Backend**       | API enhancements, performance optimization |
| 🟡 Medium | **Tests**         | Unit tests, integration tests, E2E tests   |
| 🟢 Low    | **Documentation** | Improve docs, add examples                 |
| 🟢 Low    | **DevOps**        | CI/CD pipelines, deployment configs        |

### Good First Issues

Looking for a place to start? Check out these beginner-friendly issues:

- [Add a new report category](https://github.com/org/safety-pulse/labels/good%20first%20issue)
- [Improve error handling](https://github.com/org/safety-pulse/labels/good%20first%20issue)
- [Add unit tests for trust scoring](https://github.com/org/safety-pulse/labels/good%20first%20issue)
- [Improve map UI/UX](https://github.com/org/safety-pulse/labels/good%20first%20issue)

### Coding Standards

#### Backend (Python)

- Follow [PEP 8](https://pep8.org/) style guide
- Use type hints for all functions
- Write docstrings for public functions
- Add unit tests for new features

#### Frontend (Dart/Flutter)

- Follow [Effective Dart](https://dart.dev/guides/language/effective-dart) guidelines
- Use `flutter_lints` for code analysis
- Keep widgets small and focused
- Use `Provider` for state management

### Commit Messages

We follow the [Conventional Commits](https://www.conventionalcommits.org/) specification:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

Types:

- `feat`: A new feature
- `fix`: A bug fix
- `docs`: Documentation only changes
- `style`: Changes that do not affect the meaning of the code
- `refactor`: A code change that neither fixes a bug nor adds a feature
- `perf`: A code change that improves performance
- `test`: Adding missing tests or correcting existing tests
- `chore`: Changes to the build process or auxiliary tools

Example:

```
feat(trust-scoring): add spam detection for device hashing

- Add rapid submission detection
- Implement anomaly score tracking
- Down-weight suspicious reports

Closes #123
```

---

## 🧪 Testing

### Backend Tests

```bash
cd safety-pulse-backend

# Run all tests
python -m pytest test_api.py -v

# Run with coverage
pytest --cov=app test_api.py
```

### Frontend Tests

```bash
cd safety-pulse-main/app

# Run all tests
flutter test

# Run with coverage
flutter test --coverage
```

---

## 📚 API Documentation

Once the backend is running, visit:

- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc
- **OpenAPI JSON**: http://localhost:8000/openapi.json

---

## 🔒 Security

### Privacy Guarantees

1. **Anonymity**: Reports are tied to device hashes, not personal identities
2. **Coordinate Blurring**: All coordinates are randomly offset by up to 50 meters
3. **Trust-Weighted**: Reports from trusted users have more influence
4. **Time Decay**: Old reports naturally fade away

### Reporting Security Issues

If you find a security vulnerability, please do **NOT** open a public issue. Instead, email us at security@safetypulse.example.com

---

## 📄 License

Safety Pulse is licensed under the [MIT License](LICENSE). This means you can:

✅ Use it for any purpose  
✅ Modify it freely  
✅ Distribute your modifications  
✅ Use it commercially

We just ask that you include the original copyright notice.

---

## 🙏 Acknowledgments

- **OpenStreetMap** for beautiful, free map data
- **Flutter Team** for the amazing cross-platform framework
- **FastAPI Team** for the fastest Python API framework
- **Our Contributors** who make Safety Pulse possible

---

## 📞 Get in Touch

- 💬 **Discord**: [Join our community](https://discord.gg/safetypulse)
- 🐦 **Twitter**: [@SafetyPulseApp](https://twitter.com/SafetyPulseApp)
- 📧 **Email**: hello@safetypulse.example.com

---

<div align="center">

**Made with ❤️ by the Safety Pulse Community**

</div>
