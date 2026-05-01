import { MilvusClient } from "@zilliz/milvus2-sdk-node";

async function main() {
  const milvus = new MilvusClient({
    address: process.env.MILVUS_ADDR || "localhost:19530",
    token: process.env.MILVUS_TOKEN || undefined,
  });

  for (let i = 0; i < 32; i++) {
    const partitionName = `p${i.toString().padStart(2, "0")}`;

    try {
      await milvus.createPartition({
        collection_name: "frame_color_layout",
        partition_name: partitionName,
      });

      console.log("created", partitionName);
    } catch (e) {
      console.log("exists or failed", partitionName, e.message);
    }
  }

  await milvus.closeConnection();
}

main().catch(console.error);
