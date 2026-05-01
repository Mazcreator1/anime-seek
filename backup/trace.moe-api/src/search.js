// search.js
import crypto from "node:crypto";
import os from "node:os";
import path from "node:path";
import child_process from "node:child_process";
import fs from "fs/promises";
import aniep from "aniep";
import cv from "@soruly/opencv4nodejs-prebuilt";
import { performance } from "node:perf_hooks";

const {
  TRACE_API_SALT,
  TRACE_ACCURACY = 1,
  SEARCH_QUEUE = Infinity,
} = process.env;

const FAST_CANDIDATES = 1_000_000;
const FULL_CANDIDATES = 2_000_000;
const CONFIDENCE_THRESHOLD = 0.85;

// Inline replacement for getSolrCoreList()
function getSolrCoreList() {
  const raw = (process.env.SOLA_SOLR_LIST || "").trim();
  const coreName = (process.env.LIRE_CORE || "").trim(); // optional: set this if SOLA_SOLR_LIST has only /solr base
  let bases = raw
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
    .map((s) => s.replace(/\/+$/, "")); // strip trailing slashes

  if (bases.length === 0) bases = ["http://liresolr:8983/solr"];

  // If a base ends at “…/solr” and a core name is provided, append it → “…/solr/<core>”
  return bases.map((b) =>
    /\/solr\/[^/]+$/.test(b) || !coreName ? b : `${b}/${coreName}`,
  );
}

// ---- SOLR search helper ------------------------------------------------------
const solrSearch = (image, candidates, anilistID) =>
  Promise.all(
    getSolrCoreList().map((coreURL) =>
      fetch(
        `${coreURL}/lireq?${[
          "field=cl_ha",
          "ms=false",
          `accuracy=${TRACE_ACCURACY}`,
          `candidates=${candidates}`,
          "rows=30",
          anilistID ? `fq=id:${anilistID}/*` : "",
        ].join("&")}`,
        { method: "POST", body: image },
      ),
    ),
  );

// ---- Logging (writes api_key to `logs`) --------------------------------------
async function logWithApiKey(locals, { req, uid, apiKey, status, searchTime = -1, accuracy = -1 }) {
  const knex = locals.knex;

  // increment search_count on success
  if (status === 200) {
    while (locals.mut) await new Promise((r) => setTimeout(r, 0));
    locals.mut = true;
    try {
      const row = await knex("search_count").where({ uid: String(uid) }).first();
      if (row) {
        await knex("search_count").update({ count: row.count + 1 }).where({ uid: String(uid) });
      } else {
        await knex("search_count").insert({ uid: String(uid), count: 1 });
      }
    } finally {
      locals.mut = false;
    }
  }

  const base = {
    time: knex.fn.now(),
    uid: String(uid),
    ip: req.ip,
    status,
    search_type: "scene",
  };
  if (apiKey) base.api_key = apiKey;
  if (searchTime >= 0) base.search_time = searchTime;
  if (accuracy >= 0) base.accuracy = accuracy;

  try {
    await knex("logs").insert(base);
  } catch {
    // fallback for legacy table name
    await knex("log").insert(base);
  }
}

// ---- Image utils -------------------------------------------------------------
const resizeImageForSearch = (sourceImage) => {
  let image = null;
  try {
    image = cv.imdecode(sourceImage);
  } catch {}
  if (!image) return false;

  let [height, width] = image.sizes;
  if (width <= 320 && height <= 320) {
    try {
      return cv.imencode(".jpg", image);
    } catch {
      return false;
    }
  }
  if (width > height) {
    height = Math.round(320 * (height / width));
    width = 320;
  } else {
    width = Math.round(320 * (width / height));
    height = 320;
  }
  try {
    return cv.imencode(".jpg", image.resize(width, height));
  } catch {
    return false;
  }
};

const extractImageFallback = async (searchFile) => {
  const tempFilePath = path.join(os.tmpdir(), `trace.moe-search-${process.hrtime().join("")}`);
  await fs.writeFile(tempFilePath, searchFile);
  const ffmpeg = child_process.spawnSync("ffmpeg", [
    "-hide_banner",
    "-loglevel",
    "error",
    "-nostats",
    "-y",
    "-i",
    tempFilePath,
    "-ss",
    "00:00:00",
    "-map_metadata",
    "-1",
    "-vf",
    "scale=320:-2",
    "-c:v",
    "mjpeg",
    "-vframes",
    "1",
    "-f",
    "image2pipe",
    "pipe:1",
  ]);
  await fs.rm(tempFilePath, { force: true });
  return ffmpeg;
};

// ---- Main handler ------------------------------------------------------------
export default async (req, res) => {
  const locals = req.app.locals;
  const knex = locals.knex;

  // Identify user for logging + priority
  const apiKey = req.header("x-api-key") || req.query.key || "";
  let uid = req.ip;
  let priority = 0;

  if (apiKey) {
    const row = await knex("user as u")
      .leftJoin("anime_tiers as t", "t.id", "u.anime_tier_id")
      .select("u.id as userId", "t.priority as tierPriority")
      .where("u.api_key", apiKey)
      .first();

    if (!row) {
      await logWithApiKey(locals, { req, uid, apiKey, status: 401 });
      return res.status(401).json({ error: "Invalid API key" });
    }
    uid = row.userId ?? req.ip;
    priority = Number.isFinite(row.tierPriority) ? row.tierPriority : 0;
  }

  // Optional global queue backpressure
  locals.searchQueue[priority] = (locals.searchQueue[priority] ?? 0) + 1;
  const dequeue = () => {
    locals.searchQueue[priority] = Math.max(0, (locals.searchQueue[priority] || 1) - 1);
  };
  const queueSize = locals.searchQueue.reduce(
    (acc, cur, i) => (i >= priority ? acc + cur : acc),
    0,
  );
  if (queueSize > SEARCH_QUEUE) {
    dequeue();
    await logWithApiKey(locals, { req, uid, apiKey, status: 503 });
    return res.status(503).json({ error: "Error: Search queue is full" });
  }

  // Read input
  let searchFile = Buffer.alloc(0);
  if (req.query.url) {
    try {
      new URL(req.query.url);
    } catch {
      dequeue();
      await logWithApiKey(locals, { req, uid, apiKey, status: 400 });
      return res.status(400).json({ error: `Invalid image url ${req.query.url}` });
    }
    const response = await fetch(req.query.url).catch(() => ({ status: 400 }));
    if (response.status >= 400) {
      dequeue();
      await logWithApiKey(locals, { req, uid, apiKey, status: response.status });
      return res.status(response.status).json({ error: `Failed to fetch image ${req.query.url}` });
    }
    searchFile = Buffer.from(await response.arrayBuffer());
  } else if (req.files?.length) {
    searchFile = req.files[0].buffer;
  } else if (req.rawBody?.length) {
    searchFile = req.rawBody;
  } else {
    dequeue();
    await logWithApiKey(locals, { req, uid, apiKey, status: 405 });
    return res.status(405).json({ error: "Method Not Allowed" });
  }

  // Ensure image
  let searchImage = resizeImageForSearch(searchFile);
  if (!searchImage) {
    const ffmpeg = await extractImageFallback(searchFile);
    if (!ffmpeg.stdout.length) {
      dequeue();
      await logWithApiKey(locals, { req, uid, apiKey, status: 400 });
      return res
        .status(400)
        .json({ error: `Failed to process image. ${ffmpeg.stderr.toString()}` });
    }
    searchImage = ffmpeg.stdout;
  }

  // Search pipeline
  const startTime = performance.now();

  // Phase 1
  let solrResponse = await solrSearch(searchImage, FAST_CANDIDATES, Number(req.query.anilistID));
  let solrResults = await Promise.all(solrResponse.map((e) => e.json()));

  let result = [];
  for (const { response } of solrResults) {
    result = result.concat(response.docs);
  }
  result = result
    .reduce((list, { d, id }) => {
      const anilist_id = Number(id.split("/")[0]);
      const filename = id.split("/")[1];
      const t = Number(id.split("/")[2]);
      const i = list.findIndex(
        (e) =>
          e.anilist_id === anilist_id &&
          e.filename === filename &&
          (Math.abs(e.from - t) < 5 || Math.abs(e.to - t) < 5),
      );
      if (i < 0) return list.concat({ anilist_id, filename, t, from: t, to: t, d });
      list[i].from = Math.min(list[i].from, t);
      list[i].to = Math.max(list[i].to, t);
      list[i].d = Math.min(list[i].d, d);
      list[i].t = list[i].d < d ? t : list[i].t;
      return list;
    }, [])
    .sort((a, b) => a.d - b.d)
    .slice(0, 10);

  let bestSim = result.length ? (100 - result[0].d) / 100 : 0;

  // Phase 2 (deep) if needed
  if (bestSim < CONFIDENCE_THRESHOLD) {
    solrResponse = await solrSearch(searchImage, FULL_CANDIDATES, Number(req.query.anilistID));
    solrResults = await Promise.all(solrResponse.map((e) => e.json()));
    result = [];
    for (const { response } of solrResults) {
      result = result.concat(response.docs);
    }
    result = result
      .reduce((list, { d, id }) => {
        const anilist_id = Number(id.split("/")[0]);
        const filename = id.split("/")[1];
        const t = Number(id.split("/")[2]);
        const i = list.findIndex(
          (e) =>
            e.anilist_id === anilist_id &&
            e.filename === filename &&
            (Math.abs(e.from - t) < 5 || Math.abs(e.to - t) < 5),
        );
        if (i < 0) return list.concat({ anilist_id, filename, t, from: t, to: t, d });
        list[i].from = Math.min(list[i].from, t);
        list[i].to = Math.max(list[i].to, t);
        list[i].d = Math.min(list[i].d, d);
        list[i].t = list[i].d < d ? t : list[i].t;
        return list;
      }, [])
      .sort((a, b) => a.d - b.d)
      .slice(0, 10);
  }

  const searchTime = (performance.now() - startTime) | 0;

  // Build response
  const now = ((Date.now() / 1000 / 3600) | 0) * 3600 + 3600;
  const responseData = result.map(({ anilist_id, filename, t, from, to, d }) => {
    const mid = from + (to - from) / 2;
    const token = crypto
      .createHash("sha1")
      .update([anilist_id, filename, mid, now, TRACE_API_SALT].join(""))
      .digest("base64")
      .replace(/[^0-9A-Za-z]/g, "");
    return {
      anilist: anilist_id,
      filename,
      episode: aniep(filename),
      from,
      to,
      similarity: (100 - d) / 100,
      video: `${req.protocol}://${req.get("host")}/video/${anilist_id}/${encodeURIComponent(
        filename,
      )}?t=${mid}&now=${now}&token=${token}`,
      image: `${req.protocol}://${req.get("host")}/image/${anilist_id}/${encodeURIComponent(
        filename,
      )}?t=${mid}&now=${now}&token=${token}`,
    };
  });

  // Dequeue + log with api_key
  dequeue();
  await logWithApiKey(locals, {
    req,
    uid,
    apiKey,
    status: 200,
    searchTime,
    accuracy: responseData[0]?.similarity ?? -1,
  });

  res.json({
    error: "",
    result: responseData,
    took_ms: searchTime,
  });
};
