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
 * Owner/producer accounts: always treated as Pro so the people who ship
 * the app can test every Pro feature in the production build. The email
 * must be VERIFIED (Google sign-in always is) — otherwise anyone could
 * register an unverified email/password account with one of these
 * addresses and get Pro for free.
 */
const OWNER_EMAILS = [
  "princenwanozie6666@gmail.com",
  "ifeanyinwanozie6666@gmail.com",
];
const OWNER_GRANT_MS = 10 * 365 * 24 * 60 * 60 * 1000;
const OWNER_RENEW_BELOW_MS = 365 * 24 * 60 * 60 * 1000;

function isOwnerToken(user) {
  if (!user || typeof user.email !== "string") return false;
  if (user.email_verified !== true) return false;
  return OWNER_EMAILS.includes(user.email.trim().toLowerCase());
}

/**
 * Reads the SAME field PremiumProvider.grantPremium() writes via
 * CloudVaultService.updatePremiumExpiry() — users/{uid}.premiumExpiry — so
 * this is guaranteed to agree with what the app itself considers premium.
 * Attaches req.isPremium (bool) either way; use requirePremium() below to
 * hard-block non-premium requests, or just read req.isPremium for
 * different free/premium behavior in the same endpoint (e.g. translate).
 *
 * ALSO attaches req.userTimezone — the IANA name (e.g. "Africa/Lagos")
 * that the client syncs via /updateTimezone. Every period-key computation
 * in this file (daily free limits, monthly translate limit, daily Coach
 * challenges) uses this instead of UTC, so "today" means "the user's
 * local today." A user in Lagos at 11 PM is no longer already past
 * midnight, and a user in Auckland at 1 AM is no longer still on
 * yesterday's counter. Falls back to UTC for legacy accounts that
 * haven't opened the app since the sync endpoint shipped — identical
 * behavior to before this change, so nothing can regress.
 */
async function attachPremiumStatus(req, res, next) {
  try {
    const db = admin.firestore();
    const userRef = db.collection("users").doc(req.user.uid);
    const doc = await userRef.get();
    const data = doc.data() || {};
    const expiry = data.premiumExpiry;
    req.isPremium = !!(expiry && expiry.toDate().getTime() > Date.now());
    req.isOwner = isOwnerToken(req.user);

    if (req.isOwner) {
      // Owner/producer accounts are always Pro. Writing a far-future
      // premiumExpiry (instead of only flipping req.isPremium) keeps every
      // other reader of that field in agreement: budget.js, the Cloud
      // Vault client code and the Storage/Firestore security rules.
      const msLeft = expiry ? expiry.toDate().getTime() - Date.now() : 0;
      if (data.ownerAccess !== true || msLeft < OWNER_RENEW_BELOW_MS) {
        await userRef.set({
          ownerAccess: true,
          premiumExpiry: admin.firestore.Timestamp.fromMillis(Date.now() + OWNER_GRANT_MS),
          planId: data.planId === "monthly" || data.planId === "annual" ? data.planId : "annual",
        }, {merge: true});
      }
      req.isPremium = true;
    } else if (data.ownerAccess === true) {
      // The flag is only ever valid for the allow-listed emails.
      await userRef.set({ownerAccess: false}, {merge: true});
    }

    const tz = typeof data.timezone === "string" ? data.timezone : "";
    req.userTimezone = tz || "UTC";
    next();
  } catch (e) {
    console.error("Premium status check failed:", e.message);
    req.isOwner = isOwnerToken(req.user);
    req.isPremium = req.isOwner;
    req.userTimezone = "UTC";
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
 * Returns {yyyy-mm-dd} for the given IANA timezone, using Intl.DateTimeFormat
 * so the runtime handles DST, historical offsets, and non-hour-aligned
 * zones correctly. Falls back to UTC if the timezone name is invalid —
 * the previous behavior, so a corrupt value can never break a request.
 */
function dateKeyInZone(tz) {
  try {
    const fmt = new Intl.DateTimeFormat("en-CA", {
      timeZone: tz || "UTC",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
    // en-CA renders as YYYY-MM-DD by default, which is exactly the key
    // shape the rest of this file already uses.
    return fmt.format(new Date());
  } catch (_) {
    return new Date().toISOString().slice(0, 10);
  }
}

/** Returns {yyyy-mm} for the given IANA timezone. */
function monthKeyInZone(tz) {
  return dateKeyInZone(tz).slice(0, 7);
}

/**
 * Simple per-user, per-feature, per-day credit counter stored in Firestore
 * at users/{uid}/aiCredits/{feature}_{yyyy-mm-dd}. Returns true and
 * consumes one credit if the user is under their daily limit, false if
 * they've hit it. This is what actually protects your API budget — without
 * it, a single user (or a script hitting your endpoint directly) could run
 * unlimited paid AI calls on your dime.
 *
 * tz here is optional and defaulted to UTC for backward compatibility
 * with any caller that hasn't been updated to pass req.userTimezone yet.
 */
async function checkAndConsumeCredit(uid, feature, dailyLimit, tz = "UTC") {
  const db = admin.firestore();
  const today = dateKeyInZone(tz);
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
 *
 * Checks the monthly allowance WITHOUT spending it. Call this before
 * attempting the AI call. Returns enough state to call
 * consumeMonthlyCredit() afterward — only if the call actually succeeds.
 */
async function hasMonthlyCreditRemaining(uid, feature, monthlyLimit, tz = "UTC") {
  const db = admin.firestore();
  const month = monthKeyInZone(tz);
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

async function checkBrandingAllowance(uid, isPremium, tz = "UTC") {
  if (!isPremium) {
    const check = await hasMonthlyCreditRemaining(uid, "brandOverlay", BRANDING_FREE_PER_MONTH, tz);
    return {allowed: check.allowed, tier: "free", check};
  }
  const check = await hasMonthlyCreditRemaining(uid, "brandOverlayPro", BRANDING_INCLUDED_PER_MONTH_PRO, tz);
  return {allowed: check.allowed, tier: "pro_included", check};
}

module.exports = {
  OWNER_EMAILS,
  isOwnerToken,
  requireAuth,
  attachPremiumStatus,
  requirePremium,
  checkAndConsumeCredit,
  hasMonthlyCreditRemaining,
  consumeMonthlyCredit,
  checkBrandingAllowance,
  dateKeyInZone,
  monthKeyInZone,
  BRANDING_FREE_PER_MONTH,
  BRANDING_INCLUDED_PER_MONTH_PRO,
};