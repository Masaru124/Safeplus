-- Migration: Add lifecycle columns to safety_signals table
-- Run this SQL against the PostgreSQL database to fix the schema mismatch

-- This migration adds the status field and related columns that are defined
-- in the SafetySignal model but missing in the actual database table.

-- Create enum type for report status if it doesn't exist
DO $$ BEGIN
    CREATE TYPE report_status AS ENUM ('pending', 'verified', 'disputed', 'expired', 'deleted');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- Add the missing columns to safety_signals table
-- Using ALTER TABLE ADD COLUMN for each new column

-- Status lifecycle column
ALTER TABLE safety_signals ADD COLUMN IF NOT EXISTS status report_status NOT NULL DEFAULT 'pending';

-- Enhanced tracking columns
ALTER TABLE safety_signals ADD COLUMN IF NOT EXISTS severity_weight FLOAT NOT NULL DEFAULT 0.5;
ALTER TABLE safety_signals ADD COLUMN IF NOT EXISTS confidence_score FLOAT NOT NULL DEFAULT 0.5;
ALTER TABLE safety_signals ADD COLUMN IF NOT EXISTS last_activity_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE safety_signals ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP WITH TIME ZONE;

-- Abuse and integrity fields
ALTER TABLE safety_signals ADD COLUMN IF NOT EXISTS abuse_flags JSONB;
ALTER TABLE safety_signals ADD COLUMN IF NOT EXISTS deleted_by_owner BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE safety_signals ADD COLUMN IF NOT EXISTS delete_reason TEXT;
ALTER TABLE safety_signals ADD COLUMN IF NOT EXISTS delete_cooldown_expires_at TIMESTAMP WITH TIME ZONE;

-- Vote window and verification timestamps
ALTER TABLE safety_signals ADD COLUMN IF NOT EXISTS vote_window_expires_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE safety_signals ADD COLUMN IF NOT EXISTS verified_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE safety_signals ADD COLUMN IF NOT EXISTS disputed_at TIMESTAMP WITH TIME ZONE;

-- Create index on status for faster queries
CREATE INDEX IF NOT EXISTS idx_safety_signals_status ON safety_signals(status);
CREATE INDEX IF NOT EXISTS idx_safety_signals_expires_at ON safety_signals(expires_at);
CREATE INDEX IF NOT EXISTS idx_safety_signals_is_valid ON safety_signals(is_valid);
CREATE INDEX IF NOT EXISTS idx_safety_signals_timestamp ON safety_signals(timestamp DESC);

-- Verify the columns were added
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'safety_signals'
  AND column_name IN (
    'status', 'severity_weight', 'confidence_score', 'last_activity_at',
    'expires_at', 'abuse_flags', 'deleted_by_owner', 'delete_reason',
    'delete_cooldown_expires_at', 'vote_window_expires_at', 'verified_at', 'disputed_at'
  )
ORDER BY column_name;

