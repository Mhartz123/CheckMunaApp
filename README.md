# CheckMuna

**A phone app for checking whether a medicine or health product is safe to sell and safe to buy.**

Point your phone at a product. CheckMuna reads the label, compares the product
name against the FDA Philippines advisory list of unregistered and flagged
health products, checks whether the item has expired or is missing an
ingredient list, and looks at the packaging for dents and scratches. You get a
plain verdict in a few seconds, and the scan is saved so you can look it up
again or print it in a report later.

Everything runs **on the phone itself**. The FDA list and both detection models
are bundled inside the app, so scanning works with no signal and no data
charges. An internet connection is only used to copy finished results to the
shared monitoring dashboard.

> CheckMuna is a screening aid, not an official ruling. It is designed to help
> pharmacy staff, inspectors and shoppers spot problems worth a second look —
> not to replace an FDA inspection. See [What CheckMuna can't do](#what-checkmuna-cant-do).

---

## Table of contents

- [Getting started](#getting-started)
- [The home screen](#the-home-screen)
- [Check 1 — Check Labels](#check-1--check-labels)
- [Check 2 — Damage Detection](#check-2--damage-detection)
- [Check 3 — Inspection Mode](#check-3--inspection-mode)
- [Saving your scan](#saving-your-scan)
- [Understanding your result](#understanding-your-result)
- [Records](#records)
- [Printing a report](#printing-a-report)
- [Taking good photos](#taking-good-photos)
- [What CheckMuna can't do](#what-checkmuna-cant-do)
- [Where your data goes](#where-your-data-goes)
- [Troubleshooting](#troubleshooting)
- [For developers](#for-developers)

---

## Getting started

**What you need:** an Android phone with a working rear camera.

1. Install the app (`.apk`) on the phone and open it.
2. Tap **Allow** when Android asks for camera access. CheckMuna cannot scan
   without it — this is the only permission it needs to work.
3. You'll see a short welcome screen. Tap **Get Started** to reach the home
   screen.

The app opens straight to the home screen on every launch after that.

---

## The home screen

The home screen has two tabs, switched from the bar floating at the bottom:

| Tab | What's there |
|---|---|
| **Homepage** | The three checks, photo tips, and your most recent scans |
| **Records** | Every scan you've saved, with search, filters and the report button |

On the Homepage you'll find three cards — the three ways to scan:

- **Check Labels** — reads the label only
- **Damage Detection** — looks at the packaging only
- **Inspection Mode** — does both in a single scan

There's also a **Photo tips** button (the `?` icon) you can open at any time,
and a **Recent scans** strip showing your last few results. Tap any of them to
open it in full.

Pick whichever check matches what you're worried about. If you're not sure, use
**Inspection Mode** — it covers everything.

---

## Check 1 — Check Labels

Use this when you want to know whether the product itself is registered, in
date, and properly labelled.

Tap **Check Labels**. The camera opens and asks for **three photos**, one at a
time. A white guide frame appears on screen — line the thing you're
photographing up inside it, then tap the shutter.

| Photo | What to frame |
|---|---|
| **1. Product name / label** | The product name, or the whole front of the label |
| **2. Expiration date** | Just the expiry / best-before date (the guide is a tighter box for this one) |
| **3. Ingredient list** | The ingredient list on the back or side |

**If something isn't printed on the pack,** don't photograph a blank space —
tap the checkbox instead:

- *No expiration date on the box*
- *No ingredient list on the box*

This tells the app the information is genuinely absent rather than just
missed by the camera, which is itself a compliance problem the app will flag.

**Useful while capturing:**

- Tap anywhere on the preview to refocus.
- Turn the phone sideways for wide packaging — the camera screen rotates so you
  can capture a wide box tilted.
- The counter at the top (`PHOTO 1 OF 3`) shows where you are.
- **Clear all** discards every photo and starts the scan over.
- Backing out asks *"Exit scan?"* first, so you can't lose photos by accident.

After the third photo the app analyses the scan. You'll see it work through:
*Extracting label text (OCR) → Matching FDA registry → Classifying label
result.*

---

## Check 2 — Damage Detection

Use this when the product's paperwork is fine but the packaging looks knocked
about — a crushed carton, a torn box, a scuffed corner.

**Step 1 — say what you're holding.** Tap **Damage Detection** and pick the
packaging type:

| Type | What it means | Status |
|---|---|---|
| **Box** | Anything in a cardboard carton, even if there's a bottle or foil inside | ✅ Fully working |
| **Foil** | Blister packs and sachets — tablets sealed into a sheet | ⏳ Coming soon |
| **Bottle** | Plastic or glass containers with a cap | ⏳ Coming soon |

Go by the **outside** of what you're holding. A blister pack inside a cardboard
carton is a **Box**. If you're still unsure, the *"Not sure which one?"* panel
on that screen walks through it.

Foil and Bottle can be photographed and saved today, but the app has no trained
detector for them yet — those scans come back as **Check unavailable** rather
than a damage verdict. Box is the one that gives a real answer.

**Step 2 — photograph four sides.** The camera asks for the whole item, filling
the frame, from four angles:

1. The **front**
2. **One side**
3. **The other side**
4. The **back**

No guide box this time — just fit the whole item in the frame. Hold it by the
edges so your fingers don't cover the damage you're trying to photograph.

The app then checks each photo for **dents** and **scratches**.

---

## Check 3 — Inspection Mode

The full check: the label inspection *and* the packaging inspection, saved as a
**single record** with one combined verdict.

Tap **Inspection Mode**, pick the packaging type, and the camera runs both
sequences back to back:

1. The three label close-ups (as in Check Labels)
2. A prompt — *"Label photos done — now photograph the [box]."*
3. The four packaging shots (as in Damage Detection)

Seven photos in total. You end up with one record, not two.

**How the two halves combine into one verdict:**

- A product name matching the FDA advisory list overrides everything — the
  result is **WARNING / BANNED**.
- Otherwise, if *either* the label check *or* the damage check fails, the
  result is **NON-COMPLIANT**.
- **COMPLIANT** only when everything passes.

---

## Saving your scan

Once the analysis finishes, the app asks you to name the record.

- Type a name you'll recognise later — a product name, a batch, a shelf.
  The example shown is `Loaf_of_bread`.
- Spaces become underscores automatically.
- **Names must be unique.** If you reuse one you'll see *"This name is already
  taken. Please choose another."*
- **A name cannot be changed after saving.** This is deliberate: results may
  already have been sent to the monitoring dashboard, and renaming would break
  the link between the two. Pick carefully, or delete and rescan.

You'll get a *Record "…" saved!* confirmation, then the result screen.

---

## Understanding your result

Every scan ends with one of three verdicts.

### 🟢 COMPLIANT

Nothing was flagged. The product name didn't match anything on the FDA advisory
list, the expiry date is still in the future, an ingredient list was found, and
(if you ran a damage check) the packaging looked intact.

### 🟠 NON-COMPLIANT

Something is wrong, but the product isn't on the FDA's flagged list. You'll see
one or more reasons:

| Reason | What it means |
|---|---|
| *Expired — the printed expiration date has passed* | The date read off the label is in the past |
| *No expiration date is printed on the packaging* | You confirmed no date is shown — required labelling is missing |
| *No ingredient list was detected on the label* | No ingredient list found, or you confirmed none is printed |
| *Packaging damage — …* | Dents or scratches were found on the packaging |

### 🔴 WARNING / BANNED

**The most serious result.** The product name matches an entry on the FDA
Philippines advisory list of unregistered or flagged health products. The app
shows the advisory number and category it matched, and tells you:

> *Product should not be sold or consumed. Report to the FDA hotline.*

The **Detection basis** line on the record shows exactly which product name
triggered the match, so you can check the call yourself.

### Reading the packaging result

Three different things the damage section can say — the difference matters:

| It says | It means |
|---|---|
| **No damage detected** | The check ran and the packaging looked fine |
| **Possible damage detected** | Dents and/or scratches were found — the specific findings are listed |
| **Check unavailable** | The check **could not run at all** — usually a Foil or Bottle scan, which has no detector yet |

**"Check unavailable" is not a clean result.** It means nothing was inspected.
Don't read it as "no damage found".

---

## Records

The **Records** tab holds every scan you've saved. Each card shows the name,
date, verdict badge and a thumbnail.

**Finding a scan:**

- **Search by name** — type into the search box
- **Filter** — All, Compliant, Non-Compliant, or WARNING / BANNED
- **Sort** — Name A→Z / Z→A, or Date Latest / Oldest

**Opening a scan:** tap **Inspect** on any card to see the full record — every
photo, the extracted label text, the reasons flagged, and the packaging
findings.

**Deleting:** use **Select All** / **Unselect All** to tick records, then
**Delete All**. Deleting asks you to confirm **twice** (*"Are you sure?"* then
*"Are you really sure?"*) because records cannot be recovered once removed.

---

## Printing a report

Tap **Generate Report** in the Records tab.

CheckMuna builds a **Product Compliance Summary Report** as a PDF covering all
saved records, with a label-check section and a packaging-damage section, and
opens Android's share and print sheet. From there you can print it, save it to
the phone, or send it on.

The file is named `CheckMuna_Compliance_Report_<timestamp>.pdf`.

---

## Taking good photos

Almost every disappointing result traces back to a photo the app couldn't read.
These are the same five tips as the in-app **Photo tips** sheet:

☀️ **Find good light.** A bright spot with no shadows falling across the packaging.

🔍 **Get close.** The packaging should fill most of the photo.

🧹 **Clear the background.** An empty table or counter works best.

✨ **Avoid shine.** Tilt shiny or foil packaging so light doesn't bounce back at
the camera.

✋ **Hold it by the edges,** so your fingers don't cover any damage.

One more: for the expiration photo, fill the guide box with **just the date**.
Including the surrounding text makes it harder to read correctly.

---

## What CheckMuna can't do

Being clear about the limits is part of using it well.

**The FDA list is a snapshot, not a live feed.** The advisory list — around
20,800 entries from the FDA Philippines *List of Unregistered Health Products* —
is bundled inside the app. It reflects the data as of the app's release and
only updates when the app itself is updated. A product added to the FDA list
after that won't be caught.

**Damage detection only covers cardboard boxes.** Foil and bottle scans return
*Check unavailable*. The detector recognises **dents** and **scratches** —
not tears, punctures, water damage, tampered seals or broken glass.

**It reads what the camera sees.** Text recognition can misread worn, curved,
glossy or handwritten labels. A misread expiry date can produce the wrong
verdict either way. If a result looks wrong, check the label yourself — the
record keeps the raw text it read so you can see where it went astray.

**Name matching is deliberately generous.** To cope with imperfect photos, the
app matches product names loosely rather than demanding a perfect character-for-
character match. That catches more genuine hits, but it can also flag an
unrelated product that happens to share common words with a flagged one. Always
read the **Detection basis** before acting on a WARNING / BANNED result.

**COMPLIANT is not certification.** It means *this app found nothing wrong in
what it checked*. It is not an FDA approval, and it says nothing about the
contents of the product, only its label and its packaging.

---

## Where your data goes

**On your phone.** Every scan is saved in the app's private storage, one folder
per record, containing the photos and a `data.json` with the result. Only
CheckMuna can read it. Uninstalling the app deletes all of it.

**To the dashboard.** When a scan is saved, its result is also sent to the
shared CheckMuna monitoring dashboard so results across devices can be reviewed
in one place. This includes the record name, verdict, reasons, the label text
that was read, the packaging findings, and one small photo (skipped if it's
over 200 KB).

Every saved scan is sent — clean ones too — because the dashboard needs passing
results to show a meaningful ratio against.

**If there's no connection, nothing is lost.** The scan is already saved on the
phone. A failed upload just means the dashboard misses that one row; the app
carries on without an error.

---

## Troubleshooting

**The camera doesn't open / stays black.**
Check that CheckMuna has camera permission in Android's app settings. Close and
reopen the app — the camera is released whenever you leave the scan screen.

**"Capture failed. Try again."**
Usually another app is holding the camera. Close any other camera app and
retry.

**A result says "Check unavailable" for damage.**
Expected for Foil and Bottle scans. If it appears for a Box scan, the detector
failed to load — restart the app; if it persists, the install may be incomplete.

**The expiry date came out wrong or blank.**
Retake the expiration photo with just the date filling the guide box, in good
light. If the pack genuinely has no date, tick *No expiration date on the box*
instead.

**A clearly fine product came back WARNING / BANNED.**
Open the record and read the **Detection basis** — it shows the flagged name it
matched. A weak or coincidental overlap means the app over-matched; treat it as
a prompt to check manually, not a ruling.

**My results aren't showing on the dashboard.**
The phone had no internet when the scan was saved. The record is safe on the
phone, but it won't retry the upload on its own.

**I can't rename a record.**
By design — see [Saving your scan](#saving-your-scan). Delete it and rescan if
the name matters.

---

## For developers

A Flutter (Android) app. Detection runs on-device through ONNX Runtime; text
recognition uses Google ML Kit.

```bash
flutter pub get
flutter run              # debug on a connected device
flutter build apk        # release build

flutter analyze
flutter test
```

**Layout**

```
lib/
  models/scan_record.dart      Record model — ScanKind, PackagingType, photo slots
  screens/                     Splash, home, dashboard, packaging picker, camera,
                               result, records, record detail, PDF report builder
  services/
    compliance_engine.dart     Verdict logic for all three flows
    fda_dataset_checker.dart   Word-overlap + fuzzy match against the advisory list
    onnx_semantic_matcher.dart Optional last-ditch name matcher (see below)
    damage_detection_service.dart  YOLOv8n inference: letterbox 640 → NMS
    packaging_damage_service.dart  Per-packaging-type detector registry
    label_parser.dart          Turns per-slot OCR into structured fields
    scan_store.dart            Folder-per-record local storage
    report_service.dart        Submits results to the dashboard
assets/                        FDA advisories, both ONNX models, tokenizer vocab
scripts/                       Rebuild the FDA and tokenizer assets from source
training/                      YOLOv8n Colab notebook for the damage detector
```

**Adding a damage detector for foil or bottle** — implement
`PackagingDamageDetector` and register it in the `_detectors` map in
`packaging_damage_service.dart`. The capture flow, picker UI and record storage
are already wired for all three types; nothing else needs to change.

**Known rough edges**

- `OnnxSemanticMatcher` (the fallback name matcher) ships with a model whose
  embeddings are collapsed — roughly 1% Recall@1 — so anything reaching that
  tier is likely to be mis-flagged. It only runs when name OCR confidence is
  below 0.6, and it can be switched off entirely via
  `ComplianceEngine._semanticMatcherEnabled`. Retrain and re-tune
  `_similarityFloor` before relying on it.
- The damage detector was trained on a small dataset (183 train / 15 val /
  9 test) — see `training/yolov8_damage_colab.ipynb`.
- The Android application ID and launcher label are still the scaffold defaults
  (`com.example.new_recover`, `thesis_tempname`), and the pubspec name is
  `ui_prototype`. Worth renaming before any real release.
- `ReportService._endpoint` is hardcoded. Point it at your own deployment if
  you're not using the existing one.

The dashboard that receives these results is a separate project — see the
`LabelCheck-Website` repo for its schema and the exact JSON contract.
