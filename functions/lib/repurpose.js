// lib/repurpose.js
// Real implementations for the 7 action IDs repurpose_studio.dart sends:
// caption, hashtags, subtitle, translate, summarize, script, tweet_thread.
// Until this existed, every one of these silently fell back to a canned
// "offline mode" template in the app — this is what replaces that with
// actual AI output.

const {chatComplete} = require("./openai");

const PROMPTS = {
  caption: (ctx) =>
    `Write one punchy, scroll-stopping social media caption for a ${ctx.platform} ` +
    `video titled "${ctx.videoTitle}". Include 1-2 relevant emoji. Keep it under ` +
    `220 characters. Reply with only the caption text, nothing else.`,

  hashtags: (ctx) =>
    `Suggest 12 relevant, high-reach hashtags for a ${ctx.platform} video titled ` +
    `"${ctx.videoTitle}". Reply with only the hashtags separated by spaces, ` +
    `each starting with #, nothing else.`,

  subtitle: (ctx) =>
    `Write a short, natural-sounding subtitle line (max 12 words) that could open ` +
    `a ${ctx.platform} video titled "${ctx.videoTitle}". Reply with only the line.`,

  translate: (ctx) =>
    `Translate this video title into Spanish, French, and Portuguese, each on its ` +
    `own line prefixed with the language name: "${ctx.videoTitle}"`,

  summarize: (ctx) =>
    `Write a 2-sentence summary/description for a ${ctx.platform} video titled ` +
    `"${ctx.videoTitle}", written to make someone want to watch it.`,

  script: (ctx) =>
    `Write a short 3-beat video script outline (Hook / Body / Call-to-action, one ` +
    `line each) for a ${ctx.platform} video titled "${ctx.videoTitle}".`,

  tweet_thread: (ctx) =>
    `Write a 3-tweet thread (numbered 1/3, 2/3, 3/3) repurposing a ${ctx.platform} ` +
    `video titled "${ctx.videoTitle}" into a text thread. Keep each tweet under 260 characters.`,
};

const SUPPORTED_ACTIONS = Object.keys(PROMPTS);

/**
 * @param {string} apiKey OpenAI key
 * @param {string} actionId one of SUPPORTED_ACTIONS
 * @param {{videoTitle: string, platform: string}} ctx
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
    user: buildPrompt({videoTitle: title, platform}),
    temperature: 0.7,
  });
}

module.exports = {runRepurposeAction, SUPPORTED_ACTIONS};