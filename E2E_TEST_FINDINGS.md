# Sweat2Scroll — End-to-End Test Findings

**Date:** 2026-07-12 · **Method:** full static trace of every flow (auth, solo, user, monitor, pairing, override, enforcement) plus executable simulations replicating the exact Swift logic — including a simulated partner device for the pairing, TOTP, and override flows. Simulation script: `e2e_sim.py` (results reproduced below where relevant).

**Verdict: not ready for public launch.** The solo flow is in decent shape, but every partner flow is broken across two real iCloud accounts, and there are two launch-blocking correctness bugs (P0-4, P0-5) that will hit solo users too.

---

## P0 — Launch blockers

### P0-1. All partner features use the CloudKit *private* database — cross-account sync is impossible
`CloudKitService.swift:31` — every record type (PairCode, UserAccount, BypassGrant, PartnerProgress, AuditEvent, PairingResponse, GovernanceContract) reads/writes `container.privateCloudDatabase`. A private DB is scoped to one iCloud account. Two real users can never see each other's records.

Confirmed by simulation (two separate DBs): monitor saves pair code to *their* private DB → user's `fetchPairCodeRecord` queries *their own* private DB → always `nil` → "Invalid code." The same applies to:

- 6-digit pairing (`PairingService.validateAndPair` also fetches and **writes the monitor's UserAccount from the user's device** — impossible cross-account)
- Emergency override redemption (`fetchBypassGrant` never finds the granter's record)
- Partner progress (`syncMyProgress` writes `"myProgress"` to own DB; `fetchPartnerProgress` skips `"myProgress"` and finds nothing else — partner dashboards will show 0 forever)
- Tamper alerts (the CKQuerySubscription watches the subscriber's own private DB; partner's tamper events are written to the *partner's* DB — push never fires)

It only ever worked in your testing because both "devices" were signed into the same iCloud account.

**Fix:** move PairCode, BypassGrant, PartnerProgress, and pairing-handshake records to the **public database** (with server-side TTL cleanup), or implement real **CKShare** zones for the partner relationship. Public DB is far simpler for launch: scope records by `partnershipID`, keep sensitive fields minimal (`encryptedValues` are not available in public DB — don't put display names/reasons there without your own encryption, e.g. keys derived from the pairing exchange).

### P0-2. ECDH pairing derives two *different* secrets — break-glass TOTP can never validate
`TOTPService.performECDHExchange` generates a **fresh ephemeral private key inside the function every time**. Device A's QR contains public key A1, but when A later completes pairing it calls `performECDHExchange(B_pub)` which makes a brand-new key A2. Result: B derives `B1·A1`, A derives `A2·B1`. Simulation with real P-256 keys:

```
Device A secret: 1da679d7…   Device B secret: e544596e…   MATCH: False
(If A reused its QR key A1: match = True)
Monitor TOTP 668444 → user-side validation: False
```

**Fix:** `performECDHExchange` must accept the caller's existing private key (the initiator reuses `ephemeralPrivateKey` from `OnboardingViewModel`); only the responder generates a fresh pair.

### P0-3. Partner OTP screens are stubs — release build rejects every code
`OTPRequestView.verify`: `#if DEBUG valid = code.hasPrefix("1234") #else valid = false #endif`. `OTPGeneratorView.generateCode()` never persists the code anywhere — it's display-only theater. In DEBUG, *any* of the 10,000 codes starting "1234" unlocks. In RELEASE, nothing ever validates.

**Fix:** delete these two views or rewire them to `EmergencyOverrideService` (which is the real, CloudKit-backed implementation — but see P0-1). Right now `GuardianView` links `.totp → PairCodeGeneratorView` while other screens use `EmergencyOverrideView`; consolidate on one flow.

### P0-4. Time-drift tamper detection false-positives every time the phone sleeps
`TamperDetectionService` compares wall-clock delta vs `ProcessInfo.systemUptime` delta with a 120 s threshold. `systemUptime` **pauses during device sleep**, and the 30 s check loop suspends while the app is backgrounded. Simulation: phone asleep 10 min → drift = 570 s → tamper flagged → policy fail-closed with *"Security lockout: system clock manipulation detected"* and shields force-engaged. Every user who backgrounds the app will hit this. `isTimeDriftDetected` (used in every policy evaluation) has the same flaw.

**Fix:** use a sleep-inclusive monotonic clock — `clock_gettime(CLOCK_MONOTONIC_RAW)` vs `CLOCK_BOOTTIME` comparison, or persist `(wallClock, bootTime)` pairs. Also reset baselines on `scenePhase == .active` before the first check runs.

### P0-5. HealthKit tamper check can never work (and the app's own comments say why)
`HealthKitService.validatePermissions()` returns `authorizationStatus(for: .activeEnergyBurned) == .sharingAuthorized` — but the app requests **read-only** access (`toShare: []`), and iOS reports `.sharingDenied` for read-only types by design (documented in `verifyAccess()`'s own comment). So `validatePermissions()` is permanently `false` → `healthKitEverGranted` never latches → HealthKit revocation is **never detected** (silent fail-open, contradicts the accountability model and the IEEE paper's tamper claims).

**Fix:** use `getRequestStatusForAuthorization` + "data was flowing and stopped" heuristics (e.g. anchored-query silence while steps > 0 elsewhere), or drop the claim.

---

## P1 — High priority

**P1-1. Two parallel pairing systems that don't talk to each other.** The 6-digit flow sets `CloudUserAccount.isPaired`; the QR/ECDH flow sets `PartnerViewModel.isPartnerPaired` via `GovernanceContract`. `EmergencyOverrideView` gates on `partnerVM.isPartnerPaired`, but the dashboards pair via the 6-digit flow — so after a successful 6-digit pair, the override screen still says **"Pair with a partner first."** Pick one pairing system; drive `isPartnerPaired` from `auth.cachedAccount.isPaired`.

**P1-2. Monitor dashboard shows the monitor's own health data labeled as the partner's.** `MonitorHomeTab` renders `wellnessVM` (local HealthKit) tiles under "Partner's Wellness", the week chart is hard-coded `[true,true,false,…]`, and `MonitorActivityLog` shows fabricated sample rows when empty. `MonitorGoalSheet` "Save Goal" only sets `partnerVM.partnerGoal` locally — it never syncs to the partner's device, so the "Partner must hit this to unlock" promise is false. `MonitorBypassCard` Approve/Deny buttons set local state only.

**P1-3. No pairing-consent step.** Anyone who obtains a 6-digit code can pair to the monitor with zero confirmation on the monitor's side, and `validateAndPair` silently overwrites any existing pairing on both accounts (`linkedPeerAppleUserID` clobbered). Add an accept/decline step and reject codes when either side is already paired. Also: no rate limiting on code guesses (900k space, 10-min TTL — fine for now, but add attempt limits when moving to public DB, where guessing becomes feasible).

**P1-4. Password reset requires no verification of anything.** `ForgotPasswordView` → `resetLocalPassword` overwrites the Keychain hash for any locally-registered username with no proof of ownership (no old password, no email loop, no biometric — `SecurityGate` exists but isn't used here). Anyone holding an unlocked phone takes over the account. At minimum gate it behind `SecurityGate.authenticate`.

**P1-5. Weak password hashing.** Single unsalted-iteration `SHA256(salt+password)`. Use PBKDF2/scrypt (CryptoKit: `HKDF` is not a password KDF; use CommonCrypto PBKDF2 with ≥100k iterations) — cheap change, matters if Keychain items ever leak via backup edge cases.

**P1-6. No email verification / no cross-device account recovery for email accounts.** Credentials are device-local; a user who gets a new phone loses email/password access entirely (their CloudKit data follows the *iCloud account*, not the password). The UX promises a normal account system it can't deliver. Either add a real backend or clearly steer users to Sign in with Apple/Google.

**P1-7. Shield re-engagement gaps in solo flow.**
- `breakGlassUnlock()` uses only an in-process `Task.sleep` — if the app is killed/suspended, the shield never re-engages until next launch (unlike `temporaryBypass`, which correctly schedules DeviceActivity).
- `DeviceActivityMonitorExtension.intervalDidStart` (midnight) re-engages the shield even if the user already met *yesterday's* goal at 11:59pm — correct — but there's **no handler for `.temporaryBypass` intervalDidEnd**: the extension only reacts to `.daily`. `intervalDidEnd(for: .temporaryBypass)` falls through the `guard activity == .daily` and does nothing, so OS-level bypass expiry does *not* re-engage the shield; only the in-app Task fallback does. If the app is suspended, a 15-min bypass becomes indefinite.

**P1-8. Daily reset depends on the app being opened.** `BlockingSessionService.rolloverIfNewDay` runs on init/tick; the DeviceActivity `.daily` schedule re-engages the shield at midnight, but the *grace window* starts only when the app next runs. Two overlapping "free window" systems exist (`DailyResetManager.freeWindowEnd` from midnight vs `BlockingSessionService` grace from first open) with different semantics — consolidate.

---

## P2 — Medium / polish

- **P2-1. Fake data in production UI:** `MonitorActivityLog` sample rows, `MonitorPartnerTab` hard-coded week chart, `AppWeekChart(completions: Array(repeating: false…))`. Replace with real empty states.
- **P2-2. Dev artifacts ship in the archive:** `BACKEND_SCORING_SPEC.md`, `CLOUDKIT_SCHEMA.md`, `fitness_policy.rego` are inside `Sweat2Scroll.app` — remove from the Copy Bundle Resources phase. Dev creds (`puji/1234`) are `#if DEBUG`-gated at usage but the constants ship in the release binary; harmless, but move them inside `#if DEBUG` too.
- **P2-3. WASM manifest has no signature:** `contract_manifest.json` hash matches (verified: `5c281dcb…`) but `signature`/`public_key` are absent, so the ECDSA branch is skipped — hash pinning without a signature only detects corruption, not substitution (an attacker who swaps the wasm can swap the manifest). Sign the manifest or drop the security claim.
- **P2-4. Policy edge:** for a steps-currency user with stale calorie data, Rego can return `allow=true` *and* `requires_grace=true` simultaneously (grace rule only checks calories). Harmless today because allow wins, but make `requires_grace` require `not allow`. Native-fallback parity is otherwise exact (200k-case fuzz: 0 mismatches — good work).
- **P2-5. Privacy drift:** CLAUDE.md says "never store health data to disk," but calories are written to App Group `UserDefaults` and synced to CloudKit. Update the privacy policy / App Store privacy labels to match reality (denominated health data leaves the device to iCloud).
- **P2-6. `AuthManager.signOut()` doesn't call `GoogleAuthService.shared.signOut()`** or wipe `EmailCredentialStore` — next Google tap silently reuses the cached Google session; fine if intended, surprising if not.
- **P2-7. `pollForPairingConfirmation`** treats *any* `isPaired` account state as success (stale prior pairing → instant false "Paired!"), and polling stops after 5 min with no UI feedback on the generator screen.
- **P2-8. `AppShieldBanner(locked:)` on the monitor home** derives lock state from `partnerCalories < partnerGoal` — ignores the partner's grace/bypass/override phases, so the monitor sees "locked" when the partner is actually in a bypass window. Sync the partner's `BlockingPhase` along with progress.
- **P2-9. `CloudUserAccount` last-writer-wins:** `saveUserAccount` upsert re-applies *all* fields; two devices for one user (or the pairing write from the peer per P0-1's design) can clobber each other's `dailyTargetKcal`/`partnershipRole`. Consider per-field merge or CKRecord partial updates.

---

## What's solid

Auth routing state machine (`applyReturningUserRouting`) is coherent; the strict-fetch guard against clobbering CloudKit accounts on transient errors is genuinely well done; `upsert` with `.serverRecordChanged` retry is correct; the solo blocking state machine (`BlockingSessionService`) is clean and its persistence via App Group is right; Rego ↔ Swift fallback parity is exact; shield self-exclusion (`excludingHostApplication`) is handled in both app and extension; HOTP implementation matches RFC 4226 dynamic truncation.

## Suggested order of work

1. Decide partner architecture: **public DB + partnershipID scoping** (fast) vs CKShare (correct long-term). Everything partner-related is blocked on this.
2. Fix ECDH key reuse (one-line-ish fix in `performECDHExchange` signature) — or drop TOTP entirely and standardize on CloudKit `BypassGrant` OTPs once P0-1 is fixed.
3. Fix time-drift detection (sleep-aware clocks) — this alone will lock out real users on day one.
4. Fix HealthKit tamper check or remove the claim.
5. Delete/rewire `OTPGeneratorView`/`OTPRequestView`; unify pairing state (P1-1).
6. Add `.temporaryBypass` handling in the DeviceActivity extension + DeviceActivity scheduling for break-glass.
7. Consent step + SecurityGate on password reset.
8. Sweep the fake UI data and dev artifacts before archiving.
