// lib/contentCoach.js
// Real challenge generation for AI Content Coach.
//
// Previously this took only { niche, streakDays }. It now also takes the
// user's recent activity — which platforms they download from, what they
// repurpose most, and how often — so the challenge can reflect what the
// person ACTUALLY does, not just what niche they said they were in. A
// fitness creator who only downloads from TikTok gets a different
// challenge than one who only downloads from Instagram, even with the
// same niche and streak.

const {chatComplete} = require("./openai");

function difficultyBand(streakDays) {
  if (streakDays < 3) return {label: "easy", guidance: "small and achievable in under 10 minutes"};
  if (streakDays < 10) return {label: "medium", guidance: "a real but approachable creative task"};
  return {label: "hard", guidance: "a genuinely challenging creative or strategic task that pushes them"};
}

/**
 * Turns the raw aggregation numbers into a short natural-language
 * activity summary for the prompt. Deliberately humanized rather than
 * dumped as JSON — models follow prose much better than key-value pairs.
 */
function describeActivity(activity) {
  if (!activity) return "";

  const parts = [];

  if (activity.topPlatform) {
    const count = activity.platformCounts?.[activity.topPlatform] || 0;
    parts.push(`They mostly save from ${activity.topPlatform} (${count} recent saves)`);
  }
  if (Array.isArray(activity.otherPlatforms) && activity.otherPlatforms.length > 0) {
    parts.push(`also from ${activity.otherPlatforms.join(" and ")}`);
  }
  if (activity.totalDownloads && activity.totalDownloads > 0) {
    parts.push(`${activity.totalDownloads} downloads in the last 30 days`);
  }
  if (activity.topRepurposeAction) {
    parts.push(`their most-used Repurpose tool is "${activity.topRepurposeAction}"`);
  }
  if (activity.repurposeCount && activity.repurposeCount > 0) {
    parts.push(`${activity.repurposeCount} repurpose actions this month`);
  }

  if (parts.length === 0) return "";
  return `Their recent behavior: ${parts.join("; ")}.`;
}

function safeJson(text) {
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === "object" ? parsed : {};
  } catch (_) {
    return {};
  }
}

const str = (v, max) => (typeof v === "string" ? v.trim().slice(0, max) : "");

/** One-line description of who this creator is, for every coach prompt. */
function describeCreator(profile) {
  const p = profile || {};
  const parts = [`Niche: ${p.niche || "general content creation"}.`];
  if (p.goal) parts.push(`Main goal: ${p.goal}.`);
  if (p.experience) parts.push(`Experience level: ${p.experience}.`);
  return parts.join(" ");
}

/**
 * @param {string} apiKey
 * @param {{niche?: string, goal?: string, experience?: string}} profile
 * @param {number} streakDays
 * @param {object|null} activity  { topPlatform, platformCounts, otherPlatforms,
 *                                  totalDownloads, topRepurposeAction, repurposeCount }
 * @returns {Promise<{title, description, steps, tip, difficulty, verifiable, verifyFeature, usage}>}
 */
async function generateDailyChallenge(apiKey, profile, streakDays, activity = null) {
  // Older callers passed the niche as a plain string.
  const creator = typeof profile === "string" ? {niche: profile} : (profile || {});
  const {label, guidance} = difficultyBand(streakDays);
  const activityLine = describeActivity(activity);

  const {text, usage} = await chatComplete(apiKey, {
    system: "You write a single daily challenge for a social media content " +
      "creator. Reply with ONLY a JSON object with these keys: " +
      "\"title\" (under 8 words), \"description\" (1-2 sentences saying exactly " +
      "what to do), \"steps\" (array of 2-4 short concrete steps), \"tip\" (one " +
      "short practical tip), and \"feature\" — ONE of \"repurpose\", " +
      "\"translate\", \"download\" or \"none\": the app feature the challenge is " +
      "completed through, or \"none\" if it can't be verified by an app action " +
      "(e.g. brainstorming or filming).",
    user: `${describeCreator(creator)} Write a ${label} challenge (${guidance}) ` +
      `that moves them toward their goal. ${activityLine}`.trim(),
    temperature: 0.85,
    json: true,
  });

  const data = safeJson(text);
  const feature = str(data.feature, 20).toLowerCase();
  const verifyFeature = ["repurpose", "translate", "download"].includes(feature)
    ? feature
    : null;
  const steps = Array.isArray(data.steps)
    ? data.steps.map((x) => str(x, 160)).filter(Boolean).slice(0, 4)
    : [];

  return {
    title: str(data.title, 80) || "Today's challenge",
    description: str(data.description, 400),
    steps,
    tip: str(data.tip, 200) || null,
    difficulty: label,
    verifiable: verifyFeature !== null,
    verifyFeature,
    usage,
  };
}

/**
 * Personalised content ideas + coaching tips in ONE call.
 * @returns {Promise<{ideas: object[], tips: string[], usage: object|null}>}
 */
async function generateCoachIdeas(apiKey, profile, activity = null) {
  const activityLine = describeActivity(activity);
  const {text, usage} = await chatComplete(apiKey, {
    system: "You are a practical content strategist for social media creators. " +
      "Reply with ONLY a JSON object with two keys. \"ideas\": an array of " +
      "exactly 6 content ideas, each an object with \"title\" (under 7 words), " +
      "\"description\" (1 sentence, specific to the creator's niche), \"hook\" " +
      "(the opening line they could say or write), \"format\" (e.g. \"Reel\", " +
      "\"Carousel\", \"Short video\", \"Story\", \"Thread\") and \"difficulty\" " +
      "(\"easy\", \"medium\" or \"hard\"). \"tips\": an array of 3-4 short, " +
      "specific coaching tips based on their goal and recent behaviour. No " +
      "generic advice like \"post consistently\".",
    user: `${describeCreator(profile)} ${activityLine}`.trim(),
    temperature: 0.9,
    json: true,
  });

  const data = safeJson(text);
  const ideas = (Array.isArray(data.ideas) ? data.ideas : [])
    .map((i) => ({
      title: str(i && i.title, 80),
      description: str(i && i.description, 300),
      hook: str(i && i.hook, 200),
      format: str(i && i.format, 30) || "Post",
      difficulty: ["easy", "medium", "hard"].includes(str(i && i.difficulty, 10).toLowerCase())
        ? str(i.difficulty, 10).toLowerCase() : "easy",
    }))
    .filter((i) => i.title.length > 0)
    .slice(0, 8);
  const tips = (Array.isArray(data.tips) ? data.tips : [])
    .map((t) => str(t, 220)).filter(Boolean).slice(0, 5);

  return {ideas, tips, usage};
}

/**
 * A short learning path for this creator's goal and level.
 * @returns {Promise<{steps: object[], usage: object|null}>}
 */
async function generateCoachPlan(apiKey, profile) {
  const {text, usage} = await chatComplete(apiKey, {
    system: "You design a short, practical learning path for a social media " +
      "creator. Reply with ONLY a JSON object with one key \"steps\": an array " +
      "of exactly 5 steps ordered from first to last. Each step is an object " +
      "with \"title\" (under 7 words), \"description\" (1-2 sentences on what " +
      "they will learn and why it matters for their goal), \"action\" (one " +
      "concrete thing to do to finish the step) and \"minutes\" (a number, " +
      "5-60). Match the depth to their experience level.",
    user: describeCreator(profile),
    temperature: 0.7,
    json: true,
  });

  const data = safeJson(text);
  const steps = (Array.isArray(data.steps) ? data.steps : [])
    .map((x, i) => ({
      id: `step${i + 1}`,
      title: str(x && x.title, 80),
      description: str(x && x.description, 400),
      action: str(x && x.action, 300),
      minutes: Math.min(120, Math.max(5, Math.round(Number(x && x.minutes) || 15))),
    }))
    .filter((x) => x.title.length > 0)
    .slice(0, 6);

  return {steps, usage};
}

module.exports = {
  generateDailyChallenge,
  generateCoachIdeas,
  generateCoachPlan,
  difficultyBand,
};
