// app.js
import { performance } from "node:perf_hooks";
import express from "express";
import cors from "cors";
import multer from "multer";

import { createPool } from "mysql2/promise";
import { createClient } from "redis";

import getMe from "./get-me.js";
import getStatus from "./get-status.js";
import getStats from "./get-stats.js";
import search from "./search.js";
import scan from "./scan.js";
import video from "./video.js";
import image from "./image.js";
import github from "./webhook/github.js";
import patreon from "./webhook/patreon.js";
import create from "./user/create.js";
import login from "./user/login.js";
import resetKey from "./user/reset-key.js";
import resetPassword from "./user/reset-password.js";
import rss from "./rss.js";

// ─── DB + Redis ──────────────────────────────────────────────
const pool = createPool({
  host: process.env.DB_HOST,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
  connectionLimit: 10,
});

const redis = createClient({
  url: process.env.REDIS_URL || "redis://127.0.0.1:6379",
});
await redis.connect();

// ─── Tier Helpers ───────────────────────────────────────────
const todayKey = () => new Date().toISOString().slice(0, 10); // YYYY-MM-DD
const keyFromReq = (req) =>
  req.headers["x-api-key"] || req.user?.api_key || req.ip;

async function fetchTierByApiKey(apiKey) {
  const cacheKey = `tier:${apiKey}`;
  const cached = await redis.get(cacheKey);
  if (cached) return JSON.parse(cached);

  const [rows] = await pool.query(
    `SELECT t.id AS tierId, t.quota, t.concurrency, t.notes
       FROM user u JOIN anime_tiers t ON t.id = u.anime_tier_id
      WHERE u.api_key = ? LIMIT 1`,
    [apiKey],
  );
  const r = rows?.[0];
  if (!r) return null;

  const info = {
    tierId: r.tierId,
    quota: Number(r.quota),
    concurrency: Number(r.concurrency),
    notes: r.notes,
  };
  await redis.set(cacheKey, JSON.stringify(info), { EX: 300 });
  return info;
}

async function acquireConcurrency(key, max) {
  if (max <= 0 || !Number.isFinite(max)) max = 1;
  const semKey = `sem:${key}`;
  const cur = await redis.incr(semKey);
  if (cur === 1) await redis.expire(semKey, 120);
  if (cur > max) {
    await redis.decr(semKey);
    const err = new Error("Too many concurrent requests");
    err.status = 429;
    throw err;
  }
  return async () => {
    try {
      await redis.decr(semKey);
    } catch {}
  };
}

// ─── Middleware: Tiered limiter ─────────────────────────────
async function tierLimiter(req, res, next) {
  const apiKey = keyFromReq(req);
  console.log("API key from request:", apiKey); // Debug log 

  const tier = await fetchTierByApiKey(apiKey);
  if (!tier) {
    console.warn(" Invalid or missing API key:", apiKey); 
    return res.status(401).json({ error: "Invalid API key" });
  }

  const unlimited =
    tier.tierId === 3 || tier.quota >= 4_294_967_295; // Kami-sama

  let release = async () => {};
  try {
    release = await acquireConcurrency(`conc:${apiKey}`, tier.concurrency || 1);
  } catch (e) {
    return res.status(e.status || 429).json({ error: e.message });
  }

  if (!unlimited) {
    const k = `quota:${apiKey}:${todayKey()}`;
    let used = await redis.get(k);
    let n = used ? parseInt(used, 10) : 0;
    if (n >= tier.quota) {
      await release();
      return res.status(429).json({
        error: `Quota exceeded for your tier (${tier.notes}).`,
        remaining_searches: 0,
        tier: tier.notes,
      });
    }
    await redis.incr(k);
    if (!used) {
      const midnight = new Date();
      midnight.setUTCHours(24, 0, 0, 0);
      const ex =
        Math.max(
          3600,
          Math.floor((midnight.getTime() - Date.now()) / 1000) + 3600,
        );
      await redis.expire(k, ex);
    }
    res.locals.remaining_searches = Math.max(0, tier.quota - (n + 1));
    res.locals.tier_notes = tier.notes;
  } else {
    res.locals.remaining_searches = null;
    res.locals.tier_notes = tier.notes;
  }

  res.on("finish", release);
  res.on("close", release);
  next();
}

// ─── Express App ───────────────────────────────────────────
const app = express();
app.disable("x-powered-by");
app.set("trust proxy", 2);

// CORS + headers (now includes x-api-key)
app.use((req, res, next) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.set(
    "Access-Control-Allow-Headers",
    "Content-Type, x-trace-secret, x-api-key",
  );
  next();
});

app.use((req, res, next) => {
  const startTime = performance.now();
  console.log("=>", new Date().toISOString(), req.ip, req.path);
  res.on("finish", () => {
    console.log(
      "<=",
      new Date().toISOString(),
      req.ip,
      req.path,
      res.statusCode,
      `${(performance.now() - startTime).toFixed(0)}ms`,
    );
  });
  next();
});

app.use(cors({ credentials: true, origin: true }));
app.use(
  express.raw({
    type: [
      "application/octet-stream",
      "application/x-www-form-urlencoded",
      "image/*",
      "video/*",
    ],
    limit: 25 * 1024 * 1024,
    verify: (req, res, buf) => {
      req.rawBody = buf;
    },
  }),
);
app.use(express.urlencoded({ extended: false }));
app.use(
  express.json({
    verify: (req, res, buf) => {
      req.rawBody = buf;
    },
  }),
);

// ─── Routes ────────────────────────────────────────────────
app.get("/me", getMe);
app.get("/status", getStatus);
app.get("/stats", getStats);
app.get("/scan", scan);
app.all("/webhook/github", github);
app.all("/webhook/patreon", patreon);

app.all(
  "/search",
  tierLimiter,
  multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 25 * 1024 * 1024 },
  }).any(),
  (req, res, next) => {
    res.setHeader("X-Tier", res.locals.tier_notes ?? "");
    if (res.locals.remaining_searches !== null) {
      res.setHeader(
        "X-Remaining-Searches",
        String(res.locals.remaining_searches),
      );
    }
    return search(req, res, next);
  },
);

app.get("/video/:anilistID/:filename", video);
app.get("/image/:anilistID/:filename", image);
app.all("/user/login", login);
app.all("/user/create", create);
app.all("/user/reset-key", resetKey);
app.all("/user/reset-password", resetPassword);
app.all("/rss.xml", rss);
app.all("/", async (req, res) => {
  res.send("ok");
});

export default app;