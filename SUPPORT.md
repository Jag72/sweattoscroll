# Help & Support — Sweat2Scroll

**Web version:** https://sweattoscroll.com/support.html

## Contact

Log complaints, report bugs, or ask questions: **coppersmith2222@gmail.com**
Include your iOS version, app version, and a screenshot if possible. We aim to reply within 48 hours.

You can also open an issue: https://github.com/Jag72/sweattoscroll/issues

## FAQ

**My apps didn't unlock after I hit my goal.**
The app re-checks HealthKit progress roughly every 15 minutes in the background. Open the app to force an immediate policy evaluation. Also confirm Health access in Settings → Privacy & Security → Health → Sweat2Scroll.

**I deleted Sweat2Scroll but my apps are still blocked.**
iOS automatically removes all Screen Time shields an app applied when that app is deleted. In rare cases an iOS system bug leaves a shield behind. Fixes: reinstall the app, toggle the shield off, delete again; or toggle Screen Time off/on in Settings → Screen Time; or restart your iPhone. No Sweat2Scroll servers are involved in shielding.

**What is Break-Glass?**
An emergency override held by your accountability partner. Enter their current 6-digit TOTP code to unlock apps for 15 minutes. The event is recorded in your signed audit log.

**My step / calorie data looks wrong.**
Sweat2Scroll mirrors Apple Health. If data is missing in the Health app, it will be missing here. An Apple Watch gives the most accurate calories, HRV, and sleep data.

**How do I change my blocked apps or daily goal?**
Profile tab → Daily calorie goal, or Profile tab → Restricted apps.

**Does my health data leave my phone?**
No. All processing is in-memory and on-device. See [PRIVACY.md](PRIVACY.md).

**How do I delete my account and data?**
Sign out and delete the app for local data. For CloudKit records, email coppersmith2222@gmail.com with subject "Data deletion", or manage via Settings → Apple ID → iCloud → Manage Account Storage.

## Version 1.0 — Initial Release (July 2026)

- Fitness-gated app blocking: earn access by hitting your daily calorie, step, or workout goal
- iOS Screen Time (FamilyControls) shield enforcement
- Apple HealthKit integration: steps, active calories, workouts, HRV, resting HR, sleep, respiratory rate
- On-device policy engine (OPA compiled to WebAssembly) — zero server round-trips
- Partner accountability: ECDH-secured pairing, Break-Glass TOTP codes, signed audit log
- Wellness dashboards: Recovery, Strain, Sleep, and Heart
- Solo, User, and Monitor onboarding modes

Requires iOS 16.0+ · Apple Watch recommended · Free
