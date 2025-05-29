import mysql.connector

db_config = {
    "host": "localhost",
    "user": "root",
    "password": "K1sPlc?EphAfrumonotLswLF2FrutroRatH!s4bU$",
    "database": "anime_recognition_db"
}

conn = mysql.connector.connect(**db_config)
cursor = conn.cursor()
cursor.execute("SELECT * FROM metadata")
rows = cursor.fetchall()
print(rows)
cursor.close()
conn.close()