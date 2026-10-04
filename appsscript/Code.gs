/**
 * EthioGrade cloud grading proxy (Google Apps Script edition).
 *
 * Why this exists: the Gemini API key must never ship inside the APK, so the
 * app posts to this script instead. Apps Script runs on Google's servers for
 * free and needs no billing account or credit card.
 *
 * Request  (POST, JSON body):
 *   { "action": "gradeExam", "apiKey": "...", "data": { ... } }
 *   { "action": "getCosts",  "apiKey": "..." }
 * GET (query string):  ?action=getModels&apiKey=...
 *
 * Response:
 *   { "ok": true,  "result": { ... } }
 *   { "ok": false, "error": "...", "code": 401 }
 *
 * Apps Script cannot set HTTP status codes, so success/failure is carried in
 * the `ok` envelope. The Dart client (lib/services/smart_ocr_service.dart)
 * checks `ok` rather than the status line.
 *
 * The API key is read from Script Properties, never from this file:
 *   Project Settings -> Script Properties -> GEMINI_API_KEY
 */

const GEMINI_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models';

/**
 * Model aliases. These ids match the picker in settings_tab.dart so the Dart
 * side needs no change; only this table maps them to real model names.
 */
const MODELS = {
  gemini: {
    model: 'gemini-2.0-flash',
    displayName: 'Gemini 2.0 Flash',
    costPerCall: 0.00015,
    latencyMs: 3000,
    notes: 'Best accuracy, recommended',
  },
  'gemini-flash-lite': {
    model: 'gemini-2.0-flash-lite',
    displayName: 'Gemini 2.0 Flash Lite',
    costPerCall: 0.00005,
    latencyMs: 2000,
    notes: 'Cheaper, slightly lower accuracy',
  },
  'gemini-2.5-flash': {
    model: 'gemini-2.5-flash',
    displayName: 'Gemini 2.5 Flash',
    costPerCall: 0.0003,
    latencyMs: 3000,
    notes: 'Newer Gemini, strong handwriting reading',
  },
  openai: {
    model: 'gemini-2.5-flash',
    displayName: 'Gemini 2.5 Flash (OpenAI slot)',
    costPerCall: 0.0003,
    latencyMs: 3000,
    notes: 'Kept for backwards compatibility with older settings',
  },
  'openai-mini': {
    model: 'gemini-2.0-flash-lite',
    displayName: 'Flash Lite (OpenAI slot)',
    costPerCall: 0.00005,
    latencyMs: 2000,
    notes: 'Kept for backwards compatibility with older settings',
  },
};

const DEFAULT_MODEL = 'gemini';
const DEFAULT_MONTHLY_BUDGET = 10.0;
const RATE_LIMIT_PER_MINUTE = 30;

// Script property keys for cost tracking.
const P_REQUESTS = 'requests';
const P_COST = 'cost';
const P_PROVIDER_REQUESTS = 'providerRequests';
const P_PROVIDER_COST = 'providerCost';
const P_BUDGET = 'monthlyBudget';
const P_PERIOD = 'period';
const P_RATE = 'rateTimestamps';

// ---------------------------------------------------------------------------
// Entry points
// ---------------------------------------------------------------------------

function doGet(e) {
  return route_(e, 'GET');
}

function doPost(e) {
  return route_(e, 'POST');
}

/**
 * Single entry funnel. Never throws outward — every failure is returned as
 * `{ ok: false }` so the client always receives parseable JSON.
 */
function route_(e, method) {
  try {
    const req = readRequest_(e);
    const action = req.action || (req.data && req.data.action) || '';

    if (!action) {
      return json_({ ok: false, error: 'Missing action', code: 400 });
    }
    if (method === 'GET' && action !== 'getModels') {
      return json_({ ok: false, error: 'Use POST for ' + action, code: 405 });
    }

    if (action === 'getModels') return handleGetModels_();
    if (action === 'gradeExam') return handleGradeExam_(req);
    if (action === 'getCosts') return handleGetCosts_(req);
    if (action === 'getSchoolConfig') return handleGetConfig_(req);
    if (action === 'updateSchoolConfig') return handleUpdateConfig_(req);

    return json_({ ok: false, error: 'Unknown action: ' + action, code: 404 });
  } catch (err) {
    return json_({ ok: false, error: 'Server error: ' + err.message, code: 500 });
  }
}

// ---------------------------------------------------------------------------
// Request parsing
// ---------------------------------------------------------------------------

/**
 * Accepts a JSON POST body, form-encoded body, or GET query string and always
 * returns `{ action, apiKey, data }`.
 */
function readRequest_(e) {
  const query = (e && e.parameter) || {};
  let body = {};

  const post = e && e.postData;
  if (post && post.contents) {
    const raw = post.contents;
    if (post.type === 'application/json' || raw.charAt(0) === '{') {
      body = JSON.parse(raw);
    } else {
      // form-encoded fallback: parse into a flat map
      body = {};
      raw.split('&').forEach(function (pair) {
        if (!pair) return;
        const bits = pair.split('=');
        body[decodeURIComponent(bits[0])] =
          decodeURIComponent((bits[1] || '').replace(/\+/g, ' '));
      });
    }
  }

  return {
    action: body.action || query.action || '',
    apiKey: body.apiKey || query.apiKey || '',
    data: body.data || {},
  };
}

// ---------------------------------------------------------------------------
// Auth + rate limiting
// ---------------------------------------------------------------------------

/**
 * Apps Script web apps cannot read HTTP request headers, so the shared secret
 * travels in the JSON body instead of the X-Api-Key header.
 */
function authorize_(req) {
  const expected = PropertiesService.getScriptProperties()
    .getProperty('APP_API_KEY');
  if (!expected) {
    return 'Server auth not configured (set APP_API_KEY script property)';
  }
  if (!req.apiKey) return 'Missing apiKey in request body';
  if (req.apiKey !== expected) return 'Invalid API key';
  return null;
}

/**
 * Rolling 60-second window persisted in script properties. Lock-guarded so
 * concurrent scans cannot race past the cap.
 */
function rateLimitOk_() {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const props = PropertiesService.getScriptProperties();
    const now = Date.now();
    let stamps = parseJson_(props.getProperty(P_RATE), []);
    stamps = stamps.filter(function (t) {
      return now - t < 60000;
    });
    if (stamps.length >= RATE_LIMIT_PER_MINUTE) return false;
    stamps.push(now);
    props.setProperty(P_RATE, JSON.stringify(stamps));
    return true;
  } finally {
    lock.releaseLock();
  }
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

function handleGetModels_() {
  const models = [];
  Object.keys(MODELS).forEach(function (id) {
    const m = MODELS[id];
    models.push({
      name: id,
      displayName: m.displayName,
      isAvailable: true,
      costPer1k: m.costPerCall * 1000,
      latencyMs: m.latencyMs,
      notes: m.notes,
    });
  });
  return json_({ ok: true, result: { models: models, default: DEFAULT_MODEL } });
}

function handleGradeExam_(req) {
  const authError = authorize_(req);
  if (authError) return json_({ ok: false, error: authError, code: 401 });

  if (!rateLimitOk_()) {
    return json_({
      ok: false,
      error: 'Rate limit: ' + RATE_LIMIT_PER_MINUTE + ' requests/minute',
      code: 429,
    });
  }

  const data = req.data || {};
  const imageBase64 = stripDataUrl_(data.imageBase64);
  const answerKey = data.answerKey || {};
  const hasKey = Object.keys(answerKey).length > 0;
  const ocrOnly = data.ocrOnly === true || !hasKey;

  if (!imageBase64) {
    return json_({ ok: false, error: 'Missing image', code: 400 });
  }

  const geminiKey = PropertiesService.getScriptProperties()
    .getProperty('GEMINI_API_KEY');
  if (!geminiKey) {
    return json_({
      ok: false,
      error: 'GEMINI_API_KEY script property is not set',
      code: 500,
    });
  }

  const alias = MODELS[data.preferredModel]
    ? data.preferredModel
    : DEFAULT_MODEL;
  const chosen = MODELS[alias];

  const prompt = hasKey
    ? buildGradingPrompt_(answerKey, data.assessmentTitle)
    : buildTranscribePrompt_();
  const started = Date.now();

  let modelReply;
  try {
    modelReply = callGemini_({
      apiKey: geminiKey,
      model: chosen.model,
      prompt: prompt,
      imageBase64: imageBase64,
      mimeType: data.mimeType || 'image/jpeg',
    });
  } catch (err) {
    return json_({
      ok: false,
      error: 'Gemini call failed: ' + err.message,
      code: 502,
    });
  }

  const text = readGeminiText_(modelReply);
  if (!text) {
    return json_({ ok: false, error: 'Gemini returned no content', code: 502 });
  }

  let parsed;
  try {
    parsed = JSON.parse(extractJson_(text));
  } catch (err) {
    return json_({
      ok: false,
      error: 'Model returned invalid JSON',
      code: 502,
      raw: String(text).slice(0, 500),
    });
  }

  if (hasKey) normalizeGrading_(parsed, answerKey);
  else normalizeTranscription_(parsed);

  const latencyMs = Date.now() - started;
  recordUsage_(alias, chosen.costPerCall);

  return json_({
    ok: true,
    result: {
      results: parsed.results || [],
      overallScore: num_(parsed.overallScore),
      maxScore: num_(parsed.maxScore),
      confidence: num_(parsed.confidence),
      studentName: parsed.studentName || null,
      notes: parsed.notes || null,
      ocrOnly: ocrOnly,
      provider: alias,
      model: chosen.model,
      latencyMs: latencyMs,
    },
  });
}

function handleGetCosts_(req) {
  const authError = authorize_(req);
  if (authError) return json_({ ok: false, error: authError, code: 401 });

  const props = PropertiesService.getScriptProperties();
  const byProviderRequests = parseJson_(props.getProperty(P_PROVIDER_REQUESTS), {});
  const byProviderCost = parseJson_(props.getProperty(P_PROVIDER_COST), {});

  const byProvider = {};
  Object.keys(MODELS).forEach(function (id) {
    const reqs = num_(byProviderRequests[id]);
    const cost = num_(byProviderCost[id]);
    if (reqs > 0 || cost > 0) {
      byProvider[id] = { requests: reqs, cost: Math.round(cost * 10000) / 10000 };
    }
  });

  const period = currentPeriod_();

  return json_({
    ok: true,
    result: {
      totalRequests: num_(props.getProperty(P_REQUESTS)),
      totalCost: Math.round(num_(props.getProperty(P_COST)) * 10000) / 10000,
      monthlyBudget: num_(props.getProperty(P_BUDGET)) || DEFAULT_MONTHLY_BUDGET,
      period: period,
      byProvider: byProvider,
    },
  });
}

function handleGetConfig_(req) {
  const authError = authorize_(req);
  if (authError) return json_({ ok: false, error: authError, code: 401 });

  const props = PropertiesService.getScriptProperties();
  return json_({
    ok: true,
    result: {
      preferredModel: props.getProperty('preferredModel') || DEFAULT_MODEL,
      monthlyBudget:
        num_(props.getProperty(P_BUDGET)) || DEFAULT_MONTHLY_BUDGET,
      enableFallback: true,
    },
  });
}

function handleUpdateConfig_(req) {
  const authError = authorize_(req);
  if (authError) return json_({ ok: false, error: authError, code: 401 });

  const props = PropertiesService.getScriptProperties();
  const data = req.data || {};

  if (data.preferredModel && MODELS[data.preferredModel]) {
    props.setProperty('preferredModel', data.preferredModel);
  }
  if (data.monthlyBudget !== undefined && data.monthlyBudget !== null) {
    props.setProperty(P_BUDGET, String(data.monthlyBudget));
  }
  return json_({ ok: true, result: { success: true } });
}

// ---------------------------------------------------------------------------
// Gemini call
// ---------------------------------------------------------------------------

function callGemini_(opts) {
  const url =
    GEMINI_ENDPOINT +
    '/' +
    encodeURIComponent(opts.model) +
    ':generateContent?key=' +
    encodeURIComponent(opts.apiKey);

  const payload = {
    contents: [
      {
        role: 'user',
        parts: [
          { text: opts.prompt },
          {
            inlineData: {
              mimeType: opts.mimeType,
              data: opts.imageBase64,
            },
          },
        ],
      },
    ],
    generationConfig: {
      temperature: 0.1,
      maxOutputTokens: 4096,
      responseMimeType: 'application/json',
    },
  };

  const res = UrlFetchApp.fetch(url, {
    method: 'post',
    contentType: 'application/json',
    payload: JSON.stringify(payload),
    muteHttpExceptions: true,
  });

  const code = res.getResponseCode();
  const body = res.getContentText();
  if (code < 200 || code >= 300) {
    throw new Error('HTTP ' + code + ': ' + String(body).slice(0, 300));
  }
  return JSON.parse(body);
}

function readGeminiText_(reply) {
  const candidates = (reply && reply.candidates) || [];
  for (let i = 0; i < candidates.length; i++) {
    const parts =
      candidates[i] &&
      candidates[i].content &&
      candidates[i].content.parts;
    if (!parts) continue;
    let text = '';
    for (let j = 0; j < parts.length; j++) {
      if (parts[j].text) text += parts[j].text;
    }
    if (text) return text;
  }
  return null;
}

// ---------------------------------------------------------------------------
// Prompt
// ---------------------------------------------------------------------------

function buildGradingPrompt_(answerKey, assessmentTitle) {
  return (
    'You are an expert exam grader. Your task is to:\n' +
    '1. Read ALL handwritten and printed text from this exam paper image\n' +
    '2. Identify the student answer for each question\n' +
    '3. Compare each answer against the provided answer key\n' +
    '4. Score each question and provide the final result\n\n' +
    'ASSESSMENT: ' + (assessmentTitle || 'Exam') + '\n\n' +
    'ANSWER KEY (question number -> correct answer):\n' +
    JSON.stringify(answerKey, null, 2) + '\n\n' +
    'INSTRUCTIONS:\n' +
    '- Read the image carefully, including handwritten text in pencil or pen\n' +
    '- Handle messy handwriting, crossed-out answers, and corrections\n' +
    '- For MCQ: match the letter (A, B, C, D, E)\n' +
    '- For True/False: match True/False or T/F\n' +
    '- For short answers: match the exact text or equivalent meaning\n' +
    '- For matching: match the letter pairs\n' +
    '- Award partial credit when the answer key specifies points\n\n' +
    'RESPONSE FORMAT (JSON only, no other text):\n' +
    '{\n' +
    '  "results": [\n' +
    '    {\n' +
    '      "questionNumber": 1,\n' +
    '      "detectedAnswer": "what you read from the image",\n' +
    '      "correctAnswer": "the correct answer from the key",\n' +
    '      "isCorrect": true,\n' +
    '      "score": 2,\n' +
    '      "maxScore": 2,\n' +
    '      "confidence": 0.95,\n' +
    '      "notes": "optional explanation"\n' +
    '    }\n' +
    '  ],\n' +
    '  "overallScore": 18,\n' +
    '  "maxScore": 20,\n' +
    '  "confidence": 0.92,\n' +
    '  "studentName": "if visible on the paper",\n' +
    '  "notes": "any issues or observations"\n' +
    '}\n\n' +
    'RULES:\n' +
    '- Return ONLY valid JSON, no markdown fences, no commentary\n' +
    '- If you cannot read an answer, set confidence below 0.5 and explain in notes\n' +
    '- If a question is not visible on the paper, skip it in results\n' +
    '- overallScore must equal the sum of all question scores\n' +
    '- confidence is your overall confidence in the grading (0.0 to 1.0)'
  );
}

// ---------------------------------------------------------------------------
// Normalisation + usage accounting
// ---------------------------------------------------------------------------

/**
 * Reading-only prompt used when no answer key is available at the call site.
 * Produces the same `results` array shape so the client needs one code path.
 */
function buildTranscribePrompt_() {
  return (
    'You are an expert exam-paper reader. Transcribe every student answer you ' +
    'can see in this exam paper image.\n\n' +
    'INSTRUCTIONS:\n' +
    '- Read the image carefully, including handwritten text in pencil or pen\n' +
    '- Handle messy handwriting, crossed-out answers, and corrections\n' +
    '- For MCQ answers report the bare letter (A, B, C, D, E)\n' +
    '- For True/False report True or False\n' +
    '- For short answers report the text the student wrote, unedited\n' +
    '- Do NOT judge correctness and do NOT invent answers that are not visible\n' +
    '- If a question has no visible answer, omit it from results\n\n' +
    'RESPONSE FORMAT (JSON only, no other text):\n' +
    '{\n' +
    '  "results": [\n' +
    '    {\n' +
    '      "questionNumber": 1,\n' +
    '      "detectedAnswer": "exactly what the student wrote",\n' +
    '      "confidence": 0.95,\n' +
    '      "notes": "optional, e.g. ambiguous handwriting"\n' +
    '    }\n' +
    '  ],\n' +
    '  "confidence": 0.9,\n' +
    '  "studentName": "if visible on the paper",\n' +
    '  "notes": "any issues or observations"\n' +
    '}\n\n' +
    'RULES:\n' +
    '- Return ONLY valid JSON, no markdown fences, no commentary\n' +
    '- confidence must be below 0.5 when the handwriting is genuinely unclear'
  );
}

/**
 * Coerce model output into the exact field types the Dart client expects, and
 * fill in any answers the model omitted from the answer key.
 */
function normalizeGrading_(grading, answerKey) {
  const seen = {};

  grading.results = (grading.results || []).map(function (r) {
    const qNum = parseInt(r.questionNumber, 10);
    const keyEntry = answerKey[String(qNum)] || {};
    const maxScore =
      r.maxScore !== undefined && r.maxScore !== null
        ? num_(r.maxScore)
        : num_(keyEntry.points) || 1;
    const score = r.score !== undefined && r.score !== null
      ? Math.max(0, Math.min(num_(r.score), maxScore))
      : r.isCorrect
      ? maxScore
      : 0;

    const normalized = {
      questionNumber: isNaN(qNum) ? 0 : qNum,
      detectedAnswer: r.detectedAnswer === undefined ? '' : String(r.detectedAnswer),
      correctAnswer:
        r.correctAnswer || (keyEntry.correctAnswer ? String(keyEntry.correctAnswer) : ''),
      isCorrect: typeof r.isCorrect === 'boolean' ? r.isCorrect : score >= maxScore,
      score: score,
      maxScore: maxScore,
      confidence: clamp01_(r.confidence === undefined ? 0.5 : num_(r.confidence)),
      notes: r.notes ? String(r.notes).slice(0, 300) : null,
    };

    if (!isNaN(qNum)) seen[qNum] = true;
    return normalized;
  });

  // Questions in the key but missing from the model reply are unread, not wrong.
  Object.keys(answerKey).forEach(function (key) {
    const qNum = parseInt(key, 10);
    if (isNaN(qNum) || seen[qNum]) return;
    const points = num_(answerKey[key].points) || 1;
    grading.results.push({
      questionNumber: qNum,
      detectedAnswer: '',
      correctAnswer: answerKey[key].correctAnswer
        ? String(answerKey[key].correctAnswer)
        : '',
      isCorrect: false,
      score: 0,
      maxScore: points,
      confidence: 0,
      notes: 'Not detected on paper',
    });
  });

  grading.results.sort(function (a, b) {
    return a.questionNumber - b.questionNumber;
  });

  const computedMax = grading.results.reduce(function (sum, r) {
    return sum + r.maxScore;
  }, 0);
  const computedScore = grading.results.reduce(function (sum, r) {
    return sum + r.score;
  }, 0);

  grading.maxScore =
    grading.maxScore !== undefined && grading.maxScore !== null && num_(grading.maxScore) > 0
      ? num_(grading.maxScore)
      : computedMax;
  grading.overallScore =
    grading.overallScore !== undefined &&
    grading.overallScore !== null &&
    num_(grading.overallScore) > 0
      ? num_(grading.overallScore)
      : computedScore;
  grading.confidence = clamp01_(grading.confidence);
}

/**
 * Normalise an OCR-only reply: keep question number, detected answer and
 * confidence, and drop anything the model could not read. No scoring fields
 * are invented here — the local ScoringService owns grading.
 */
function normalizeTranscription_(parsed) {
  const kept = [];
  const seen = {};

  (parsed.results || []).forEach(function (r) {
    const qNum = parseInt(r.questionNumber, 10);
    if (isNaN(qNum) || qNum <= 0) return;
    if (seen[qNum]) return;

    const answer = r.detectedAnswer === undefined ? '' : String(r.detectedAnswer).trim();
    if (!answer) return;

    seen[qNum] = true;
    kept.push({
      questionNumber: qNum,
      detectedAnswer: answer,
      correctAnswer: '',
      isCorrect: false,
      score: 0,
      maxScore: 0,
      confidence: clamp01_(r.confidence === undefined ? 0.5 : r.confidence),
      notes: r.notes ? String(r.notes).slice(0, 300) : null,
    });
  });

  kept.sort(function (a, b) {
    return a.questionNumber - b.questionNumber;
  });

  parsed.results = kept;
  parsed.overallScore = 0;
  parsed.maxScore = 0;
  parsed.confidence = clamp01_(parsed.confidence);
}

/**
 * Increment request/cost counters. Resets automatically when the calendar
 * month changes, so the budget reflects a rolling monthly window.
 */
function recordUsage_(providerAlias, costPerCall) {
  const lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    const props = PropertiesService.getScriptProperties();
    const period = currentPeriod_();

    if (props.getProperty(P_PERIOD) !== period) {
      props.setProperty(P_PERIOD, period);
      props.setProperty(P_REQUESTS, '0');
      props.setProperty(P_COST, '0');
      props.setProperty(P_PROVIDER_REQUESTS, '{}');
      props.setProperty(P_PROVIDER_COST, '{}');
    }

    props.setProperty(P_REQUESTS, String(num_(props.getProperty(P_REQUESTS)) + 1));
    props.setProperty(
      P_COST,
      String(num_(props.getProperty(P_COST)) + costPerCall)
    );

    const providerRequests = parseJson_(props.getProperty(P_PROVIDER_REQUESTS), {});
    const providerCost = parseJson_(props.getProperty(P_PROVIDER_COST), {});
    providerRequests[providerAlias] = num_(providerRequests[providerAlias]) + 1;
    providerCost[providerAlias] = num_(providerCost[providerAlias]) + costPerCall;

    props.setProperty(P_PROVIDER_REQUESTS, JSON.stringify(providerRequests));
    props.setProperty(P_PROVIDER_COST, JSON.stringify(providerCost));
  } finally {
    lock.releaseLock();
  }
}

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

function json_(payload) {
  return ContentService.createTextOutput(JSON.stringify(payload)).setMimeType(
    ContentService.MimeType.JSON
  );
}

/** Strip a `data:image/jpeg;base64,` prefix if the caller included one. */
function stripDataUrl_(value) {
  if (!value) return '';
  const str = String(value);
  const comma = str.indexOf(',');
  return str.indexOf('base64,') === 5 || str.indexOf('base64,') === -1
    ? str.replace(/^data:[^;]+;base64,/, '')
    : comma > -1
    ? str.slice(comma + 1)
    : str;
}

/** Pull the outermost JSON object out of a possibly fenced reply. */
function extractJson_(text) {
  let out = String(text).trim();
  const fence = out.match(/^```(?:json)?\s*([\s\S]*?)\s*```$/);
  if (fence) out = fence[1].trim();
  return out;
}

function currentPeriod_() {
  const now = new Date();
  return now.getFullYear() + '-' + String(now.getMonth() + 1).padStart(2, '0');
}

function num_(value) {
  const n = parseFloat(value);
  return isNaN(n) ? 0 : n;
}

function clamp01_(value) {
  return Math.max(0, Math.min(1, num_(value)));
}

function parseJson_(raw, fallback) {
  if (!raw) return fallback;
  try {
    return JSON.parse(raw);
  } catch (err) {
    return fallback;
  }
}

/** Manual smoke test: run `testGemini` from the editor to verify the key. */
function testGemini() {
  const key = PropertiesService.getScriptProperties().getProperty('GEMINI_API_KEY');
  if (!key) return 'GEMINI_API_KEY is not set';
  try {
    const reply = callGemini_({
      apiKey: key,
      model: MODELS[DEFAULT_MODEL].model,
      prompt: 'Reply with the single word: pong',
      imageBase64: '',
      mimeType: 'image/jpeg',
    });
    return 'OK: ' + readGeminiText_(reply);
  } catch (err) {
    return 'FAILED: ' + err.message;
  }
}