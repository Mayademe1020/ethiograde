# EthioGrade — Deployment Guide

## Prerequisites

- Node.js 18+
- Firebase CLI: `npm install -g firebase-tools`
- A Firebase project (free Spark plan is enough)
- A Gemini API key: https://aistudio.google.com/app/apikey

## 1. Firebase Setup

```bash
# Log into Firebase
firebase login

# In the project root (D:\ethiograde_fresh)
firebase init
#  → Select your project
#  → YES for Functions (do NOT host, storage, etc. — just Functions)
#  → JavaScript
#  → ESLint? No
#  → Overwrite? No
```

## 2. Set Secrets

The server needs three secrets:

```bash
# REQUIRED: Shared app key (the app uses this to authenticate)
firebase functions:secrets:set APP_API_KEY

# REQUIRED: At least one AI provider key
firebase functions:secrets:set GEMINI_API_KEY

# OPTIONAL: OpenAI as fallback (skip if using only Gemini)
# firebase functions:secrets:set OPENAI_API_KEY
```

**Generate the APP_API_KEY** (any random string works — teachers do nothing):

```bash
# On Linux/macOS:
openssl rand -hex 20

# On Windows (PowerShell):
-join ((1..20) | ForEach-Object { '{0:x2}' -f (Get-Random -Max 256) })
```

Save this key — you'll configure it in the app's Settings > Cloud OCR > App API Key.

## 3. Install Dependencies & Deploy

```bash
cd server/functions
npm install
cd ../..
firebase deploy --only functions
```

This deploys 5 functions to `us-central1`:

| Function | Endpoint |
|----------|----------|
| `gradeExam` | `https://us-central1-PROJECT.cloudfunctions.net/gradeExam` |
| `getModels` | `https://us-central1-PROJECT.cloudfunctions.net/getModels` |
| `getCosts` | `https://us-central1-PROJECT.cloudfunctions.net/getCosts` |
| `getSchoolConfig` | `https://us-central1-PROJECT.cloudfunctions.net/getSchoolConfig` |
| `updateSchoolConfig` | `https://us-central1-PROJECT.cloudfunctions.net/updateSchoolConfig` |

Replace `PROJECT` with your Firebase project ID.

## 4. Configure the App

On each teacher's device:

1. Open EthioGrade → Settings
2. Enable **Cloud OCR**
3. Set **Endpoint** to: `https://us-central1-PROJECT.cloudfunctions.net`
4. Set **App API Key** to the value of APP_API_KEY (given to you by your administrator)
5. Select **AI Model** (Gemini 2.0 Flash recommended)
6. Done — grading now uses cloud AI

## 5. How to Add a New Model Later

When a new AI provider (Claude, Mistral, etc.) becomes better/cheaper:

1. Add the provider in `server/functions/model_registry.js`:
   - Add an entry in `MODEL_REGISTRY` with name, model, cost
   - Add a `callNewProvider()` async function
   - Register it in `PROVIDER_BUILDERS`
   - Add its env var to `checkConfig()`

2. Set the API key:
   ```bash
   firebase functions:secrets:set NEW_PROVIDER_API_KEY
   ```

3. Redeploy:
   ```bash
   firebase deploy --only functions
   ```

4. Teachers can immediately select it in Settings > AI Model

No app updates required — the server abstraction handles it.

## 6. Cost Limits

Default monthly budget per school: $10.00

- Gemini 2.0 Flash: ~$0.15/1000 scans → **6,600 scans/month** on $1
- Gemini Flash Lite: ~$0.05/1000 scans → **20,000 scans/month** on $1

To change a school's budget, call `updateSchoolConfig` or edit Firestore directly:
```
Firestore → school_configs/{apiKey} → monthlyBudget: 20.00
```

## 7. Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| "Server auth not configured" | APP_API_KEY secret not set | `firebase functions:secrets:set APP_API_KEY` |
| "Invalid API key" | Wrong key in app | Check Settings > Cloud OCR > App API Key |
| "Missing X-Api-Key header" | App not sending auth | Enable Cloud OCR and set API Key in settings |
| "All models failed" | No AI provider keys | Set at least GEMINI_API_KEY |
| 429 / Rate limit | Too many requests | Wait 1 minute (limit: 30 req/min per key) |
| Timeout | Slow response | Check internet, retry |

## 8. Offline Mode

When there is no internet, the app automatically falls back to ML Kit (on-device):
- Printed text: ~95% accuracy
- Handwriting: ~50-65% accuracy
- No API cost

The fallback is automatic — teachers never need to toggle anything.
