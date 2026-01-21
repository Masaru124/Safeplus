"""
Simple Rate Limiter Middleware for Safety Pulse

This middleware provides basic rate limiting for local development.
"""

import time
from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.responses import JSONResponse
from typing import Dict

# In-memory storage for local development
_in_memory_requests: Dict[str, list] = {}


class RateLimiterMiddleware(BaseHTTPMiddleware):
    """
    Simple rate limiting middleware with device-based limits.
    
    Limits:
    - Anonymous users: 60 requests per minute
    - Authenticated users: 200 requests per minute
    """
    
    # Rate limits
    ANONYMOUS_LIMIT = 60
    AUTHENTICATED_LIMIT = 200
    
    # Time window (seconds)
    WINDOW = 60
    
    async def dispatch(self, request: Request, call_next):
        # Skip rate limiting for health and docs endpoints
        if request.url.path in ["/health", "/docs", "/openapi.json", "/"]:
            return await call_next(request)
        
        # Skip rate limiting for auth endpoints
        if "/auth/" in request.url.path:
            return await call_next(request)
        
        # Get client identifier
        client_id = (
            request.headers.get("X-Device-Hash") or 
            request.headers.get("Authorization") or 
            request.client.host or 
            "anonymous"
        )
        
        # Determine rate limit
        auth_header = request.headers.get("Authorization")
        limit = self.AUTHENTICATED_LIMIT if auth_header else self.ANONYMOUS_LIMIT
        
        # Rate limiting logic
        current_time = time.time()
        key = f"rate_limit:{client_id}"
        
        if key not in _in_memory_requests:
            _in_memory_requests[key] = []
        
        # Clean old requests
        _in_memory_requests[key] = [
            t for t in _in_memory_requests[key] 
            if current_time - t < self.WINDOW
        ]
        
        # Check limit
        if len(_in_memory_requests[key]) >= limit:
            return JSONResponse(
                status_code=429,
                content={"detail": "Rate limit exceeded. Please try again later."}
            )
        
        # Add current request
        _in_memory_requests[key].append(current_time)
        
        # Continue with request
        try:
            response = await call_next(request)
            return response
        except HTTPException as exc:
            raise exc
        except Exception as exc:
            return JSONResponse(
                status_code=500,
                content={"detail": f"Internal server error: {str(exc)}"}
            )

