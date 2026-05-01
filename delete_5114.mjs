import { MilvusClient } from "@zilliz/milvus2-sdk-node";

const client = new MilvusClient({
  address: "milvus:19530",
  token: "root:Milvus",
});

const res = await client.delete({
  collection_name: "frame_color_layout",
  filter: "anilist_id == 5114",
});

console.log(JSON.stringify(res, null, 2));
