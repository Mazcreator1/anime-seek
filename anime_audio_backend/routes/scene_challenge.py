from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from sqlalchemy import func
import random
import re

from database import get_db
from auth_utils import get_current_user
from models import User, SceneChallenge, SceneChallengeAttempt

router = APIRouter(prefix="/scene-challenge", tags=["scene-challenge"])


def _normalize_title(value: str) -> str:
    value = (value or "").lower().strip()
    value = re.sub(r"[^a-z0-9\s]", "", value)
    value = re.sub(r"\s+", " ", value)
    return value


def _preferred_display_title(challenge: SceneChallenge) -> str:
    if challenge.anime_title_english and challenge.anime_title_english.strip():
        return challenge.anime_title_english.strip()
    if challenge.anime_title_romaji and challenge.anime_title_romaji.strip():
        return challenge.anime_title_romaji.strip()
    return (challenge.anime_title or "").strip()


def _all_valid_titles(challenge: SceneChallenge) -> set[str]:
    titles = set()

    if challenge.anime_title:
        titles.add(_normalize_title(challenge.anime_title))
    if challenge.anime_title_romaji:
        titles.add(_normalize_title(challenge.anime_title_romaji))
    if challenge.anime_title_english:
        titles.add(_normalize_title(challenge.anime_title_english))

    return {t for t in titles if t}


def _is_correct_guess(guess: str, challenge: SceneChallenge) -> bool:
    normalized_guess = _normalize_title(guess)
    return normalized_guess in _all_valid_titles(challenge)


def _build_scene_image_url(image_value: str) -> str:
    if not image_value:
        return ""

    image_value = image_value.strip()

    if image_value.startswith("http://") or image_value.startswith("https://"):
        return image_value

    image_value = image_value.lstrip("/")

    if image_value.startswith("fastapi/static/"):
        return f"https://anime-seek.com/{image_value}"

    if image_value.startswith("static/"):
        return f"https://anime-seek.com/fastapi/{image_value}"

    return f"https://anime-seek.com/fastapi/static/{image_value}"


def _build_choices(db: Session, correct_challenge: SceneChallenge, total_choices: int = 4) -> list[str]:
    correct_display = _preferred_display_title(correct_challenge)
    correct_norms = _all_valid_titles(correct_challenge)

    distractor_rows = (
        db.query(SceneChallenge)
        .filter(
            SceneChallenge.is_active.is_(True),
            SceneChallenge.id != correct_challenge.id,
        )
        .order_by(func.random())
        .limit(100)
        .all()
    )

    distractors = []
    seen_norms = set(correct_norms)

    for row in distractor_rows:
        candidate = _preferred_display_title(row)
        candidate_norm = _normalize_title(candidate)

        if not candidate or not candidate_norm:
            continue
        if candidate_norm in seen_norms:
            continue

        distractors.append(candidate)
        seen_norms.add(candidate_norm)

        if len(distractors) >= total_choices - 1:
            break

    choices = [correct_display] + distractors
    random.shuffle(choices)
    return choices




@router.get("/random")
def get_random_scene_challenge(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    row = (
        db.query(SceneChallenge)
        .filter(
            SceneChallenge.is_active.is_(True),
            SceneChallenge.is_daily.is_(False),
        )
        .order_by(func.random())
        .first()
    )

    if not row:
        raise HTTPException(status_code=404, detail="No active scene challenges found")

    choices = _build_choices(db, row, total_choices=4)

    return {
        "id": row.id,
        "anilist_id": row.anilist_id,
        "episode": row.episode,
        "timestamp": row.timestamp,
        "image_url": _build_scene_image_url(row.image_url),
        "difficulty": row.difficulty,
        "hints": [h for h in [row.hint_1, row.hint_2, row.hint_3] if h],
        "choices": choices,
        "answer_display": _preferred_display_title(row),
    }


@router.post("/{challenge_id}/submit")
def submit_scene_challenge(
    challenge_id: int,
    payload: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    challenge = (
        db.query(SceneChallenge)
        .filter(SceneChallenge.id == challenge_id, SceneChallenge.is_active.is_(True))
        .first()
    )

    if not challenge:
        raise HTTPException(status_code=404, detail="Challenge not found")

    guessed_title = (payload.get("guessed_title") or "").strip()
    hints_used = int(payload.get("hints_used", 0) or 0)
    time_taken_ms = payload.get("time_taken_ms")
    mode = (payload.get("mode") or "endless").strip()

    correct = _is_correct_guess(guessed_title, challenge)

    attempt = SceneChallengeAttempt(
        challenge_id=challenge.id,
        user_id=current_user.id,
        guessed_title=guessed_title,
        is_correct=correct,
        hints_used=hints_used,
        time_taken_ms=time_taken_ms,
        mode=mode,
    )
    db.add(attempt)
    db.commit()

    return {
        "correct": correct,
        "answer": _preferred_display_title(challenge),
        "episode": challenge.episode,
        "timestamp": challenge.timestamp,
        "anilist_id": challenge.anilist_id,
    }


@router.get("/me/stats")
def get_my_scene_stats(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
    ):
    attempts = (
        db.query(SceneChallengeAttempt)
        .filter(SceneChallengeAttempt.user_id == current_user.id)
        .order_by(SceneChallengeAttempt.created_at.asc())
        .all()
    )

    total_attempts = len(attempts)
    correct_attempts = sum(1 for a in attempts if a.is_correct)

    best_streak = 0
    running = 0

    for a in attempts:
        if a.is_correct:
            running += 1
            best_streak = max(best_streak, running)
        else:
            running = 0

    current_streak = running
    accuracy = round((correct_attempts / total_attempts) * 100, 2) if total_attempts else 0.0

    return {
        "total_attempts": total_attempts,
        "correct_attempts": correct_attempts,
        "accuracy": accuracy,
        "current_streak": current_streak,
        "best_streak": best_streak,
    }


