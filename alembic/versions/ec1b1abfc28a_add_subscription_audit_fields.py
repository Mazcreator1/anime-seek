"""add subscription & audit fields

Revision ID: ec1b1abfc28a
Revises: 
Create Date: 2025-05-28 00:36:16.545892

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import mysql

# revision identifiers, used by Alembic.
revision: str = 'ec1b1abfc28a'
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade():
    # ── Add subscription‐related columns ────────────────────────────────────────
    #op.add_column(
    #    'users',
    #    sa.Column('is_subscribed', sa.Boolean(), nullable=False, server_default=sa.false())
    #)
    #op.add_column(
    #    'users',
    #    sa.Column('subscription_expires', sa.DateTime(), nullable=True)
    #)
    #op.add_column(
     #   'users',
     #   sa.Column('stripe_customer_id', sa.String(length=255), nullable=True)
    #)
    #op.add_column(
    #    'users',
    #    sa.Column('stripe_subscription_id', sa.String(length=255), nullable=True)
    #)

    # ── (Optional) drop the server_default now that the column exists ───────────
    #op.alter_column(
        #'users',
        #'is_subscribed',
        #server_default=None
    #)
    def downgrade():
        op.drop_column('users', 'stripe_subscription_id')
        op.drop_column('users', 'stripe_customer_id')
        op.drop_column('users', 'subscription_expires')
        op.drop_column('users', 'is_subscribed')