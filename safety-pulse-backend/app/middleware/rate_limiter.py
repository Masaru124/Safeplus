import time
from fastapi import Request, HTTPException
from starlette.middleware.base import BaseHTTPMiddleware

class RateLimiterMiddleware(BaseHTTPMiddleware):
    def __init__(self, app, redis_url: str = "redis://localhost:6379"):
        super().__init__(app)
        # Use in-memory storage for local development
        self.requests = {}
        self.rate_limit = 10  # requests per minute
        self.window = 60  # seconds

    async def dispatch(self, request: Request, call_next):
        # Get client identifier (device hash from header or IP)
        client_id = request.headers.get("X-Device-Hash") or request.client.host

        if not client_id:
            raise HTTPException(status_code=400, detail="Missing client identifier")

        # Check rate limit using in-memory storage
        current_time = time.time()
        key = f"rate_limit:{client_id}"

        if key not in self.requests:
            self.requests[key] = []

        # Remove old requests outside the window
        self.requests[key] = [req_time for req_time in self.requests[key] if current_time - req_time < self.window]

        if len(self.requests[key]) >= self.rate_limit:
            raise HTTPException(status_code=429, detail="Rate limit exceeded")

        # Add current request
        self.requests[key].append(current_time)

        response = await call_next(request)
        return response
