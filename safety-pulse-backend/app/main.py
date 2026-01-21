from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from app.routes import report, pulse, health, auth, intelligence, realtime
from app.database import engine
from app.models import Base
from app.middleware.rate_limiter import RateLimiterMiddleware
from contextlib import asynccontextmanager
import threading
import time
from datetime import datetime, timezone

# Create database tables
Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="Safety Pulse Backend",
    version="2.0.0",
    description="Community-powered safety reporting with trust scoring and real-time pulse aggregation"
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
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
app.include_router(intelligence.router, prefix="/api/v1", tags=["intelligence"])
app.include_router(realtime.router, prefix="/api/v1", tags=["realtime"])
app.include_router(health.router, tags=["health"])


# ============ Background Workers ============

def pulse_decay_worker():
    """
    Background worker that decays pulse tiles every 10 minutes.
    
    This worker:
    1. Applies time decay to active pulses
    2. Removes pulses that have decayed below threshold
    3. Emits real-time events for expired pulses
    """
    while True:
        try:
            from app.services.pulse_aggregation import PulseDecayService
            from app.services.realtime import connection_manager, RealtimeService, EventType, WebSocketMessage
            from app.database import SessionLocal
            
            db = SessionLocal()
            try:
                decay_service = PulseDecayService(db)
                result = decay_service.decay_pulses()
                print(f"[Pulse Decay] Updated: {result['updated_pulses']}, Deleted: {result['deleted_pulses']}")
                
                # Emit expiration events for deleted pulses
                if result['deleted_pulses'] > 0:
                    realtime_service = RealtimeService(db)
                    # Note: We don't track which pulses were deleted, just count
                    # In production, you'd track this and emit specific events
                
                # Also cleanup expired pulses periodically
                if datetime.now(timezone.utc).minute % 5 == 0:
                    cleanup_count = decay_service.cleanup_expired_pulses()
                    print(f"[Pulse Cleanup] Removed {cleanup_count} expired pulses")
                    
            finally:
                db.close()
                
        except Exception as e:
            print(f"[Pulse Decay Error] {e}")
        
        # Sleep for 10 minutes (600 seconds)
        time.sleep(600)


def pulse_refresh_worker():
    """
    Background worker that refreshes pulse aggregates every 5 minutes.
    
    This worker:
    1. Aggregates recent reports into pulse tiles
    2. Emits real-time events for new/updated pulses
    """
    while True:
        try:
            from app.services.pulse_aggregation import PulseAggregationService
            from app.services.realtime import RealtimeService, EventType, WebSocketMessage
            from app.database import SessionLocal
            
            db = SessionLocal()
            try:
                service = PulseAggregationService(db)
                updated_tiles = service.aggregate_pulse_tiles()
                print(f"[Pulse Refresh] Aggregated {len(updated_tiles)} tiles")
                
                # Emit real-time updates for new/modified pulses
                realtime_service = RealtimeService(db)
                for tile in updated_tiles:
                    # Don't await - fire and forget
                    try:
                        # This would emit WebSocket events in production
                        pass
                    except Exception:
                        pass
                        
            finally:
                db.close()
                
        except Exception as e:
            print(f"[Pulse Refresh Error] {e}")
        
        # Sleep for 5 minutes (300 seconds)
        time.sleep(300)


def expiration_cleanup_worker():
    """
    Background worker that runs daily maintenance.
    
    This worker:
    1. Expires old safety signals
    2. Cleans up expired patterns and alerts
    3. Removes empty pulse tiles
    """
    while True:
        try:
            from app.services.expiration import ExpirationService
            from app.database import SessionLocal
            
            db = SessionLocal()
            try:
                expiration_service = ExpirationService(db)
                result = expiration_service.run_full_maintenance()
                print(f"[Expiration Cleanup] Signals expired: {result['expired_signals']}, "
                      f"Patterns deleted: {result['deleted_patterns']}, "
                      f"Alerts deleted: {result['deleted_alerts']}")
            finally:
                db.close()
                
        except Exception as e:
            print(f"[Expiration Cleanup Error] {e}")
        
        # Sleep for 24 hours (86400 seconds)
        time.sleep(86400)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application lifecycle - start background tasks"""
    print("[Startup] Initializing Safety Pulse Backend...")
    
    # Start background workers
    workers_started = 0
    
    try:
        decay_thread = threading.Thread(target=pulse_decay_worker, daemon=True, name="pulse-decay")
        decay_thread.start()
        workers_started += 1
        print("[Startup] Pulse decay worker started")
    except Exception as e:
        print(f"[Startup Error] Failed to start decay worker: {e}")
    
    try:
        refresh_thread = threading.Thread(target=pulse_refresh_worker, daemon=True, name="pulse-refresh")
        refresh_thread.start()
        workers_started += 1
        print("[Startup] Pulse refresh worker started")
    except Exception as e:
        print(f"[Startup Error] Failed to start refresh worker: {e}")
    
    try:
        cleanup_thread = threading.Thread(target=expiration_cleanup_worker, daemon=True, name="expiration-cleanup")
        cleanup_thread.start()
        workers_started += 1
        print("[Startup] Expiration cleanup worker started")
    except Exception as e:
        print(f"[Startup Error] Failed to start cleanup worker: {e}")
    
    print(f"[Startup] {workers_started}/3 background workers started")
    
    yield
    
    # Cleanup on shutdown
    print("[Shutdown] Shutting down background workers...")


# Update lifespan
app.router.lifespan_context = lifespan


@app.on_event("startup")
async def startup_event():
    """Run initial pulse aggregation on startup"""
    try:
        from app.services.pulse_aggregation import PulseAggregationService
        from app.database import SessionLocal
        
        db = SessionLocal()
        try:
            service = PulseAggregationService(db)
            updated_tiles = service.aggregate_pulse_tiles()
            print(f"[Startup] Initial aggregation complete: {len(updated_tiles)} tiles created")
        finally:
            db.close()
    except Exception as e:
        print(f"[Startup Error] {e}")


@app.on_event("shutdown")
async def shutdown_event():
    """Cleanup on shutdown"""
    print("[Shutdown] Safety Pulse Backend shutting down...")


# ============ Request Logging Middleware ============

@app.middleware("http")
async def log_requests(request: Request, call_next):
    """Log incoming requests for debugging"""
    start_time = datetime.now()
    
    try:
        response = await call_next(request)
        process_time = (datetime.now() - start_time).total_seconds()
        
        # Log slow requests (> 1 second)
        if process_time > 1.0:
            print(f"[Slow Request] {request.method} {request.url.path} - {process_time:.2f}s")
        
        return response
    except Exception as e:
        print(f"[Request Error] {request.method} {request.url.path} - {str(e)}")
        raise


# ============ Root Endpoint ============

@app.get("/")
async def root():
    """Root endpoint with API information"""
    return {
        "name": "Safety Pulse Backend",
        "version": "2.0.0",
        "description": "Community-powered safety reporting API",
        "endpoints": {
            "documentation": "/docs",
            "health": "/health",
            "authentication": "/api/v1/auth",
            "reports": "/api/v1/reports",
            "pulses": "/api/v1/pulses/active",
            "realtime": "/api/v1/realtime"
        }
    }

