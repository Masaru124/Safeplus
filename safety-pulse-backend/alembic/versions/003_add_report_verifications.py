"""Add report verifications and vote tracking

Revision ID: 003
Revises: 002
Create Date: 2024-01-03 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '003'
down_revision = '002'
branch_labels = None
depends_on = None

def upgrade():
    # Add vote tracking columns to safety_signals table
    op.add_column('safety_signals', sa.Column('true_votes', sa.Integer(), nullable=True, default=0))
    op.add_column('safety_signals', sa.Column('false_votes', sa.Integer(), nullable=True, default=0))
    
    # Update existing rows to have 0 instead of NULL
    op.execute("UPDATE safety_signals SET true_votes = 0 WHERE true_votes IS NULL")
    op.execute("UPDATE safety_signals SET false_votes = 0 WHERE false_votes IS NULL")
    
    # Alter columns to NOT NULL with default
    op.alter_column('safety_signals', 'true_votes', existing_type=sa.Integer(), nullable=False, existing_server_default=sa.text('0'))
    op.alter_column('safety_signals', 'false_votes', existing_type=sa.Integer(), nullable=False, existing_server_default=sa.text('0'))
    
    # Create report_verifications table
    op.create_table('report_verifications',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('signal_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('is_true', sa.Boolean(), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.ForeignKeyConstraint(['signal_id'], ['safety_signals.id'], name='fk_verifications_signal_id'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], name='fk_verifications_user_id')
    )
    
    # Create indexes for report_verifications
    op.create_index('idx_report_verifications_signal_id', 'report_verifications', ['signal_id'])
    op.create_index('idx_report_verifications_user_id', 'report_verifications', ['user_id'])
    
    # Create unique constraint to prevent multiple votes per user per signal
    op.create_unique_constraint(
        'uq_user_signal_vote',
        'report_verifications',
        ['signal_id', 'user_id']
    )


def downgrade():
    # Drop unique constraint
    op.drop_constraint('uq_user_signal_vote', 'report_verifications', type_='unique')
    
    # Drop indexes
    op.drop_index('idx_report_verifications_user_id', table_name='report_verifications')
    op.drop_index('idx_report_verifications_signal_id', table_name='report_verifications')
    
    # Drop report_verifications table
    op.drop_table('report_verifications')
    
    # Drop vote columns from safety_signals
    op.drop_column('safety_signals', 'false_votes')
    op.drop_column('safety_signals', 'true_votes')

