// lib/videoAnalysis.js
//
// Real video content analysis — the missing piece Repurpose Studio needs
// so its captions/hashtags/summaries describe what is ACTUALLY in the
// video instead of being invented from a bare title.
//
// HOW THE VIDEO GETS HERE: the app uploads the video it already has on the
// phone to a private, per-user temporary Storage path
// (users/{uid}/analysis_temp/…); the server reads those bytes through the
// Admin SDK, transcribes them, and deletes the temp file. An earlier
// version of this file fetched an arbitrary URL sent by the client. That
// was wrong twice over: DownloadItem.url is the POST link the user pasted
// (an HTML page, not a video), and a server that fetches any URL a client
// names is an SSRF hole. Nothing here fetches a client-supplied URL.
//
// COST CONTROL (margin): Whisper bills per minute of audio. Duration is
// read from the file itself BEFORE any paid call, and anything over
// MAX_ANALYSIS_MINUTES is rejected for free. That makes the worst possible
// charge for one analysis exactly MAX_ANALYSIS_MINUTES × the per-minute
// price — the same number index.js uses as its up-front budget gate — so
// the gate and the real maximum spend can never disagree.

// Whisper API pricing — check https://openai.com/api/pricing before
// trusting this long-term (same caveat as openai.js).
const WHISPER_PRICE_PER_MINUTE_USD = 0.006;
const MAX_ANALYSIS_MINUTES = 10;
// A hair under Whisper's own 25MB request ceiling.
const MAX_VIDEO_BYTES = 24 * 1024 * 1024;

/**
 * Reads the duration (seconds) from an MP4/MOV/3GP/M4A container's 'mvhd'
 * box — free, no ffmpeg, no paid call. Returns null if it can't be read
 * (e.g. WebM/MKV), in which case the caller refuses to analyze rather
 * than risk an unbounded paid transcription.
 */
function readMp4DurationSeconds(buf) {
  const idx = buf.indexOf("mvhd");
  if (idx < 0 || idx + 36 > buf.length) return null;
  const version = buf[idx + 4];
  let timescale;
  let duration;
  if (version === 1) {
    timescale = buf.readUInt32BE(idx + 24);
    duration = Number(buf.readBigUInt64BE(idx + 28));
  } else {
    timescale = buf.readUInt32BE(idx + 16);
    duration = buf.readUInt32BE(idx + 20);
  }
  if (!timescale || !duration) return null;
  return duration / timescale;
}

/**
 * Transcribes video bytes with Whisper.
 * @returns {Promise<{transcript: string, durationMinutes: number}>}
 */
async function transcribeVideoBytes(apiKey, buffer) {
  if (buffer.length > MAX_VIDEO_BYTES) {
    throw Object.assign(new Error("Video is too large to analyze (24MB limit)"), {httpStatus: 413});
  }

  const parsedSeconds = readMp4DurationSeconds(buffer);
  if (parsedSeconds === null) {
    throw Object.assign(new Error("This video format can't be analyzed"), {httpStatus: 415});
  }
  if (parsedSeconds / 60 > MAX_ANALYSIS_MINUTES) {
    throw Object.assign(
      new Error(`Video is longer than the ${MAX_ANALYSIS_MINUTES}-minute analysis limit`),
      {httpStatus: 413},
    );
  }

  const form = new FormData();
  form.append("file", new Blob([buffer]), "video.mp4");
  form.append("model", "whisper-1");
  form.append("response_format", "verbose_json");

  const response = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: {"Authorization": `Bearer ${apiKey}`},
    body: form,
  });
  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`Whisper transcription failed (${response.status}): ${errText}`);
  }

  const data = await response.json();
  // Bill on the LARGER of the two durations — never undercharge your own
  // cost if the container header and Whisper disagree slightly.
  const billedSeconds = Math.max(data.duration || 0, parsedSeconds);
  return {transcript: data.text || "", durationMinutes: billedSeconds / 60};
}

/**
 * Turns a raw transcript into a short, structured content summary.
 * @returns {Promise<{summary: string, keyPhrases: string[], usage: object|null}>}
 */
async function summarizeTranscript(apiKey, transcript) {
  const {chatComplete} = require("./openai");

  if (!transcript || transcript.trim().length < 10) {
    // Music-only / no-speech clip: a valid outcome, not an error. Callers
    // fall back to title-only, same as before this feature existed.
    return {summary: "", keyPhrases: [], usage: null};
  }

  const {text, usage} = await chatComplete(apiKey, {
    system: "You extract the actual substance from a video transcript. Reply with " +
      "exactly two lines: line 1 is a 1-2 sentence summary of what's actually said " +
      "or happening; line 2 is 3-5 key phrases or topics, comma-separated. No other " +
      "text, no labels, no markdown.",
    user: transcript.slice(0, 6000),
    temperature: 0.3,
  });

  const lines = text.split("\n").map((l) => l.trim()).filter(Boolean);
  return {
    summary: lines[0] || "",
    keyPhrases: (lines[1] || "").split(",").map((p) => p.trim()).filter(Boolean),
    usage,
  };
}

module.exports = {
  transcribeVideoBytes,
  summarizeTranscript,
  readMp4DurationSeconds,
  WHISPER_PRICE_PER_MINUTE_USD,
  MAX_ANALYSIS_MINUTES,
  MAX_VIDEO_BYTES,
};
