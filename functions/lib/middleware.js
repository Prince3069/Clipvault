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
/**
 * Checks the monthly allowance WITHOUT spending it. Call this before
 * attempting the AI call. Returns enough state to call
 * consumeMonthlyCredit() afterward — only if the call actually succeeds.
 */
async function hasMonthlyCreditRemaining(uid, feature, monthlyLimit) {
  const db = admin.firestore();
  const month = new Date().toISOString().slice(0, 7); // "2026-09"
  const ref = db.collection("users").doc(uid).collection("aiCredits").doc(`${feature}_${month}`);
  const snap = await ref.get();
  const used = snap.exists ? snap.data().count || 0 : 0;
  return {allowed: used < monthlyLimit, used, ref, month, feature};
}

/**
 * Actually spends one credit — call this ONLY after the AI call succeeded.
 * A failed call (bad response, provider error, timeout) must never cost
 * the person their monthly allowance — that was the bug: the old
 * checkAndConsumeMonthlyCredit spent the credit up front, before knowing
 * whether the call would even work, so a single flaky request could burn
 * someone's one free translation for the month and give them nothing.
 */
async function consumeMonthlyCredit(check) {
  await check.ref.set(
    {
      count: check.used + 1,
      feature: check.feature,
      month: check.month,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
}

/**
 * Checks and consumes the free tier's allowance (once/month) AND, for
 * Pro, a separate generous monthly-included count — for the branding/
 * overlay feature (Quick Edit's replacement). Deliberately NOT the same
 * system as budget.js's AI dollar budget: that system exists to cap real,
 * variable AI provider spend against subscription price. This feature has
 * no such cost — the actual price/text/logo compositing happens entirely
 * on the DEVICE (Canvas), not on this server at all, so there is nothing
 * here to protect a dollar budget from. Routing it through budget.js
 * anyway would risk a real problem: a Pro user who uses this feature
 * heavily could exhaust the SAME pool translateText/Repurpose Studio draw
 * from, starving real AI features to protect a feature that costs nothing.
 * This is its own counter, on purpose.
 *
 * Free tier: 1/month (matches translateText's cadence).
 * Pro tier: BRANDING_INCLUDED_PER_MONTH/month, then falls back to the
 * user's purchased credit-pack balance (via budget.js) same as any other
 * paid usage — Pro doesn't mean unlimited forever, it means a generous
 * included amount, matching what was actually decided.
 */
const BRANDING_FREE_PER_MONTH = 1;
const BRANDING_INCLUDED_PER_MONTH_PRO = 30; // generous — costs ~nothing to grant, since there's no AI spend behind it

async function checkBrandingAllowance(uid, isPremium) {
  if (!isPremium) {
    const check = await hasMonthlyCreditRemaining(uid, "brandOverlay", BRANDING_FREE_PER_MONTH);
    return {allowed: check.allowed, tier: "free", check};
  }
  const check = await hasMonthlyCreditRemaining(uid, "brandOverlayPro", BRANDING_INCLUDED_PER_MONTH_PRO);
  return {allowed: check.allowed, tier: "pro_included", check};
}

module.exports = {
  requireAuth,
  attachPremiumStatus,
  requirePremium,
  checkAndConsumeCredit,
  hasMonthlyCreditRemaining,
  consumeMonthlyCredit,
  checkBrandingAllowance,
  BRANDING_FREE_PER_MONTH,
  BRANDING_INCLUDED_PER_MONTH_PRO,
};