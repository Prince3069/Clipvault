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
// plausible-sounding output from a bare title every time.
//
// When no video analysis is available (no source URL, analysis failed,
// over the length cap), every prompt falls back to the exact same
// title-only behavior this file always had — never a hard failure, just
// a lower-quality result, same as before this feature existed.

const {chatComplete} = require("./openai");

/**
 * Detects machine-generated filenames (WhatsApp/Instagram/etc. auto-named
 * files like "whatsapp_1792091033341.mp4") that carry no semantic content.
 * When the title IS one of these, sending it to the AI is worse than
 * sending nothing — the AI ends up describing "a video titled
 * 'whatsapp_1792091033341'", which is where most of the "Repurpose output
 * feels generic/random" impression comes from on WhatsApp clips in
 * particular. Replacing it with "an untitled clip" plus a real transcript
 * summary (when analysis succeeded) is what actually fixes that.
 *
 * Returns the title as-is when it looks like a real human title.
 */
function cleanTitle(raw) {
  if (!raw) return "an untitled clip";
  const trimmed = String(raw).trim();
  if (trimmed.length === 0) return "an untitled clip";

  // Strip the file extension before matching
  const withoutExt = trimmed.replace(/\.[a-z0-9]{2,5}$/i, "");

  // Patterns: <platform>_<digits>, <platform>-<digits>, video_<digits>, etc.
  const looksMachine =
    /^(whatsapp|waba|wa|instagram|insta|tiktok|musically|facebook|fb|twitter|x|vimeo|dailymotion|reddit|snapchat|telegram|signal|download|video|image|clip|media|screenrecord)[\s_-]*\d{6,}$/i
      .test(withoutExt);

  if (looksMachine) return "an untitled clip";

  // All-digits filenames — also meaningless
  if (/^\d{6,}$/.test(withoutExt)) return "an untitled clip";

  return trimmed;
}

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

  // When the video was actually analyzed, produce a subtitle-track PREVIEW
  // — several short, timestamped lines derived from what is really said.
  // This is what "Subtitles" means to a user, and it's honest about being
  // a preview (real SRT timing would need the Whisper segment timings,
  // which this pipeline doesn't carry). When there's no transcript, this
  // falls back to a single opening-line hook, which is genuinely all that
  // can be produced without real speech — and the prompt says so.
  subtitle: (ctx) => {
    if (ctx.videoSummary) {
      return `Generate a short subtitle-track preview for this ${ctx.platform} ` +
        `video, based on what is actually said.${contentContext(ctx)} ` +
        `Output 5-7 numbered lines in this exact format: ` +
        `"00:00  <the actual line of dialogue>" — each line under 12 words, ` +
        `timestamps increasing by roughly 3 seconds starting at 00:00 ` +
        `(00:00, 00:03, 00:06, 00:09, …). Reply with ONLY those lines, ` +
        `nothing else — no intro text, no labels.`;
    }
    return `Write a single opening subtitle line (max 12 words) that could ` +
      `appear at the very start of a ${ctx.platform} video titled ` +
      `"${ctx.videoTitle}".${contentContext(ctx)} ` +
      `Reply with only the line. (No speech transcript was available for ` +
      `this video, so this is a hook/opener, not a full subtitle track.)`;
  },

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
  const title = cleanTitle(ctx.videoTitle);
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

module.exports = {runRepurposeAction, SUPPORTED_ACTIONS, cleanTitle};