class AniListResolver(BaseResolver):
    source = "ANILIST"

    def fetch(self, resolution_data):
        anilist_id = resolution_data["provider_id"]

        # call AniList API
        return {
            "ranking": 7,
            "score": 8.9,
            "popularity": 124000
        }

    def evaluate(self, data, resolution_data):
        metric = resolution_data["metric"]

        if metric == "ranking":
            return data["ranking"] <= resolution_data["threshold"]

        if metric == "score":
            return data["score"] >= resolution_data["value"]

        raise ValueError("Unsupported metric")
