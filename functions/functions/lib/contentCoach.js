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

/**
 * @param {string} apiKey
 * @param {string} niche
 * @param {number} streakDays
 * @param {object|null} activity  { topPlatform, platformCounts, otherPlatforms,
 *                                  totalDownloads, topRepurposeAction, repurposeCount }
 * @returns {Promise<{title, description, difficulty, verifiable, verifyFeature, usage}>}
 */
async function generateDailyChallenge(apiKey, niche, streakDays, activity = null) {
  const {label, guidance} = difficultyBand(streakDays);
  const activityLine = describeActivity(activity);

  const {text, usage} = await chatComplete(apiKey, {
    system: "You write a single daily content-creator challenge. Reply with EXACTLY " +
      "three lines, nothing else: line 1 is a short title (under 8 words); line 2 is a " +
      "1-2 sentence description of exactly what to do; line 3 is ONE of these words only " +
      "— repurpose, translate, download, or none — naming which app feature this " +
      "challenge is actually completed through, or 'none' if it can't be verified by " +
      "an app action at all (e.g. a brainstorming or research task).",
    user: `Niche: ${niche}. Write a ${label} challenge (${guidance}) for ` +
      `someone in this niche. ${activityLine}`.trim(),
    temperature: 0.85,
  });

  const lines = text.split("\n").map((l) => l.trim()).filter(Boolean);
  const verifyFeature = ["repurpose", "translate", "download"].includes(lines[2])
    ? lines[2]
    : null;

  return {
    title: lines[0] || "Today's challenge",
    description: lines[1] || "",
    difficulty: label,
    verifiable: verifyFeature !== null,
    verifyFeature,
    usage,
  };
}

module.exports = {generateDailyChallenge, difficultyBand};