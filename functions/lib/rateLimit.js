// lib/rateLimit.js
// Per-user rate limiting for the paid AI endpoints.
//
// Every paid endpoint currently has a budget cap, but nothing stops a
// single client from hammering the endpoint with rapid-fire requests.
// Each individual request still has to fit under the budget, so money
// can't disappear in one shot — but the app can still degrade for
// everyone (Firestore contention, OpenAI rate limits, Cloud Function
// concurrency) while one script spams.
//
// Token bucket per (uid, feature): the bucket starts full, refills at a
// fixed rate, and each request costs one token. If the bucket is empty,
// the request is rejected with 429. Stored in Firestore so the count is
// consistent across Cloud Function instances (an in-memory counter would
// only limit within a single warm instance — useless against a script).

const admin = require("firebase-admin");

// Conservative defaults. Each feature gets its own bucket because they
// cost different amounts and have different typical cadences — e.g.
// a translate request every few seconds is normal; 10 repurpose actions
// a minute is not.
const BUCKETS = {
  translateText: { capacity: 20, refillPerSecond: 0.2 },   // ~12/min sustained
  processRepurposeAction: { capacity: 10, refillPerSecond: 0.1 }, // ~6/min sustained
  processRepurposeVariants: { capacity: 10, refillPerSecond: 0.1 },
  detectLanguage: { capacity: 30, refillPerSecond: 1 },
  getDailyChallenge: { capacity: 10, refillPerSecond: 0.05 },
  analyzeVideo: { capacity: 5, refillPerSecond: 0.05 },
  getCoachIdeas: { capacity: 6, refillPerSecond: 0.02 },
  getCoachPlan: { capacity: 6, refillPerSecond: 0.02 },
};

/**
 * @param {string} uid
 * @param {string} feature  key of BUCKETS
 * @returns {Promise<{allowed: boolean, retryAfterSeconds?: number}>}
 */
async function checkRateLimit(uid, feature) {
  const cfg = BUCKETS[feature];
  if (!cfg) return {allowed: true}; // no bucket defined → unlimited (fail-open)

  const db = admin.firestore();
  const ref = db
    .collection("users").doc(uid)
    .collection("rateLimits").doc(feature);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const now = Date.now();

    let tokens;
    let lastRefill;

    if (!snap.exists) {
      tokens = cfg.capacity;
      lastRefill = now;
    } else {
      const data = snap.data();
      tokens = typeof data.tokens === "number" ? data.tokens : cfg.capacity;
      lastRefill = typeof data.lastRefill === "number" ? data.lastRefill : now;
    }

    // Refill based on elapsed time, capped at capacity.
    const elapsedSeconds = Math.max(0, (now - lastRefill) / 1000);
    tokens = Math.min(cfg.capacity, tokens + elapsedSeconds * cfg.refillPerSecond);

    if (tokens < 1) {
      const shortfall = 1 - tokens;
      const waitSeconds = Math.ceil(shortfall / cfg.refillPerSecond);
      return {allowed: false, retryAfterSeconds: waitSeconds};
    }

    tokens -= 1;
    tx.set(
      ref,
      {
        tokens,
        lastRefill: now,
        feature,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
    return {allowed: true};
  });
}

module.exports = {checkRateLimit, BUCKETS};