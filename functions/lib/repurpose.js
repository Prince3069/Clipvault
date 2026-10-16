// lib/repurpose.js
// Real implementations for the 7 action IDs repurpose_studio.dart sends:
// caption, hashtags, subtitle, translate, summarize, script, tweet_thread.
//
// Every prompt below now takes an optional REAL content description —
// videoSummary and videoKeyPhrases, from lib/videoAnalysis.js's actual
// transcription of the video (see index.js's /processRepurposeAction) —
// instead of working from just a title and platform name. That was the
// actual root cause of "Repurpose generates random, unrelated content":
// the AI was never given anything real to describe; it was inventing
// plausible-sounding output from a bare title every time, which is
// exactly why it felt unrelated to the actual video.
//
// When no video analysis is available (no source URL, analysis failed,
// over the length cap), every prompt falls back to the exact same
// title-only behavior this file always had — never a hard failure, just
// a lower-quality result, same as before this feature existed.

const {chatComplete} = require("./openai");

/**
 * Builds the shared "what this video actually contains" block every
 * prompt below folds in when it's available. Centralized here so the
 * fallback behavior (nothing, when there's no real analysis) is defined
 * in exactly one place, not duplicated seven times.
 */
function contentContext(ctx) {
  if (!ctx.videoSummary) return "";
  const phrases = (ctx.videoKeyPhrases && ctx.videoKeyPhrases.length > 0)
    ? ` Key topics: ${ctx.videoKeyPhrases.join(", ")}.`
    : "";
  return ` The video is actually about: "${ctx.videoSummary}".${phrases}`;
}

const PROMPTS = {
  caption: (ctx) =>
    `Write one punchy, scroll-stopping social media caption for a ${ctx.platform} ` +
    `video titled "${ctx.videoTitle}".${contentContext(ctx)} Include 1-2 relevant ` +
    `emoji. Keep it under 220 characters. Reply with only the caption text, nothing else.`,

  hashtags: (ctx) =>
    `Suggest 12 relevant, high-reach hashtags for a ${ctx.platform} video titled ` +
    `"${ctx.videoTitle}".${contentContext(ctx)} Reply with only the hashtags ` +
    `separated by spaces, each starting with #, nothing else.`,

  subtitle: (ctx) =>
    `Write a short, natural-sounding subtitle line (max 12 words) that could open ` +
    `a ${ctx.platform} video titled "${ctx.videoTitle}".${contentContext(ctx)} ` +
    `Reply with only the line.`,

  // Deliberately unchanged — this translates the TITLE itself for
  // localization, a well-defined task on its own that doesn't need or
  // benefit from a content summary the same way the others do.
  translate: (ctx) =>
    `Translate this video title into Spanish, French, and Portuguese, each on its ` +
    `own line prefixed with the language name: "${ctx.videoTitle}"`,

  summarize: (ctx) =>
    ctx.videoSummary
      ? `Rewrite this into a punchy 2-sentence description for a ${ctx.platform} ` +
        `video, written to make someone want to watch it: "${ctx.videoSummary}"`
      : `Write a 2-sentence summary/description for a ${ctx.platform} video titled ` +
        `"${ctx.videoTitle}", written to make someone want to watch it.`,

  script: (ctx) =>
    `Write a short 3-beat video script outline (Hook / Body / Call-to-action, one ` +
    `line each) for a ${ctx.platform} video titled "${ctx.videoTitle}".${contentContext(ctx)}`,

  tweet_thread: (ctx) =>
    `Write a 3-tweet thread (numbered 1/3, 2/3, 3/3) repurposing a ${ctx.platform} ` +
    `video titled "${ctx.videoTitle}" into a text thread.${contentContext(ctx)} ` +
    `Keep each tweet under 260 characters.`,
};

const SUPPORTED_ACTIONS = Object.keys(PROMPTS);

/**
 * @param {string} apiKey OpenAI key
 * @param {string} actionId one of SUPPORTED_ACTIONS
 * @param {{videoTitle: string, platform: string, videoSummary?: string|null, videoKeyPhrases?: string[]|null}} ctx
 * @returns {Promise<{text: string, usage: object|null}>}
 */
async function runRepurposeAction(apiKey, actionId, ctx) {
  const buildPrompt = PROMPTS[actionId];
  if (!buildPrompt) {
    throw new Error(`Unsupported actionId: ${actionId}`);
  }
  const title = ctx.videoTitle && ctx.videoTitle.trim().length > 0
    ? ctx.videoTitle.trim()
    : "this clip";
  const platform = ctx.platform && ctx.platform !== "unknown" ? ctx.platform : "social media";

  return chatComplete(apiKey, {
    system: "You are a sharp, concise social media content assistant. Follow the " +
      "user's formatting instructions exactly and never add extra commentary.",
    user: buildPrompt({
      videoTitle: title,
      platform,
      videoSummary: ctx.videoSummary || null,
      videoKeyPhrases: ctx.videoKeyPhrases || null,
    }),
    temperature: 0.7,
  });
}

module.exports = {runRepurposeAction, SUPPORTED_ACTIONS};
