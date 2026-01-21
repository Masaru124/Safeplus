from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Database URL from environment (Neon DB)
DATABASE_URL = os.getenv("DB_URL")

if not DATABASE_URL:
    raise ValueError("DB_URL environment variable is not set. Please configure your Neon DB credentials.")

# Create engine with Neon-compatible settings
# pool_pre_ping=True helps with connection health checks (important for serverless Neon DB)
engine = create_engine(
    DATABASE_URL,
    pool_pre_ping=True,
    pool_size=5,
    max_overflow=10
)

# Create SessionLocal class
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

# Create Base class
Base = declarative_base()

def get_db():
    """Dependency to get database session"""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
