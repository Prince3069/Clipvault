// lib/middleware.js
const admin = require("firebase-admin");

/**
 * Verifies the Firebase Auth ID token sent as "Authorization: Bearer <token>".
 * The Flutter client already does this — AIService._getIdToken() — for
 * every call, so this just has to actually check it server-side. Skipping
 * this check is what would let anyone call your paid AI endpoints for free
 * with a captured/forged request.
 */
async function requireAuth(req, res, next) {
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : null;
  if (!token) {
    return res.status(401).json({error: "Missing Authorization header"});
  }
  try {
    req.user = await admin.auth().verifyIdToken(token);
    next();
  } catch (e) {
    console.error("Auth verify failed:", e.message);
    return res.status(401).json({error: "Invalid or expired auth token"});
  }
}

/**
 * Reads the SAME field PremiumProvider.grantPremium() writes via
 * CloudVaultService.updatePremiumExpiry() — users/{uid}.premiumExpiry — so
 * this is guaranteed to agree with what the app itself considers premium.
 * Attaches req.isPremium (bool) either way; use requirePremium() below to
 * hard-block non-premium requests, or just read req.isPremium for
 * different free/premium behavior in the same endpoint (e.g. translate).
 */
async function attachPremiumStatus(req, res, next) {
  try {
    const db = admin.firestore();
    const doc = await db.collection("users").doc(req.user.uid).get();
    const expiry = doc.data()?.premiumExpiry;
    req.isPremium = !!(expiry && expiry.toDate().getTime() > Date.now());
    next();
  } catch (e) {
    console.error("Premium status check failed:", e.message);
    req.isPremium = false;
    next();
  }
}

/** Hard-blocks the request unless the user is premium. */
function requirePremium(req, res, next) {
  if (!req.isPremium) {
    return res.status(403).json({error: "Premium subscription required"});
  }
  next();
}

/**
 * Simple per-user, per-feature, per-day credit counter stored in Firestore
 * at users/{uid}/aiCredits/{feature}_{yyyy-mm-dd}. Returns true and
 * consumes one credit if the user is under their daily limit, false if
 * they've hit it. This is what actually protects your API budget — without
 * it, a single user (or a script hitting your endpoint directly) could run
 * unlimited paid AI calls on your dime.
 */
async function checkAndConsumeCredit(uid, feature, dailyLimit) {
  const db = admin.firestore();
  const today = new Date().toISOString().slice(0, 10);
  const ref = db.collection("users").doc(uid).collection("aiCredits").doc(`${feature}_${today}`);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const used = snap.exists ? snap.data().count || 0 : 0;
    if (used >= dailyLimit) return false;
    tx.set(
        ref,
        {
          count: used + 1,
          feature,
          date: today,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
    );
    return true;
  });
}

/**
 * Same idea as checkAndConsumeCredit, but the period key is {yyyy-mm}
 * instead of {yyyy-mm-dd} — for limits like "1 free translation, then
 * wait until next month," where a daily reset would give far more free
 * usage than intended.
 */
async function checkAndConsumeMonthlyCredit(uid, feature, monthlyLimit) {
  const db = admin.firestore();
  const month = new Date().toISOString().slice(0, 7); // "2026-09"
  const ref = db.collection("users").doc(uid).collection("aiCredits").doc(`${feature}_${month}`);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const used = snap.exists ? snap.data().count || 0 : 0;
    if (used >= monthlyLimit) return false;
    tx.set(
        ref,
        {
          count: used + 1,
          feature,
          month,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        {merge: true},
    );
    return true;
  });
}

module.exports = {
  requireAuth,
  attachPremiumStatus,
  requirePremium,
  checkAndConsumeCredit,
  checkAndConsumeMonthlyCredit,
};