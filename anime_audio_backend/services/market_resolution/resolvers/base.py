class BaseResolver:
    source = None  # "ANILIST", "MAL"

    def fetch(self, resolution_data: dict) -> dict:
        raise NotImplementedError

    def evaluate(self, data: dict, resolution_data: dict) -> bool:
        raise NotImplementedError
        