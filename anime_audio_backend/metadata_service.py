from models import Anime
from sqlalchemy.orm import Session

def store_anime_metadata(anilist_data, db: Session):
    media = anilist_data["data"]["Media"]

    genre_string = ",".join(media.get("genres", []))
    tag_string = ",".join([
        t["name"] for t in media.get("tags", [])
        if not t.get("isGeneralSpoiler", False)
    ])

    anime = Anime(
        id=media["id"],
        title_romaji=media["title"]["romaji"],
        title_english=media["title"]["english"],
        description=media["description"],
        cover_image=media["coverImage"]["large"],
        season=media["season"],
        season_year=media["seasonYear"],
        format=media["format"]
    )

    # Add these if your Anime model supports them:
    anime.genres = genre_string
    anime.tags = tag_string

    db.merge(anime)
    db.commit()
