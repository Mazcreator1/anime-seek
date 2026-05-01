from sqlalchemy.orm import Session
from models import User, Badge
from datetime import datetime

def assign_badges(user: User, analytics: dict, db: Session):
    badge_defs = [
        # Scene Searches
        ("Rookie Seeker", analytics["totalSceneSearches"] >= 5),
        ("Scene Scout", analytics["totalSceneSearches"] >= 15),
        ("Gintoki Vision", analytics["totalSceneSearches"] >= 35),
        ("Sharingan Seer", analytics["totalSceneSearches"] >= 75),

        # Audio Searches
        ("Audio Adept", analytics["totalAudioSearches"] >= 5),
        ("Sound Shinobi", analytics["totalAudioSearches"] >= 20),
        ("Echo Alchemist", analytics["totalAudioSearches"] >= 50),

        # Playlists
        ("Playlist Rookie", analytics["playlistsCreated"] >= 1),
        ("Mix Master", analytics["playlistsCreated"] >= 5),
        ("Groove Hashira", analytics["playlistsCreated"] >= 10),

        # Rank & Streak
        ("Top 10 Hero", analytics["userRank"] <= 10),
        ("Top 3 Legend", analytics["userRank"] <= 3),
        ("1 Week Streak", analytics["longestStreakDays"] >= 7),
        ("2 Week Streak", analytics["longestStreakDays"] >= 14),
        ("Streak Titan", analytics["longestStreakDays"] >= 30),

        # Confidence
        ("Sharp Ear", analytics["averageConfidence"] >= 0.85),
        ("Ultra Instinct", analytics["averageConfidence"] >= 0.95),

        # Genre Explorer
        ("Genre Hopper", len(analytics["genreDistribution"]) >= 5),
        ("Otaku Completionist", len(analytics["genreDistribution"]) >= 10),

        # Artist Match
        ("Artist Hunter", len(analytics["topArtists"]) >= 3),

        # Bonus
        ("Veteran Seeker", analytics["totalSceneSearches"] + analytics["totalAudioSearches"] >= 100),
        ("Summoned Hero", analytics["successfulSceneMatches"] + analytics["successfulAudioMatches"] >= 50),
    ]

    # Load existing badge names for user
    existing = db.query(Badge.name).filter(Badge.api_key == user.api_key).all()
    existing_names = {name for (name,) in existing}

    # ✅ Only add new badges, never remove
    for name, eligible in badge_defs:
        if eligible and name not in existing_names:
            db.add(Badge(
                user_id=user.id,
                api_key=user.api_key,
                name=name,
                unlocked_at=datetime.utcnow()
            ))

    db.commit()
