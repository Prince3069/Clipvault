// functions/index.js
//
// Single Cloud Function named "apiV1" (2nd gen, HTTPS) — matches the URL
// ai_service.dart already builds.
//
// New in this version:
//   • /processRepurposeVariants — multi-variant + tone-aware Repurpose
//   • /registerFcmToken — stores a device's push token for streak reminders
//   • /getDailyChallenge now gathers recent activity so the Coach prompt
//     can reflect what the person actually does
//   • rate limiting applied to every paid endpoint via lib/rateLimit.js
//
// SECRETS: never hardcode API keys. Declared with defineSecret() and read
// at request time via `openaiKey.value()`.

const {onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const express = require("express");
const cors = require("cors");
const multer = require("multer"); // ADDED: For direct multipart video uploads

const {
  requireAuth,
  attachPremiumStatus,
  hasMonthlyCreditRemaining,
  consumeMonthlyCredit,
  checkBrandingAllowance,
  dateKeyInZone,
  monthKeyInZone,
} = require("./lib/middleware");
const {chatComplete} = require("./lib/openai");
const {
  runRepurposeVariants,
  runRepurposeAction,
  SUPPORTED_ACTIONS,
  SUPPORTED_TONES,
} = require("./lib/repurpose");
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
const {checkRateLimit} = require("./lib/rateLimit");
const crypto = require("crypto");

function validateTimezone(name) {
  if (typeof name !== "string") return null;
  const trimmed = name.trim();
  if (trimmed.length === 0 || trimmed.length > 60) return null;
  try {
    new Intl.DateTimeFormat("en-CA", {timeZone: trimmed});
    return trimmed;
  } catch (_) {
    return null;
  }
}

/**
 * Wraps a handler with a per-user rate limit check. If the limit is
 * exceeded, responds 429 with retryAfterSeconds and a clear message.
 * Applied only to endpoints that cost real money or are worth spamming.
 */
function withRateLimit(feature, handler) {
  return async (req, res, next) => {
    try {
      const gate = await checkRateLimit(req.user.uid, feature);
      if (!gate.allowed) {
        res.set("Retry-After", String(gate.retryAfterSeconds || 5));
        return res.status(429).json({
          error: "Slow down a moment — try again shortly.",
          retryAfterSeconds: gate.retryAfterSeconds,
          rateLimited: true,
        });
      }
    } catch (e) {
      // Rate-limiter failure must not break the feature. Fail open.
      console.error("Rate limit check failed, allowing request:", e.message);
    }
    return handler(req, res, next);
  };
}

// FIXED: Accepts the video buffer directly instead of downloading from Firebase Storage
async function analyzeUploadedVideo(uid, buffer, openaiKey) {
  if (!buffer || buffer.length === 0) {
    throw Object.assign(new Error("No video data received"), {httpStatus: 400});
  }
  const size = buffer.length;
  if (size > MAX_VIDEO_BYTES) {
    throw Object.assign(new Error("Video is too large to analyze (24MB limit)"), {httpStatus: 413});
  }

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
}

admin.initializeApp();
const db = admin.firestore();

const openaiKey = defineSecret("OPENAI_API_KEY");
const anthropicKey = defineSecret("ANTHROPIC_API_KEY");
const deepseekKey = defineSecret("DEEPSEEK_API_KEY");
const replicateKey = defineSecret("REPLICATE_API_TOKEN");
const deepgramKey = defineSecret("DEEPGRAM_API_KEY");

const ALL_SECRETS = [openaiKey, anthropicKey, deepseekKey, replicateKey, deepgramKey];

const LIMITS = {
  translateText: {free: 1},
  processRepurposeAction: {free: 0},
};

const app = express();
app.use(cors({origin: true}));
app.use(express.json({limit: "2mb"}));

// ADDED: Multer configuration for in-memory file uploads
const upload = multer({ 
  storage: multer.memoryStorage(),
  limits: { fileSize: MAX_VIDEO_BYTES } 
});

// ─── Health check ────────────────────────────────────────────────────────
app.get("/health", (req, res) => {
  res.json({status: "ok", time: new Date().toISOString()});
});

// ─── Premium status ─────────────────────────────────────────────────────
app.get("/verifyPremium", requireAuth, attachPremiumStatus, (req, res) => {
  res.json({isPremium: req.isPremium});
});

// ─── Timezone sync ──────────────────────────────────────────────────────
app.post("/updateTimezone", requireAuth, async (req, res) => {
  try {
    const tz = validateTimezone(req.body && req.body.timezone);
    if (!tz) return res.status(400).json({error: "Invalid timezone"});
    await db.collection("users").doc(req.user.uid).set(
      {timezone: tz, timezoneUpdatedAt: admin.firestore.FieldValue.serverTimestamp()},
      {merge: true},
    );
    res.json({success: true, timezone: tz});
  } catch (e) {
    console.error("updateTimezone error:", e);
    res.status(500).json({error: "Could not update timezone"});
  }
});

// ─── FCM token registration ─────────────────────────────────────────────
// The client registers (and re-registers) its FCM token here. A user can
// have multiple tokens — one per device — so this stores an array of
// tokens, deduplicated. When the server wants to send a push, it iterates
// every token and prunes any that return UNREGISTERED on send.
app.post("/registerFcmToken", requireAuth, async (req, res) => {
  try {
    const {token, platform} = req.body || {};
    if (typeof token !== "string" || token.length < 20 || token.length > 500) {
      return res.status(400).json({error: "Invalid token"});
    }
    const cleanPlatform = typeof platform === "string" && platform.length < 20
      ? platform : "unknown";

    const userRef = db.collection("users").doc(req.user.uid);
    await userRef.set({
      fcmTokens: admin.firestore.FieldValue.arrayUnion(token),
      [`fcmTokenMeta.${token}`]: {
        platform: cleanPlatform,
        registeredAt: admin.firestore.FieldValue.serverTimestamp(),
      },
    }, {merge: true});

    res.json({success: true});
  } catch (e) {
    console.error("registerFcmToken error:", e);
    res.status(500).json({error: "Could not register token"});
  }
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

    const tz = req.userTimezone;
    const today = dateKeyInZone(tz);
    const month = monthKeyInZone(tz);
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
    res.json({date: today, month, used, limits, isPremium: false, timezone: tz});
  } catch (e) {
    console.error("getAICredits error:", e);
    res.status(500).json({error: "Could not load AI credit usage"});
  }
});

// ─── Branding/overlay feature (Quick Edit's replacement) ────────────────
app.get("/checkBrandingAllowance", requireAuth, attachPremiumStatus, async (req, res) => {
  try {
    const gate = await checkBrandingAllowance(req.user.uid, req.isPremium, req.userTimezone);
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
    const gate = await checkBrandingAllowance(req.user.uid, req.isPremium, req.userTimezone);
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
  withRateLimit("translateText", async (req, res) => {
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
        freeCheck = await hasMonthlyCreditRemaining(
          req.user.uid, "translateText", LIMITS.translateText.free, req.userTimezone);
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
  }),
);

// ─── Detect language ─────────────────────────────────────────────────────
app.post(
  "/detectLanguage",
  requireAuth,
  attachPremiumStatus,
  withRateLimit("detectLanguage", async (req, res) => {
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
  }),
);

// ─── Repurpose Studio — multi-variant, tone-aware ───────────────────────
app.post(
  "/processRepurposeVariants",
  requireAuth,
  attachPremiumStatus,
  withRateLimit("processRepurposeVariants", async (req, res) => {
    try {
      const {actionId, videoTitle, platform, analysisKey, tone} = req.body;
      if (!actionId || !SUPPORTED_ACTIONS.includes(actionId)) {
        return res.status(400).json({
          error: `Unsupported actionId. Supported: ${SUPPORTED_ACTIONS.join(", ")}`,
        });
      }
      if (tone && !SUPPORTED_TONES.includes(tone)) {
        return res.status(400).json({
          error: `Unsupported tone. Supported: ${SUPPORTED_TONES.join(", ")}`,
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

      const result = await runRepurposeVariants(openaiKey.value(), actionId, {
        videoTitle,
        platform,
        videoSummary,
        videoKeyPhrases,
        tone,
      });

      const spent = await recordSpend(req.user.uid, result.usage);
      const remainingUsd = Math.max(0, budget.remainingUsd - spent);

      db.collection("users").doc(req.user.uid).collection("events").add({
        event: "repurpose_action_completed",
        properties: {actionId, tone: result.tone, variantCount: result.variants.length},
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      }).catch((e) => console.error("Coach event log failed (non-critical):", e.message));

      res.json({
        variants: result.variants,
        tone: result.tone,
        remainingCredits: usdToCredits(remainingUsd),
      });
    } catch (e) {
      console.error("processRepurposeVariants error:", e);
      res.status(502).json({error: `AI generation failed: ${e.message || "please try again"}`});
    }
  }),
);

// ─── Repurpose Studio — legacy single-variant (kept for old clients) ────
app.post(
  "/processRepurposeAction",
  requireAuth,
  attachPremiumStatus,
  withRateLimit("processRepurposeAction", async (req, res) => {
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
  }),
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

// ─── AI Content Coach — real daily challenges (activity-aware) ─────────
//
// Now gathers recent activity before generating. The activity block is
// derived from downloadLog (last 30 days) and events (repurpose actions),
// so the challenge reflects what the person actually does on the app.
app.get("/getDailyChallenge", requireAuth, attachPremiumStatus,
  withRateLimit("getDailyChallenge", async (req, res) => {
  try {
    const today = dateKeyInZone(req.userTimezone);
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

    // ─── Gather 30-day activity ────────────────────────────────────────
    // Both queries are cheap (indexed on the collection by timestamp in
    // the downloadLog case and by the event field in the events case),
    // and both are bounded to 30 days. If either fails, the challenge is
    // still generated — activity is enrichment, not a dependency.
    let activity = null;
    try {
      const thirtyDaysAgo = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);

      const downloadSnap = await userRef.collection("downloadLog")
        .where("timestamp", ">=", thirtyDaysAgo)
        .limit(200)
        .get();

      const platformCounts = {};
      downloadSnap.forEach((d) => {
        const p = d.data().platform || "unknown";
        platformCounts[p] = (platformCounts[p] || 0) + 1;
      });

      const sortedPlatforms = Object.entries(platformCounts)
        .sort((a, b) => b[1] - a[1]);
      const topPlatform = sortedPlatforms.length > 0 ? sortedPlatforms[0][0] : null;
      const otherPlatforms = sortedPlatforms.slice(1, 3).map((p) => p[0]);

      const repurposeSnap = await userRef.collection("events")
        .where("event", "==", "repurpose_action_completed")
        .where("timestamp", ">=", thirtyDaysAgo)
        .limit(200)
        .get();

      const actionCounts = {};
      repurposeSnap.forEach((e) => {
        const actionId = (e.data().properties || {}).actionId || "unknown";
        actionCounts[actionId] = (actionCounts[actionId] || 0) + 1;
      });
      const sortedActions = Object.entries(actionCounts)
        .sort((a, b) => b[1] - a[1]);
      const topRepurposeAction = sortedActions.length > 0 ? sortedActions[0][0] : null;

      activity = {
        topPlatform,
        platformCounts,
        otherPlatforms,
        totalDownloads: downloadSnap.size,
        topRepurposeAction,
        repurposeCount: repurposeSnap.size,
      };
    } catch (e) {
      console.error("Activity aggregation failed (non-critical):", e.message);
    }

    const budget = await hasBudgetRemaining(req.user.uid, 0.001);
    if (!budget.allowed) {
      return res.status(429).json({
        error: "This billing period's AI budget is used up.",
        canBuyCredits: true,
      });
    }

    const challenge = await generateDailyChallenge(
      openaiKey.value(), niche, streakDays, activity);
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
}));

app.post("/completeDailyChallenge", requireAuth, attachPremiumStatus, async (req, res) => {
  try {
    const today = dateKeyInZone(req.userTimezone);
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
      const startOfDay = startOfLocalDay(req.userTimezone);
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

function startOfLocalDay(tz) {
  try {
    const now = new Date();
    const ymd = dateKeyInZone(tz).split("-").map(Number);
    const utcMidnight = Date.UTC(ymd[0], ymd[1] - 1, ymd[2]);
    const parts = new Intl.DateTimeFormat("en-US", {
      timeZone: tz,
      timeZoneName: "shortOffset",
      hour: "2-digit",
    }).formatToParts(now);
    let offsetMinutes = 0;
    const tzName = parts.find((p) => p.type === "timeZoneName")?.value || "";
    const m = tzName.match(/GMT([+-])(\d{1,2})(?::(\d{2}))?/);
    if (m) {
      const sign = m[1] === "-" ? -1 : 1;
      offsetMinutes = sign * (parseInt(m[2], 10) * 60 + (m[3] ? parseInt(m[3], 10) : 0));
    }
    return new Date(utcMidnight - offsetMinutes * 60 * 1000);
  } catch (_) {
    const ymd = new Date().toISOString().slice(0, 10).split("-").map(Number);
    return new Date(Date.UTC(ymd[0], ymd[1] - 1, ymd[2]));
  }
}

// ─── AI Content Coach — profile ─────────────────────────────────────────
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
app.get("/getAnalyzedVideos", requireAuth, notImplemented("getAnalyzedVideos"));
app.get("/getLibraryStats2", requireAuth, notImplemented("getLibraryStats2"));
app.post("/suggestCollections", requireAuth, notImplemented("suggestCollections"));
app.get("/getCloudVaultFiles", requireAuth, notImplemented("getCloudVaultFiles"));
app.post("/deleteCloudFile", requireAuth, notImplemented("deleteCloudFile"));

// FIXED: Using multer to parse the uploaded video bytes directly
app.post("/analyzeVideo", requireAuth, attachPremiumStatus, upload.single("video"),
  withRateLimit("analyzeVideo", async (req, res) => {
  try {
    if (!req.isPremium) {
      return res.status(402).json({error: "Upgrade to Pro to analyze videos"});
    }
    if (!req.file) {
      return res.status(400).json({error: "No video file uploaded"});
    }
    
    const analysis = await analyzeUploadedVideo(
      req.user.uid, req.file.buffer, openaiKey.value(),
    );
    res.json(analysis);
  } catch (e) {
    console.error("analyzeVideo error:", e.message);
    res.status(e.httpStatus || 502).json({
      error: e.message || "Video analysis failed",
      canBuyCredits: e.canBuyCredits || false,
    });
  }
}));

exports.apiV1 = onRequest({secrets: ALL_SECRETS, region: "us-central1"}, app);