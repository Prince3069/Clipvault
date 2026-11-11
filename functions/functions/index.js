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
const Busboy = require("busboy");

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
const {
  generateDailyChallenge,
  generateCoachIdeas,
  generateCoachPlan,
} = require("./lib/contentCoach");
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

/**
 * Reads ONE uploaded file (field "video") out of a multipart request.
 *
 * Cloud Functions has already consumed the request stream by the time
 * Express sees it and exposes the bytes as req.rawBody — which is why
 * stream-based parsers (multer) never receive anything there. Busboy is
 * fed rawBody directly; piping req is only the fallback for the local
 * emulator / plain Express.
 * @returns {Promise<{buffer: Buffer, fileName: string}|null>}
 */
function parseVideoUpload(req) {
  return new Promise((resolve, reject) => {
    const contentType = req.headers["content-type"] || "";
    if (!contentType.toLowerCase().startsWith("multipart/form-data")) {
      return resolve(null);
    }
    let busboy;
    try {
      busboy = Busboy({
        headers: req.headers,
        limits: {fileSize: MAX_VIDEO_BYTES, files: 1},
      });
    } catch (e) {
      return reject(Object.assign(new Error("Malformed upload"), {httpStatus: 400}));
    }

    const chunks = [];
    let fileName = "video.mp4";
    let tooLarge = false;
    let gotFile = false;

    busboy.on("file", (fieldName, file, info) => {
      if (gotFile) {
        file.resume();
        return;
      }
      gotFile = true;
      if (info && typeof info.filename === "string" && info.filename) {
        fileName = info.filename;
      }
      file.on("data", (d) => chunks.push(d));
      file.on("limit", () => {
        tooLarge = true;
      });
    });
    busboy.on("error", (e) => reject(Object.assign(e, {httpStatus: 400})));
    busboy.on("finish", () => {
      if (tooLarge) {
        return reject(Object.assign(
          new Error("Video is too large to analyze (24MB limit)"), {httpStatus: 413}));
      }
      if (!gotFile) return resolve(null);
      resolve({buffer: Buffer.concat(chunks), fileName});
    });

    if (req.rawBody) {
      busboy.end(req.rawBody);
    } else {
      req.pipe(busboy);
    }
  });
}

/** Whisper picks its decoder from the file extension, so keep a real one. */
function whisperFileName(original) {
  const m = /\.([a-z0-9]{2,5})$/i.exec(original || "");
  const ext = m ? m[1].toLowerCase() : "mp4";
  const allowed = ["mp4", "m4a", "mov", "3gp", "mpeg", "mpga", "mp3", "wav", "webm"];
  return `video.${allowed.includes(ext) ? ext : "mp4"}`;
}

/**
 * Transcribes + summarizes an uploaded video, cached per user by content
 * hash so the same video is never paid for twice.
 */
async function analyzeUploadedVideo(uid, buffer, openaiKey, originalName) {
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
  // Entries cached before timed segments were stored are re-analyzed once
  // so subtitles can be real.
  if (cached.exists && Array.isArray(cached.data().segments)) {
    const c = cached.data();
    return {
      analysisKey,
      summary: c.summary || "",
      keyPhrases: c.keyPhrases || [],
      transcript: c.transcript || "",
      segments: c.segments || [],
      language: c.language || null,
      durationMinutes: c.durationMinutes || 0,
      hasSpeech: !!(c.transcript && c.transcript.trim().length >= 10),
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

  const {transcript, segments, language, durationMinutes} =
    await transcribeVideoBytes(openaiKey, buffer, whisperFileName(originalName));
  const {summary, keyPhrases, usage} = await summarizeTranscript(openaiKey, transcript);
  await recordVideoAnalysisSpend(uid, durationMinutes, usage);

  const safeTranscript = typeof transcript === "string" && transcript.length > 50000
    ? transcript.slice(0, 50000)
    : (transcript || "");

  await analysisRef.set({
    summary,
    keyPhrases,
    transcript: safeTranscript,
    segments,
    language,
    durationMinutes,
    analyzedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  return {
    analysisKey,
    summary,
    keyPhrases,
    transcript: safeTranscript,
    segments,
    language,
    durationMinutes,
    hasSpeech: safeTranscript.trim().length >= 10,
  };
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

// ─── Health check ────────────────────────────────────────────────────────
app.get("/health", (req, res) => {
  res.json({status: "ok", time: new Date().toISOString()});
});

// ─── Premium status ─────────────────────────────────────────────────────
app.get("/verifyPremium", requireAuth, attachPremiumStatus, (req, res) => {
  res.json({isPremium: req.isPremium, isOwner: req.isOwner === true});
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
      const targetLanguage = typeof req.body.targetLanguage === "string"
        ? req.body.targetLanguage.replace(/[^\p{L} ()-]/gu, "").trim().slice(0, 40)
        : "";
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
      let transcript = null;
      let segments = null;
      if (typeof analysisKey === "string" && /^[a-f0-9]{64}$/.test(analysisKey)) {
        try {
          const doc = await db.collection("users").doc(req.user.uid)
            .collection("videoAnalysis").doc(analysisKey).get();
          if (doc.exists) {
            const a = doc.data();
            videoSummary = a.summary || null;
            videoKeyPhrases = a.keyPhrases || null;
            transcript = a.transcript || null;
            segments = Array.isArray(a.segments) ? a.segments : null;
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
        transcript,
        segments,
        targetLanguage: targetLanguage || null,
        tone,
      });

      if (!result.variants || result.variants.length === 0) {
        return res.status(502).json({error: "The AI returned nothing usable — please try again."});
      }

      const spent = result.usage ? await recordSpend(req.user.uid, result.usage) : 0;
      const remainingUsd = Math.max(0, budget.remainingUsd - spent);

      db.collection("users").doc(req.user.uid).collection("events").add({
        event: "repurpose_action_completed",
        properties: {actionId, tone: result.tone, variantCount: result.variants.length},
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
      }).catch((e) => console.error("Coach event log failed (non-critical):", e.message));

      res.json({
        variants: result.variants,
        tone: result.tone,
        usedTranscript: result.usedTranscript === true,
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

    res.json({
      totalDownloads,
      platformCounts,
      // Same data in the shape older app builds read.
      stats: {total: totalDownloads, platforms: platformCounts, categories: {}},
    });
  } catch (e) {
    console.error("getLibraryStats error:", e);
    res.status(500).json({error: "Could not load library stats"});
  }
});

// ─── AI Content Coach ───────────────────────────────────────────────────

/** Calendar date key (yyyy-mm-dd) for "now + offsetDays" in the user's zone. */
function dateKeyOffset(tz, offsetDays) {
  try {
    return new Intl.DateTimeFormat("en-CA", {
      timeZone: tz || "UTC", year: "numeric", month: "2-digit", day: "2-digit",
    }).format(new Date(Date.now() + offsetDays * 24 * 60 * 60 * 1000));
  } catch (_) {
    return new Date(Date.now() + offsetDays * 86400000).toISOString().slice(0, 10);
  }
}

/**
 * The streak the person actually has right now: it only counts if the
 * last completed challenge was today or yesterday (their local dates).
 */
function effectiveStreak(userData, tz) {
  const streak = userData.coachStreak || 0;
  const last = userData.coachLastCompletedDate || null;
  if (!last) return streak > 0 && !("coachLastCompletedDate" in userData) ? streak : 0;
  if (last === dateKeyInZone(tz) || last === dateKeyOffset(tz, -1)) return streak;
  return 0;
}

function coachProfileFrom(userData) {
  return {
    niche: userData.coachNiche || "general content creation",
    goal: userData.coachGoal || "",
    experience: userData.coachExperience || "",
  };
}

/**
 * Last-30-days activity summary. Both queries filter on `timestamp` ONLY
 * (single-field indexes exist automatically) and narrow by event name in
 * memory — an equality + range query across two fields would need a
 * composite index that was never created, and failed every time.
 */
async function gatherCoachActivity(userRef) {
  try {
    const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000);

    const downloadSnap = await userRef.collection("downloadLog")
      .where("timestamp", ">=", since).limit(300).get();
    const platformCounts = {};
    downloadSnap.forEach((d) => {
      const p = d.data().platform || "unknown";
      platformCounts[p] = (platformCounts[p] || 0) + 1;
    });
    const sortedPlatforms = Object.entries(platformCounts).sort((a, b) => b[1] - a[1]);

    const eventSnap = await userRef.collection("events")
      .where("timestamp", ">=", since).limit(500).get();
    const actionCounts = {};
    let repurposeCount = 0;
    let translateCount = 0;
    eventSnap.forEach((e) => {
      const data = e.data();
      if (data.event === "repurpose_action_completed") {
        repurposeCount++;
        const actionId = (data.properties || {}).actionId || "unknown";
        actionCounts[actionId] = (actionCounts[actionId] || 0) + 1;
      } else if (data.event === "translate_action_completed") {
        translateCount++;
      }
    });
    const sortedActions = Object.entries(actionCounts).sort((a, b) => b[1] - a[1]);

    return {
      topPlatform: sortedPlatforms.length > 0 ? sortedPlatforms[0][0] : null,
      platformCounts,
      otherPlatforms: sortedPlatforms.slice(1, 3).map((p) => p[0]),
      totalDownloads: downloadSnap.size,
      topRepurposeAction: sortedActions.length > 0 ? sortedActions[0][0] : null,
      repurposeCount,
      translateCount,
    };
  } catch (e) {
    console.error("Activity aggregation failed (non-critical):", e.message);
    return null;
  }
}

const COACH_PRO_ERROR = "AI Content Coach is a Pro feature";

app.get("/getDailyChallenge", requireAuth, attachPremiumStatus,
  withRateLimit("getDailyChallenge", async (req, res) => {
  try {
    if (!req.isPremium) return res.status(402).json({error: COACH_PRO_ERROR});

    const today = dateKeyInZone(req.userTimezone);
    const userRef = db.collection("users").doc(req.user.uid);
    const challengeRef = userRef.collection("coachChallenges").doc(today);

    const cached = await challengeRef.get();
    if (cached.exists) {
      return res.json(cached.data());
    }

    const userData = (await userRef.get()).data() || {};
    const streakDays = effectiveStreak(userData, req.userTimezone);
    const activity = await gatherCoachActivity(userRef);

    const budget = await hasBudgetRemaining(req.user.uid, 0.001);
    if (!budget.allowed) {
      return res.status(429).json({
        error: "This billing period's AI budget is used up.",
        canBuyCredits: true,
      });
    }

    const challenge = await generateDailyChallenge(
      openaiKey.value(), coachProfileFrom(userData), streakDays, activity);
    const spent = await recordSpend(req.user.uid, challenge.usage);

    const points = challenge.difficulty === "hard" ? 30 :
      challenge.difficulty === "medium" ? 20 : 10;
    const toSave = {
      title: challenge.title,
      description: challenge.description,
      steps: challenge.steps,
      tip: challenge.tip,
      difficulty: challenge.difficulty,
      points,
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
    if (!req.isPremium) return res.status(402).json({error: COACH_PRO_ERROR});

    const tz = req.userTimezone;
    const today = dateKeyInZone(tz);
    const userRef = db.collection("users").doc(req.user.uid);
    const challengeRef = userRef.collection("coachChallenges").doc(today);

    const snap = await challengeRef.get();
    if (!snap.exists) {
      return res.status(400).json({error: "No challenge found for today"});
    }
    const challenge = snap.data();
    if (challenge.completed) {
      const u = (await userRef.get()).data() || {};
      return res.json({
        success: true,
        alreadyCompleted: true,
        newStreak: effectiveStreak(u, tz),
        points: u.coachPoints || 0,
        pointsEarned: 0,
      });
    }

    if (challenge.verifiable && challenge.verifyFeature) {
      const startOfDay = startOfLocalDay(tz);
      let verified = false;

      if (challenge.verifyFeature === "download") {
        const downloads = await userRef.collection("downloadLog")
          .where("timestamp", ">=", startOfDay).limit(1).get();
        verified = !downloads.empty;
      } else {
        const eventName = challenge.verifyFeature === "repurpose"
          ? "repurpose_action_completed" : "translate_action_completed";
        // Range filter on timestamp only + in-memory match — no composite
        // index needed (see gatherCoachActivity).
        const events = await userRef.collection("events")
          .where("timestamp", ">=", startOfDay).limit(300).get();
        events.forEach((e) => {
          if (e.data().event === eventName) verified = true;
        });
      }

      if (!verified) {
        const how = challenge.verifyFeature === "download"
          ? "Download at least one video or photo today"
          : challenge.verifyFeature === "repurpose"
            ? "Use Repurpose Studio at least once today"
            : "Translate something at least once today";
        return res.status(400).json({
          error: `${how} to complete this challenge.`,
          verified: false,
        });
      }
    }

    const pointsEarned = typeof challenge.points === "number" ? challenge.points :
      (challenge.difficulty === "hard" ? 30 : challenge.difficulty === "medium" ? 20 : 10);

    const result = await db.runTransaction(async (tx) => {
      const userSnap = await tx.get(userRef);
      const u = userSnap.data() || {};
      const last = u.coachLastCompletedDate || null;
      const prev = u.coachStreak || 0;
      let newStreak;
      if (last === today) {
        newStreak = Math.max(1, prev);
      } else if (last === dateKeyOffset(tz, -1) || (!last && prev > 0)) {
        newStreak = prev + 1;
      } else {
        newStreak = 1;
      }
      const points = (u.coachPoints || 0) + pointsEarned;
      tx.set(userRef, {
        coachStreak: newStreak,
        coachBestStreak: Math.max(u.coachBestStreak || 0, newStreak),
        coachPoints: points,
        coachLastCompletedDate: today,
      }, {merge: true});
      tx.update(challengeRef, {
        completed: true,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return {newStreak, points};
    });

    res.json({success: true, newStreak: result.newStreak, points: result.points, pointsEarned});
  } catch (e) {
    console.error("completeDailyChallenge error:", e);
    res.status(502).json({error: "Could not complete challenge"});
  }
});

// Personalised content ideas + coaching tips. Cached per local day;
// ?refresh=1 regenerates (bounded by the rate limiter and the AI budget).
app.get("/getCoachIdeas", requireAuth, attachPremiumStatus,
  withRateLimit("getCoachIdeas", async (req, res) => {
  try {
    if (!req.isPremium) return res.status(402).json({error: COACH_PRO_ERROR});

    const today = dateKeyInZone(req.userTimezone);
    const userRef = db.collection("users").doc(req.user.uid);
    const ideasRef = userRef.collection("coachIdeas").doc(today);
    const refresh = req.query.refresh === "1";

    const activity = await gatherCoachActivity(userRef);
    const activityOut = activity ? {
      topPlatform: activity.topPlatform,
      platformCounts: activity.platformCounts,
      totalDownloads: activity.totalDownloads,
      repurposeCount: activity.repurposeCount,
      translateCount: activity.translateCount,
      topRepurposeAction: activity.topRepurposeAction,
    } : null;

    if (!refresh) {
      const cached = await ideasRef.get();
      if (cached.exists) {
        const c = cached.data();
        return res.json({ideas: c.ideas || [], tips: c.tips || [], date: today, activity: activityOut});
      }
    }

    const budget = await hasBudgetRemaining(req.user.uid, 0.002);
    if (!budget.allowed) {
      return res.status(429).json({
        error: "This billing period's AI budget is used up.",
        canBuyCredits: true,
      });
    }

    const userData = (await userRef.get()).data() || {};
    const result = await generateCoachIdeas(
      openaiKey.value(), coachProfileFrom(userData), activity);
    await recordSpend(req.user.uid, result.usage);

    if (result.ideas.length === 0) {
      return res.status(502).json({error: "Could not generate ideas — please try again."});
    }

    await ideasRef.set({
      ideas: result.ideas,
      tips: result.tips,
      date: today,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    res.json({ideas: result.ideas, tips: result.tips, date: today, activity: activityOut});
  } catch (e) {
    console.error("getCoachIdeas error:", e);
    res.status(502).json({error: "Could not load content ideas"});
  }
}));

// Learning path. Generated once per (niche, goal, experience) and kept,
// with per-step progress, until the profile changes.
app.get("/getCoachPlan", requireAuth, attachPremiumStatus,
  withRateLimit("getCoachPlan", async (req, res) => {
  try {
    if (!req.isPremium) return res.status(402).json({error: COACH_PRO_ERROR});

    const userRef = db.collection("users").doc(req.user.uid);
    const planRef = userRef.collection("meta").doc("coachPlan");
    const userData = (await userRef.get()).data() || {};
    const profile = coachProfileFrom(userData);
    const profileKey = `${profile.niche}|${profile.goal}|${profile.experience}`.toLowerCase();

    const cached = await planRef.get();
    if (cached.exists && cached.data().profileKey === profileKey &&
        Array.isArray(cached.data().steps) && cached.data().steps.length > 0) {
      const c = cached.data();
      return res.json({steps: c.steps, completed: c.completed || []});
    }

    const budget = await hasBudgetRemaining(req.user.uid, 0.002);
    if (!budget.allowed) {
      return res.status(429).json({
        error: "This billing period's AI budget is used up.",
        canBuyCredits: true,
      });
    }

    const result = await generateCoachPlan(openaiKey.value(), profile);
    await recordSpend(req.user.uid, result.usage);
    if (result.steps.length === 0) {
      return res.status(502).json({error: "Could not build your learning path — please try again."});
    }

    await planRef.set({
      profileKey,
      steps: result.steps,
      completed: [],
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    res.json({steps: result.steps, completed: []});
  } catch (e) {
    console.error("getCoachPlan error:", e);
    res.status(502).json({error: "Could not load your learning path"});
  }
}));

app.post("/setCoachStepDone", requireAuth, attachPremiumStatus, async (req, res) => {
  try {
    if (!req.isPremium) return res.status(402).json({error: COACH_PRO_ERROR});
    const {stepId, done} = req.body || {};
    if (typeof stepId !== "string" || !/^step\d{1,2}$/.test(stepId)) {
      return res.status(400).json({error: "Invalid stepId"});
    }
    const planRef = db.collection("users").doc(req.user.uid)
      .collection("meta").doc("coachPlan");
    const snap = await planRef.get();
    if (!snap.exists) return res.status(400).json({error: "No learning path yet"});
    await planRef.update({
      completed: done === false
        ? admin.firestore.FieldValue.arrayRemove(stepId)
        : admin.firestore.FieldValue.arrayUnion(stepId),
    });
    const after = (await planRef.get()).data() || {};
    res.json({success: true, completed: after.completed || []});
  } catch (e) {
    console.error("setCoachStepDone error:", e);
    res.status(500).json({error: "Could not save progress"});
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
app.get("/getCoachProfile", requireAuth, attachPremiumStatus, async (req, res) => {
  try {
    const doc = await db.collection("users").doc(req.user.uid).get();
    const data = doc.data() || {};
    res.json({
      streak: effectiveStreak(data, req.userTimezone),
      bestStreak: data.coachBestStreak || data.coachStreak || 0,
      points: data.coachPoints || 0,
      niche: data.coachNiche || null,
      goal: data.coachGoal || null,
      name: data.coachName || null,
      experience: data.coachExperience || null,
    });
  } catch (e) {
    console.error("getCoachProfile error:", e);
    res.status(500).json({error: "Could not load coach profile"});
  }
});

app.post("/saveCoachProfile", requireAuth, async (req, res) => {
  try {
    const {niche, goal, name, experience} = req.body || {};
    const update = {};
    const clean = (v, max) =>
      typeof v === "string" ? v.replace(/[\x00-\x1F\x7F]/g, "").trim().slice(0, max) : null;

    const cleanNiche = clean(niche, 60);
    const cleanGoal = clean(goal, 60);
    const cleanName = clean(name, 40);

    if (cleanNiche) update.coachNiche = cleanNiche;
    if (cleanGoal) update.coachGoal = cleanGoal;
    if (cleanName) update.coachName = cleanName;
    const cleanExperience = clean(experience, 20);
    if (cleanExperience && ["beginner", "intermediate", "advanced"].includes(cleanExperience.toLowerCase())) {
      update.coachExperience = cleanExperience.toLowerCase();
    }

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
    if (!event || typeof event !== "string" || event.length > 80) {
      return res.status(400).json({error: "event is required"});
    }
    // These two are what Coach challenges are verified against — only the
    // server itself may record them.
    if (event === "repurpose_action_completed" || event === "translate_action_completed") {
      return res.json({success: true});
    }

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
    const {platform, fileName, isVideo} = req.body || {};
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

// ─── Video analysis (transcribe + summarize an uploaded video) ──────────
app.post("/analyzeVideo", requireAuth, attachPremiumStatus,
  withRateLimit("analyzeVideo", async (req, res) => {
  try {
    if (!req.isPremium) {
      return res.status(402).json({error: "Upgrade to Pro to analyze videos"});
    }
    const upload = await parseVideoUpload(req);
    if (!upload || upload.buffer.length === 0) {
      return res.status(400).json({error: "No video file uploaded"});
    }

    const analysis = await analyzeUploadedVideo(
      req.user.uid, upload.buffer, openaiKey.value(), upload.fileName,
    );
    res.json(analysis);
  } catch (e) {
    console.error("analyzeVideo error:", e.message);
    const status = e.httpStatus || 502;
    res.status(status).json({
      error: status === 502
        ? "The video could not be transcribed right now — please try again."
        : (e.message || "Video analysis failed"),
      canBuyCredits: e.canBuyCredits || false,
    });
  }
}));

exports.apiV1 = onRequest({
  secrets: ALL_SECRETS,
  region: "us-central1",
  // Video analysis holds an uploaded file (up to 24MB) in memory and waits
  // on transcription, so it needs more than the 256MiB / 60s defaults.
  memory: "1GiB",
  timeoutSeconds: 300,
}, app);