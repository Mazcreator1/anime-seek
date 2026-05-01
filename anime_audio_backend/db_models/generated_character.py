from sqlalchemy import Boolean, Column, DateTime, Integer, String, Text, ForeignKey
from sqlalchemy.sql import func

from database import Base


ART_STYLE_HINTS = {
    "modern_anime": "modern polished anime illustration, crisp digital rendering, detailed lighting, clean linework",
    "90s_anime": "1990s anime cel shading, retro OVA aesthetic, thicker outlines, softer film-like colors, hand-painted anime frame feel, less glossy rendering, classic 90s eye design",
    "80s_anime": "1980s anime aesthetic, bold cel shading, vintage palette, sharper facial structure, classic hand-drawn anime look",
    "early_2000s_anime": "early 2000s anime look, lighter digital coloring, classic TV anime rendering, simpler highlights",
    "retro_ova": "retro OVA anime frame, cinematic cel shading, painted background feel, nostalgic composition",
    "shojo_90s": "1990s shojo anime style, elegant large eyes, delicate linework, pastel color palette, romantic vintage anime feel",
    "grainy_vhs_anime": "retro anime VHS look, visible film grain, analog softness, faded colors, nostalgic tape-era anime frame",
    "cel_shaded_classic": "classic anime cel shading, flat shadow layers, hand-drawn look, bold outlines, traditional animation feel",
}


class GeneratedCharacter(Base):
    __tablename__ = "generated_characters"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer,
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    prompt = Column(Text, nullable=False)
    style = Column(String(100), nullable=False)
    art_style = Column(String(100), nullable=False, default="modern_anime")

    gender = Column(String(50), nullable=False)
    hair = Column(String(50), nullable=False)
    eyes = Column(String(50), nullable=False)
    outfit = Column(String(50), nullable=False)
    mood = Column(String(50), nullable=False)

    image_url = Column(Text, nullable=False)
    is_favorite = Column(Boolean, default=False, nullable=False)

    name = Column(String(120), nullable=True)
    backstory = Column(Text, nullable=True)
    story_scene = Column(Text, nullable=True)

    created_at = Column(DateTime(timezone=True), server_default=func.now(), nullable=False)