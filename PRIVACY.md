# Privacy Policy — Sweat2Scroll

**Effective date:** July 20, 2026 · Applies to Sweat2Scroll v1.0 and later
**Web version:** https://sweattoscroll.com/privacy.html

**The short version:** your health data never leaves your phone. Sweat2Scroll has no servers, no analytics SDKs, no ads, and nothing to sell. The only cloud storage used is your own private Apple iCloud (CloudKit) container, which we cannot access.

## 1. Who We Are

Sweat2Scroll is developed by Jagadish Krishna Pilla ("we", "us"). It is an iOS app that unlocks your chosen apps only after you hit a daily fitness goal, using Apple HealthKit and the Screen Time (FamilyControls) framework.

## 2. Data We Read

With your explicit HealthKit authorization, the app reads: steps, active energy (calories), workout minutes, heart rate, heart-rate variability (HRV), resting heart rate, respiratory rate, and sleep stages. This data is processed entirely in-memory on your device by an on-device policy engine (Open Policy Agent / WebAssembly), is never written to disk, is never transmitted to us or any third party, and is used for exactly one purpose: deciding whether your daily goal is met.

## 3. Data We Store

On your device: your goal settings (calorie/step/minute targets), selected apps to block (as opaque Apple tokens — we cannot see which apps they are), and app preferences.

In your private CloudKit container: your partner-pairing contract and audit-log events (shield toggles, Break-Glass usage). This container belongs to your Apple ID. We have no access to it — only you and, where the pairing contract allows, your paired partner can read it.

## 4. Screen Time Data

App-blocking uses Apple's FamilyControls and ManagedSettings frameworks. Apple provides the app only anonymous tokens for the apps you select — we never see app names, usage history, or browsing activity. Shields are applied locally by iOS and are automatically removed by the system if you delete Sweat2Scroll.

## 5. What We Don't Do

No selling, sharing, or disclosing of health or personal data — to anyone, ever. No advertising, no tracking, no third-party analytics SDKs. No accounts on our servers — we don't operate any servers. No use of HealthKit data for advertising or marketing, as required by Apple's guidelines.

## 6. Security

Partner pairing uses ECDH P-256 key exchange — no passwords are transmitted or stored. Break-Glass emergency codes are time-based one-time passwords (TOTP, RFC 6238) — short-lived and single-use. Audit-log entries are cryptographically signed to prevent tampering.

## 7. Data Retention & Deletion

Local data is deleted when you delete the app. CloudKit records live in your personal iCloud and can be removed via Settings → Apple ID → iCloud → Manage Account Storage, or by emailing a deletion request to coppersmith2222@gmail.com. Because health data is never persisted, there is no health data to delete.

## 8. Children

Sweat2Scroll is rated 4+ and contains no objectionable content, but it is not directed at children under 13. We do not knowingly collect personal information from children; since the app collects no personal information on our systems at all, none can be retained.

## 9. Your Rights

Depending on your region (e.g., GDPR, CCPA), you may have rights to access, correct, or delete personal data. Because we hold no personal data on our systems, most requests can be satisfied on-device as described above — but you can always contact us and we will help.

## 10. Changes to This Policy

If we change this policy, we will update this page and the effective date above. Material changes will be noted in the App Store release notes of the version that introduces them.

## 11. Contact

Questions or complaints about privacy: **coppersmith2222@gmail.com**
Project page: https://github.com/Jag72/sweattoscroll
