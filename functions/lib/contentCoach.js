// lib/contentCoach.js
//
// Real challenge generation for AI Content Coach — replacing a static,
// finite, hardcoded pool of sample tasks that was identical for every
// user regardless of niche, and that ran out permanently once worked
// through. This generates one fresh challenge per day, from the
// person's actual niche and how far into their streak they are — not
// AI-generated before, at all; this is new, not a fix to something that
// silently called a stub.

const {chatComplete} = require("./openai");

/**
 * Scales difficulty language by streak length — early days build the
 * habit with small, achievable asks; a longer streak earns a harder,
 * more creative or strategic challenge. This is the "it's too easy and
 * never changes" fix: difficulty now actually has somewhere to go.
 */
function difficultyBand(streakDays) {
  if (streakDays < 3) return {label: "easy", guidance: "small and achievable in under 10 minutes"};
  if (streakDays < 10) return {label: "medium", guidance: "a real but approachable creative task"};
  return {label: "hard", guidance: "a genuinely challenging creative or strategic task that pushes them"};
}

/**
 * @returns {Promise<{title: string, description: string, difficulty: string, verifiable: boolean, verifyFeature: string|null, usage: object|null}>}
 */
async function generateDailyChallenge(apiKey, niche, streakDays) {
  const {label, guidance} = difficultyBand(streakDays);

  const {text, usage} = await chatComplete(apiKey, {
    system: "You write a single daily content-creator challenge. Reply with EXACTLY " +
      "three lines, nothing else: line 1 is a short title (under 8 words); line 2 is a " +
      "1-2 sentence description of exactly what to do; line 3 is ONE of these words only " +
      "— repurpose, translate, download, or none — naming which app feature this " +
      "challenge is actually completed through, or 'none' if it can't be verified by " +
      "an app action at all (e.g. a brainstorming or research task).",
    user: `Niche: ${niche}. Write a ${label} challenge (${guidance}) for someone in this niche.`,
    temperature: 0.8,
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
