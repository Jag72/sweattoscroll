# Sweat2Scroll — App Store Metadata

## App Information

| Field | Value |
|-------|-------|
| **App Name** | Sweat2Scroll |
| **Subtitle** | Earn your scroll time. |
| **Bundle ID** | com.jagadishkrishna.sweattoscroll |
| **SKU** | SWEAT2SCROLL-001 |
| **Primary Language** | English (U.S.) |
| **Category** | Health & Fitness |
| **Secondary Category** | Productivity |

---

## Description (4000 char max)

```
Sweat2Scroll is the only fitness app that locks your social media until you actually earn it.

Set a daily calorie burn goal. Connect your Apple Health data. The moment you hit your target — steps, active calories, or workout minutes — your apps unlock. Until then, the shield stays up.

NO MORE DOOM-SCROLLING BEFORE YOU'VE MOVED.

HOW IT WORKS
• Set your daily fitness goal (steps, active calories, or workout minutes)
• Choose which apps stay locked (Instagram, TikTok, Twitter, YouTube — your call)
• Hit your goal → apps unlock automatically for the rest of the day
• Miss your goal → shield stays active until you've earned your access

POWERED BY REAL DATA
Sweat2Scroll reads directly from Apple Health — no manual entry, no cheating. Steps, active calories, heart rate, and workout sessions are all tracked in real time. The Open Policy Agent (OPA) engine evaluates your activity against your goal every 15 minutes.

FEATURES
• Progress Ring — see your real-time calorie burn toward your daily goal
• Recovery Score — HRV, resting heart rate, and 7-day trend
• Strain Tracking — daily strain score, heart rate zones, activity breakdown
• Sleep Performance — efficiency, sleep stages, and sleep debt
• Social Leaderboard — compete with friends and accountability partners
• Partner Mode — pair with a friend to see each other's progress
• Streak Counter — track your consecutive days of hitting your goal

PRIVACY FIRST
Your health data never leaves your device. Sweat2Scroll never stores workout data to disk — all processing happens in memory using Apple's HealthKit framework.

REQUIREMENTS
• iPhone running iOS 16 or later
• Apple Health app installed and authorized
• Screen Time / Family Controls permissions

Built by Jagadish Krishna Pilla. Presented at IEEE SoutheastCon 2026.

"Fitness-Contingent Screen Access Control Using OPA and WebAssembly on Mobile Edge Devices"
```

---

## Keywords (100 char max, comma-separated)

```
fitness,screen time,social media lock,health goals,calorie tracker,digital wellbeing,step counter
```

---

## What's New (Version 1.0)

```
Initial release of Sweat2Scroll.

Set your daily fitness goal, earn your screen time, and build real consistency — one sweat session at a time.
```

---

## App Store URLs

| Field | Value |
|-------|-------|
| **Support URL** | https://github.com/Jag72/sweattoscroll |
| **Marketing URL** | https://github.com/Jag72/sweattoscroll |
| **Privacy Policy URL** | https://github.com/Jag72/sweattoscroll/blob/main/PRIVACY.md |

> ⚠️ You need a real Privacy Policy URL before submitting. Use the GitHub page or create one at app-privacy-policy-generator.firebaseapp.com

---

## Age Rating

Answer these in App Store Connect under Age Rating:

| Question | Answer |
|----------|--------|
| Cartoon or Fantasy Violence | None |
| Realistic Violence | None |
| Sexual Content or Nudity | None |
| Profanity or Crude Humor | None |
| Medical/Treatment Information | None |
| Alcohol, Tobacco, or Drug Use | None |
| Gambling | None |
| Contests | None |
| Social Networking | Yes — users can add partners |
| User Generated Content | No |

**Result: 4+**

---

## Screenshots Ready ✅

All 5 screenshots at **1284×2778px** (iPhone 14 Pro Max / 6.7") are in the `screenshots/` folder:

| File | Screen |
|------|--------|
| `screenshot_01_home.png` | Home — Progress ring + Shield banner |
| `screenshot_02_recovery.png` | Recovery — HRV gauge + 7-day trend |
| `screenshot_03_strain.png` | Strain — Daily strain + HR zones |
| `screenshot_04_social.png` | Social — Leaderboard + activity feed |
| `screenshot_05_hero.png` | Hero — 82% ring + feature highlights |

---

## Submission Checklist

- [ ] Archive built in Xcode (Product → Archive)
- [ ] Upload to App Store Connect via Xcode Organizer or Transporter
- [ ] Fill in metadata above in App Store Connect
- [ ] Upload all 5 screenshots under "iPhone 6.7" display"
- [ ] Set Privacy Policy URL
- [ ] Complete Age Rating questionnaire
- [ ] Add test credentials under "Sign-in Required" (if applicable)
- [ ] Add review notes: "App requires HealthKit and Screen Time entitlements. FamilyControls requires physical device — simulator will not work."
- [ ] Click **"Add for Review"**

---

## Review Notes (paste into App Store Connect)

```
This app uses Apple HealthKit to read fitness data and FamilyControls (Screen Time) to lock/unlock apps based on daily activity goals.

HealthKit usage: Read steps, active energy burned, heart rate, and workout sessions.
FamilyControls usage: Lock selected social media apps until daily fitness goal is met.

The app cannot be tested on Simulator as both HealthKit real data and FamilyControls require a physical device.

Test account for review:
Email: review@sweattoscroll.app
Password: ReviewSweat2026!

(If no test account is available, the reviewer can use the app in demo mode — all displayed values are pre-populated for UI review purposes.)
```
