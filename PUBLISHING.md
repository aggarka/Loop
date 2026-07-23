# Publishing Loop to the App Store

A step-by-step guide to submitting Loop for App Store review. Assets referenced
here are already generated in this repo:

- **App icon:** `Loop/Assets.xcassets/AppIcon.appiconset/` (light, dark, tinted 1024×1024)
- **Screenshots:** `screenshots/iphone-6.9/` (1320×2868) and `screenshots/ipad-13/` (2064×2752)
- **Legal/support pages:** `docs/` (host via GitHub Pages)
- **Icon sources:** `branding/*.svg`

> Prerequisite: a paid **Apple Developer Program** membership and admin access to
> **App Store Connect** (https://appstoreconnect.apple.com).

---

## 0. Before you start — replace placeholders

- [x] Support email set to `kamal_a@hotmail.com` in `docs/privacy.html`,
      `docs/terms.html`, and `docs/support.html`.
- [ ] Decide the public **App Name** ("Loop" may be taken on the App Store — have a
      backup like "Loop: Networking Follow-ups"). The name must be unique.
- [ ] Confirm the production Supabase project is live and the app's
      `Loop/Supabase-Info.plist` points at it. Run:
      ```bash
      ./scripts/verify-production.sh
      ```
      It reads the URL/key from the plist and checks auth, the `persons` table, the
      `ai-proxy` function, and enabled providers. (Free-tier Supabase projects pause
      after ~1 week idle — make sure it's not paused during App Review.)

---

## 1. Host the legal & support pages (GitHub Pages)

App Store Connect requires a **Support URL** and a **Privacy Policy URL**.

GitHub Pages is **live** for this repo (Settings → Pages → branch `main`, folder
`/docs`). Use these final URLs in App Store Connect:

- Landing: `https://aggarka.github.io/Loop/`
- Support: `https://aggarka.github.io/Loop/support.html`
- Privacy: `https://aggarka.github.io/Loop/privacy.html`
- Terms: `https://aggarka.github.io/Loop/terms.html`

---

## 2. Xcode project checks

1. Open `Loop.xcodeproj`, select the **Loop** target → **General**:
   - **Display Name:** Loop
   - **Version (Marketing):** 1.0.0
   - **Build:** 1
   - **Deployment target:** iOS 26.5 (or lower if you want broader device support)
   - **Supported destinations:** iPhone + iPad
2. **Signing & Capabilities:** Automatically manage signing, your team, and the
   **Sign in with Apple** capability present.
3. Confirm the app icon shows in the asset catalog (AppIcon).
4. **Production readiness** (recommended before release):
   - The DEBUG-only email sign-in is compiled out of Release builds (it's behind
     `#if DEBUG`) — verify by archiving in Release.
   - The `NSAllowsLocalNetworking` ATS exception in `Info.plist` is only needed for
     local development. Since the shipping app talks to the hosted HTTPS backend,
     consider removing it before release.

---

## 3. Register the App ID and create the app record

1. **Apple Developer → Identifiers:** ensure an App ID for bundle id `Kamal.Loop`
   exists with **Sign in with Apple** enabled (already configured for auth).
2. **App Store Connect → Apps → +  → New App:**
   - Platform: iOS
   - Name: your chosen app name
   - Primary language, Bundle ID: `Kamal.Loop`
   - SKU: any unique string (e.g., `loop-001`)
   - User access: Full.

---

## 4. Archive and upload the build

1. In Xcode, set the run destination to **Any iOS Device (arm64)**.
2. **Product → Archive.** Wait for the Organizer to open.
3. Select the archive → **Distribute App → App Store Connect → Upload.**
4. Keep the defaults (upload symbols, manage version/build automatically), sign with
   your team, and finish. The build appears in App Store Connect under
   **TestFlight / Build activity** after processing (a few minutes to ~an hour).

CLI alternative (optional):
```bash
xcodebuild -project Loop.xcodeproj -scheme Loop -configuration Release \
  -archivePath build/Loop.xcarchive archive
xcodebuild -exportArchive -archivePath build/Loop.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export
xcrun altool --upload-app -f build/export/Loop.ipa --type ios \
  --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
```

---

## 5. Complete the App Store listing

In App Store Connect → your app → the **1.0 version** page:

**App information**
- Subtitle (optional, 30 chars): e.g. "Remember every follow-up"
- Category: **Productivity** (secondary: Business)
- Support URL / Privacy Policy URL: the GitHub Pages URLs from step 1.

**Description** (suggested starting copy):
> Loop is your personal networking memory. Log every coffee chat, event, and intro
> the moment it happens, capture what you committed to, and let Loop surface clear,
> timely follow-ups so relationships never slip through the cracks.
>
> • People & interactions — a private record of everyone you meet
> • Next Actions — one feed of overdue and upcoming follow-ups
> • Reminders — local notifications so you never miss a follow-up
> • AI assistance — summarize notes, extract action items, and draft follow-ups,
>   with names and contact details removed on-device before any AI processing
> • Business card scanning & contacts import
> • Private sync across your iPhone and iPad
>
> Privacy-first: your data lives on your device and syncs privately to your account.

**Keywords** (100 chars, comma-separated): `networking,follow up,CRM,contacts,reminders,relationships,notes,coffee chat,intro`

**Promotional text** (optional, 170 chars): "Never forget a conversation or miss a follow-up again."

**Screenshots** — upload from this repo:
- iPhone 6.9" Display: `screenshots/iphone-6.9/01-NextActions.png` … `04-Settings.png`
- iPad 13" Display: `screenshots/ipad-13/01-NextActions.png` … `04-Settings.png`
- (Apple auto-scales 6.9" iPhone shots to smaller iPhone sizes; the 6.9" + 13" sets are sufficient.)

**Build:** select the build uploaded in step 4.

**General:** Copyright "2026 <your name>", set the age rating (Loop has no
objectionable content → likely 4+), and provide contact info.

---

## 5b. Content Rights (required to submit)

App Information → **Content Rights** → Set Up:
- Choose **"No, it does not contain, show, or access third-party content."**
  (Users enter their own data; AI-generated text is not third-party content.)

## 6. App Privacy ("nutrition label")

Under **App Privacy → Get Started**, declare data collection accurately:

- **Contact Info → Name, Email, Phone:** collected. Linked to the user's identity.
  Purpose: **App Functionality**. Not used for tracking. Not used for advertising.
- **User Content → Other (notes about contacts):** collected, linked, App
  Functionality, not for tracking.
- **Identifiers → User ID:** collected (account id), App Functionality.
- **Tracking:** **No** — Loop does not track users across apps/sites and has no
  third-party analytics or ad SDKs.

Notes for the reviewer about AI: the AI feature tokenizes personal identifiers
(names, companies, emails, phones) on-device before sending text to the AI provider,
and the endpoint is configured for no retention / no training.

---

## 7. Review notes & demo account (important)

Because the app requires sign-in, provide the reviewer a way in under
**App Review Information**:

- **Sign-in required:** Yes.
- **Demo account:** create a real account in the production app (Sign in with Apple,
  Google, or — if you keep an email path in the review build — email/password) and
  provide working credentials. If you only ship social sign-in, add clear notes that
  the reviewer can use their own Apple ID, and pre-seed a demo account they can use.
- **Notes:** "Loop is a personal networking tracker. Sign in, add a person, log an
  interaction with a follow-up date, and it appears under Next Actions. AI features
  redact personal identifiers on-device before processing."

**Guideline 4.8 (Sign in with Apple):** because Loop offers Google sign-in, Apple
requires **Sign in with Apple** to also be offered — it is. Keep it visible on the
sign-in screen.

---

## 8. Submit

1. Set **Version Release** (manual or automatic after approval).
2. Click **Add for Review → Submit.**
3. Watch status in App Store Connect; respond to any reviewer messages in Resolution
   Center. First reviews typically take a day or two.

---

## 9. Post-submission checklist

- [ ] Legal/support URLs live and correct.
- [ ] Screenshots uploaded for iPhone 6.9" and iPad 13".
- [ ] App Privacy answers match actual behavior.
- [ ] Demo credentials work from a clean device.
- [ ] Sign in with Apple visible and functional.
- [ ] Production Supabase project reachable; `ai-proxy` deployed; auth providers enabled.
- [ ] (Optional) `AI_PROVIDER_API_KEY` set on the hosted project for a live AI model.

---

## Regenerating assets

**App icon** (edit `branding/icon-*.svg`, then):
```bash
ICON_DIR="Loop/Assets.xcassets/AppIcon.appiconset"
rsvg-convert -w 1024 -h 1024 branding/icon-light.svg  -o "$ICON_DIR/AppIcon.png"
rsvg-convert -w 1024 -h 1024 branding/icon-dark.svg   -o "$ICON_DIR/AppIcon-Dark.png"
rsvg-convert -w 1024 -h 1024 branding/icon-tinted.svg -o "$ICON_DIR/AppIcon-Tinted.png"
python3 -c "from PIL import Image; import glob; [Image.open(p).convert('RGB').save(p) for p in glob.glob('$ICON_DIR/AppIcon*.png')]"
```

**Screenshots** (requires `supabase start`):
```bash
# clean status bar on the target sim, then:
xcodebuild test -project Loop.xcodeproj -scheme Loop \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -only-testing:LoopUITests/ScreenshotUITests
# then export attachments from the .xcresult (see repo history for the helper).
```
Note: `ScreenshotUITests` points at the **local** stack, so temporarily set
`Loop/Supabase-Info.plist` to the local URL/key while capturing, then restore the
hosted values.
