// lib/repurpose.js
// Multi-variant + tone-aware Repurpose Studio prompts.
//
// Previously each action returned ONE string built from one prompt.
// This version returns THREE variants per call, each written with a
// distinct angle, and lets the client pass a tone modifier that is
// folded into the prompt. The point: users pick the caption that fits
// their voice, instead of being handed a single AI opinion and told
// to like it.

const {chatComplete} = require("./openai");

/**
 * Detects machine-generated filenames (WhatsApp/Instagram/etc. auto-named
 * files like "whatsapp_1792091033341.mp4") that carry no semantic content.
 * When the title IS one of these, sending it to the AI is worse than
 * sending nothing.
 */
function cleanTitle(raw) {
  if (!raw) return "an untitled clip";
  const trimmed = String(raw).trim();
  if (trimmed.length === 0) return "an untitled clip";

  const withoutExt = trimmed.replace(/\.[a-z0-9]{2,5}$/i, "");

  const looksMachine =
    /^(whatsapp|waba|wa|instagram|insta|tiktok|musically|facebook|fb|twitter|x|vimeo|dailymotion|reddit|snapchat|telegram|signal|download|video|image|clip|media|screenrecord)[\s_-]*\d{6,}$/i
      .test(withoutExt);

  if (looksMachine) return "an untitled clip";
  if (/^\d{6,}$/.test(withoutExt)) return "an untitled clip";

  return trimmed;
}

/** Maps a tone name to a directive the model will actually follow. */
const TONE_DIRECTIVES = {
  default: "",
  funny: "Tone: light, playful, and slightly funny. One tasteful joke is fine.",
  professional: "Tone: polished, credible, and professional — no slang, no emojis.",
  bold: "Tone: high-contrast and punchy. Short, confident sentences.",
  warm: "Tone: warm and personal, like talking to a friend — one gentle emoji OK.",
  punchy: "Tone: ultra-concise. Cut every word that isn't pulling weight.",
};

/** Formats the "what this video is about" context block. */
function contentContext(ctx) {
  if (!ctx.videoSummary) return "";
  const phrases = (ctx.videoKeyPhrases && ctx.videoKeyPhrases.length > 0)
    ? ` Key topics: ${ctx.videoKeyPhrases.join(", ")}.`
    : "";
  return ` The video is actually about: "${ctx.videoSummary}".${phrases}`;
}

/**
 * Per-action definition. Each builds a prompt that asks for THREE
 * variants on separate numbered lines. The variants are parsed back
 * out from the reply by the server before returning to the client.
 */
const PROMPTS = {
  caption: (ctx) =>
    `Write THREE different scroll-stopping social media captions for a ` +
    `${ctx.platform} video titled "${ctx.videoTitle}".${contentContext(ctx)} ` +
    `Each variant should take a DIFFERENT angle: one curiosity-driven, one ` +
    `value-driven, one emotional. Each under 220 characters. Include 1-2 ` +
    `relevant emoji per caption. Format your reply as exactly three lines, ` +
    `each starting with "1. ", "2. ", "3. " — nothing else on those lines.`,

  hashtags: (ctx) =>
    `Suggest THREE different sets of hashtags for a ${ctx.platform} video ` +
    `titled "${ctx.videoTitle}".${contentContext(ctx)} Each set has 10-12 ` +
    `hashtags. The three sets should differ in emphasis: (a) broad reach, ` +
    `(b) niche community, (c) trend-riding. Format your reply as exactly ` +
    `three lines, each starting with "1. ", "2. ", "3. ", with hashtags ` +
    `separated by spaces. No other text.`,

  subtitle: (ctx) => {
    if (ctx.videoSummary) {
      return `Generate THREE alternate subtitle-track previews for this ` +
        `${ctx.platform} video, all based on the same underlying content.` +
        `${contentContext(ctx)} Each preview is 4-5 short timestamped lines ` +
        `in the format "00:00  <line>" (timestamps rising by roughly 3 ` +
        `seconds). Variant 1: literal and faithful. Variant 2: punchy and ` +
        `condensed. Variant 3: warm and conversational. Format your reply ` +
        `as three blocks, each starting with "1. ", "2. ", "3. " on its ` +
        `first line. No other text.`;
    }
    return `Write THREE alternate opening subtitle lines (max 12 words each) ` +
      `for a ${ctx.platform} video titled "${ctx.videoTitle}".${contentContext(ctx)} ` +
      `Variant 1: curiosity hook. Variant 2: bold statement. Variant 3: ` +
      `question. Format your reply as exactly three lines, each starting ` +
      `with "1. ", "2. ", "3. ". No other text.`;
  },

  translate: (ctx) =>
    `Translate this title into three combinations, each on its own line: ` +
    `(1) Spanish + French, (2) Portuguese + Italian, (3) German + Dutch. ` +
    `Format as: "1. ES: <es> | FR: <fr>" then same for 2 and 3. Title: ` +
    `"${ctx.videoTitle}"`,

  summarize: (ctx) => {
    const subject = ctx.videoSummary
        ? `the following content: "${ctx.videoSummary}"`
        : `a ${ctx.platform} video titled "${ctx.videoTitle}"`;
    return `Write THREE different 2-sentence descriptions for ${subject}, ` +
      `each written to make someone want to watch it. Variant 1: ` +
      `story-driven. Variant 2: benefit-driven. Variant 3: question-driven. ` +
      `Format your reply as exactly three lines, each starting with ` +
      `"1. ", "2. ", "3. ". No other text.`;
  },

  script: (ctx) =>
    `Write THREE different short video script outlines (Hook / Body / ` +
    `Call-to-action, one line each) for a ${ctx.platform} video titled ` +
    `"${ctx.videoTitle}".${contentContext(ctx)} Variant 1: fast and ` +
    `energetic. Variant 2: thoughtful and narrative. Variant 3: ` +
    `teaching-focused. Format your reply as three blocks, each starting ` +
    `with "1. ", "2. ", "3. ". No other text.`,

  tweet_thread: (ctx) =>
    `Write THREE different 3-tweet threads (numbered 1/3, 2/3, 3/3) ` +
    `repurposing a ${ctx.platform} video titled "${ctx.videoTitle}" into ` +
    `text.${contentContext(ctx)} Variant 1: contrarian take. Variant 2: ` +
    `lesson-learned. Variant 3: story-driven. Each tweet under 260 chars. ` +
    `Format your reply as three blocks, each starting with "1. ", "2. ", ` +
    `"3. ". No other text.`,
};

const SUPPORTED_ACTIONS = Object.keys(PROMPTS);
const SUPPORTED_TONES = Object.keys(TONE_DIRECTIVES);

/**
 * Splits the model's reply into 3 variants. Handles the case where the
 * model returns numbered lines ("1. ", "2. ", "3. ") as well as the case
 * where it returns blocks separated by blank lines.
 */
function parseVariants(text) {
  if (!text) return [];

  // First try: numbered-line splitting. Matches "1. ", "1) ", "1 - " etc.
  const numbered = text
    .split(/\n(?=\s*\d\s*[.\-)]\s)/)
    .map((block) => block.replace(/^\s*\d\s*[.\-)]\s*/, "").trim())
    .filter((s) => s.length > 0);

  if (numbered.length >= 2) return numbered.slice(0, 3);

  // Fallback: blank-line-separated blocks.
  const blocks = text
    .split(/\n\s*\n/)
    .map((b) => b.trim())
    .filter((b) => b.length > 0);
  if (blocks.length >= 2) return blocks.slice(0, 3);

  // Last resort: return the whole thing as a single variant.
  return [text.trim()].filter((s) => s.length > 0);
}

/**
 * @param {string} apiKey OpenAI key
 * @param {string} actionId one of SUPPORTED_ACTIONS
 * @param {{videoTitle: string, platform: string, videoSummary?: string|null, videoKeyPhrases?: string[]|null, tone?: string|null}} ctx
 * @returns {Promise<{variants: string[], usage: object|null, tone: string}>}
 */
async function runRepurposeVariants(apiKey, actionId, ctx) {
  const buildPrompt = PROMPTS[actionId];
  if (!buildPrompt) throw new Error(`Unsupported actionId: ${actionId}`);

  const tone = typeof ctx.tone === "string" && SUPPORTED_TONES.includes(ctx.tone)
    ? ctx.tone
    : "default";

  const title = cleanTitle(ctx.videoTitle);
  const platform = ctx.platform && ctx.platform !== "unknown" ? ctx.platform : "social media";

  const baseUser = buildPrompt({
    videoTitle: title,
    platform,
    videoSummary: ctx.videoSummary || null,
    videoKeyPhrases: ctx.videoKeyPhrases || null,
  });

  const toneDirective = TONE_DIRECTIVES[tone];
  const user = toneDirective ? `${baseUser}\n\n${toneDirective}` : baseUser;

  // Slightly higher temperature than single-variant because we WANT the
  // three options to actually differ — a low-temperature model would
  // produce three near-identical outputs and defeat the point.
  const {text, usage} = await chatComplete(apiKey, {
    system: "You are a sharp, concise social media content assistant. Follow " +
      "the user's formatting instructions exactly and never add extra " +
      "commentary. When asked for three variants, produce three DISTINCT, " +
      "genuinely different options — not three rephrasings of the same idea.",
    user,
    temperature: 0.9,
  });

  return {
    variants: parseVariants(text),
    usage,
    tone,
  };
}

module.exports = {
  runRepurposeVariants,
  runRepurposeAction: async (apiKey, actionId, ctx) => {
    // Legacy single-variant path — kept so the old /processRepurposeAction
    // endpoint keeps working for any client that hasn't updated yet.
    const result = await runRepurposeVariants(apiKey, actionId, ctx);
    const combined = result.variants[0] || "";
    return {text: combined, usage: result.usage};
  },
  SUPPORTED_ACTIONS,
  SUPPORTED_TONES,
  cleanTitle,
};