from pydantic import BaseModel, EmailStr
from datetime import date
from typing import Dict, List, Optional
from pydantic import BaseModel
from typing import Optional

class ResetPasswordRequest(BaseModel):
    token: str
    new_password: str

class LoginRequest(BaseModel):
    email: EmailStr
    password: str

class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str

class ForgotPasswordRequest(BaseModel):
    email: EmailStr


class DayCount(BaseModel):
    date: date
    count: int

class ConfidencePoint(BaseModel):
    date: date
    confidence: float

class AnalyticsResponse(BaseModel):
    totalAudioSearches: int
    successfulAudioMatches: int
    totalSceneSearches: int
    successfulSceneMatches: int
    audioSearchesPerDay: List[DayCount]
    sceneSearchesPerDay: List[DayCount]
    longestStreakDays: int
    averageConfidence: float
    topArtists: Dict[str,int]
    genreDistribution: Dict[str,int]
    matchesPerDay: List[DayCount]
    confidenceTrend: List[ConfidencePoint]