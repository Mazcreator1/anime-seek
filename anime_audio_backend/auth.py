# auth.py



import os

import re

import uuid

import secrets

import stripe

import logging



from datetime import datetime, timedelta

from typing import Optional, Dict



from fastapi import (

    APIRouter, Depends, HTTPException, status,

    BackgroundTasks, Query, Request, Form, Response, Body

)

from fastapi.responses import HTMLResponse

from fastapi.security import OAuth2PasswordBearer, OAuth2PasswordRequestForm

from fastapi.templating import Jinja2Templates



from jose import JWTError, jwt



from pydantic_settings import BaseSettings

from pydantic import BaseModel, EmailStr, Field, field_validator  # <-- updated



from sqlalchemy import func, text

from sqlalchemy.orm import Session



from database import get_db

from security import (

    hash_password, verify_password,

    create_token, decode_token

)

from config import settings

from models import User, Logs, PasswordResetToken, Playlist, Post, Comment

from auth_utils import get_current_user

from models import SceneChallenge, SceneChallengeAttempt

router = APIRouter(prefix="/auth", tags=["auth"])

templates = Jinja2Templates(directory="templates")

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/token")



logger = logging.getLogger("uvicorn.error")





# ----------------- Cookie helpers -----------------





def _bool_env(v: Optional[object], default: bool) -> bool:

    if v is None:

        return default

    if isinstance(v, bool):

        return v

    s = str(v).strip().lower()

    if s in {"1", "true", "yes", "y"}:

        return True

    if s in {"0", "false", "no", "n"}:

        return False

    return default





_COOKIE_SECURE = _bool_env(getattr(settings, "COOKIE_SECURE", None), True)

_COOKIE_SAMESITE = getattr(settings, "COOKIE_SAMESITE", "Lax") or "Lax"





def _set_auth_cookies(response: Response, access_token: str, refresh_token: Optional[str] = None):

    """

    Set HttpOnly cookies. Access is short-lived; refresh is long-lived.

    """

    access_max_age = int(timedelta(minutes=getattr(settings, "ACCESS_EXPIRE_MINUTES", 30)).total_seconds())

    response.set_cookie(

        key="access_token",

        value=access_token,

        max_age=access_max_age,

        httponly=True,

        secure=_COOKIE_SECURE,

        samesite=_COOKIE_SAMESITE,

        path="/",

    )

    if refresh_token:

        refresh_max_age = int(timedelta(days=getattr(settings, "REFRESH_EXPIRE_DAYS", 180)).total_seconds())

        response.set_cookie(

            key="refresh_token",

            value=refresh_token,

            max_age=refresh_max_age,

            httponly=True,

            secure=_COOKIE_SECURE,

            samesite=_COOKIE_SAMESITE,

            path="/auth",  # scope to auth routes

        )





def _clear_auth_cookies(response: Response):

    response.delete_cookie("access_token", path="/")

    response.delete_cookie("refresh_token", path="/auth")





# ----------------- helpers for IP extraction (optional / for logging only) -----------------



from ipaddress import ip_address





def _first_public_from_xff(xff: str) -> str | None:

    for token in (t.strip() for t in xff.split(",")):

        host = token.split(":")[0]

        try:

            ip = ip_address(host)

            if not (ip.is_private or ip.is_loopback or ip.is_link_local or ip.is_reserved):

                return str(ip)

        except ValueError:

            continue

    return None





def get_candidate_ips(request: Request) -> set[str]:

    h = request.headers

    ips: set[str] = set()

    for key in ("cf-connecting-ip", "x-real-ip"):

        v = h.get(key)

        if v:

            ips.add(v.split(",")[0].strip().split(":")[0])

    xff = h.get("x-forwarded-for")

    if xff:

        pub = _first_public_from_xff(xff)

        ips.add((pub or xff.split(",")[0]).strip().split(":")[0])

    if request.client:

        ips.add(request.client.host.split(":")[0])

    return {ip for ip in ips if ip}





# ----------------- Schemas -----------------





class TokenResponse(BaseModel):

    access_token: str

    refresh_token: Optional[str] = ""

    token_type: str = "bearer"





class LoginRequest(BaseModel):

    email: EmailStr

    password: str





class RegisterSchema(BaseModel):

    display_name: str

    first_name:   Optional[str] = None

    last_name:    Optional[str] = None

    email:        EmailStr

    password:     str



    @field_validator("password")

    @classmethod

    def password_strength(cls, v: str) -> str:

        if len(v) <= 6:

            raise ValueError("Password must be longer than 6 characters")

        if not re.search(r"[A-Z]", v):

            raise ValueError("Password must contain at least one uppercase letter")

        if not re.search(r"[a-z]", v):

            raise ValueError("Password must contain at least one lowercase letter")

        if not re.search(r"\d", v):

            raise ValueError("Password must contain at least one digit")

        return v





class ResetSchema(BaseModel):

    token:        str

    new_password: str



    @field_validator("new_password")

    @classmethod

    def password_strength(cls, v: str) -> str:

        if len(v) <= 6:

            raise ValueError("Password must be longer than 6 characters")

        if not re.search(r"[A-Z]", v):

            raise ValueError("Password must contain at least one uppercase letter")

        if not re.search(r"[a-z]", v):

            raise ValueError("Password must contain at least one lowercase letter")

        if not re.search(r"\d", v):

            raise ValueError("Password must contain at least one digit")

        return v





# ----------------- Endpoints -----------------





@router.post(

    "/login",

    response_model=TokenResponse,

    summary="Authenticate and get a token",

)

def login(payload: LoginRequest, response: Response, db: Session = Depends(get_db)):

    user = db.query(User).filter(User.email == payload.email).first()

    if not user or not verify_password(payload.password, user.password):

        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Bad credentials")



    # Short-lived access + long-lived refresh for "stay signed in"

    access_mins = getattr(settings, "ACCESS_EXPIRE_MINUTES", 30)

    refresh_days = getattr(settings, "REFRESH_EXPIRE_DAYS", 180)



    access_token = create_token({"sub": str(user.id), "type": "access"}, expires_delta=timedelta(minutes=access_mins))

    refresh_token = create_token({"sub": str(user.id), "type": "refresh"}, expires_delta=timedelta(days=refresh_days))



    _set_auth_cookies(response, access_token, refresh_token)



    # Still return tokens for compatibility (e.g., mobile apps)

    return {"access_token": access_token, "refresh_token": refresh_token, "token_type": "bearer"}





@router.get("/check-display-name")

def check_display_name(display_name: str = Query(..., alias="display_name"), db: Session = Depends(get_db)):

    normalized = display_name.strip().lower()

    exists = db.query(User).filter(func.lower(User.display_name) == normalized).first()

    return {"available": exists is None}





@router.post("/register", status_code=status.HTTP_201_CREATED)

def register(payload: RegisterSchema, background_tasks: BackgroundTasks, response: Response, db: Session = Depends(get_db)):

    email = payload.email.strip().lower()

    display_name = payload.display_name.strip()



    if db.query(User).filter_by(email=email).first():

        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Email already registered")



    now = datetime.utcnow()

    user = User(

        email=email,

        display_name=display_name,

        first_name=payload.first_name,

        last_name=payload.last_name,

        password=hash_password(payload.password),

        is_verified=False,

        email_verified=False,

        is_active=True,

        created_at=now,

        updated_at=now,

        anime_tier_id=0,

        provider_uid=uuid.uuid4().hex,

        api_key=secrets.token_hex(16),  # generate once

    )



    db.add(user)

    db.commit()

    db.refresh(user)



    cust = stripe.Customer.create(email=user.email, metadata={"user_id": str(user.id)})

    user.stripe_customer_id = cust.id

    db.add(user)

    db.commit()

    db.refresh(user)



    verification_token = create_token(

        {"sub": str(user.id), "action": "verify_email"},

        expires_delta=timedelta(hours=24),

    )



    from send_email import send_verification_email

    background_tasks.add_task(send_verification_email, user.email, verification_token)



    return {

        "msg": "Account created  check your email to verify",

        "user_id": user.id,

        "verification_token": verification_token,

        "stripe_customer_id": user.stripe_customer_id,

    }





@router.get("/verify-email", summary="Verify user's email via JWT (HTML)", response_class=HTMLResponse)

def verify_email_html(token: str, db: Session = Depends(get_db)) -> HTMLResponse:

    try:

        payload = decode_token(token)

        if payload.get("action") != "verify_email":

            raise JWTError()

    except JWTError:

        return HTMLResponse("<h2 style='color:red'>L Invalid or expired link.</h2>", status_code=400)



    user = db.get(User, int(payload["sub"]))

    if not user:

        return HTMLResponse("<h2 style='color:red'> User not found.</h2>", status_code=404)



    user.is_verified = True

    user.email_verified = True

    db.commit()



    html = f"""

    <!DOCTYPE html>

    <html><head><title>Email Verified</title></head>

    <body style="font-family:sans-serif;text-align:center;padding:50px">

      <h1>Email Verified!</h1>

      <p>Your address <strong>{user.email}</strong> has been verified.</p>

      <p><a href="{settings.FRONTEND_URL}">Return to Home Page</a></p>

    </body></html>

    """

    return HTMLResponse(content=html, status_code=200)





@router.get("/verify-email-api", summary="Verify user's email via JWT (API)", response_model_exclude_none=True)

def verify_email_api(token: str = Query(...), response: Response = None, db: Session = Depends(get_db)) -> Dict[str, object]:

    try:

        payload = decode_token(token)

        if payload.get("action") != "verify_email":

            raise JWTError()

    except JWTError:

        raise HTTPException(status_code=400, detail="Invalid or expired verification link.")



    user = db.get(User, int(payload["sub"]))

    if not user:

        raise HTTPException(status_code=404, detail="User not found.")



    user.is_verified = True

    user.email_verified = True

    db.commit()



    # Auto-sign-in on verify: set cookies so they stay logged in

    access_mins = getattr(settings, "ACCESS_EXPIRE_MINUTES", 30)

    refresh_days = getattr(settings, "REFRESH_EXPIRE_DAYS", 180)

    access_token = create_token({"sub": str(user.id), "type": "access"}, expires_delta=timedelta(minutes=access_mins))

    refresh_token = create_token({"sub": str(user.id), "type": "refresh"}, expires_delta=timedelta(days=refresh_days))

    if response is not None:

        _set_auth_cookies(response, access_token, refresh_token)



    return {"verified": True, "email": user.email, "access_token": access_token, "token_type": "bearer"}





@router.get("/reset-password", include_in_schema=False)

def reset_password_form(request: Request, token: str, db: Session = Depends(get_db)):

    prt = db.query(PasswordResetToken).filter_by(token=token, used=False).first()

    if not prt:

        return HTMLResponse("<h2 style='color:red'> This reset link is invalid or has already been used.</h2>", status_code=400)

    return templates.TemplateResponse("reset_password.html", {"request": request, "token": token})





@router.post("/forgot-password", include_in_schema=False)

async def forgot_password_submit(request: Request, db: Session = Depends(get_db)):

    ct = request.headers.get("content-type", "")

    if "application/json" in ct:

        body = await request.json()

        email = body.get("email", "").strip()

    else:

        form = await request.form()

        email = form.get("email", "").strip()



    if not email:

        raise HTTPException(status_code=422, detail="Missing email in JSON body or form field")



    user = db.query(User).filter_by(email=email).first()

    if user:

        token = create_token(

            {"sub": str(user.id), "action": "reset_password"},

            expires_delta=timedelta(hours=1),   # fixed typo

        )

        prt = PasswordResetToken(user_id=user.id, token=token, used=False, created_at=datetime.utcnow())

        db.add(prt)

        db.commit()

        from send_email import send_password_reset_email

        send_password_reset_email(to_email=user.email, token=token)



    return templates.TemplateResponse("forgot_password.html", {"request": request, "success": " If that email exists, youll receive a reset link shortly."})





@router.post("/reset-password", include_in_schema=False)

def reset_password_submit(

    request: Request,

    token: str = Form(...),

    new_password: str = Form(...),

    confirm_password: str = Form(...),

    db: Session = Depends(get_db),

):

    if new_password != confirm_password:

        return templates.TemplateResponse("reset_password.html", {"request": request, "token": token, "error": "Passwords do not match."})

    prt = db.query(PasswordResetToken).filter_by(token=token, used=False).first()

    if not prt:

        raise HTTPException(400, "Invalid or expired link")

    data = decode_token(token)

    if data.get("action") != "reset_password":

        raise HTTPException(400, "Bad token")

    user = db.get(User, int(data["sub"]))

    if not user:

        raise HTTPException(404, "User not found")



    user.password = hash_password(new_password)

    prt.used = True

    db.commit()



    return templates.TemplateResponse("reset_password.html", {"request": request, "success": " Your password has been reset! You can now log in."})





@router.post("/token", summary="Log in and receive access & refresh tokens")

def login_for_access(

    request: Request,

    response: Response,

    form_data: OAuth2PasswordRequestForm = Depends(),

    db: Session = Depends(get_db),

):

    user = db.query(User).filter_by(email=form_data.username).first()

    if not user or not verify_password(form_data.password, user.password):

        raise HTTPException(status_code=401, detail="Invalid credentials")

    if not user.is_active:

        raise HTTPException(status_code=403, detail="Inactive user")



    # You can still log IPs for analytics, but DO NOT bind auth to IP here.

    ips = get_candidate_ips(request)

    logger.info(f"[auth] login ip(s)={list(ips)} user_id={user.id}")



    access_mins = getattr(settings, "ACCESS_EXPIRE_MINUTES", 30)

    refresh_days = getattr(settings, "REFRESH_EXPIRE_DAYS", 180)

    access_token = create_token({"sub": str(user.id), "type": "access"}, expires_delta=timedelta(minutes=access_mins))

    refresh_token = create_token({"sub": str(user.id), "type": "refresh"}, expires_delta=timedelta(days=refresh_days))



    _set_auth_cookies(response, access_token, refresh_token)

    return {"access_token": access_token, "refresh_token": refresh_token, "token_type": "bearer"}



class RefreshRequest(BaseModel):
    refresh_token: str



@router.post("/refresh", summary="Refresh your access token")
def refresh_token(
    response: Response,
    request: Request,
    refresh_token: str | None = Body(default=None, embed=True),
    db: Session = Depends(get_db),
):
    token = (refresh_token or "").strip() or request.cookies.get("refresh_token")
    if not token:
        raise HTTPException(status_code=401, detail="Missing refresh token")

    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
    except JWTError:
        raise HTTPException(status_code=401, detail="Invalid refresh token")

    if payload.get("type") != "refresh":
        raise HTTPException(status_code=401, detail="Invalid refresh token type")

    user_id = int(payload.get("sub") or 0)
    user = db.get(User, user_id)
    if not user or not user.is_active:
        raise HTTPException(status_code=401, detail="Inactive user")

    access_mins = getattr(settings, "ACCESS_EXPIRE_MINUTES", 44,640)
    logger.error(f"ACCESS_EXPIRE_MINUTES={access_mins}")
    refresh_days = getattr(settings, "REFRESH_EXPIRE_DAYS", 180)

    new_access = create_token({"sub": str(user.id), "type": "access"}, expires_delta=timedelta(minutes=access_mins))
    new_refresh = create_token({"sub": str(user.id), "type": "refresh"}, expires_delta=timedelta(days=refresh_days))

    _set_auth_cookies(response, new_access, new_refresh)
    return {"access_token": new_access, "refresh_token": new_refresh, "token_type": "bearer"}

@router.post("/logout", summary="Logout and clear auth cookies")

def logout(response: Response):

    _clear_auth_cookies(response)

    return {"ok": True}





@router.delete("/delete-me", status_code=204, operation_id="delete_current_user")

def delete_me(db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):

    deleted = db.query(User).filter(User.id == current_user.id).delete(synchronize_session=False)

    if not deleted:

        raise HTTPException(404, "User not found")

    db.commit()

    return Response(status_code=204)





@router.get("/me")
def me(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    user = db.get(User, current_user.id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    if not user.stripe_customer_id:
        cust = stripe.Customer.create(
            email=user.email,
            metadata={"user_id": str(user.id)}
        )
        user.stripe_customer_id = cust.id
        db.commit()

    scene_history = (
        db.query(Logs)
        .filter(Logs.api_key == user.api_key, Logs.search_type == "scene")
        .order_by(Logs.created_at.desc())
        .limit(10)
        .all()
    )
    scene_data = [
        {
            "id": logs.id,
            "anime_id": logs.anime_id,
            "timestamp": logs.created_at.isoformat(),
            "match_confidence": logs.accuracy,
        }
        for logs in scene_history
    ]

    audio_history = (
        db.query(Logs)
        .filter(Logs.api_key == user.api_key, Logs.search_type == "audio")
        .order_by(Logs.created_at.desc())
        .limit(10)
        .all()
    )
    audio_data = [
        {
            "id": logs.id,
            "song_id": logs.song_id,
            "anime_id": logs.anime_id,
            "timestamp": logs.created_at.isoformat(),
            "match_confidence": logs.accuracy,
        }
        for logs in audio_history
    ]

    playlists = db.query(Playlist).filter(Playlist.user_id == user.id).all()
    playlist_data = [
        {
            "id": p.id,
            "name": p.name,
            "count": len(p.songs),
        }
        for p in playlists
    ]

    badge_data = [
        {
            "id": b.id,
            "name": b.name,
            "icon": b.icon_url,
        }
        for b in getattr(user, "badges", [])
    ]

    # ----------------------------
    # Guess-the-Scene merged stats
    # ----------------------------
    challenge_attempts_query = (
        db.query(SceneChallengeAttempt)
        .filter(SceneChallengeAttempt.user_id == user.id)
    )

    total_scene_challenge_attempts = challenge_attempts_query.count()
    total_scene_challenge_correct = (
        challenge_attempts_query
        .filter(SceneChallengeAttempt.is_correct.is_(True))
        .count()
    )

    challenge_rows = (
        db.query(SceneChallengeAttempt)
        .filter(SceneChallengeAttempt.user_id == user.id)
        .order_by(SceneChallengeAttempt.created_at.asc())
        .all()
    )

    best_scene_challenge_streak = 0
    current_scene_challenge_streak = 0
    running_streak = 0

    for row in challenge_rows:
        if row.is_correct:
            running_streak += 1
            if running_streak > best_scene_challenge_streak:
                best_scene_challenge_streak = running_streak
        else:
            running_streak = 0

    current_scene_challenge_streak = running_streak

    scene_challenge_accuracy = (
        round((total_scene_challenge_correct / total_scene_challenge_attempts) * 100, 2)
        if total_scene_challenge_attempts > 0
        else 0.0
    )

    # Optional recent challenge attempts
    recent_scene_challenge_attempts = (
        db.query(SceneChallengeAttempt, SceneChallenge)
        .join(SceneChallenge, SceneChallenge.id == SceneChallengeAttempt.challenge_id)
        .filter(SceneChallengeAttempt.user_id == user.id)
        .order_by(SceneChallengeAttempt.created_at.desc())
        .limit(10)
        .all()
    )

    scene_challenge_history = [
        {
            "attempt_id": attempt.id,
            "challenge_id": attempt.challenge_id,
            "anime_title": challenge.anime_title,
            "guessed_title": attempt.guessed_title,
            "is_correct": attempt.is_correct,
            "difficulty": challenge.difficulty,
            "timestamp": attempt.created_at.isoformat(),
            "episode": challenge.episode,
            "scene_timestamp": challenge.timestamp,
            "image_url": challenge.image_url,
        }
        for attempt, challenge in recent_scene_challenge_attempts
    ]

    return {
        "id": user.id,
        "email": user.email,
        "display_name": user.display_name or f"User{user.id}",
        "avatar_url": user.avatar_url or "/uploads/user_avatars/default_avatar.jpg",
        "is_verified": user.email_verified,
        "is_subscribed": user.is_subscribed,
        "subscription_expires": user.subscription_expires.isoformat() if user.subscription_expires else None,
        "anime_tier_id": user.anime_tier_id,
        "stripe_customer_id": user.stripe_customer_id,
        "stripe_subscription_id": user.stripe_subscription_id,
        "cancel_at_period_end": bool(user.cancel_at_period_end),
        "badges": badge_data,
        "scene_history": scene_data,
        "audio_history": audio_data,
        "playlists": playlist_data,
        "api_key": user.api_key,
        "is_admin": bool(getattr(user, "is_admin", False)),

        # Guess-the-Scene section
        "scene_challenge_stats": {
            "total_attempts": total_scene_challenge_attempts,
            "correct_attempts": total_scene_challenge_correct,
            "accuracy": scene_challenge_accuracy,
            "current_streak": current_scene_challenge_streak,
            "best_streak": best_scene_challenge_streak,
        },
        "scene_challenge_history": scene_challenge_history,
    }