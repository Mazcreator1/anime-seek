import base64
import json
import logging
import os
import uuid
from pathlib import Path

from openai import OpenAI

from schemas.character import CharacterGenerateRequest

logger = logging.getLogger(__name__)


ART_STYLE_HINTS = {
    "modern_anime": (
        "modern polished anime illustration, crisp digital rendering, "
        "clean linework, refined lighting, contemporary anime proportions"
    ),
    "90s_anime": (
        "1990s anime cel shading, retro OVA aesthetic, thicker black outlines, "
        "hand-painted anime frame feel, softer film-like colors, classic 90s eye design, "
        "less glossy rendering"
    ),
    "80s_anime": (
        "1980s anime aesthetic, bold cel shading, vintage palette, sharper facial structure, "
        "classic hand-drawn anime look"
    ),
    "early_2000s_anime": (
        "early 2000s anime look, lighter digital coloring, classic TV anime rendering, "
        "simpler highlights, less modern polish"
    ),
    "retro_ova": (
        "retro OVA anime frame, cinematic cel shading, painted background feel, "
        "nostalgic composition"
    ),
    "shojo_90s": (
        "1990s shojo anime style, elegant large eyes, delicate linework, pastel color palette, "
        "romantic vintage anime feel"
    ),
    "grainy_vhs_anime": (
        "retro anime VHS look, visible film grain, analog softness, faded colors, "
        "nostalgic tape-era anime frame"
    ),
    "cel_shaded_classic": (
        "classic anime cel shading, flat shadow layers, hand-drawn look, "
        "bold outlines, traditional animation feel"
    ),
}

STYLE_QUALITY_SUFFIX = {
    "modern_anime": (
        "high quality anime character portrait, crisp clean line art, "
        "detailed modern anime shading, single character focus"
    ),
    "90s_anime": (
        "high quality retro anime portrait, cel shading, thicker outlines, "
        "softer vintage anime colors, single character focus"
    ),
    "80s_anime": (
        "high quality vintage anime portrait, bold cel shading, "
        "classic hand-drawn look, single character focus"
    ),
    "early_2000s_anime": (
        "high quality early 2000s anime portrait, flatter digital shading, "
        "classic TV anime feel, single character focus"
    ),
    "retro_ova": (
        "high quality retro OVA anime frame, cinematic cel shading, "
        "painted anime feel, single character focus"
    ),
    "shojo_90s": (
        "high quality 90s shojo anime portrait, elegant eyes, pastel palette, "
        "delicate linework, single character focus"
    ),
    "grainy_vhs_anime": (
        "high quality retro VHS anime frame, analog softness, faded colors, "
        "film grain feel, single character focus"
    ),
    "cel_shaded_classic": (
        "high quality classic cel-shaded anime portrait, flat shadows, "
        "bold outlines, single character focus"
    ),
}


class CharacterGenerationService:
    def __init__(self) -> None:
        self.client = OpenAI(api_key=os.getenv("OPENAI_API_KEY"))
        self.output_dir = Path("generated_characters")
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def _get_art_style(self, payload: CharacterGenerateRequest) -> str:
        art_style = getattr(payload, "art_style", None) or getattr(payload, "artStyle", None)
        return str(art_style or "modern_anime").strip()

    def _build_prompt(self, payload: CharacterGenerateRequest) -> str:
        art_style = self._get_art_style(payload)
        art_hint = ART_STYLE_HINTS.get(art_style, ART_STYLE_HINTS["modern_anime"])
        quality_suffix = STYLE_QUALITY_SUFFIX.get(
            art_style,
            STYLE_QUALITY_SUFFIX["modern_anime"],
        )

        sections = [
            "Create a single anime character illustration.",
            f"Theme preference: {payload.style}",
            f"Art style preference: {art_style}",
            f"Style direction: {art_hint}",
            "Character details:",
            f"- Gender: {payload.gender}",
            f"- Hair: {payload.hair}",
            f"- Eyes: {payload.eyes}",
            f"- Outfit: {payload.outfit}",
            f"- Mood: {payload.mood}",
            "User request:",
            payload.prompt.strip(),
            "Important rules:",
            f"- The final result must clearly reflect the requested art style: {art_style}.",
            "- Respect the user's selected style preference rather than defaulting to a generic anime look.",
            "- Use era-accurate linework, eye shape, shading, palette, and composition.",
            "- Keep a single character focus.",
            quality_suffix,
        ]

        if art_style == "90s_anime":
            sections.extend(
                [
                    "Strong 90s anime requirements:",
                    "- use cel shading",
                    "- use thicker black outlines",
                    "- use softer analog-era color treatment",
                    "- use retro OVA-inspired face and eye design",
                    "- avoid glossy modern rendering",
                    "- avoid hyper-detailed digital airbrushing",
                    "- avoid gacha-style modern character rendering",
                ]
            )
        elif art_style == "80s_anime":
            sections.extend(
                [
                    "Strong 80s anime requirements:",
                    "- use bold cel shading",
                    "- use vintage anime proportions",
                    "- use sharper facial structure",
                    "- avoid modern glossy rendering",
                ]
            )
        elif art_style == "early_2000s_anime":
            sections.extend(
                [
                    "Strong early 2000s anime requirements:",
                    "- use flatter digital shading",
                    "- use simpler highlight treatment",
                    "- avoid ultra-modern cinematic rendering",
                ]
            )
        elif art_style == "grainy_vhs_anime":
            sections.extend(
                [
                    "Strong VHS anime requirements:",
                    "- include analog softness",
                    "- include faded colors",
                    "- include subtle film grain aesthetic",
                    "- avoid ultra-clean digital sharpness",
                ]
            )

        return "\n".join(part for part in sections if part)

    def _build_lore_prompt(self, payload: CharacterGenerateRequest) -> str:
        art_style = self._get_art_style(payload)

        return f"""
Create an original anime character profile based on the following traits.

User prompt: {payload.prompt}
Theme preference: {payload.style}
Art style preference: {art_style}
Gender: {payload.gender}
Hair: {payload.hair}
Eyes: {payload.eyes}
Outfit: {payload.outfit}
Mood: {payload.mood}

Return:
1. a character name
2. a backstory between 80 and 140 words
3. a short story scene between 120 and 180 words

Requirements:
- make it original
- make it anime-inspired
- match the selected theme and art style preference
- style is based on the user's selected preference, not a default
- do not reference copyrighted characters or franchises
- keep it vivid and readable
""".strip()

    def _generate_lore(self, payload: CharacterGenerateRequest) -> dict:
        prompt = self._build_lore_prompt(payload)
        logger.info(
            "Starting lore generation for prompt=%s style=%s art_style=%s",
            payload.prompt,
            payload.style,
            self._get_art_style(payload),
        )

        response = self.client.responses.create(
            model="gpt-4.1-mini",
            input=prompt,
            text={
                "format": {
                    "type": "json_schema",
                    "name": "character_lore",
                    "schema": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string"},
                            "backstory": {"type": "string"},
                            "story_scene": {"type": "string"},
                        },
                        "required": ["name", "backstory", "story_scene"],
                        "additionalProperties": False,
                    },
                    "strict": True,
                }
            },
        )

        logger.info("Lore raw output_text: %s", response.output_text)
        lore = json.loads(response.output_text)
        logger.info("Lore parsed successfully: %s", lore)
        return lore

    def _save_base64_image(self, image_b64: str) -> str:
        filename = f"{uuid.uuid4().hex}.png"
        file_path = self.output_dir / filename

        with open(file_path, "wb") as f:
            f.write(base64.b64decode(image_b64))

        logger.info("Saved character image to %s", file_path)
        return f"/generated_characters/{filename}"

    async def generate(self, payload: CharacterGenerateRequest) -> dict:
        art_style = self._get_art_style(payload)
        final_prompt = self._build_prompt(payload)

        logger.info(
            "Starting image generation with style=%s art_style=%s final_prompt=%s",
            payload.style,
            art_style,
            final_prompt,
        )

        result = self.client.images.generate(
            model="gpt-image-1",
            prompt=final_prompt,
            size="1024x1024",
            quality="high",
        )

        image_b64 = result.data[0].b64_json
        image_url = self._save_base64_image(image_b64)

        try:
            lore = self._generate_lore(payload)
        except Exception as e:
            logger.exception("Lore generation failed: %s", e)
            lore = {
                "name": None,
                "backstory": None,
                "story_scene": None,
            }

        response_data = {
            "prompt": payload.prompt,
            "style": payload.style,
            "art_style": art_style,
            "gender": payload.gender,
            "hair": payload.hair,
            "eyes": payload.eyes,
            "outfit": payload.outfit,
            "mood": payload.mood,
            "image_url": image_url,
            "is_favorite": False,
            "name": lore.get("name"),
            "backstory": lore.get("backstory"),
            "story_scene": lore.get("story_scene"),
        }

        logger.info("Final generated character payload: %s", response_data)
        return response_data