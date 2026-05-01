from pymilvus import connections, Collection

connections.connect(
    host="127.0.0.1",
    port="19530"
)

COLLECTION = "frame_color_layout"
PARTITION = "p00"   # load ONE partition only

col = Collection(COLLECTION)

print(f"Loading partition {PARTITION}...")
col.load(partition_names=[PARTITION])
print("Load request sent.")

print("Current load state:", col.get_load_state())

