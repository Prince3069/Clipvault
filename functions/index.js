// functions/index.js
//
// This deploys as a single Cloud Function named "apiV1" (2nd gen, HTTPS),
// which is exactly the URL your Flutter app already calls:
//   https://us-central1-social-downloader-2d02b.cloudfunctions.net/apiV1/...
// Every route below is one of the paths ai_service.dart already builds —
// nothing on the Flutter side needs to change for the endpoints implemented
// here.
//
// SECRETS: never hardcode API keys. They're declared with defineSecret()
// below and read at request time via `openaiKey.value()`. See the bottom of
// this file and the deployment guide for how to actually set their values —
// they live in Google Secret Manager, not in this repo, not in git, not on
// the device.

const {onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const admin = require("firebase-admin");
const express = require("express");
const cors = require("cors");

const {requireAuth, attachPremiumStatus, checkAndConsumeCredit} = require("./lib/middleware");
const {chatComplete} = require("./lib/openai");
const {runRepurposeAction, SUPPORTED_ACTIONS} = require("./lib/repurpose");
const {
  hasBudgetRemaining,
  recordSpend,
  addTopUp,
  usdToCredits,
  CREDIT_PACKS,
  TOPUP_BUDGET_FRACTION,
} = require("./lib/budget");
const {verifyAndConsumePurchase} = require("./lib/playVerify");

admin.initializeApp();
const db = admin.firestore();

// ─── Secrets ────────────────────────────────────────────────────────────
// Declaring all five now even though only OPENAI_API_KEY is used by the
// routes below — Deepgram (speech-to-text/transcription), Replicate
// (image/video generation), Anthropic and DeepSeek (alternate text models)
// are wired up and ready for whichever feature you want to point at them
// next, without having to touch the deployment config again.
const openaiKey = defineSecret("OPENAI_API_KEY");
const anthropicKey = defineSecret("ANTHROPIC_API_KEY");
const deepseekKey = defineSecret("DEEPSEEK_API_KEY");
const replicateKey = defineSecret("REPLICATE_API_TOKEN");
const deepgramKey = defineSecret("DEEPGRAM_API_KEY");

const ALL_SECRETS = [openaiKey, anthropicKey, deepseekKey, replicateKey, deepgramKey];

// ─── Free-tier daily limits ─────────────────────────────────────────────
// Free users have no "price paid" to base a budget on, so they get a small
// flat daily allowance instead — cheap enough that it's not worth abusing,
// and a taste of the feature to convert to Pro.
//
// Premium users are NOT capped by a count here — they're capped by real
// dollars spent, at 30% of what they actually paid, via lib/budget.js. See
// the /getAICredits route for how remaining budget is reported to the app.
const LIMITS = {
  translateText: {free: 1},
  processRepurposeAction: {free: 0}, // Repurpose Studio is fully premium-gated
};

const app = express();
app.use(cors({origin: true}));
app.use(express.json({limit: "2mb"}));

// ─── Health check — no auth, for uptime monitoring ─────────────────────
app.get("/health", (req, res) => {
  res.json({status: "ok", time: new Date().toISOString()});
});

// ─── Premium status ─────────────────────────────────────────────────────
app.get("/verifyPremium", requireAuth, attachPremiumStatus, (req, res) => {
  res.json({isPremium: req.isPremium});
});

// ─── AI credit usage (today / this billing period) ──────────────────────
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
    const features = Object.keys(LIMITS);
    const used = {};
    for (const feature of features) {
      const doc = await db
        .collection("users")
        .doc(req.user.uid)
        .collection("aiCredits")
        .doc(`${feature}_${today}`)
        .get();
      used[feature] = doc.exists ? doc.data().count || 0 : 0;
    }
    const limits = {};
    for (const feature of features) {
      limits[feature] = LIMITS[feature].free;
    }
    res.json({date: today, used, limits, isPremium: false});
  } catch (e) {
    console.error("getAICredits error:", e);
    res.status(500).json({error: "Could not load AI credit usage"});
  }
});

// ─── Translate text (Smart Translator screen) ───────────────────────────
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
        const allowed = await checkAndConsumeCredit(req.user.uid, "translateText", LIMITS.translateText.free);
        if (!allowed) {
          return res.status(429).json({
            error: "Free daily translation limit reached — upgrade to Pro for more",
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
      }

      const budgetAfter = req.isPremium ? await hasBudgetRemaining(req.user.uid) : null;
      res.json({
        translatedText: translated,
        targetLanguage,
        remainingCredits: budgetAfter ? budgetAfter.remainingCredits : null,
      });
    } catch (e) {
      console.error("translateText error:", e);
      res.status(502).json({error: "Translation service error — please try again"});
    }
  },
);

// ─── Detect language ─────────────────────────────────────────────────────
// Free for everyone — tiny, near-zero-cost call (short reply, no real
// translation work), not worth metering separately.
app.post(
  "/detectLanguage",
  requireAuth,
  async (req, res) => {
    try {
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
      res.status(502).json({error: "Language detection service error"});
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
      const {actionId, videoTitle, platform} = req.body;
      if (!actionId || !SUPPORTED_ACTIONS.includes(actionId)) {
        return res.status(400).json({
          error: `Unsupported actionId. Supported: ${SUPPORTED_ACTIONS.join(", ")}`,
        });
      }

      // Repurpose Studio is a premium feature end-to-end.
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

      const {text: result, usage} = await runRepurposeAction(openaiKey.value(), actionId, {
        videoTitle,
        platform,
      });

      const spent = await recordSpend(req.user.uid, usage);
      const remainingUsd = Math.max(0, budget.remainingUsd - spent);

      res.json({
        result,
        remainingCredits: usdToCredits(remainingUsd),
      });
    } catch (e) {
      console.error("processRepurposeAction error:", e);
      res.status(502).json({error: "AI generation failed — please try again"});
    }
  },
);

// ─── Redeem a purchased credit pack ─────────────────────────────────────
// The client calls this right after a consumable purchase completes, with
// the real Play purchase token. This is the ONLY place credits get added
// to a top-up balance — everything here is designed so a person can't get
// credited without Google Play itself confirming a real purchase happened.
app.post("/redeemCreditPurchase", requireAuth, async (req, res) => {
  try {
    const {productId, purchaseToken} = req.body;
    if (!productId || !purchaseToken) {
      return res.status(400).json({error: "productId and purchaseToken are required"});
    }

    const pack = CREDIT_PACKS[productId];
    if (!pack) {
      return res.status(400).json({error: "Unknown credit pack productId"});
    }

    // Idempotency: the exact same purchase token can never be redeemed
    // twice, even if this endpoint gets called more than once for it (a
    // retry, a duplicate purchase-stream event on the client, etc.)
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

    // Same 30% rule as the subscription itself — what you actually charged
    // times 0.30 is what gets added to spend on AI, guaranteeing this
    // top-up can't be a worse deal for your margin than a subscription.
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

// ─── Library stats (AI Content Coach dashboard) ─────────────────────────
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

// ─── Analytics event logging ─────────────────────────────────────────────
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
    // Analytics failures should never break the app experience.
    res.json({success: false});
  }
});

// ─── Download logging (feeds getLibraryStats/getDownloadStats) ─────────
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

// ─── Not yet implemented — the client tolerates a 501 gracefully, but this
// is an honest placeholder, not a silent fake success. Come back to these
// once the ones above are live and stable. ───────────────────────────────
const notImplemented = (name) => (req, res) => {
  res.status(501).json({error: `${name} is not implemented on the server yet`});
};
app.post("/analyzeVideo", requireAuth, notImplemented("analyzeVideo"));
app.get("/getAnalyzedVideos", requireAuth, notImplemented("getAnalyzedVideos"));
app.get("/getLibraryStats2", requireAuth, notImplemented("getLibraryStats2"));
app.post("/suggestCollections", requireAuth, notImplemented("suggestCollections"));
app.get("/getCloudVaultFiles", requireAuth, notImplemented("getCloudVaultFiles"));
app.post("/deleteCloudFile", requireAuth, notImplemented("deleteCloudFile"));

exports.apiV1 = onRequest({secrets: ALL_SECRETS, region: "us-central1"}, app);