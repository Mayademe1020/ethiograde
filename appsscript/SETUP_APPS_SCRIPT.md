# Cloud Grading Setup (Google Apps Script)

Gemini reads handwriting far better than on-device OCR, but your `AIza...` key
must never ship inside the APK — anyone could unzip the app and spend your
quota. So the app posts the paper image to a small proxy instead, and the proxy
holds the key.

This proxy runs on **Google Apps Script**: free forever, no credit card, no
billing account. You paste the code into a browser editor and click Deploy.

> Firebase Cloud Functions was the original plan but it requires the Blaze
> (pay-as-you-go) plan, which needs a payment method Ethiopia cannot provide.
> Apps Script needs none of that.

---

## What you need

- The Gemini API key you already have (`AIza...`)
- A random 40-character hex string (the app's shared secret)
- About 10 minutes in a browser

---

## Step 1 — Create the script project

1. Open **https://script.google.com**
2. Click **New project**
3. Rename it to `EthioGrade Proxy` (click the "Untitled project" title)

---

## Step 2 — Paste the code

1. Delete everything in the editor
2. Open `appsscript/Code.gs` from this repo
3. Copy the whole file and paste it into the Apps Script editor

Your editor should show one file called `Code.gs` with roughly 700 lines.

---

## Step 3 — Add your two keys

1. Click the gear icon **Project Settings** (left sidebar, bottom)
2. Scroll to **Script Properties**
3. Click **Add script property** twice:

| Property | Value |
|----------|-------|
| `GEMINI_API_KEY` | your `AIza...` key |
| `APP_API_KEY` | your 40-char hex string |

To generate the hex string, run this in PowerShell:

```powershell
-join ((1..20) | ForEach-Object { '{0:x2}' -f (Get-Random -Max 256) })
```

---

## Step 4 — Verify the key works (recommended)

1. In the toolbar dropdown at the top, select the function **`testGemini`**
2. Click **Run**
3. Approve the permission prompt (Google will warn you the app is unverified — click **Advanced** → **Go to EthioGrade Proxy (unsafe)**)
4. Check the Execution log at the bottom:

```
OK: pong
```

If you see `FAILED: ...`, your `GEMINI_API_KEY` is wrong. Double-check it.

---

## Step 5 — Deploy

1. Click the blue **Deploy** button (top right)
2. Click **New deployment**
3. Click the gear next to "Select type" → **Web app**
4. Fill in:

| Field | Value |
|-------|-------|
| Description | `v1` |
| Execute as | **Me** |
| Who has access | **Anyone** |

5. Click **Deploy**
6. Copy the **Web app URL**

---

## Step 6 — Use the `googleusercontent` URL

The URL you copied looks like this:

```
https://script.google.com/macros/s/AKfycbXXXXXXXX/exec
                ^^^^^^^^^^^^^ REPLACE THIS PART ^^^^^^^^^^^^
```

Change `script.google.com` to `script.googleusercontent.com`:

```
https://script.googleusercontent.com/macros/s/AKfycbXXXXXXXX/exec
```

**This matters.** The `script.google.com` form issues a redirect that drops
the POST body, so scans would arrive empty. The `googleusercontent.com` form
serves the request directly.

---

## Step 7 — Configure the app

On each phone that needs cloud grading:

1. Open EthioGrade → **Settings**
2. Scroll to **Cloud OCR**
3. Set:

| Field | Value |
|-------|-------|
| Enable Cloud OCR | **on** |
| Endpoint | the `script.googleusercontent.com/.../exec` URL |
| App API Key | your 40-char hex string |
| AI Model | **Gemini 2.0 Flash** |

4. Tap **Usage & Cost** — it should show `0 scans` and a budget of `$10.00`.
   If it says "No data yet" and stays that way, the app cannot reach the
   proxy; re-check the endpoint and key.

---

## Test it

1. Create an assessment and fill in its answer key
2. Print the sheet, or just write answers on paper
3. Fill in a few answers in messy handwriting
4. Scan it

Cloud grading kicks in only when local OCR looks like handwriting, so the first
scan may still use ML Kit. Handwriting-heavy papers route to Gemini.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `App API key not set` in Settings | Endpoint or key blank | Re-enter both |
| Usage & Cost stuck on "No data yet" | Proxy unreachable | Check URL uses `googleusercontent.com`, no trailing slash |
| `Invalid API key` | `APP_API_KEY` mismatch | The phone value must match the script property exactly |
| `GEMINI_API_KEY script property is not set` | Property missing | Redo Step 3 |
| Scans return no answers | Old URL still in use | Switch to `googleusercontent.com` |
| "Exceeded rate limit" | Over 30 scans/minute | Wait a minute |
| Everything works on Wi-Fi, not mobile data | — | Expected: Apps Script is public, so mobile data works too. If it does not, check the phone's network. |

---

## Limits to be aware of

- **Rate limit:** 30 requests/minute
- **Execution:** 6 minutes per call, and Google allots roughly 90 min/day on
  consumer accounts. A scan costs ~3–8 s, so ~90 min covers roughly
  700–1,800 papers/day. Fine for a pilot; if you outgrow it, move the same
  handler to Cloudflare Workers (also free, 100k requests/day).
- **Offline:** with Cloud OCR off or unreachable, the app falls back to ML Kit
  automatically. Nothing breaks.

---

## Adding another model later

Edit the `MODELS` table at the top of `Code.gs`, add the model name, then
Deploy → **Manage deployments** → edit → **New version**. No app update needed.

To change the default budget, add a script property named `monthlyBudget`.