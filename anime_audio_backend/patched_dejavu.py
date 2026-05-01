# patched_dejavu.py
from dejavu import Dejavu
from dejavu.database import get_database



class PatchedDejavu(Dejavu):
    def __init__(self, config):
        # Use stock get_database
        self.db = get_database(config)

        # Patch the fingerprints table schema 
        self.db.CREATE_FINGERPRINTS_TABLE = """
            CREATE TABLE IF NOT EXISTS fingerprints (
                id INT NOT NULL AUTO_INCREMENT,
                hash BINARY(20) NOT NULL,
                song_id INT NOT NULL,
                offset INT NOT NULL,
                PRIMARY KEY (id),
                FOREIGN KEY (song_id) REFERENCES songs(song_id)
            )
        """

        # Call base init stuff manually
        self.config = config
