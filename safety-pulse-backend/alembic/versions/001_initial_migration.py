"""Initial migration

Revision ID: 001
Revises:
Create Date: 2024-01-01 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '001'
down_revision = None
branch_labels = None
depends_on = None

def upgrade():
    # Create enum types
    op.execute("CREATE TYPE signaltype AS ENUM ('followed', 'suspicious_activity', 'unsafe_area', 'harassment', 'other')")
    op.execute("CREATE TYPE confidencelevel AS ENUM ('low', 'medium', 'high')")

    # Create safety_signals table
    op.create_table('safety_signals',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('signal_type', postgresql.ENUM('followed', 'suspicious_activity', 'unsafe_area', 'harassment', 'other', name='signaltype'), nullable=False),
        sa.Column('severity', sa.Integer(), nullable=False),
        sa.Column('latitude', sa.Float(), nullable=False),
        sa.Column('longitude', sa.Float(), nullable=False),
        sa.Column('geohash', sa.String(), nullable=False),
        sa.Column('timestamp', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.Column('device_hash', sa.String(), nullable=False),
        sa.Column('context_tags', postgresql.JSONB(), nullable=True),
        sa.Column('trust_score', sa.Float(), nullable=False),
        sa.Column('is_valid', sa.Boolean(), nullable=True),
        sa.PrimaryKeyConstraint('id')
    )

    # Create pulse_tiles table
    op.create_table('pulse_tiles',
        sa.Column('tile_id', sa.String(), nullable=False),
        sa.Column('pulse_score', sa.Integer(), nullable=False),
        sa.Column('confidence_level', postgresql.ENUM('low', 'medium', 'high', name='confidencelevel'), nullable=False),
        sa.Column('last_updated', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.Column('signal_count', sa.Integer(), nullable=True),
        sa.PrimaryKeyConstraint('tile_id')
    )

    # Create device_activity table
    op.create_table('device_activity',
        sa.Column('device_hash', sa.String(), nullable=False),
        sa.Column('submission_count', sa.Integer(), nullable=True),
        sa.Column('last_submission', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.Column('anomaly_score', sa.Float(), nullable=True),
        sa.PrimaryKeyConstraint('device_hash')
    )

    # Create indexes
    op.create_index('idx_safety_signals_device_hash', 'safety_signals', ['device_hash'])
    op.create_index('idx_safety_signals_timestamp', 'safety_signals', ['timestamp'])
    op.create_index('idx_safety_signals_geohash', 'safety_signals', ['geohash'])
    op.create_index('idx_pulse_tiles_last_updated', 'pulse_tiles', ['last_updated'])
    op.create_index('idx_device_activity_last_submission', 'device_activity', ['last_submission'])

def downgrade():
    # Drop indexes
    op.drop_index('idx_device_activity_last_submission', table_name='device_activity')
    op.drop_index('idx_pulse_tiles_last_updated', table_name='pulse_tiles')
    op.drop_index('idx_safety_signals_geohash', table_name='safety_signals')
    op.drop_index('idx_safety_signals_timestamp', table_name='safety_signals')
    op.drop_index('idx_safety_signals_device_hash', table_name='safety_signals')

    # Drop tables
    op.drop_table('device_activity')
    op.drop_table('pulse_tiles')
    op.drop_table('safety_signals')

    # Drop enum types
    op.execute('DROP TYPE confidencelevel')
    op.execute('DROP TYPE signaltype')
