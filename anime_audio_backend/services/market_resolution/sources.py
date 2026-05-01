def resolve_market_outcome(market):
    if market.resolution_source == "manual":
        raise RuntimeError("Manual resolution required")

    if market.resolution_source == "anilist":
        return resolve_anilist(market.resolution_data)

    if market.resolution_source == "mal":
        return resolve_mal(market.resolution_data)

    raise RuntimeError("Unknown resolution source")
