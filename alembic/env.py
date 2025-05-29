# alembic/env.py

# … logging, load_dotenv, sys.path tweaks …

from database import Base
import anime_audio_backend.models

# <<< ADD THIS BLOCK >>>
# import all modules that define tables so they register with Base
# or wherever your models live
# if you split them up:
# import anime_audio_backend.playlists
# import anime_audio_backend.server
# etc.

target_metadata = Base.metadata
