# Sweat2Scroll

> **Earn your screen time. Move first. Then scroll.**

Landing page for [sweattoscroll.com](https://sweattoscroll.com) — the upcoming iOS app that gates social media and screen time behind real physical activity, powered by HealthKit, Open Policy Agent, and WebAssembly.

---

## About the App

Sweat2Scroll is a fitness-contingent screen access control system for iOS. Instead of willpower, it uses policy enforcement: your phone stays locked to designated apps until you've hit your daily activity target. No fitness, no feed.

Built on:
- **Apple HealthKit** — reads real workout data (steps, active calories, heart rate)
- **Open Policy Agent (OPA) + WebAssembly** — evaluates access policy entirely on-device
- **FamilyControls API** — enforces app restrictions via Apple's official Screen Time framework
- **Swift / SwiftUI** — native iOS app

## Research Foundation

This app is based on a peer-reviewed research paper accepted and presented at **IEEE SoutheastCon 2026** (March 7, 2026):

> *Fitness-Contingent Screen Access Control Using Open Policy Agent and WebAssembly on Mobile Edge Devices*
> — Jagadish Krishna Pilla

Publication pending in IEEE Xplore.

---

## This Repository

This repo hosts the static landing page for `sweattoscroll.com`, served via **GitHub Pages**.

```
sweattoscroll/
└── index.html      # Landing page (single file, no dependencies)
└── README.md
```

### Local Development

No build step needed. Just open in a browser:

```bash
open index.html
```

Or serve locally:

```bash
python3 -m http.server 8080
# → http://localhost:8080
```

### Deploying Changes

Push to `main` — GitHub Pages auto-deploys within ~60 seconds.

```bash
git add index.html
git commit -m "Update landing page"
git push origin main
```

---

## Waitlist

The waitlist form submits to Google Forms. To configure:

1. Create a Google Form with a single **Short Answer** question titled "Email"
2. Get a pre-filled link → extract your `FORM_ID` and `ENTRY_ID`
3. In `index.html`, update:
   ```js
   const GOOGLE_FORM_ID  = 'YOUR_FORM_ID';
   const GOOGLE_ENTRY_ID = 'entry.000000000';
   ```

Responses are collected in a linked Google Sheet.

---

## Status

- [x] Landing page live
- [x] Waitlist form (Google Forms)
- [x] Custom domain (`sweattoscroll.com`)
- [ ] Google Form ID wired
- [ ] iOS app — SwiftUI scaffolding
- [ ] App Store submission

---

## License

All rights reserved © 2026 Jagadish Krishna Pilla. Research paper and app concept are original work presented at IEEE SoutheastCon 2026.
