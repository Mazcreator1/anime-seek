# save as dump_hashes.py
import psycopg2
from pathlib import Path
import shutil

OUT = Path("/home/ubuntu/hash")  # mounted to /app/hash
PG  = dict(host="127.0.0.1", port=5433, user="postgres", password="postgres", dbname="postgres")

con = psycopg2.connect(**PG)
cur = con.cursor(name="c")       # server-side cursor to stream results
cur.itersize = 2000

cur.execute("""
  SELECT
    f.id,
    f.path,                                 -- e.g. 9999/[Opfans...]Movie11.mp4
    regexp_replace(f.path, '.*/', '') AS base,
    fcl.color_layout                        -- zstd-compressed JSON payload
  FROM files f
  JOIN files_color_layout fcl ON f.id = fcl.id
  ORDER BY f.id
""")

moved = wrote = skipped = 0

for fid, path, base, blob in cur:
    # new expected target: /home/ubuntu/hash/<path>.json.zst
    dst = (OUT / path).with_suffix( Path(path).suffix + ".json.zst" )
    dst.parent.mkdir(parents=True, exist_ok=True)

    if dst.exists():
        skipped += 1
        continue

    # old location (if you previously wrote by <id>/<basename>.json.zst)
    legacy = OUT / str(fid) / f"{base}.json.zst"
    if legacy.exists():
        shutil.move(str(legacy), str(dst))
        moved += 1
        continue

    # otherwise write from DB (already zstd-compressed)
    dst.write_bytes(blob)
    wrote += 1

con.close()
print(f"done: moved={moved} wrote={wrote} skipped={skipped}")
