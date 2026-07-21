# Sweat2Scroll — App Store Connect Metadata
## Ready to paste field-by-field into App Store Connect

---

## 1. APP NAME  (30 chars max)
```
Sweat2Scroll
```

---

## 2. SUBTITLE  (30 chars max)
```
Earn Your Screen Time Daily
```

---

## 3. PROMOTIONAL TEXT  (170 chars max — shown at top, can change without resubmit)
```
Your social media is locked until you earn it. Hit your daily fitness goal — steps, calories, or workouts — and watch the apps unlock automatically.
```

---

## 4. DESCRIPTION  (4000 chars max)

```
Sweat2Scroll turns your daily fitness goal into the key that unlocks your social media.

Set a calorie, step, or workout target each morning. Until you hit it, Instagram, TikTok, Twitter, and any apps you choose stay locked by iOS Screen Time. No tricks, no shortcuts — just move your body and earn your scroll.

─── CORE FEATURES ───────────────────────────────

🔥  BURN TO EARN
Connect to Apple HealthKit and set a daily activity goal. The moment you cross the finish line — whether that's 300 calories burned, 8,000 steps walked, or 30 minutes of exercise — your selected apps unlock automatically.

🛡️  SCREEN TIME ENFORCEMENT
Powered by Apple's FamilyControls API, the shield cannot be dismissed from the lock screen or notification shade. It requires either goal completion or your accountability partner's Break-Glass code to lift.

👥  PARTNER ACCOUNTABILITY SYSTEM
Pair with a friend, coach, or family member. They don't see your screen — they hold your Break-Glass TOTP code for genuine emergencies. Every unlock event is logged to a cryptographically signed audit trail. No fake fitness. No cheating.

💚  WHOOP-STYLE WELLNESS DASHBOARD
Track Recovery Score, Day Strain, Sleep Score, and HRV — the same metrics professional athletes use — powered entirely by your Apple Watch and HealthKit. Know exactly how hard you pushed and how ready you are to do it again.

📊  OPA POLICY ENGINE ON-DEVICE
The unlock decision is enforced by Open Policy Agent compiled to WebAssembly and evaluated on-device. No server round-trips. No cloud dependency. Your fitness data never leaves your phone.

─── DASHBOARD TABS ──────────────────────────────

• Home — Daily activity ring, live goal progress, shield status, partner card
• Recovery — Recovery Score (0–100), HRV, Resting HR, component breakdown
• Strain — Day Strain (0–21 TRIMP scale), workout sessions, heart rate chart
• Sleep — Sleep Score, Deep/REM/Light stage breakdown, sleep history
• Heart — RMSSD, lnRMSSD, Respiratory Rate trends over 7 days
• Social — Partner leaderboard, activity feed, weekly challenges, applaud

─── PRIVACY FIRST ───────────────────────────────

• All health data stays in-memory — nothing written to disk beyond your goal settings
• ECDH P256 key exchange for partner pairing (no passwords)
• Break-Glass codes are TOTP (RFC 6238) — time-limited and single-use
• Audit log signed and stored in your private CloudKit container

─── RESEARCH BACKED ─────────────────────────────

Sweat2Scroll is based on published research: "Fitness-Contingent Screen Access Control Using OPA and WebAssembly on Mobile Edge Devices," presented at IEEE SoutheastCon 2026.

─── REQUIREMENTS ────────────────────────────────

• iPhone with iOS 16.0 or later
• Apple Watch recommended for HRV and sleep data
• HealthKit authorization required
• FamilyControls entitlement (Screen Time) required

Stop doom-scrolling. Start earning it.
```

---

## 5. KEYWORDS  (100 chars max — comma-separated, no spaces after commas)
```
screen time,fitness,healthkit,productivity,accountability,step counter,calories,digital wellness
```

---

## 6. SUPPORT URL
```
https://sweattoscroll.com/support.html
```
*(Live page with FAQ, v1.0 release notes, and support email coppersmith2222@gmail.com. Backup: https://github.com/Jag72/sweattoscroll/issues)*

---

## 7. MARKETING URL  (optional)
```
https://github.com/Jag72/sweattoscroll
```

---

## 8. VERSION  (matches your Xcode build)
```
1.0
```

---

## 9. COPYRIGHT
```
2026 Jagadish Krishna Pilla
```

---

## 10. PRIVACY POLICY URL  (REQUIRED — Apple will reject without this)
```
https://sweattoscroll.com/privacy.html
```
✅  Published — privacy.html is live on the site; PRIVACY.md mirror is in the repo root.

---

## 11. APP REVIEW NOTES  (for the Apple reviewer — very helpful to avoid rejection)
```
Dear Reviewer,

This app uses the FamilyControls API (Screen Time framework) to restrict app access
until a daily fitness goal is met via HealthKit.

TEST ACCOUNT: No login required for initial exploration.
Tap "Continue as Guest" on the landing screen to explore the dashboard with sample data.

KEY FLOWS:
1. Landing → Create Account → Onboarding (set goal, select apps to block)
2. Dashboard shows today's activity progress from HealthKit
3. Shield automatically disengages when the calorie/step goal is met
4. Break-Glass: tap "Break-Glass" → enter 6-digit TOTP code from partner

SIMULATOR NOTE: HealthKit returns mock data in Simulator. FamilyControls
shield enforcement requires a physical device with Screen Time enabled.

The FamilyControls entitlement was approved for this app. Bundle ID: com.jagadish.sweat2scroll

Thank you for your time.
```

---

## 12. RATING / AGE RATING  (select in App Store Connect)
```
4+ (No objectionable content)
```

---

## 13. CATEGORY
```
Primary:   Health & Fitness
Secondary: Productivity
```

---
---

# PRIVACY POLICY  (paste into GitHub as PRIVACY.md)

```markdown
# Privacy Policy — Sweat2Scroll

Last updated: March 28, 2026

## Data We Collect
Sweat2Scroll reads fitness data (steps, active calories, heart rate, HRV, sleep stages)
from Apple HealthKit solely to evaluate your daily activity goal. This data is processed
in-memory on your device and is never transmitted to any external server or third party.

## Data We Store
- Your goal settings (calorie/step target) are stored locally on your device.
- Your governance contract (partner pairing agreement) is stored in your private
  Apple CloudKit container, accessible only to you and your paired partner.
- Audit log events (shield toggles, Break-Glass usage) are stored in your private
  CloudKit container and are not accessible to us.

## Health Data
We do not sell, share, or disclose your health or fitness data.
We do not use health data for advertising or marketing.
Health data is accessed only with your explicit HealthKit authorization.

## Analytics
This app does not include any third-party analytics SDKs.

## Contact
For privacy questions and complaints: coppersmith2222@gmail.com
GitHub: https://github.com/Jag72/sweattoscroll
```
*(Superseded by the full policy in PRIVACY.md / https://sweattoscroll.com/privacy.html — use those.)*

---

# QUICK CHECKLIST — Before Clicking "Add for Review"

- [ ] All 5 screenshots uploaded (1284×2778 iPhone 6.7")
- [ ] Name, Subtitle, Description, Keywords filled in
- [ ] Support URL is live and reachable
- [ ] Privacy Policy URL is live and reachable (CRITICAL)
- [ ] App Review Notes filled in
- [ ] Age Rating questionnaire completed (4+)
- [ ] Category set to Health & Fitness
- [ ] Build uploaded from Xcode (Product → Archive → Distribute)
- [ ] Pricing set (Free recommended for v1.0 review)
- [ ] Copyright year and name correct
```
