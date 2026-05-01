from database import engine, Base
import models
from typing import Optional

Base.metadata.create_all(bind=engine)