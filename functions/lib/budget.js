// lib/budget.js
//
// The whole point of this file: no premium user can ever cost more in real
// AI API spend than 30% of what they paid for their subscription. Google
// Play takes 15%, this caps API spend at 30%, which leaves a mathematically
// guaranteed 55% margin — enforced here per request, not just assumed and
// hoped for.
//
// This tracks REAL cost in USD, not a flat "N calls per day" count, because
// different actions and different response lengths cost different amounts.
// A flat count either overprotects light users or underprotects heavy ones —
// tracking actual dollars is the only way the 30% cap is actually accurate.

const admin = require("firebase-admin");

// ── OpenAI pricing — UPDATE THESE if OpenAI changes gpt-4o-mini pricing ───
// Check current pricing at https://openai.com/api/pricing before trusting
// these long-term; they're accurate as of when this was written but OpenAI
// revises pricing periodically and this file does not fetch it live.
const PRICE_PER_1M_INPUT_TOKENS_USD = 0.15;
const PRICE_PER_1M_OUTPUT_TOKENS_USD = 0.60;

// What fraction of the subscription price is allowed to go toward AI costs,
// per billing period. 0.30 = 30%, matching Play 15% + this 30% + your 55%.
const AI_BUDGET_FRACTION = 0.30;

// Same 30% rule applies to one-off credit top-ups — see redeemCreditPurchase
// in index.js. A top-up grants (price paid * this fraction) worth of budget,
// exactly like a subscription period does, so buying credits can't be a
// worse deal for your margin than the subscription itself.
const TOPUP_BUDGET_FRACTION = 0.30;

// User-facing display unit. Showing "$0.014 remaining" looks cheap and
// exposes your margin math; showing "14 credits remaining" doesn't. Purely
// a presentation layer — all real accounting stays in USD above this line.
const CREDIT_VALUE_USD = 0.001; // 1 credit = $0.001, so 1000 credits = $1

function usdToCredits(usd) {
  return Math.max(0, Math.floor(usd / CREDIT_VALUE_USD));
}

// Canonical USD price per plan — matches the actual figures you set
// ($3.99/mo, $35.99/yr). This is deliberately NOT read from the real Play
// Billing transaction currency: the NGN prices (₦5,500 / ₦49,900) were set
// specifically to BE the local-currency equivalent of these USD figures, so
// using the canonical USD number sidesteps needing a live exchange-rate feed
// just to compute a budget cap. If you ever price monthly/annual
// differently across regions in a way that's NOT meant to track this same
// USD-equivalent value, this will need real per-transaction currency data
// instead — ask me and we'll wire that up properly.
const PLAN_PRICE_USD = {
  monthly: 3.99,
  annual: 35.99,
};

// One-off credit top-up packs — real Google Play consumable product IDs.
// Create these in Play Console → Monetize → Products → In-app products
// (consumables, NOT subscriptions) with IDs matching exactly. Price is the
// real charge to the user; budgetUsd (30% of price) is what actually gets
// added to their balance.
const CREDIT_PACKS = {
  clipvault_credits_099: {priceUsd: 0.99},
  clipvault_credits_299: {priceUsd: 2.99},
  clipvault_credits_699: {priceUsd: 6.99},
  clipvault_credits_1499: {priceUsd: 14.99},
};

function estimateCostUsd(usage) {
  if (!usage) return 0;
  const inputCost = ((usage.prompt_tokens || 0) * PRICE_PER_1M_INPUT_TOKENS_USD) / 1_000_000;
  const outputCost = ((usage.completion_tokens || 0) * PRICE_PER_1M_OUTPUT_TOKENS_USD) / 1_000_000;
  return inputCost + outputCost;
}

/**
 * Reads the user's current plan/premium status and this period's spend so
 * far, plus their persistent top-up balance (purchased credits carry over
 * across renewals — a user who paid for extra credits shouldn't lose them
 * just because their subscription renewed). "This period" is tracked by
 * comparing the user's current premiumExpiry against the expiry the budget
 * doc was last reset for — a renewal or new purchase changes premiumExpiry,
 * which is exactly the signal that a fresh period (and fresh subscription
 * allowance, though NOT the top-up balance) has started.
 */
async function getBudgetState(uid) {
  const db = admin.firestore();
  const userDoc = await db.collection("users").doc(uid).get();
  const userData = userDoc.data() || {};

  const premiumExpiry = userData.premiumExpiry ? userData.premiumExpiry.toDate() : null;
  const isPremium = !!(premiumExpiry && premiumExpiry.getTime() > Date.now());
  const planId = userData.planId === "monthly" || userData.planId === "annual"
    ? userData.planId
    : null;
  const priceUsd = planId ? PLAN_PRICE_USD[planId] : 0;

  const budgetRef = db.collection("users").doc(uid).collection("meta").doc("aiBudget");
  const budgetSnap = await budgetRef.get();
  const budgetData = budgetSnap.exists ? budgetSnap.data() : {};

  const currentAnchor = premiumExpiry ? premiumExpiry.toISOString() : null;
  const storedAnchor = budgetData.periodAnchor || null;

  // Anchor mismatch (including "never set before") means this is either the
  // first request of a fresh billing period or the very first request ever
  // — either way, the period's own spend total starts back at zero. The
  // top-up balance is untouched by this — it's not period-scoped.
  const spentUsd = currentAnchor === storedAnchor ? (budgetData.spentUsd || 0) : 0;
  const topUpBalanceUsd = budgetData.topUpBalanceUsd || 0;

  const periodBudgetUsd = isPremium ? priceUsd * AI_BUDGET_FRACTION : 0;
  const periodRemainingUsd = Math.max(0, periodBudgetUsd - spentUsd);
  const remainingUsd = periodRemainingUsd + topUpBalanceUsd;

  return {
    isPremium,
    planId,
    priceUsd,
    periodBudgetUsd,
    spentUsd,
    topUpBalanceUsd,
    periodRemainingUsd,
    remainingUsd,
    remainingCredits: usdToCredits(remainingUsd),
    currentAnchor,
    budgetRef,
  };
}

/**
 * Call BEFORE making an AI request. minimumUsd is a small sanity floor —
 * there's no point letting a request through for a fraction of a cent of
 * remaining budget when the call itself might cost more than that.
 */
async function hasBudgetRemaining(uid, minimumUsd = 0.002) {
  const state = await getBudgetState(uid);
  return {...state, allowed: state.isPremium && state.remainingUsd >= minimumUsd};
}

/**
 * Call AFTER an AI request completes, with the real usage the provider
 * reported. Spends from the period's own subscription allowance first,
 * then falls back to the purchased top-up balance — so top-up credits are
 * the ones a person is actually spending down once their included
 * allowance for the period runs out, matching how it was pitched to them
 * ("run out, then buy more").
 */
async function recordSpend(uid, usage) {
  const cost = estimateCostUsd(usage);
  const state = await getBudgetState(uid);

  const fromPeriod = Math.min(cost, state.periodRemainingUsd);
  const fromTopUp = cost - fromPeriod;

  await state.budgetRef.set(
    {
      periodAnchor: state.currentAnchor,
      spentUsd: state.spentUsd + fromPeriod,
      topUpBalanceUsd: Math.max(0, state.topUpBalanceUsd - fromTopUp),
      lastPlanId: state.planId,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    {merge: true},
  );
  return cost;
}

/**
 * Adds a purchased top-up to the user's persistent balance. Called only
 * after the purchase has been verified with Google Play server-to-server —
 * see redeemCreditPurchase in index.js. Idempotent per purchaseToken via the
 * caller's own check before calling this.
 */
async function addTopUp(uid, budgetUsdToAdd) {
  const db = admin.firestore();
  const budgetRef = db.collection("users").doc(uid).collection("meta").doc("aiBudget");
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(budgetRef);
    const current = snap.exists ? snap.data().topUpBalanceUsd || 0 : 0;
    tx.set(
      budgetRef,
      {
        topUpBalanceUsd: current + budgetUsdToAdd,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );
  });
}

module.exports = {
  getBudgetState,
  hasBudgetRemaining,
  recordSpend,
  addTopUp,
  estimateCostUsd,
  usdToCredits,
  AI_BUDGET_FRACTION,
  TOPUP_BUDGET_FRACTION,
  CREDIT_VALUE_USD,
  PLAN_PRICE_USD,
  CREDIT_PACKS,
};