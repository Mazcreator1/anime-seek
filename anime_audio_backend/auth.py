# auth.py

import re
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import (
    OAuth2PasswordBearer,
    OAuth2PasswordRequestForm,
)
from pydantic import BaseModel, EmailStr, validator
from sqlalchemy.orm import Session
from jose import JWTError, jwt

from database import get_db
from models import User
from security import hash_password, verify_password, create_token
from config import settings
from fastapi import BackgroundTasks
from utils.email import send_email



SECRET_KEY = settings.SECRET_KEY
router = APIRouter(prefix="/auth", tags=["auth"])
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/token")


class RegisterSchema(BaseModel):
    email: EmailStr
    password: str

    @validator("password")
    def password_strength(cls, v):
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
    token: str
    new_password: str

    @validator("new_password")  # reuse your strength rules
    def password_strength(cls, v):
        if len(v) <= 6:
            raise ValueError("Password must be longer than 6 characters")
        if not re.search(r"[A-Z]", v):
            raise ValueError("Password must contain at least one uppercase letter")
        if not re.search(r"[a-z]", v):
            raise ValueError("Password must contain at least one lowercase letter")
        if not re.search(r"\d", v):
            raise ValueError("Password must contain at least one digit")
        return v

@router.post("/password-reset")
def password_reset(data: ResetSchema, db: Session = Depends(get_db)):
    payload = decode_token(data.token)
    if payload.get("action") != "reset_password":
        raise HTTPException(400, "Invalid token")
    user = db.query(User).get(int(payload["sub"]))
    user.hashed_pw = hash_password(data.new_password)
    db.commit()
    return {"msg": "Password updated"}

@router.post("/register", status_code=status.HTTP_201_CREATED,summary="Create a new user account")
def register(
        payload: RegisterSchema,
        db: Session = Depends(get_db),
):
    # payload.email is already a valid EmailStr
    if db.query(User).filter_by(email=payload.email).first():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Email already registered",
        )

    user = User(
        email=payload.email,
        hashed_pw=hash_password(payload.password),
        # leave is_subscribed=False, subscription_expires=None by default
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return {"msg": "Account created", "user_id": user.id}

    token = create_token(
        {"sub": str(user.id), "action": "verify_email"},
        expires_delta=timedelta(hours=24)
    )
    verify_link = f"{settings.FRONTEND_URL}/verify-email?token={token}"
    background.add_task(
        send_email,
        to=user.email,
        subject="Verify your email",
        body=f"Click to verify: {verify_link}"
    )
    return {"msg": "Account created – check your email to verify"}

@router.get("/verify-email")
def verify_email(token: str, db: Session = Depends(get_db)):
    payload = decode_token(token)  # must validate SECRET_KEY + algorithm
    if payload.get("action") != "verify_email":
        raise HTTPException(400, "Invalid token")
    user = db.query(User).get(int(payload["sub"]))
    user.email_verified = True
    user.verified_at = datetime.utcnow()
    db.commit()
    return {"msg": "Email verified"}

@router.post("/password-reset-request")
def password_reset_request(
        email: EmailStr, background: BackgroundTasks, db: Session = Depends(get_db)
):
    user = db.query(User).filter_by(email=email).first()
    if not user:
        # don't reveal existence
        return {"msg": "If that account exists, you’ll get an email"}
    token = create_token(
        {"sub": str(user.id), "action": "reset_password"},
        expires_delta=timedelta(hours=1)
    )
    reset_link = f"{settings.FRONTEND_URL}/reset-password?token={token}"
    background.add_task(
        send_email,
        to=user.email,
        subject="Reset your password",
        body=f"Click to reset: {reset_link}"
    )
    return {"msg": "If that account exists, you’ll get an email"}





@router.post(
    "/token",
    summary="Log in and receive access & refresh tokens"
)
def login_for_access(
        form_data: OAuth2PasswordRequestForm = Depends(),
        db: Session = Depends(get_db),
):
    user = db.query(User).filter_by(email=form_data.username).first()
    if not user or not verify_password(form_data.password, user.hashed_pw):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid credentials",
        )
    if not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Inactive user",
        )

    access_token = create_token(
        {"sub": str(user.id)},
        expires_delta=timedelta(minutes=ACCESS_EXPIRE_MINUTES),
    )
    refresh_token = create_token(
        {"sub": str(user.id)},
        expires_delta=timedelta(days=REFRESH_EXPIRE_DAYS),
    )
    return {
        "access_token": access_token,
        "refresh_token": refresh_token,
        "token_type": "bearer",
    }


@router.post(
    "/refresh",
    summary="Refresh your access token"
)
def refresh_token(
        refresh_token: str,
        db: Session = Depends(get_db),
):
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        user_id = int(payload.get("sub"))
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token",
        )

    user = db.query(User).get(user_id)
    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Inactive user",
        )

    new_access = create_token(
        {"sub": str(user.id)},
        expires_delta=timedelta(minutes=ACCESS_EXPIRE_MINUTES),
    )
    return {"access_token": new_access, "token_type": "bearer"}


async def get_current_user(
        token: str = Depends(oauth2_scheme),
        db: Session = Depends(get_db),
):
    try:
        payload = jwt.decode(token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM])
        user_id = int(payload.get("sub"))
    except JWTError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication token",
        )

    user = db.query(User).get(user_id)
    if not user or not user.is_active:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Inactive user",
        )
    return user


@router.post(
    "/subscribe",
    summary="Start a 3-day trial subscription for the current user"
)
def subscribe(
        current_user: User = Depends(get_current_user),
        db: Session = Depends(get_db),
):
    now = datetime.utcnow()

    # Enforce one-time trial
    if getattr(current_user, "trial_used", False):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="3-day trial already used",
        )

    # Enforce you haven’t already got an active subscription
    if current_user.is_subscribed and current_user.subscription_expires > now:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Subscription already active",
        )

    trial_expires = now + timedelta(days=3)
    current_user.trial_used = True
    current_user.is_subscribed = True
    current_user.subscription_expires = trial_expires

    db.commit()
    db.refresh(current_user)
    return {
        "msg": "3-day trial started",
        "subscription_expires": trial_expires.isoformat(),
    }
