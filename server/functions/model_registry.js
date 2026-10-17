/**
 * Model abstraction layer for cloud grading (Node.js).
 *
 * Any model provider implements the same interface. The registry tries
 * providers in order and falls back to the next one on failure.
 *
 * To add a new provider:
 * 1. Add a callXxx() function below
 * 2. Register it in MODEL_REGISTRY and PROVIDER_BUILDERS
 * 3. Set its API key via Firebase env config
 */

const { GoogleGenAI } = require("@google/genai");

// ── Available models ──
const MODEL_REGISTRY = {
  gemini: {
    api: "gemini",
    model: "gemini-2.0-flash",
    displayName: "Gemini 2.0 Flash",
    costPer1k: 0.15,
    latencyMs: 3000,
    notes: "Best accuracy, recommended default",
  },
  "gemini-flash-lite": {
    api: "gemini",
    model: "gemini-2.0-flash-lite",
    displayName: "Gemini 2.0 Flash Lite",
    costPer1k: 0.05,
    latencyMs: 2000,
    notes: "Cheaper, slightly lower accuracy",
  },
  openai: {
    api: "openai",
    model: "gpt-4o",
    displayName: "GPT-4o",
    costPer1k: 1.25,
    latencyMs: 4000,
    notes: "High accuracy, more expensive",
  },
  "openai-mini": {
    api: "openai",
    model: "gpt-4o-mini",
    displayName: "GPT-4o-mini",
    costPer1k: 0.05,
    latencyMs: 2000,
    notes: "Cheap alternative",
  },
};

// ── Gemini implementation ──
async function callGemini({
  apiKey,
  model,
  imageBase64,
  prompt,
  mimeType,
  temperature = 0.1,
  maxOutputTokens = 4096,
  timeoutSeconds = 50,
}) {
  const genAI = new GoogleGenAI({ apiKey });

  const parts = [{ text: prompt }];
  if (imageBase64) {
    parts.push({ inlineData: { mimeType, data: imageBase64 } });
  }

  const result = await withTimeout(
    genAI.models.generateContent({
      model,
      contents: [{ role: "user", parts }],
      config: {
        temperature,
        maxOutputTokens,
        responseMimeType: "application/json",
      },
    }),
    timeoutSeconds * 1000
  );

  const text = result.text;
  if (!text) throw new Error("No response from Gemini");

  return { text, model, api: "gemini" };
}

// ── OpenAI implementation ──
async function callOpenAi({
  apiKey,
  model,
  imageBase64,
  prompt,
  mimeType,
  temperature = 0.1,
  maxOutputTokens = 4096,
  timeoutSeconds = 50,
}) {
  const baseUrl = "https://api.openai.com/v1";

  const content = [];
  if (imageBase64) {
    content.push({
      type: "image_url",
      image_url: { url: `data:${mimeType};base64,${imageBase64}`, detail: "high" },
    });
  }
  content.push({ type: "text", text: prompt });

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutSeconds * 1000);

  try {
    const response = await fetch(`${baseUrl}/chat/completions`, {
      method: "POST",
      signal: controller.signal,
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        messages: [{ role: "user", content }],
        temperature,
        max_tokens: maxOutputTokens,
        response_format: { type: "json_object" },
      }),
    });

    if (!response.ok) {
      const body = await response.text();
      throw new Error(`HTTP ${response.statusCode || response.status}: ${body.slice(0, 200)}`);
    }

    const data = await response.json();
    const text = data.choices?.[0]?.message?.content;
    if (!text) throw new Error("No content in response");

    return { text, model, api: "openai" };
  } finally {
    clearTimeout(timer);
  }
}

// ── Provider builders ──
const PROVIDER_BUILDERS = {
  gemini: callGemini,
  openai: callOpenAi,
};

// ── ModelRegistry: resolves keys, runs fallback ──
class ModelRegistry {
  constructor() {
    // env config → { APP_API_KEY, GEMINI_API_KEY, OPENAI_API_KEY }
    this.env = {};
  }

  configure(env) {
    this.env = env || {};
  }

  /**
   * Resolve which model ids are usable given configured API keys.
   */
  availableModels() {
    const out = [];
    for (const [id, meta] of Object.entries(MODEL_REGISTRY)) {
      const apiKey = this.env[meta.api === "gemini" ? "GEMINI_API_KEY" : "OPENAI_API_KEY"];
      out.push({
        name: id,
        displayName: meta.displayName,
        isAvailable: Boolean(apiKey),
        costPer1k: meta.costPer1k,
        latencyMs: meta.latencyMs,
        notes: meta.notes,
      });
    }
    return out;
  }

  /**
   * Process with automatic fallback: preferred first (if given),
   * then everything else configured. Throws if all fail.
   */
  async process({
    imageBase64,
    prompt,
    mimeType = "image/jpeg",
    preferredModel,
    enableFallback = true,
  }) {
    const keys = {
      gemini: this.env.GEMINI_API_KEY,
      openai: this.env.OPENAI_API_KEY,
    };

    // Build candidate order: preferred first, then remaining available
    const usable = Object.entries(MODEL_REGISTRY).filter(([id, meta]) => {
      const key = keys[meta.api];
      return key && id !== preferredModel;
    });

    const ordered = [];
    if (preferredModel && MODEL_REGISTRY[preferredModel] && keys[MODEL_REGISTRY[preferredModel].api]) {
      ordered.push(preferredModel);
    }
    if (enableFallback !== false) {
      for (const [id] of usable) ordered.push(id);
    } else if (ordered.length === 0) {
      throw new Error("Preferred model unavailable and fallback disabled");
    }

    const errors = [];
    for (const id of ordered) {
      const meta = MODEL_REGISTRY[id];
      const apiKey = keys[meta.api];
      const builder = PROVIDER_BUILDERS[meta.api];

      try {
        const result = await builder({
          apiKey,
          model: meta.model,
          imageBase64,
          prompt,
          mimeType,
        });
        return { ...result, providerId: id };
      } catch (e) {
        errors.push(`${id}: ${e.message}`);
      }
    }

    throw new Error(`All models failed — ${errors.join("; ")}`);
  }
}

// ── Shared timeout helper ──
function withTimeout(promise, ms) {
  return Promise.race([
    promise,
    new Promise((_, reject) =>
      setTimeout(() => reject(new Error(`Timed out after ${ms}ms`)), ms)
    ),
  ]);
}

module.exports = { ModelRegistry, MODEL_REGISTRY, withTimeout };
