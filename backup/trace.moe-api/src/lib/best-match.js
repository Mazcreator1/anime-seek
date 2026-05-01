export function bestMatch(payload) {
  const pick = (item) => {
    if (!item || typeof item !== "object") return null;
    let aid = item.anilist?.id ?? item.anilist ?? item.anilist_id ?? item.aniListId ?? item.anilistID;
    if (typeof aid === "string") { const n = parseInt(aid, 10); if (!Number.isNaN(n)) aid = n; }
    let sim = item.similarity ?? item.confidence ?? item.accuracy;
    if (sim != null && sim <= 1) sim = sim * 100; // 0..1 -> 0..100
    const ep = item.episode ?? item.ep;
    return aid ? { sim: sim ?? -1, id: Number(aid), ep: ep != null ? String(ep) : null } : null;
  };

  const arr = Array.isArray(payload) ? payload
            : Array.isArray(payload?.result) ? payload.result
            : Array.isArray(payload?.results) ? payload.results
            : Array.isArray(payload?.docs) ? payload.docs
            : Array.isArray(payload?.matches) ? payload.matches
            : [payload];

  const cands = (arr || []).map(pick).filter(Boolean);
  if (!cands.length) return { id: null, acc: null, ep: null };
  const best = cands.reduce((a, b) => (a.sim >= b.sim ? a : b));
  return { id: best.id, acc: best.sim >= 0 ? Math.round(best.sim * 100) / 100 : null, ep: best.ep };
}
