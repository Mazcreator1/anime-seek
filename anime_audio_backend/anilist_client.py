import aiohttp
from fastapi import HTTPException

ANILIST_API_URL = "https://graphql.anilist.co"

async def fetch_anime_by_title(title: str) -> dict:
    query = """
query ($search: String) {
  Media(search: $search, type: ANIME) {
    id
    title { romaji english native }
    description(asHtml: false)
    coverImage { large }
    season
    seasonYear
    format
    genres
    tags { name rank isGeneralSpoiler }
  }
}
"""
    variables = {"search": title}
    headers = {
        "Content-Type": "application/json",
        "Accept": "application/json",
    }

    async with aiohttp.ClientSession() as session:
        async with session.post(ANILIST_API_URL,
                                json={"query": query, "variables": variables},
                                headers=headers) as resp:
            text = await resp.text()
            if resp.status != 200:
                # AniList itself returned an HTTP error
                raise HTTPException(
                    status_code=502,
                    detail=f"AniList HTTP {resp.status}: {text}"
                )
            data = await resp.json()
            if "errors" in data:
                # GraphQL-level errors
                raise HTTPException(
                    status_code=502,
                    detail=f"AniList GraphQL errors: {data['errors']}"
                )
            # At this point data["data"]["Media"] should exist
            return data
