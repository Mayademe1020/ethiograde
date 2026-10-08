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

## What teachers have to do: nothing

The proxy URL ships inside the app. A teacher flips one toggle and cloud
grading works. There is no API key to paste, no URL to copy, nothing to get
wrong.

The Gemini key lives only in your Script Properties and never reaches any
device.

### What actually protects your quota

Not a secret token — a hard budget ceiling plus rate limiting:

| Control | Where | Effect |
|---------|-------|--------|
| Gemini key isolation | Script Properties | Key never leaves Google's servers |
| Monthly budget ceiling | `monthlyBudget` script property | Proxy **refuses** to call Gemini once spend hits the limit |
| Per-IP rate limit | 30 req/min per caller | Bounds throughput regardless of client |

The budget ceiling is the real control: worst case spend is exactly the number
you set, not an open tab.

---

## What you need

- The Gemini API key you already have (`AIza...`)
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

Your editor should show one file called `Code.gs` of roughly 800 lines.

---

## Step 3 — Add your Gemini key

1. Click the gear icon **Project Settings** (left sidebar, bottom)
2. Scroll to **Script Properties**
3. Click **Add script property**:

| Property | Value |
|----------|-------|
| `GEMINI_API_KEY` | your `AIza...` key |

That is the only value you need to supply. There is no `APP_API_KEY` — the
proxy is intentionally unauthenticated.

### Optional: set your budget ceiling

Add a second script property to control your maximum monthly spend:

| Property | Value |
|----------|-------|
| `monthlyBudget` | e.g. `5` for $5/month |

Leave it unset and the default is `$10`. When tracked spend reaches this
number the proxy starts refusing grading instead of calling Gemini, so your
exposure is capped exactly here. The **Usage & Cost** tile in the app shows
progress against it.

---

## Step 4 — Verify the key works (recommended)

1. In the toolbar dropdown at the top, select the function **`testGemini`**
2. Click **Run**
3. Approve the permission prompt (Google warns the app is unverified — click **Advanced** → **Go to EthioGrade Proxy (unsafe)**)
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

## Step 7 — Put the URL in the app

Open `lib/config/cloud_grading_config.dart` and set two values:

```dart
static const String proxyUrl =
    'https://script.googleusercontent.com/macros/s/AKfycbXXXXXXXX/exec';

static const bool available = true;
```

Rebuild and reinstall the app. That is the last configuration step — the
proxy URL ships inside the build, so no teacher ever pastes anything.

On the phone, Settings → **Cloud Grading** now shows a working toggle, the
model picker, and a **Test Connection** row. Endpoint and model details sit
behind a collapsed **Advanced** section for troubleshooting only.

---

## Test it

1. Create an assessment and fill in its answer key
2. Fill in a few answers in messy handwriting on the sheet
3. Scan it

Cloud grading kicks in when local OCR looks like handwriting, so printed
answers may still use ML Kit. Handwriting-heavy papers route to Gemini.

Latency is ~3–8s per paper versus ~1s local. That is the trade for accuracy.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `Test Connection` reports unreachable | Bad or unset `proxyUrl` | Re-check Steps 6–7 |
| `Monthly cloud grading budget reached` | Ceiling hit | Raise `monthlyBudget`, or wait for next month. Counters reset automatically on the 1st |
| "Exceeded rate limit" | Over 30 scans/min from one IP | Wait a minute |
| Usage & Cost stuck on "No data yet" | Proxy unreachable | Re-check the URL |
| Scans return no answers | `script.google.com` URL still in use | Must be `googleusercontent.com` |
| `GEMINI_API_KEY script property is not set` | Property missing | Redo Step 3 |
| Handwriting still graded locally | Sheet reads as printed text | Expected — cloud only engages when ML Kit output looks like handwriting |

---

## Limits to be aware of

- **Rate limit:** 30 requests/minute per caller IP
- **Execution:** 6 minutes per call; Google allots roughly 90 min/day on
  consumer accounts. At 3–8s per paper that covers roughly 700–1,800
  papers/day. Fine for a pilot; outgrow it by moving the same handler to
  Cloudflare Workers (also free, 100k requests/day).
- **Offline:** with cloud disabled or unreachable, the app falls back to ML Kit
  automatically. Nothing breaks.

---

## Adding another model later

Edit the `MODELS` table at the top of `Code.gs`, add the model name, then
Deploy → **Manage deployments** → edit → **New version**. Add the matching id
to the picker in `lib/screens/home/settings_tab.dart` and rebuild the app.