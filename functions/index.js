// functions/index.js
//
// Single Cloud Function named "apiV1" (2nd gen, HTTPS) — matches the URL
// ai_service.dart already builds. Every route below is one the Flutter
// client already calls, plus two new Coach endpoints and (in this version)
// returning the raw transcript from /analyzeVideo so the Smart Translator
// Video tab can translate real speech instead of a summary.
//
// SECRETS: never hardcode API keys. Declared with defineSecret() and read
// at request time via `openaiKey.value()`.

const {onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const express = require("express");
const cors = require("cors");

const {requireAuth, attachPremiumStatus, checkAndConsumeCredit, hasMonthlyCreditRemaining, consumeMonthlyCredit, checkBrandingAllowance, BRANDING_FREE_PER_MONTH, BRANDING_INCLUDED_PER_MONTH_PRO} = require("./lib/middleware");
const {chatComplete} = require("./lib/openai");
const {runRepurposeAction, SUPPORTED_ACTIONS} = require("./lib/repurpose");
const {
  hasBudgetRemaining,
  recordSpend,
  recordVideoAnalysisSpend,
  addTopUp,
  spendFromTopUpOnly,
  usdToCredits,
  CREDIT_PACKS,
  TOPUP_BUDGET_FRACTION,
  BRANDING_TOPUP_COST_USD,
} = require("./lib/budget");
const {verifyAndConsumePurchase, verifySubscriptionPurchase} = require("./lib/playVerify");
const {
  transcribeVideoBytes,
  summarizeTranscript,
  MAX_ANALYSIS_MINUTES,
  MAX_VIDEO_BYTES,
  WHISPER_PRICE_PER_MINUTE_USD,
} = require("./lib/videoAnalysis");
const {generateDailyChallenge} = require("./lib/contentCoach");
const crypto = require("crypto");

/**
 * Analyzes a video the app has uploaded to its OWN private temp path
 * (users/{uid}/analysis_temp/…) — never a URL supplied by the client.
 *
 * Returns {analysisKey, summary, keyPhrases, transcript, durationMinutes}.
 * The transcript is included because the Smart Translator Video tab needs
 * the raw words to translate (a summary would lose them); Repurpose only
 * reads summary/keyPhrases and ignores the transcript. Cached per unique
 * video bytes, so analyzing the same video for Translator and then for
 * Repurpose (or vice versa) only pays for Whisper once.
 */
async function analyzeUploadedVideo(uid, storagePath, openaiKey) {
  const prefix = `users/${uid}/analysis_temp/`;
  if (typeof storagePath !== "string" || !storagePath.startsWith(prefix) ||
      storagePath.includes("..") || storagePath.length > 200) {
    throw Object.assign(new Error("Invalid upload path"), {httpStatus: 400});
  }

  const file = admin.storage().bucket().file(storagePath);
  try {
    const [meta] = await file.getMetadata();
    const size = Number(meta.size);
    if (!size || size > MAX_VIDEO_BYTES) {
      throw Object.assign(new Error("Video is too large to analyze (24MB limit)"), {httpStatus: 413});
    }
    const [buffer] = await file.download();

    const analysisKey = crypto.createHash("sha256").update(buffer).digest("hex");
    const analysisRef = db.collection("users").doc(uid)
      .collection("videoAnalysis").doc(analysisKey);

    const cached = await analysisRef.get();
    if (cached.exists) {
      const c = cached.data();
      return {
        analysisKey,
        summary: c.summary,
        keyPhrases: c.keyPhrases,
        // Legacy entries (analyzed before this version) may not have the
        // transcript stored — return null in that case, which the client
        // already tolerates.
        transcript: c.transcript || null,
        durationMinutes: c.durationMinutes,
      };
    }

    const worstCaseUsd = MAX_ANALYSIS_MINUTES * WHISPER_PRICE_PER_MINUTE_USD + 0.002;
    const gate = await hasBudgetRemaining(uid, worstCaseUsd);
    if (!gate.allowed) {
      throw Object.assign(
        new Error("Not enough AI budget left for video analysis"),
        {httpStatus: 429, canBuyCredits: true},
      );
    }

    const {transcript, durationMinutes} = await transcribeVideoBytes(openaiKey, buffer);
    const {summary, keyPhrases, usage} = await summarizeTranscript(openaiKey, transcript);
    await recordVideoAnalysisSpend(uid, durationMinutes, usage);

    // Cap stored transcript at 50KB as a sanity guard (10-min video @150wpm
    // is ~7.5KB, so this is only hit by pathological cases) — Firestore
    // documents are capped at 1MB.
    const safeTranscript = typeof transcript === "string" && transcript.length > 50000
      ? transcript.slice(0, 50000)
      : transcript;

    await analysisRef.set({
      summary,
      keyPhrases,
      transcript: safeTranscript,
      durationMinutes,
      analyzedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {analysisKey, summary, keyPhrases, transcript: safeTranscript, durationMinutes};
  } finally {
    await file.delete().catch(() => {});
  }
}

admin.initializeApp();
const db = admin.firestore();

// ─── Secrets ────────────────────────────────────────────────────────────
const openaiKey = defineSecret("OPENAI_API_KEY");
const anthropicKey = defineSecret("ANTHROPIC_API_KEY");
const deepseekKey = defineSecret("DEEPSEEK_API_KEY");
const replicateKey = defineSecret("REPLICATE_API_TOKEN");
const deepgramKey = defineSecret("DEEPGRAM_API_KEY");

const ALL_SECRETS = [openaiKey, anthropicKey, deepseekKey, replicateKey, deepgramKey];

// ─── Free-tier limits ────────────────────────────────────────────────────
const LIMITS = {
  translateText: {free: 1}, // per calendar MONTH
  processRepurposeAction: {free: 0}, // fully premium-gated
};

const app = express();
app.use(cors({origin: true}));
app.use(express.json({limit: "2mb"}));

// ─── Health check ────────────────────────────────────────────────────────
app.get("/health", (req, res) => {
  res.json({status: "ok", time: new Date().toISOString()});
});

// ─── Premium status ─────────────────────────────────────────────────────
app.get("/verifyPremium", requireAuth, attachPremiumStatus, (req, res) => {
  res.json({isPremium: req.isPremium});
});

// ─── AI credit usage ─────────────────────────────────────────────────────
app.get("/getAICredits", requireAuth, attachPremiumStatus, async (req, res) => {
  try {
    if (req.isPremium) {
      const budget = await hasBudgetRemaining(req.user.uid);
      return res.json({
        isPremium: true,
        planId: budget.planId,
        remainingCredits: budget.remainingCredits,
        topUpCredits: usdToCredits(budget.topUpBalanceUsd),
        includedCreditsRemaining: usdToCredits(budget.periodRemainingUsd),
      });
    }

    const today = new Date().toISOString().slice(0, 10);
    const month = new Date().toISOString().slice(0, 7);
    const features = Object.keys(LIMITS);
    const used = {};
    for (const feature of features) {
      const periodKey = feature === "translateText" ? month : today;
      const doc = await db
        .collection("users")
        .doc(req.user.uid)
        .collection("aiCredits")
        .doc(`${feature}_${periodKey}`)
        .get();
      used[feature] = doc.exists ? doc.data().count || 0 : 0;
    }
    const limits = {};
    for (const feature of features) {
      limits[feature] = LIMITS[feature].free;
    }
    res.json({date: today, month, used, limits, isPremium: false});
  } catch (e) {
    console.error("getAICredits error:", e);
    res.status(500).json({error: "Could not load AI credit usage"});
  }
});

// ─── Branding/overlay feature (Quick Edit's replacement) ────────────────
app.get("/checkBrandingAllowance", requireAuth, attachPremiumStatus, async (req, res) => {
  try {
    const gate = await checkBrandingAllowance(req.user.uid, req.isPremium);
    if (gate.allowed) {
      return res.json({allowed: true, tier: gate.tier});
    }
    if (!req.isPremium) {
      return res.json({
        allowed: false,
        tier: "free",
        reason: "Your free use for this month is used. Upgrade to Pro for a monthly allowance, or wait until next month.",
      });
    }
    const budget = await hasBudgetRemaining(req.user.uid, BRANDING_TOPUP_COST_USD);
    if (budget.allowed) {
      return res.json({allowed: true, tier: "topup", topUpCredits: usdToCredits(budget.topUpBalanceUsd)});
    }
    return res.json({
      allowed: false,
      tier: "pro_exhausted",
      reason: "Your included uses for this month are used up. Buy a credit pack to keep going, or wait until next month.",
    });
  } catch (e) {
    console.error("checkBrandingAllowance error:", e);
    res.status(500).json({error: "Could not check branding allowance"});
  }
});

app.post("/consumeBrandingUse", requireAuth, attachPremiumStatus, async (req, res) => {
  try {
    const gate = await checkBrandingAllowance(req.user.uid, req.isPremium);
    if (gate.allowed) {
      await consumeMonthlyCredit(gate.check);
      return res.json({success: true, tier: gate.tier});
    }
    if (!req.isPremium) {
      return res.status(429).json({error: "Your free use for this month is used."});
    }
    const spend = await spendFromTopUpOnly(req.user.uid, BRANDING_TOPUP_COST_USD);
    if (!spend.allowed) {
      return res.status(429).json({
        error: "Your included uses for this month are used up, and there's no credit balance to fall back on. Buy a credit pack to keep going.",
        canBuyCredits: true,
      });
    }
    res.json({success: true, tier: "topup", topUpCredits: usdToCredits(spend.remainingTopUpUsd)});
  } catch (e) {
    console.error("consumeBrandingUse error:", e);
    res.status(500).json({error: "Could not record branding use"});
  }
});

// ─── Translate text ─────────────────────────────────────────────────────
app.post(
  "/translateText",
  requireAuth,
  attachPremiumStatus,
  async (req, res) => {
    try {
      const {text, targetLanguage, sourceLanguage} = req.body;
      if (!text || !targetLanguage) {
        return res.status(400).json({error: "text and targetLanguage are required"});
      }
      if (text.length > 4000) {
        return res.status(400).json({error: "Text is too long (max 4000 characters)"});
      }

      let freeCheck = null;
      if (req.isPremium) {
        const budget = await hasBudgetRemaining(req.user.uid);
        if (!budget.allowed) {
          return res.status(429).json({
            error: "This billing period's AI budget is used up. Buy more " +
              "credits to keep going, or it renews automatically with your next payment.",
            canBuyCredits: true,
          });
        }
      } else {
        freeCheck = await hasMonthlyCreditRemaining(req.user.uid, "translateText", LIMITS.translateText.free);
        if (!freeCheck.allowed) {
          return res.status(429).json({
            error: "Your free translation for this month is used — upgrade to Pro for unlimited, or wait until next month for another free one.",
          });
        }
      }

      const {text: translated, usage} = await chatComplete(openaiKey.value(), {
        system: `Translate the user's text to ${targetLanguage}` +
          `${sourceLanguage ? ` from ${sourceLanguage}` : ""}. ` +
          "Reply with only the translated text — no notes, no quotes, no explanation.",
        user: text,
        temperature: 0.2,
      });

      if (req.isPremium) {
        await recordSpend(req.user.uid, usage);
      } else if (freeCheck) {
        await consumeMonthlyCredit(freeCheck);
      }

      db.collection("users").doc(req.user.uid).collection("events").add({
        event: "translate_action_completed",
        properties: {targetLanguage},
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      }).catch((e) => console.error("Coach event log failed (non-critical):", e.message));

      const budgetAfter = req.isPremium ? await hasBudgetRemaining(req.user.uid) : null;
      res.json({
        translatedText: translated,
        targetLanguage,
        remainingCredits: budgetAfter ? budgetAfter.remainingCredits : null,
      });
    } catch (e) {
      console.error("translateText error:", e);
      res.status(502).json({error: `Translation service error: ${e.message || "please try again"}`});
    }
  },
);

// ─── Detect language ─────────────────────────────────────────────────────
app.post(
  "/detectLanguage",
  requireAuth,
  attachPremiumStatus,
  async (req, res) => {
    try {
      if (!req.isPremium) {
        return res.status(402).json({error: "Auto-detect language is a Pro feature"});
      }

      const {text} = req.body;
      if (!text) return res.status(400).json({error: "text is required"});

      const {text: language} = await chatComplete(openaiKey.value(), {
        system: "Identify the language of the user's text. Reply with only the " +
          "language name in English — nothing else.",
        user: text,
        temperature: 0,
      });

      res.json({language: language || "Unknown"});
    } catch (e) {
      console.error("detectLanguage error:", e);
      res.status(502).json({error: `Language detection error: ${e.message || "please try again"}`});
    }
  },
);

// ─── Repurpose Studio ─────────────────────────────────────────────────────
app.post(
  "/processRepurposeAction",
  requireAuth,
  attachPremiumStatus,
  async (req, res) => {
    try {
      const {actionId, videoTitle, platform, analysisKey} = req.body;
      if (!actionId || !SUPPORTED_ACTIONS.includes(actionId)) {
        return res.status(400).json({
          error: `Unsupported actionId. Supported: ${SUPPORTED_ACTIONS.join(", ")}`,
        });
      }

      if (!req.isPremium) {
        return res.status(402).json({error: "Upgrade to Pro to use Repurpose Studio"});
      }

      const budget = await hasBudgetRemaining(req.user.uid);
      if (!budget.allowed) {
        return res.status(429).json({
          error: "This billing period's AI budget is used up. Buy more credits to keep going, or it renews automatically with your next payment.",
          canBuyCredits: true,
        });
      }

      let videoSummary = null;
      let videoKeyPhrases = null;
      if (typeof analysisKey === "string" && /^[a-f0-9]{64}$/.test(analysisKey)) {
        try {
          const doc = await db.collection("users").doc(req.user.uid)
            .collection("videoAnalysis").doc(analysisKey).get();
          if (doc.exists) {
            videoSummary = doc.data().summary || null;
            videoKeyPhrases = doc.data().keyPhrases || null;
          }
        } catch (e) {
          console.error("Analysis lookup failed, falling back to title-only:", e.message);
        }
      }

      const {text: result, usage} = await runRepurposeAction(openaiKey.value(), actionId, {
        videoTitle,
        platform,
        videoSummary,
        videoKeyPhrases,
      });

      const spent = await recordSpend(req.user.uid, usage);
      const remainingUsd = Math.max(0, budget.remainingUsd - spent);

      db.collection("users").doc(req.user.uid).collection("events").add({
        event: "repurpose_action_completed",
        properties: {actionId},
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      }).catch((e) => console.error("Coach event log failed (non-critical):", e.message));

      res.json({
        result,
        remainingCredits: usdToCredits(remainingUsd),
      });
    } catch (e) {
      console.error("processRepurposeAction error:", e);
      res.status(502).json({error: `AI generation failed: ${e.message || "please try again"}`});
    }
  },
);

// ─── Redeem a purchased credit pack ─────────────────────────────────────
app.post("/redeemCreditPurchase", requireAuth, attachPremiumStatus, async (req, res) => {
  try {
    const {productId, purchaseToken} = req.body;
    if (!productId || !purchaseToken) {
      return res.status(400).json({error: "productId and purchaseToken are required"});
    }

    const pack = CREDIT_PACKS[productId];
    if (!pack) {
      return res.status(400).json({error: "Unknown credit pack productId"});
    }

    if (!req.isPremium) {
      return res.status(403).json({
        error: "Credits require an active Pro subscription. If you were " +
          "charged, request a refund from Google Play — Play Store → Menu " +
          "→ Payments & subscriptions → Order history.",
      });
    }

    const redemptionRef = db.collection("creditRedemptions").doc(purchaseToken);
    const already = await redemptionRef.get();
    if (already.exists) {
      return res.status(409).json({error: "This purchase has already been redeemed"});
    }

    const verification = await verifyAndConsumePurchase(productId, purchaseToken);
    if (!verification.valid) {
      console.error("redeemCreditPurchase: verification failed:", verification.reason);
      return res.status(402).json({error: "Purchase could not be verified with Google Play"});
    }

    const budgetUsdToAdd = pack.priceUsd * TOPUP_BUDGET_FRACTION;
    await addTopUp(req.user.uid, budgetUsdToAdd);

    await redemptionRef.set({
      uid: req.user.uid,
      productId,
      priceUsd: pack.priceUsd,
      budgetUsdAdded: budgetUsdToAdd,
      redeemedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({
      success: true,
      creditsAdded: usdToCredits(budgetUsdToAdd),
    });
  } catch (e) {
    console.error("redeemCreditPurchase error:", e);
    res.status(500).json({error: "Could not redeem credit purchase"});
  }
});

// ─── Verify and activate a subscription purchase ─────────────────────────
app.post("/verifySubscriptionPurchase", requireAuth, async (req, res) => {
  try {
    const {productId, purchaseToken} = req.body;
    console.log(`verifySubscriptionPurchase called by uid: ${req.user.uid}, productId: ${productId}`);
    if (!productId || !purchaseToken) {
      return res.status(400).json({error: "productId and purchaseToken are required"});
    }
    if (productId !== "saveit_premium_monthly" && productId !== "saveit_premium_annual") {
      return res.status(400).json({error: "Unknown subscription productId"});
    }

    const activationRef = db.collection("subscriptionActivations").doc(purchaseToken);
    const already = await activationRef.get();
    if (already.exists) {
      const data = already.data();
      return res.json({success: true, expiryTime: data.expiryTime, planId: data.planId});
    }

    const verification = await verifySubscriptionPurchase(productId, purchaseToken);
    if (!verification.valid) {
      console.error(`verifySubscriptionPurchase: verification failed for uid ${req.user.uid}:`, verification.reason);
      return res.status(402).json({error: "Subscription could not be verified with Google Play"});
    }

    const planId = productId === "saveit_premium_monthly" ? "monthly" : "annual";
    const expiryTime = verification.expiryTime;

    await db.collection("users").doc(req.user.uid).set(
      {
        premiumExpiry: admin.firestore.Timestamp.fromDate(expiryTime),
        planId,
        lastVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true},
    );

    await activationRef.set({
      uid: req.user.uid,
      productId,
      planId,
      expiryTime: expiryTime.toISOString(),
      verifiedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({success: true, expiryTime: expiryTime.toISOString(), planId});
  } catch (e) {
    console.error("verifySubscriptionPurchase error:", e);
    res.status(500).json({error: "Could not verify subscription purchase"});
  }
});

// ─── Library stats ───────────────────────────────────────────────────────
app.get("/getLibraryStats", requireAuth, async (req, res) => {
  try {
    const snapshot = await db
      .collection("users")
      .doc(req.user.uid)
      .collection("downloadLog")
      .get();

    let totalDownloads = 0;
    const platformCounts = {};
    snapshot.forEach((doc) => {
      totalDownloads++;
      const platform = doc.data().platform || "unknown";
      platformCounts[platform] = (platformCounts[platform] || 0) + 1;
    });

    res.json({totalDownloads, platformCounts});
  } catch (e) {
    console.error("getLibraryStats error:", e);
    res.status(500).json({error: "Could not load library stats"});
  }
});

// ─── AI Content Coach — real daily challenges ───────────────────────────
app.get("/getDailyChallenge", requireAuth, async (req, res) => {
  try {
    const today = new Date().toISOString().slice(0, 10);
    const userRef = db.collection("users").doc(req.user.uid);
    const challengeRef = userRef.collection("coachChallenges").doc(today);

    const cached = await challengeRef.get();
    if (cached.exists) {
      return res.json(cached.data());
    }

    const userDoc = await userRef.get();
    const userData = userDoc.data() || {};
    const niche = userData.coachNiche || "general content creation";
    const streakDays = userData.coachStreak || 0;

    const budget = await hasBudgetRemaining(req.user.uid, 0.001);
    if (!budget.allowed) {
      return res.status(429).json({
        error: "This billing period's AI budget is used up.",
        canBuyCredits: true,
      });
    }

    const challenge = await generateDailyChallenge(openaiKey.value(), niche, streakDays);
    const spent = await recordSpend(req.user.uid, challenge.usage);

    const toSave = {
      title: challenge.title,
      description: challenge.description,
      difficulty: challenge.difficulty,
      verifiable: challenge.verifiable,
      verifyFeature: challenge.verifyFeature,
      date: today,
      completed: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    };
    await challengeRef.set(toSave);
    res.json({...toSave, remainingCredits: usdToCredits(Math.max(0, budget.remainingUsd - spent))});
  } catch (e) {
    console.error("getDailyChallenge error:", e);
    res.status(502).json({error: "Could not generate today's challenge"});
  }
});

app.post("/completeDailyChallenge", requireAuth, async (req, res) => {
  try {
    const today = new Date().toISOString().slice(0, 10);
    const userRef = db.collection("users").doc(req.user.uid);
    const challengeRef = userRef.collection("coachChallenges").doc(today);

    const snap = await challengeRef.get();
    if (!snap.exists) {
      return res.status(400).json({error: "No challenge found for today"});
    }
    const challenge = snap.data();
    if (challenge.completed) {
      return res.json({success: true, alreadyCompleted: true});
    }

    if (challenge.verifiable && challenge.verifyFeature) {
      const startOfDay = new Date(`${today}T00:00:00.000Z`);
      let verified = false;

      if (challenge.verifyFeature === "download") {
        const downloads = await userRef.collection("downloadLog")
          .where("timestamp", ">=", startOfDay).limit(1).get();
        verified = !downloads.empty;
      } else {
        const eventName = challenge.verifyFeature === "repurpose"
          ? "repurpose_action_completed" : "translate_action_completed";
        const events = await userRef.collection("events")
          .where("event", "==", eventName)
          .where("timestamp", ">=", startOfDay).limit(1).get();
        verified = !events.empty;
      }

      if (!verified) {
        return res.status(400).json({
          error: `Use ${challenge.verifyFeature} at least once today to complete this challenge.`,
          verified: false,
        });
      }
    }

    const newStreak = (await userRef.get()).data()?.coachStreak || 0;
    await challengeRef.update({completed: true, completedAt: admin.firestore.FieldValue.serverTimestamp()});
    await userRef.set({
      coachStreak: newStreak + 1,
      coachPoints: admin.firestore.FieldValue.increment(
        challenge.difficulty === "hard" ? 30 : challenge.difficulty === "medium" ? 20 : 10,
      ),
    }, {merge: true});

    res.json({success: true, newStreak: newStreak + 1});
  } catch (e) {
    console.error("completeDailyChallenge error:", e);
    res.status(502).json({error: "Could not complete challenge"});
  }
});

// ─── AI Content Coach — profile (streak, points, niche, goal) ───────────
app.get("/getCoachProfile", requireAuth, async (req, res) => {
  try {
    const doc = await db.collection("users").doc(req.user.uid).get();
    const data = doc.data() || {};
    res.json({
      streak: data.coachStreak || 0,
      points: data.coachPoints || 0,
      niche: data.coachNiche || null,
      goal: data.coachGoal || null,
      name: data.coachName || null,
    });
  } catch (e) {
    console.error("getCoachProfile error:", e);
    res.status(500).json({error: "Could not load coach profile"});
  }
});

// ─── AI Content Coach — save niche/goal/name ─────────────────────────────
app.post("/saveCoachProfile", requireAuth, async (req, res) => {
  try {
    const {niche, goal, name} = req.body || {};
    const update = {};
    const clean = (v, max) =>
      typeof v === "string" ? v.replace(/[\x00-\x1F\x7F]/g, "").trim().slice(0, max) : null;

    const cleanNiche = clean(niche, 60);
    const cleanGoal = clean(goal, 60);
    const cleanName = clean(name, 40);

    if (cleanNiche) update.coachNiche = cleanNiche;
    if (cleanGoal) update.coachGoal = cleanGoal;
    if (cleanName) update.coachName = cleanName;

    if (Object.keys(update).length === 0) {
      return res.status(400).json({error: "Nothing valid to save"});
    }

    await db.collection("users").doc(req.user.uid).set(update, {merge: true});
    res.json({success: true});
  } catch (e) {
    console.error("saveCoachProfile error:", e);
    res.status(500).json({error: "Could not save coach profile"});
  }
});

app.post("/trackEvent", requireAuth, async (req, res) => {
  try {
    const {event, properties} = req.body;
    if (!event) return res.status(400).json({error: "event is required"});

    await db.collection("users").doc(req.user.uid).collection("events").add({
      event,
      properties: properties || {},
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });

    res.json({success: true});
  } catch (e) {
    console.error("trackEvent error:", e);
    res.json({success: false});
  }
});

// ─── Download logging ───────────────────────────────────────────────────
app.post("/logDownload", requireAuth, async (req, res) => {
  try {
    const {platform, fileName, isVideo} = req.body;
    await db.collection("users").doc(req.user.uid).collection("downloadLog").add({
      platform: platform || "unknown",
      fileName: fileName || "",
      isVideo: !!isVideo,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
    });
    res.json({success: true});
  } catch (e) {
    console.error("logDownload error:", e);
    res.json({success: false});
  }
});

app.get("/getDownloadStats", requireAuth, async (req, res) => {
  try {
    const snapshot = await db
      .collection("users")
      .doc(req.user.uid)
      .collection("downloadLog")
      .get();
    res.json({totalDownloads: snapshot.size});
  } catch (e) {
    console.error("getDownloadStats error:", e);
    res.status(500).json({error: "Could not load download stats"});
  }
});

// ─── Not-yet-implemented placeholders ───────────────────────────────────
const notImplemented = (name) => (req, res) => {
  res.status(501).json({error: `${name} is not implemented on the server yet`});
};
app.post("/analyzeVideo", requireAuth, attachPremiumStatus, async (req, res) => {
  try {
    if (!req.isPremium) {
      return res.status(402).json({error: "Upgrade to Pro to analyze videos"});
    }
    const analysis = await analyzeUploadedVideo(
      req.user.uid, req.body && req.body.storagePath, openaiKey.value(),
    );
    res.json(analysis);
  } catch (e) {
    console.error("analyzeVideo error:", e.message);
    res.status(e.httpStatus || 502).json({
      error: e.message || "Video analysis failed",
      canBuyCredits: e.canBuyCredits || false,
    });
  }
});
app.get("/getAnalyzedVideos", requireAuth, notImplemented("getAnalyzedVideos"));
app.get("/getLibraryStats2", requireAuth, notImplemented("getLibraryStats2"));
app.post("/suggestCollections", requireAuth, notImplemented("suggestCollections"));
app.get("/getCloudVaultFiles", requireAuth, notImplemented("getCloudVaultFiles"));
app.post("/deleteCloudFile", requireAuth, notImplemented("deleteCloudFile"));

exports.apiV1 = onRequest({secrets: ALL_SECRETS, region: "us-central1"}, app);