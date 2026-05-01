from fastapi import APIRouter, Query
import pymysql
from fastapi.responses import JSONResponse
from typing import Optional

search_router = APIRouter()

def get_db_connection():
    return pymysql.connect(
        host="54.204.150.214",
        user="animeseeker",
        password=r9G$7nL^w2X#qPzV8bM!kT3,
        database="dejavu",
        cursorclass=pymysql.cursors.DictCursor
    )

@search_router.get("/songs/search")
async def search_songs(query: str = Query(..., min_length=1)):
    try:
        connection = get_db_connection()
        with connection.cursor() as cursor:
            sql = """
                SELECT name, duration, author, streaming_service, audio_url
                FROM songs
                WHERE name LIKE %s OR author LIKE %s
                LIMIT 20
            """
            wildcard_query = f"%{query}%"
            cursor.execute(sql, (wildcard_query, wildcard_query))
            results = cursor.fetchall()
        connection.close()
        return {"results": results}
    except Exception as e:
        return JSONResponse(status_code=500, content={"error": str(e)})
