import pymysql
from typing import Optional

# — adjust these to match your DATABASE_CONFIG in server.py —
DB_HOST = "localhost"
DB_USER = "root"
DB_PASS = "K1sPlc?EphAfrumonotLswLF2FrutroRatH!s4bU$"
DB_NAME = "dejavu"

def main():
    conn = pymysql.connect(
        host=DB_HOST,
        user=DB_USER,
        password=DB_PASS,
        database=DB_NAME,
        cursorclass=pymysql.cursors.DictCursor
    )
    try:
        with conn.cursor() as c:
            # show every song_name alongside its anime_title
            c.execute("SELECT song_name, anime_title FROM songs")
            rows = c.fetchall()
            print(f"{'song_name':40s} | anime_title")
            print("-"*80)
            for r in rows:
                print(f"{r['song_name']!r:40s} | {r['anime_title']!r}")

            # also show just the ones missing anime_title
            print("\n-- Missing anime_title --")
            c.execute("SELECT song_name FROM songs WHERE anime_title IS NULL OR anime_title = ''")
            for r in c.fetchall():
                print("   ", r["song_name"])
    finally:
        conn.close()

if __name__ == "__main__":
    main()