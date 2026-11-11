// lib/openai.js
// Thin wrapper around OpenAI's chat completions endpoint. Node 20's built-in
// fetch means no extra HTTP dependency is needed.

/**
 * @param {string} apiKey
 * @param {{system: string, user: string, temperature?: number, model?: string, json?: boolean}} opts
 *   json: true asks the model for a single JSON object (the prompt must
 *   mention JSON), which is far more reliable to parse than free text.
 * @returns {Promise<{text: string, usage: object|null}>} the model's reply
 *   plus the token usage OpenAI reports — usage is what budget.js needs to
 *   compute real cost, so every caller should hang onto it and pass it to
 *   recordSpend() after the call.
 */
async function chatComplete(apiKey, {system, user, temperature = 0.4, model = "gpt-4o-mini", json = false}) {
  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages: [
        {role: "system", content: system},
        {role: "user", content: user},
      ],
      temperature,
      ...(json ? {response_format: {type: "json_object"}} : {}),
    }),
  });

  if (!response.ok) {
    const errText = await response.text();
    throw new Error(`OpenAI error (${response.status}): ${errText}`);
  }

  const data = await response.json();
  return {
    text: data.choices?.[0]?.message?.content?.trim() || "",
    usage: data.usage || null,
  };
}

module.exports = {chatComplete};