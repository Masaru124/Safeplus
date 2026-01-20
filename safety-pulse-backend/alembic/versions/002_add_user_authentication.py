"""Add user authentication

Revision ID: 002
Revises: 001
Create Date: 2024-01-02 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision = '002'
down_revision = '001'
branch_labels = None
depends_on = None

def upgrade():
    # Create users table
    op.create_table('users',
        sa.Column('id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('email', sa.String(255), nullable=False),
        sa.Column('username', sa.String(100), nullable=False),
        sa.Column('hashed_password', sa.String(255), nullable=False),
        sa.Column('is_active', sa.Boolean(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=True),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('email'),
        sa.UniqueConstraint('username')
    )

    # Create indexes for users
    op.create_index('idx_users_email', 'users', ['email'])
    op.create_index('idx_users_username', 'users', ['username'])

    # Add user_id column to safety_signals table (FK to users)
    op.add_column('safety_signals', sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=True))

    # Create foreign key constraint
    op.create_foreign_key(
        'fk_safety_signals_user_id',
        'safety_signals',
        'users',
        ['user_id'],
        ['id']
    )

    # Create index for user_id in safety_signals
    op.create_index('idx_safety_signals_user_id', 'safety_signals', ['user_id'])


def downgrade():
    # Drop index
    op.drop_index('idx_safety_signals_user_id', table_name='safety_signals')

    # Drop foreign key
    op.drop_constraint('fk_safety_signals_user_id', 'safety_signals', type_='foreignkey')

    # Drop user_id column
    op.drop_column('safety_signals', 'user_id')

    # Drop indexes
    op.drop_index('idx_users_username', table_name='users')
    op.drop_index('idx_users_email', table_name='users')

    # Drop users table
    op.drop_table('users')

