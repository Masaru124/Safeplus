from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.routes import report, pulse, health, auth
from app.database import engine
from app.models import Base
from app.middleware.rate_limiter import RateLimiterMiddleware

# Create database tables
Base.metadata.create_all(bind=engine)

app = FastAPI(title="Safety Pulse Backend", version="1.0.0")

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify your Flutter app's origin
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Rate limiting middleware
app.add_middleware(RateLimiterMiddleware)

# Include routers
app.include_router(auth.router, prefix="/api/v1", tags=["authentication"])
app.include_router(report.router, prefix="/api/v1", tags=["report"])
app.include_router(pulse.router, prefix="/api/v1", tags=["pulse"])
app.include_router(health.router, tags=["health"])

@app.on_event("startup")
async def startup_event():
    # Initialize any startup tasks here
    pass

@app.on_event("shutdown")
async def shutdown_event():
    # Cleanup tasks here
    pass
