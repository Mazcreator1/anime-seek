import os
import subprocess
import json
from pydub import AudioSegment

# Path to your fpcalc (it must be installed and on PATH)
FPCALC_COMMAND = "fpcalc"

# Folder where your test WAV files are located
TEST_FOLDER = "test_audio"

# Helper: generate fingerprint
def generate_fingerprint(file_path):
    try:
        result = subprocess.run([FPCALC_COMMAND, "-json", file_path], capture_output=True, text=True)
        if result.returncode != 0:
            raise Exception(f"fpcalc failed for {file_path}")

        data = json.loads(result.stdout)
        fingerprint = list(map(int, data["fingerprint"]))
        duration = data["duration"]
        return fingerprint, duration
    except Exception as e:
        print(f"Error generating fingerprint for {file_path}: {e}")
        return None, None

# Helper: sliding window matching
def sliding_window_match(uploaded_fp_list, stored_fp_list):
    best_score = 0
    len_uploaded = len(uploaded_fp_list)

    for i in range(len(stored_fp_list) - len_uploaded + 1):
        window = stored_fp_list[i:i + len_uploaded]
        score = sum(1 for a, b in zip(uploaded_fp_list, window) if a == b)
        if score > best_score:
            best_score = score

    match_score_normalized = best_score / len_uploaded if len_uploaded > 0 else 0
    return match_score_normalized

# Test two files
def compare_audio(file1, file2):
    fp1, dur1 = generate_fingerprint(file1)
    fp2, dur2 = generate_fingerprint(file2)

    if fp1 is None or fp2 is None:
        print("Failed to fingerprint one or both files.")
        return

    print(f"Comparing {file1} (duration {dur1}s) to {file2} (duration {dur2}s)")

    score = sliding_window_match(fp1, fp2)
    print(f"Match score: {score:.3f}")

if __name__ == "__main__":
    # Example usage
    file_a = os.path.join(TEST_FOLDER, "Clip.wav")    # Your recorded snippet
    file_b = os.path.join(TEST_FOLDER, "Vinland Saga Opening 1 (1080p).wav")     # Full anime OP

    compare_audio(file_a, file_b)
