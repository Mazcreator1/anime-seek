from fastapi import FastAPI, UploadFile, File
from fastapi.responses import JSONResponse
from fastapi.middleware.cors import CORSMiddleware
import os, json, shutil, subprocess
from pydub import AudioSegment
import mysql.connector

# Initialize FastAPI app
app = FastAPI()

# CORS Configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Allow all origins for development
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

UPLOAD_FOLDER = "uploads"
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

# DB Config
db_config = {
    "host": "localhost",
    "user": "root",
    "password": "K1sPlc?EphAfrumonotLswLF2FrutroRatH!s4bU$",  # Update your DB password here
    "database": "anime_recognition_db"
}

@app.post("/recognize")
async def recognize_audio(file: UploadFile = File(...)):
    file_location = os.path.join(UPLOAD_FOLDER, file.filename)

    try:
        # Save the uploaded file to disk
        with open(file_location, "wb") as f:
            shutil.copyfileobj(file.file, f)

        # Convert to WAV if needed (since fpcalc works with WAV files)
        if not file.filename.endswith(".wav"):
            sound = AudioSegment.from_file(file_location)
            file_location_wav = file_location + ".wav"
            sound.export(file_location_wav, format="wav")
            os.remove(file_location)
            file_location = file_location_wav

        # Get the fingerprint using fpcalc
        fingerprint, duration = generate_fingerprint(file_location)
        if not fingerprint:
            return JSONResponse(status_code=500, content={"error": "Failed to generate fingerprint"})

        # Clean up the temporary WAV file
        os.remove(file_location)

        # Connect to DB and fetch stored fingerprints
        connection = mysql.connector.connect(**db_config)
        cursor = connection.cursor(dictionary=True)

        cursor.execute("SELECT anime_title, fingerprint, duration FROM metadata")
        records = cursor.fetchall()

        if not records:
            return JSONResponse(status_code=404, content={"error": "No fingerprints found in database"})

        # Match the uploaded fingerprint with stored fingerprints
        best_match = None
        max_match_score = 0

        for record in records:
            stored_fp = record["fingerprint"]
            match_score = calculate_match_score(fingerprint, stored_fp)

            if match_score > max_match_score:
                max_match_score = match_score
                best_match = record

        if best_match and max_match_score > 0.8:  # Match threshold (adjust as needed)
            return JSONResponse(content={
                "anime_title": best_match["anime_title"],
                "confidence": max_match_score,
                "match_duration": best_match["duration"],
                "uploaded_duration": duration
            })
        else:
            return JSONResponse(status_code=404, content={"error": "No good match found"})

    except Exception as e:
        return JSONResponse(status_code=500, content={"error": str(e)})

    finally:
        # Ensure the cursor and DB connection are closed
        if 'cursor' in locals() and cursor:
            cursor.close()
        if 'connection' in locals() and connection and connection.is_connected():
            connection.close()


def generate_fingerprint(file_path: str):
    try:
        # Run fpcalc to generate the fingerprint for the audio file
        result = subprocess.run(["fpcalc", "-json", file_path], capture_output=True, text=True)

        if result.returncode != 0:
            return None, None

        data = json.loads(result.stdout)
        fingerprint = ",".join(map(str, data["fingerprint"]))
        duration = data["duration"]
        return fingerprint, duration
    except Exception as e:
        print(f"Error generating fingerprint: {e}")
        return None, None


def calculate_match_score(uploaded_fp: str, stored_fp: str):
    # Split the fingerprints into lists of integers
    uploaded_fp_list = list(map(int, uploaded_fp.split(",")))
    stored_fp_list = list(map(int, stored_fp.split(",")))

    # Use a simple match score based on common prefix length or exact match count
    match_score = sum(1 for a, b in zip(uploaded_fp_list, stored_fp_list) if a == b)
    return match_score
