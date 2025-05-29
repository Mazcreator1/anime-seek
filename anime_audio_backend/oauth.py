from authlib.integrations.starlette_client import OAuth
from fastapi import Request, HTTPException
from fastapi.responses import RedirectResponse, JSONResponse
from config import settings
from database import get_db
from models import User
from security import hash_password, create_token

oauth = OAuth()
oauth.register(
    name="google",
    client_id=settings.OAUTH_GOOGLE_CLIENT_ID,
    client_secret=settings.OAUTH_GOOGLE_CLIENT_SECRET,
    server_metadata_url="https://accounts.google.com/.well-known/openid-configuration",
    client_kwargs={"scope": "openid email profile"},
)

@router.get("/login/google")
async def login_google(request: Request):
    redirect_uri = request.url_for("auth_google_callback")
    return await oauth.google.authorize_redirect(request, redirect_uri)

@router.get("/auth/google/callback")
async def auth_google_callback(request: Request, db: Session = Depends(get_db)):
    token = await oauth.google.authorize_access_token(request)
    userinfo = token.get("userinfo") or await oauth.google.parse_id_token(request, token)
    email = userinfo["email"]
    user = db.query(User).filter_by(email=email).first()
    if not user:
        user = User(
            email=email,
            hashed_pw=hash_password(uuid4().hex),
            email_verified=True
        )
        db.add(user); db.commit(); db.refresh(user)
    # issue your JWT:
    access = create_token({"sub": str(user.id)}, timedelta(minutes=settings.ACCESS_EXPIRE_MINUTES))
    return JSONResponse({"access_token": access, "token_type": "bearer"})
