"""create stub user table

Revision ID: c2089d327f43
Revises: fa80185103b8
Create Date: 2025-07-16 01:19:03.675813

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'c2089d327f43'
down_revision: Union[str, None] = 'fa80185103b8'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Upgrade schema."""
    pass


def downgrade() -> None:
    """Downgrade schema."""
    pass
