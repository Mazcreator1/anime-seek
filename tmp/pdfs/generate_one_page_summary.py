import hashlib

# Workaround for environments where hashlib.md5 does not accept usedforsecurity=
_orig_md5 = hashlib.md5
def _md5_compat(*args, **kwargs):
    kwargs.pop('usedforsecurity', None)
    return _orig_md5(*args, **kwargs)
hashlib.md5 = _md5_compat

from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, ListFlowable, ListItem
from reportlab.lib.units import inch
from pypdf import PdfReader

out_path = r"output/pdf/anime_finder_one_page_summary.pdf"

doc = SimpleDocTemplate(
    out_path,
    pagesize=letter,
    leftMargin=0.55*inch,
    rightMargin=0.55*inch,
    topMargin=0.45*inch,
    bottomMargin=0.45*inch,
)

styles = getSampleStyleSheet()
styles.add(ParagraphStyle(
    name='TitleTight',
    parent=styles['Title'],
    fontName='Helvetica-Bold',
    fontSize=17,
    leading=19,
    textColor=colors.HexColor('#1f2d3d'),
    spaceAfter=6,
))
styles.add(ParagraphStyle(
    name='H2',
    parent=styles['Heading2'],
    fontName='Helvetica-Bold',
    fontSize=11.5,
    leading=13,
    textColor=colors.HexColor('#0e5a8a'),
    spaceBefore=4,
    spaceAfter=2,
))
styles.add(ParagraphStyle(
    name='Body',
    parent=styles['BodyText'],
    fontName='Helvetica',
    fontSize=9.2,
    leading=11.4,
    textColor=colors.black,
    spaceAfter=2,
))
styles.add(ParagraphStyle(
    name='Small',
    parent=styles['BodyText'],
    fontName='Helvetica',
    fontSize=8.4,
    leading=10,
    textColor=colors.HexColor('#333333'),
    spaceAfter=1,
))

story = []
story.append(Paragraph('Anime Finder App Summary (One Page)', styles['TitleTight']))
story.append(Paragraph('Repo analyzed: Flutter client + FastAPI backend + Docker services', styles['Small']))
story.append(Spacer(1, 4))

story.append(Paragraph('What It Is', styles['H2']))
story.append(Paragraph(
    'Anime Finder (app title shown as <b>Anime Seek</b>) is a cross-platform Flutter app with a FastAPI backend for anime scene and audio recognition, plus account and community features. '
    'The repo includes client code, backend API code, and containerized infrastructure for Solr and MariaDB-backed search.',
    styles['Body']
))

story.append(Paragraph('Who It\'s For', styles['H2']))
story.append(Paragraph(
    'Primary persona: anime fans who want to identify scenes/songs and track/share discoveries in-app. '
    '<b>Explicit product persona documentation: Not found in repo.</b>',
    styles['Body']
))

story.append(Paragraph('What It Does', styles['H2']))
features = [
    'Scene search from gallery image or URL via `/search`, with top matches, similarity scores, and preview clips/images.',
    'Audio fingerprint recognition flow (`/recognize` and `/fingerprint`) with matched anime/song metadata and match history.',
    'User authentication and account flows: register, token login, refresh token handling, verify/reset password, and profile updates.',
    'Social/feed features: global feed, likes, reshares, comments/replies, and profile follow actions.',
    'Favorites and personal history models for anime results and scene logs, persisted locally in app preferences.',
    'Subscription/payment integration signals in code (Stripe key in app, subscription endpoints, webhook module in backend).',
    'Optional market/wallet screens and services (`/markets`, `/me/wallet`) present in codebase.',
]
story.append(ListFlowable(
    [ListItem(Paragraph(f, styles['Body'])) for f in features],
    bulletType='bullet',
    leftIndent=13,
    bulletFontName='Helvetica',
    bulletFontSize=7,
    bulletOffsetY=2,
))

story.append(Paragraph('How It Works (Repo-Evidenced Architecture)', styles['H2']))
arch_lines = [
    '<b>Client:</b> Flutter app (`lib/`) using Provider state management and Dio/http clients; routes include recognition, feed, profile, notifications, and auth screens.',
    '<b>APIs:</b> App calls `https://anime-seek.com/fastapi` and `https://api.anime-seek.com` endpoints; also queries AniList GraphQL for metadata enrichment.',
    '<b>Backend:</b> FastAPI app (`anime_audio_backend/main.py`) exposes recognition/search/playlist endpoints; uses ffmpeg + Dejavu/PyDejavu for audio processing/fingerprints.',
    '<b>Data:</b> SQLAlchemy + PyMySQL models/sessions (`database.py`, `models.py`) with MariaDB/MySQL tables for users, playlists, songs, and anime metadata.',
    '<b>Infra:</b> `Docker-compose.yaml` defines services for web/api, FastAPI, MariaDB, LIRE Solr, and static UI on a shared bridge network.',
    '<b>Flow:</b> User submits media in app -> API search/recognize -> metadata enrichment/cache (AniList + local DB) -> results returned to client and optionally persisted.',
]
for line in arch_lines:
    story.append(Paragraph(line, styles['Small']))

story.append(Paragraph('How To Run (Minimal Getting Started)', styles['H2']))
run_steps = [
    'Create and populate `.env` for compose variables (template file for required keys: <b>Not found in repo</b>).',
    'Start backend stack from repo root: <b>`docker compose -f Docker-compose.yaml up --build`</b>.',
    'Install Flutter deps: <b>`flutter pub get`</b>.',
    'Run client: <b>`flutter run`</b> (or platform-specific target).',
    'If running backend without Docker, use `anime_audio_backend/requirements.txt`; exact non-Docker startup procedure: <b>Not found in repo</b>.',
]
story.append(ListFlowable(
    [ListItem(Paragraph(s, styles['Body'])) for s in run_steps],
    bulletType='1',
    start='1',
    leftIndent=13,
))

doc.build(story)

reader = PdfReader(out_path)
if len(reader.pages) != 1:
    raise SystemExit(f"Generated PDF has {len(reader.pages)} pages; expected 1 page.")

print(out_path)
