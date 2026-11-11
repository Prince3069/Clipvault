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
 * Per-action definition. Each builds the task description; the shared
 * JSON output contract (three variants) is appended in
 * runRepurposeVariants, so no prompt has to describe formatting itself.
 */
const PROMPTS = {
  caption: (ctx) =>
    `Write THREE different scroll-stopping social media captions for a ` +
    `${ctx.platform} video${titlePart(ctx)}.${contentContext(ctx)} ` +
    `Each variant takes a DIFFERENT angle: one curiosity-driven, one ` +
    `value-driven, one emotional. Each under 220 characters, with 1-2 ` +
    `relevant emoji.`,

  hashtags: (ctx) =>
    `Suggest THREE different sets of hashtags for a ${ctx.platform} ` +
    `video${titlePart(ctx)}.${contentContext(ctx)} Each set has 10-12 ` +
    `hashtags separated by spaces. The sets differ in emphasis: (1) broad ` +
    `reach, (2) niche community, (3) trend-riding.`,

  // Only used when there is NO real transcript (see buildSubtitleVariants
  // for the transcript path, which needs no AI at all).
  subtitle: (ctx) =>
    `Write THREE alternate opening on-screen text lines (max 12 words ` +
    `each) for a ${ctx.platform} video${titlePart(ctx)}.` +
    `${contentContext(ctx)} Variant 1: curiosity hook. Variant 2: bold ` +
    `statement. Variant 3: question.`,

  translate: (ctx) => {
    const lang = ctx.targetLanguage || "Spanish";
    if (ctx.transcript) {
      return `Translate what is said in this video into ${lang}. Give THREE ` +
        `versions: (1) a faithful, complete translation; (2) a natural, ` +
        `localized translation that reads like a native speaker wrote it; ` +
        `(3) a short social caption in ${lang} (under 220 characters) that ` +
        `captures the main point. Everything must be written in ${lang}.\n\n` +
        `Transcript:\n"""${ctx.transcript.slice(0, 3500)}"""`;
    }
    return `Write THREE short social captions in ${lang} for a ` +
      `${ctx.platform} video${titlePart(ctx)}.${contentContext(ctx)} ` +
      `Variant 1: faithful and plain. Variant 2: casual and local-sounding. ` +
      `Variant 3: punchy with one emoji. Everything must be in ${lang}.`;
  },

  summarize: (ctx) => {
    const subject = ctx.videoSummary
        ? `the following content: "${ctx.videoSummary}"`
        : `a ${ctx.platform} video${titlePart(ctx)}`;
    return `Write THREE different 2-sentence descriptions for ${subject}, ` +
      `each written to make someone want to watch it. Variant 1: ` +
      `story-driven. Variant 2: benefit-driven. Variant 3: question-driven.`;
  },

  script: (ctx) =>
    `Write THREE different short video script outlines for a ` +
    `${ctx.platform} video${titlePart(ctx)}.${contentContext(ctx)} Each ` +
    `outline has three labelled lines: "Hook:", "Body:" and "CTA:". ` +
    `Variant 1: fast and energetic. Variant 2: thoughtful and narrative. ` +
    `Variant 3: teaching-focused.`,

  tweet_thread: (ctx) =>
    `Write THREE different 3-tweet threads repurposing a ${ctx.platform} ` +
    `video${titlePart(ctx)} into text.${contentContext(ctx)} Inside each ` +
    `thread, label the tweets "1/3", "2/3", "3/3" on separate lines; each ` +
    `tweet under 260 characters. Variant 1: contrarian take. Variant 2: ` +
    `lesson-learned. Variant 3: story-driven.`,
};

/** ` titled "X"` — or nothing when the title is a meaningless filename. */
function titlePart(ctx) {
  return ctx.hasRealTitle ? ` titled "${ctx.videoTitle}"` : "";
}

const SUPPORTED_ACTIONS = Object.keys(PROMPTS);
const SUPPORTED_TONES = Object.keys(TONE_DIRECTIVES);

function srtTime(seconds) {
  const ms = Math.max(0, Math.round(seconds * 1000));
  const h = String(Math.floor(ms / 3600000)).padStart(2, "0");
  const m = String(Math.floor((ms % 3600000) / 60000)).padStart(2, "0");
  const sec = String(Math.floor((ms % 60000) / 1000)).padStart(2, "0");
  const milli = String(ms % 1000).padStart(3, "0");
  return `${h}:${m}:${sec},${milli}`;
}

function clockTime(seconds) {
  const total = Math.max(0, Math.floor(seconds));
  const m = String(Math.floor(total / 60)).padStart(2, "0");
  const sec = String(total % 60).padStart(2, "0");
  return `${m}:${sec}`;
}

/**
 * Real subtitles from the real Whisper segments — no AI call, no
 * invention. Returns three formats of the same track: a ready-to-use
 * .srt, a readable timestamped list, and the plain transcript.
 */
function buildSubtitleVariants(segments, transcript) {
  if (!Array.isArray(segments) || segments.length === 0) return [];
  const srt = segments.map((seg, i) =>
    `${i + 1}\n${srtTime(seg.start)} --> ${srtTime(Math.max(seg.end, seg.start + 0.5))}\n${seg.text}`,
  ).join("\n\n");
  const timed = segments.map((seg) => `${clockTime(seg.start)}  ${seg.text}`).join("\n");
  const plain = (transcript || segments.map((seg) => seg.text).join(" ")).trim();
  return [srt, timed, plain].filter((v) => v.length > 0);
}

/**
 * Pulls the three variants out of the model's reply. The reply is asked
 * for as JSON ({"variants": [...]}); the numbered-line and blank-line
 * fallbacks only matter if the model ignores that.
 */
function parseVariants(text) {
  if (!text) return [];

  try {
    const parsed = JSON.parse(text);
    const list = Array.isArray(parsed) ? parsed : parsed.variants;
    if (Array.isArray(list)) {
      const cleaned = list
        .map((v) => (typeof v === "string" ? v : (v && (v.text || v.content)) || ""))
        .map((v) => String(v).trim())
        .filter((v) => v.length > 0);
      if (cleaned.length > 0) return cleaned.slice(0, 3);
    }
  } catch (_) {
    // fall through to the text fallbacks
  }

  const numbered = text
    .split(/\n(?=\s*\d\s*[.\-)]\s)/)
    .map((block) => block.replace(/^\s*\d\s*[.\-)]\s*/, "").trim())
    .filter((s) => s.length > 0);
  if (numbered.length >= 2) return numbered.slice(0, 3);

  const blocks = text
    .split(/\n\s*\n/)
    .map((b) => b.trim())
    .filter((b) => b.length > 0);
  if (blocks.length >= 2) return blocks.slice(0, 3);

  return [text.trim()].filter((s) => s.length > 0);
}

/**
 * @param {string} apiKey OpenAI key
 * @param {string} actionId one of SUPPORTED_ACTIONS
 * @param {{videoTitle: string, platform: string, videoSummary?: string|null,
 *   videoKeyPhrases?: string[]|null, transcript?: string|null,
 *   segments?: object[]|null, targetLanguage?: string|null,
 *   tone?: string|null}} ctx
 * @returns {Promise<{variants: string[], usage: object|null, tone: string, usedTranscript: boolean}>}
 */
async function runRepurposeVariants(apiKey, actionId, ctx) {
  const buildPrompt = PROMPTS[actionId];
  if (!buildPrompt) throw new Error(`Unsupported actionId: ${actionId}`);

  const tone = typeof ctx.tone === "string" && SUPPORTED_TONES.includes(ctx.tone)
    ? ctx.tone
    : "default";

  // Subtitles with a real transcript are assembled directly — free,
  // instant, and exactly what was said.
  if (actionId === "subtitle") {
    const real = buildSubtitleVariants(ctx.segments, ctx.transcript);
    if (real.length > 0) {
      return {variants: real, usage: null, tone, usedTranscript: true};
    }
  }

  const title = cleanTitle(ctx.videoTitle);
  const platform = ctx.platform && ctx.platform !== "unknown" ? ctx.platform : "social media";
  const transcript = typeof ctx.transcript === "string" && ctx.transcript.trim().length >= 10
    ? ctx.transcript.trim()
    : null;

  const baseUser = buildPrompt({
    videoTitle: title,
    hasRealTitle: title !== "an untitled clip",
    platform,
    videoSummary: ctx.videoSummary || null,
    videoKeyPhrases: ctx.videoKeyPhrases || null,
    transcript,
    targetLanguage: ctx.targetLanguage || null,
  });

  const toneDirective = TONE_DIRECTIVES[tone];
  const user = (toneDirective ? `${baseUser}\n\n${toneDirective}` : baseUser) +
    `\n\nReturn ONLY a JSON object of the form {"variants": ["...", "...", "..."]} ` +
    `with exactly three strings. Use \\n for line breaks inside a variant.`;

  // Slightly higher temperature than single-variant because we WANT the
  // three options to actually differ.
  const {text, usage} = await chatComplete(apiKey, {
    system: "You are a sharp, concise social media content assistant. Follow " +
      "the user's instructions exactly and never add extra commentary. When " +
      "asked for three variants, produce three DISTINCT, genuinely different " +
      "options — not three rephrasings of the same idea. Never invent facts " +
      "about the video that were not given to you. You always answer in JSON.",
    user,
    temperature: actionId === "translate" ? 0.4 : 0.9,
    json: true,
  });

  return {
    variants: parseVariants(text),
    usage,
    tone,
    usedTranscript: !!(transcript || ctx.videoSummary),
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
  buildSubtitleVariants,
  parseVariants,
  SUPPORTED_ACTIONS,
  SUPPORTED_TONES,
  cleanTitle,
};
