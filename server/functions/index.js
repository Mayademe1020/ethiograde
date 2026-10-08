const { onRequest } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { ModelRegistry } = require("./model_registry");

initializeApp();

const registry = new ModelRegistry();

// Rate limiting: requests per key per minute
const rateLimitMap = new Map();

// ── Shared helpers ──

function cors(res) {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type, X-Api-Key");
}

function json(res, status, body) {
  res.set("Content-Type", "application/json");
  res.status(status).send(body);
}

function failure(res, message, extra = {}) {
  json(res, 400, { error: message, ...extra });
}

function checkConfig() {
  const env = {
    APP_API_KEY: process.env.APP_API_KEY,
    GEMINI_API_KEY: process.env.GEMINI_API_KEY,
    OPENAI_API_KEY: process.env.OPENAI_API_KEY,
  };
  registry.configure(env);
  return env;
}

/**
 * API-key auth. The app sends the key in the X-Api-Key header.
 * Teachers do nothing — the key ships with the app or is set in settings.
 */
function checkAuth(req) {
  const env = checkConfig();

  if (!env.APP_API_KEY) {
    return { error: "Server auth not configured (set APP_API_KEY secret)" };
  }

  const apiKey = req.get("X-Api-Key");
  if (!apiKey) {
    return { error: "Missing X-Api-Key header" };
  }
  if (apiKey !== env.APP_API_KEY) {
    return { error: "Invalid API key" };
  }

  return { apiKey };
}

/**
 * Rate limit: 30 requests/minute per key.
 */
function checkRateLimit(apiKey) {
  const now = Date.now();
  const requests = rateLimitMap.get(apiKey) || [];
  const recent = requests.filter((t) => now - t < 60000);

  if (recent.length >= 30) {
    return false;
  }

  recent.push(now);
  rateLimitMap.set(apiKey, recent);
  return true;
}

// ── Cloud Function: gradeExam ──
//
// POST { data: { imageBase64, answerKey, assessmentTitle, mimeType, preferredModel } }
// ←   { result: { results, overallScore, maxScore, confidence, provider } }
exports.gradeExam = onRequest(
  {
    region: "us-central1",
    timeoutSeconds: 120,
    memory: "256MB",
    maxInstances: 10,
  },
  async (req, res) => {
    cors(res);
    if (req.method === "OPTIONS") return res.status(204).send("");

    if (req.method !== "POST") {
      return failure(res, "POST only");
    }

    // 1. Auth
    const auth = checkAuth(req);
    if (auth.error) return failure(res, auth.error);
    const apiKey = auth.apiKey;

    // 2. Rate limiting
    if (!checkRateLimit(apiKey)) {
      return failure(res, "Rate limit: 30 requests/minute");
    }

    // 3. Input validation
    const data = req.body?.data;
    if (!data?.imageBase64 || !data?.answerKey) {
      return failure(res, "Missing image or answer key");
    }

    // 4. Load school config (preferred model, fallback)
    let preferredModel = data.preferredModel;
    let enableFallback = true;
    try {
      const doc = await getFirestore()
        .collection("school_configs")
        .doc(apiKey)
        .get();
      if (doc.exists) {
        const cfg = doc.data();
        preferredModel = preferredModel || cfg.preferredModel;
        enableFallback = cfg.enableFallback !== false;
      }
    } catch (e) {
      console.warn("Failed to load school config:", e.message);
    }

    // 5. Build grading prompt
    const prompt = buildGradingPrompt(data.answerKey, data.assessmentTitle);

    // 6. Call models with automatic fallback
    const started = Date.now();
    try {
      const result = await registry.process({
        imageBase64: data.imageBase64,
        prompt,
        mimeType: data.mimeType || "image/jpeg",
        preferredModel,
        enableFallback,
      });

      const latencyMs = Date.now() - started;

      // 7. Parse JSON response
      let grading;
      try {
        grading = JSON.parse(result.text);
      } catch (e) {
        return failure(res, "Model returned invalid JSON", {
          raw: String(result.text).slice(0, 500),
        });
      }

      // 8. Log to Firestore for cost tracking
      await logGrading(apiKey, data.assessmentTitle, grading, result.providerId, latencyMs);

      return json(res, 200, {
        result: { ...grading, provider: result.providerId },
      });
    } catch (e) {
      console.error("Grading failed:", e.message);
      return failure(res, "Grading failed: " + e.message);
    }
  }
);

// ── Cloud Function: getModels ──
//
// GET → { result: { models: [...], default } }
exports.getModels = onRequest(
  { region: "us-central1", timeoutSeconds: 10, memory: "128MB" },
  async (req, res) => {
    cors(res);
    if (req.method === "OPTIONS") return res.status(204).send("");

    const env = checkConfig();
    const models = registry.availableModels();
    const defaultModel =
      env.GEMINI_API_KEY
        ? "gemini"
        : env.OPENAI_API_KEY
          ? "openai"
          : null;

    return json(res, 200, { result: { models, default: defaultModel } });
  }
);

// ── Cloud Function: getCosts ──
//
// POST { data: {} } → { result: { totalRequests, totalCost, byProvider, monthlyBudget } }
exports.getCosts = onRequest(
  { region: "us-central1", timeoutSeconds: 10, memory: "128MB" },
  async (req, res) => {
    cors(res);
    if (req.method === "OPTIONS") return res.status(204).send("");

    const auth = checkAuth(req);
    if (auth.error) return failure(res, auth.error);

    try {
      const snapshot = await getFirestore()
        .collection("grading_logs")
        .where("apiKey", "==", auth.apiKey)
        .get();

      const { MODEL_REGISTRY } = require("./model_registry");
      let totalRequests = 0;
      let totalCost = 0;
      const byProvider = {};

      snapshot.forEach((doc) => {
        const d = doc.data();
        totalRequests++;

        const meta = MODEL_REGISTRY[d.provider];
        const cost = meta ? meta.costPer1k / 1000 : 0.00015;
        totalCost += cost;

        if (!byProvider[d.provider]) {
          byProvider[d.provider] = { requests: 0, cost: 0 };
        }
        byProvider[d.provider].requests++;
        byProvider[d.provider].cost += cost;
      });

      // Monthly budget from school config
      let monthlyBudget = 10.0;
      try {
        const cfgDoc = await getFirestore()
          .collection("school_configs")
          .doc(auth.apiKey)
          .get();
        if (cfgDoc.exists && cfgDoc.data().monthlyBudget) {
          monthlyBudget = cfgDoc.data().monthlyBudget;
        }
      } catch (e) {
        // Non-critical
      }

      return json(res, 200, {
        result: {
          totalRequests,
          totalCost: Math.round(totalCost * 10000) / 10000,
          byProvider,
          monthlyBudget,
          period: "all-time",
        },
      });
    } catch (e) {
      console.warn("Failed to get costs:", e.message);
      return failure(res, "Failed to get costs: " + e.message);
    }
  }
);

// ── Cloud Function: getSchoolConfig ──
exports.getSchoolConfig = onRequest(
  { region: "us-central1", timeoutSeconds: 10, memory: "128MB" },
  async (req, res) => {
    cors(res);
    if (req.method === "OPTIONS") return res.status(204).send("");

    const auth = checkAuth(req);
    if (auth.error) return failure(res, auth.error);

    try {
      const doc = await getFirestore()
        .collection("school_configs")
        .doc(auth.apiKey)
        .get();

      if (doc.exists) {
        return json(res, 200, { result: doc.data() });
      }

      return json(res, 200, {
        result: {
          preferredModel: "gemini",
          monthlyBudget: 10.0,
          enableFallback: true,
        },
      });
    } catch (e) {
      console.warn("Failed to get school config:", e.message);
      return failure(res, "Failed to get config");
    }
  }
);

// ── Cloud Function: updateSchoolConfig ──
exports.updateSchoolConfig = onRequest(
  { region: "us-central1", timeoutSeconds: 10, memory: "128MB" },
  async (req, res) => {
    cors(res);
    if (req.method === "OPTIONS") return res.status(204).send("");

    const auth = checkAuth(req);
    if (auth.error) return failure(res, auth.error);

    const data = req.body?.data || {};
    const { preferredModel, monthlyBudget, enableFallback } = data;

    try {
      await getFirestore()
        .collection("school_configs")
        .doc(auth.apiKey)
        .set(
          {
            preferredModel: preferredModel || "gemini",
            monthlyBudget: monthlyBudget || 10.0,
            enableFallback: enableFallback !== false,
            updatedAt: new Date(),
          },
          { merge: true }
        );

      return json(res, 200, { result: { success: true } });
    } catch (e) {
      console.warn("Failed to update school config:", e.message);
      return failure(res, "Failed to update config");
    }
  }
);

// ── Log grading to Firestore ──
async function logGrading(apiKey, assessmentTitle, result, provider, latencyMs) {
  try {
    await getFirestore().collection("grading_logs").add({
      apiKey,
      assessmentTitle,
      timestamp: new Date(),
      overallScore: result.overallScore,
      maxScore: result.maxScore,
      confidence: result.confidence,
      questionCount: result.results?.length || 0,
      provider,
      latencyMs,
    });
  } catch (e) {
    // Non-critical
    console.warn("Failed to log:", e.message);
  }
}

// ── Build the grading prompt ──
function buildGradingPrompt(answerKey, assessmentTitle) {
  return `You are an expert exam grader. Your task is to:
1. Read ALL handwritten and printed text from this exam paper image
2. Identify the student's answers for each question
3. Compare each answer against the provided answer key
4. Score each question and provide the final result

ASSESSMENT: ${assessmentTitle || "Exam"}

ANSWER KEY:
${JSON.stringify(answerKey, null, 2)}

INSTRUCTIONS:
- Read the image carefully, including handwritten text in pencil or pen
- Handle messy handwriting, crossed-out answers, and corrections
- For MCQ: match the letter (A, B, C, D, E)
- For True/False: match True/False or T/F
- For short answers: match the exact text or equivalent meaning
- For matching: match the letter pairs
- Award partial credit if applicable based on the answer key

RESPONSE FORMAT (JSON only, no other text):
{
  "results": [
    {
      "questionNumber": 1,
      "detectedAnswer": "what you read from the image",
      "correctAnswer": "the correct answer from the key",
      "isCorrect": true,
      "score": 2,
      "maxScore": 2,
      "confidence": 0.95,
      "notes": "optional explanation"
    }
  ],
  "overallScore": 18,
  "maxScore": 20,
  "confidence": 0.92,
  "studentName": "if visible on the paper",
  "notes": "any issues or observations"
}

RULES:
- Return ONLY valid JSON, no markdown, no explanation
- If you cannot read an answer, set confidence < 0.5 and explain in notes
- If a question is not visible on the paper, skip it in results
- Calculate overallScore as the sum of all question scores
- confidence is your overall confidence in the grading (0.0 to 1.0)`;
}
