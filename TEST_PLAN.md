# Sweat2Scroll — Functional test plan

Manual QA checklist for release readiness while **Family Controls (Distribution)** and other Apple approvals are pending. Pair with Xcode builds from `app/Sweat2Scroll.xcodeproj`.

---

## 1. Purpose & scope

| In scope | Out of scope (unless explicitly tested) |
|----------|----------------------------------------|
| Auth (Sign in with Apple, email/password per implemented flows) | Automated UI suite (add later in XCTest) |
| Onboarding: mode selection, PRD chain, solo/user/monitor profiles | Backend services outside CloudKit |
| Solo dashboard & self-blocking behavior | Android |
| User / Monitor dashboards, paired vs unpaired | App Store Connect metadata |
| Partner pairing, roles, progress sync | Legal/compliance sign-off |
| HealthKit & Screen Time authorization (device) | Simulator-only Screen Time parity |
| **UI/UX end-to-end:** navigation, forms, sheets, loading/error/empty states, accessibility | — |

---

## 2. Verification policy — 100% UI & flows

**Treat this document as the acceptance contract.** Every test case below must reach **Pass** for the release you ship (or be explicitly **Blocked** with an external dependency and a tracked follow-up).

### Definition of done

- **Pass:** UI matches expected copy/behavior; no crash; state persists or errors are clear and recoverable.
- **Fail:** Any mismatch with the **Expected** column — layout broken, wrong navigation, silent failure, misleading copy, or accessibility blocker.

### When UI or a flow does not work as expected

1. **Record:** TC ID, steps, device/OS, build number, screenshot or screen recording.
2. **Fix:** Implement or scope-cut in code; update copy/spec if the test plan was wrong (note the change in git).
3. **Re-test:** Run the **failed** case plus any cases in the **Regression sweep** (§13) and affected **UI E2E** rows (§14) that touch the same code paths.
4. **Close:** Mark **Pass** only after re-verification. Do not carry forward “mostly works.”

### Release gate

Ship only when **all non-blocked rows** in §5–§13 **and** §14 are **Pass**, or when remaining failures are explicitly deferred with product sign-off (document TC IDs in release notes).

---

## 3. Preconditions

- **Hardware:** At least one **physical iPhone** (HealthKit + Family Controls / Screen Time APIs are unreliable or unavailable on Simulator for real enforcement).
- **Pairing scenarios:** **Two physical devices** with distinct Apple IDs (or test accounts) as required by your pairing design.
- **Network:** Wi‑Fi + cellular spot-check for CloudKit-dependent flows.
- **Developer:** Valid signing team; note if builds use **Development-only** Family Controls (expect Xcode yellow warning until Distribution is approved).
- **Bundle IDs:** Main app and extensions match **Certificates, Identifiers & Profiles** and App Store Connect listing.

Record per run: **build number**, **iOS version**, **device model(s)**, **tester initials**, **date**.

---

## 4. Product flows (reference)

These match app routing (`RootView`, `AuthManager`, `AppAuthModels`).

### 4.1 `AppAuthState`

| State | Expected UI |
|-------|-------------|
| `unauthenticated` | Sign-in |
| `onboarding` | Flow driven by `postAuthStep` (below) |
| `solo` | Solo dashboard |
| `user(paired:)` | User dashboard |
| `monitor(paired:)` | Monitor dashboard |
| `breakGlassActive` | Emergency / override UX (verify against current product spec) |

### 4.2 `PostAuthOnboardingStep` (onboarding screens)

| Step | Screen |
|------|--------|
| `modeSelection` | Mode selection (solo / user / monitor) |
| `soloProfile` | Solo profile onboarding |
| `userProfile` | User profile onboarding |
| `monitorProfile` | Monitor profile onboarding |
| `prdHealth` | PRD: Health |
| `prdManual` | PRD: Manual body data (conditional in progress strip) |
| `prdCalorie` | PRD: Calorie goal |
| `prdApps` | PRD: App blocking selection |
| `prdPairingPrompt` | PRD: Pairing prompt |
| `prdRoleSelection` | Partnership role selection (conditional after pairing) |
| `prdComplete` | PRD: Completion |

### 4.3 `PartnershipRole`

| Role | Grant override OTP | Redeem override OTP |
|------|--------------------|----------------------|
| `mutual` | Yes | Yes |
| `controller` | Yes | No |
| `controlled` | No | Yes |

---

## 5. Test cases — authentication & session

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-AUTH-01 | Fresh launch, no session | Delete app (or clear keychain/defaults per test policy), launch | Sign Up presented (auth root); Sign In reachable via "Sign In" link |
| TC-AUTH-02 | Sign in with Apple — new user | Complete Apple flow | Lands in onboarding or PRD start per routing |
| TC-AUTH-03 | Sign in with Apple — returning | Sign out (if available), sign in again same Apple ID | Routes per `CloudUserAccount` (solo/user/monitor, paired flag), no duplicate onboarding if fully onboarded |
| TC-AUTH-04 | Username sign up — success | Valid username + password, submit | Session established; CloudKit account created/updated |
| TC-AUTH-05 | Username sign up — network failure | Airplane mode during submit | Clear error; **no** silent overwrite of cloud state (retry path works when online) |
| TC-AUTH-06 | Username sign in — returning | Existing credentials | Correct dashboard |
| TC-AUTH-07 | Session restore | Kill app, relaunch | Still authenticated when ID persisted |
| TC-AUTH-08 | Dev / debug session | If `dev_*` session exists | Confirm documented limitations (e.g. skips CloudKit writes) |
| TC-AUTH-09 | Apple capability missing in build | Build a target where the **Sign In with Apple** capability is *not* enabled, tap the Apple button | Friendly copy via `friendlyAuthError` (`.unknown` branch) explains how to enable the capability — **no** opaque crash or blank state |
| TC-AUTH-10 | Re-install on same device, same Apple ID | Delete app → reinstall → sign in with same Apple ID | `restoreSessionIfPossible` re-fetches the cached `CloudUserAccount`; user lands in their previous dashboard, **not** onboarding; pairing survives; calorie goal preserved |
| TC-AUTH-11 | Re-install on same device, same username/password | Delete app → reinstall → sign in via username/password used previously | `AuthManager.signIn(username:password:)` resolves the same `appleUserID` from `EmailCredentialStore`; existing CloudKit account loads; user **is not** sent through PRD again |
| TC-AUTH-12 | Same Apple ID, second device | Sign in with the same Apple ID on Device B | Behavior is well-defined per product (either: B takes over the session, or both stay signed in; in either case CloudKit `UserAccount` stays consistent — no duplicate records, no pairing drop) |
| TC-AUTH-13 | Username sign-in transient CloudKit failure | Trigger a non-`unknownItem` error from `fetchUserAccountStrict` (e.g., flaky network) | `lastAuthError` shows "Couldn't reach iCloud..."; **no** blank fallback `UserAccount` is written that would overwrite real cloud state (per `AuthManager.signIn` doc comment) |
| TC-AUTH-14 | Username sign-up transient CloudKit failure | Same as TC-AUTH-13 but during `AuthManager.signUp` | Same safety property — no blank overwrite; user can retry when online |
| TC-AUTH-15 | Sign Out clears session | If sign-out UI is exposed, tap it | `appleIDDefaultsKey` removed; `AppSession.clear()` runs; `authState == .unauthenticated`; relaunch lands on Sign Up, **not** auto-resumed |
| TC-AUTH-16 | Forgot Password — wired or hidden | Tap **Forgot Password?** | Either (a) opens a real reset flow **or** (b) shows a clear "coming soon" alert with a contact path. **Silent no-op** is a fail. (See TC-UI-16) |

---

## 6. Test cases — onboarding & mode selection

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-ONB-01 | Mode: Solo | Choose solo → complete `soloProfile` | `authState` → `.solo`; profile fields persisted |
| TC-ONB-02 | Mode: User | Choose user → complete `userProfile` | `.user(paired: false)` until paired |
| TC-ONB-03 | Mode: Monitor | Choose monitor → complete `monitorProfile` | `.monitor(paired: false)` until paired |
| TC-ONB-04 | PRD sequence — happy path | New account through `prdHealth` → … → `prdComplete` | Order matches visible progress strip; optional steps (`prdManual`, `prdRoleSelection`) match profile/pairing branch |
| TC-ONB-05 | PRD — back navigation | From mid-PRD, use back where offered | Previous step correct; state not corrupted |
| TC-ONB-06 | Incomplete cloud profile — solo | Account missing age or goal | Routed to `soloProfile` until ready |
| TC-ONB-07 | Incomplete cloud profile — user | Missing age/goal | Routed to `userProfile` |
| TC-ONB-08 | Incomplete cloud profile — monitor | Missing relationship label | Routed to `monitorProfile` |
| TC-ONB-09 | Legacy mode selection | Flow hitting `modeSelection` | All three modes selectable; routing matches |

---

## 7. Test cases — solo execution

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-SOLO-01 | Solo dashboard load | Complete solo onboarding | Dashboard metrics/load without crash |
| TC-SOLO-02 | HealthKit authorization | Grant / deny in Settings | App handles denial gracefully; grant enables data |
| TC-SOLO-03 | App picker / shields | Select apps in onboarding or settings | Selection persists; extension reads shared container if applicable |
| TC-SOLO-04 | Daily monitoring | Complete day boundary or trigger schedule | Blocking/unblocking aligns with policy (steps/calories/workouts per product) |
| TC-SOLO-05 | Optional partner step in solo flow | If UI offers “pair later” | State remains solo; no bogus paired flag |
| TC-SOLO-06 | Foreground resume | Background app, return | `restoreSessionIfPossible` / Screen Time refresh — no stuck UI |

---

## 8. Test cases — user & monitor dashboards

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-USER-01 | User unpaired | `.user(paired: false)` | Pair affordance visible; correct empty states |
| TC-USER-02 | User paired | After successful pair | `.user(paired: true)`; partner-aware UI |
| TC-MON-01 | Monitor unpaired | `.monitor(paired: false)` | Pair affordance visible |
| TC-MON-02 | Monitor paired | After successful pair | `.monitor(paired: true)` |
| TC-DASH-01 | Open pair sheet after mode switch | Trigger `openPairCodeOnNextUserDashboard` path if applicable | Sheet appears once as designed |

---

## 9. Test cases — partner pairing (two devices)

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-PAIR-01 | Happy path — initiator/responder | A generates code/QR; B accepts | Both show paired; `CloudUserAccount` reflects linkage |
| TC-PAIR-02 | Invalid code | Enter wrong code | `PairingResult.invalid` or equivalent UX; recoverable |
| TC-PAIR-03 | Expired / stale code | Wait beyond TTL if applicable | `expired` handling; clear messaging |
| TC-PAIR-04 | Offline initiator | B offline during accept | Error surfaced; retry succeeds when online |
| TC-PAIR-05 | Pairing record cleanup | After successful consume | Temporary pairing records removed where designed |
| TC-PAIR-06 | Zone / shared DB errors | Simulate CK zone missing (per docs) | User sees re-pair guidance (`CloudKitService` copy) |

---

## 10. Test cases — partnership roles

Run **three focused passes** with two devices after pairing.

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-ROLE-01 | Mutual | Both choose mutual-aligned behavior | Both tracked; **either** can grant override per product |
| TC-ROLE-02 | Controller + controlled | Parent/controller vs child/controlled | Controller **not** blocked per role semantics; controlled blocked until goal/override; OTP flows match `canGrantOverride` / `canRedeemOverride` |
| TC-ROLE-03 | Role mismatch tolerance | Each side picks role independently (e.g. controller vs controlled) | Product allows asymmetric picks without inconsistent crashes |

---

## 11. Test cases — CloudKit & background

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-CK-01 | Schema bootstrap | First launch clean container | `CloudKitSchemaBootstrap` completes without user-visible failure |
| TC-CK-02 | Partner progress sync | Burn activity on A | B sees updated progress within expected latency |
| TC-CK-03 | Tamper / subscription | If tamper path implemented | Partner notified per design (silent push / subscription) |
| TC-CK-04 | Account refresh | Pull-to-refresh or automatic refresh | No duplicate records; errors non-destructive |

---

## 12. Test cases — Screen Time & extensions

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-ST-01 | Family Controls authorization | System prompt | Status reflected in app; `refreshAuthorizationStatus` on foreground |
| TC-ST-02 | Shield configuration | Launch blocked app | Correct shield UI from extension |
| TC-ST-03 | Shield action | Primary/secondary actions | Matches policy (open Sweat2Scroll, defer, etc.) |
| TC-ST-04 | Device activity monitor | Interval start/end | Schedules align with `ScreenTimeService` |

---

## 13. Regression sweep (before each upload)

- [ ] Cold start → authenticated path → primary dashboard
- [ ] Sign out → sign in (both auth methods you ship)
- [ ] Onboarding from zero → complete for **each** mode once per milestone
- [ ] Pair → unpair/re-pair if supported
- [ ] Deep link / associated domain (`applinks:sweat2scroll.app`) if enabled in build
- [ ] Push / `aps-environment`: Release build uses **production** when archiving for App Store

---

## 14. UI end-to-end scenarios (functional UI QA)

Execute these **in order within each journey** the first time you qualify a build; thereafter run **full §14** before major releases and **§14.1–§14.3** on every RC.

Cross-cutting **for every screen:** no clipped text at default Dynamic Type; scroll views scroll when keyboard is open; loading states show spinners/disabled CTAs where implemented; errors use visible inline or alert copy (not blank UI).

### 14.1 App shell & global behavior

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-UI-01 | Cold launch | Install/fresh launch | Splash / router leads to correct root (`SignInView` or dashboard per session); no flash of wrong state |
| TC-UI-02 | Deep link — pairing URL | Open `onOpenURL` pairing link while app backgrounded & foregrounded | `DeepLinkService.isPairingURL` path runs; onboarding/partner flow consumes URL without crash |
| TC-UI-03 | Foreground from background | Send app to background 30s+, return | No frozen UI; Screen Time auth refresh does not spam sheets |
| TC-UI-04 | Light mode | Navigate auth + onboarding | UI remains readable (`preferredColorScheme(.light)` on auth flows does not break dashboards) |
| TC-UI-05 | Dynamic Type | Settings → largest Accessibility sizes → repeat one auth + one dashboard path | No overlapping labels; critical CTAs remain tappable |
| TC-UI-06 | VoiceOver (spot) | Enable VoiceOver on Sign In + one primary CTA | Focus order logical; `accessibilityIdentifier` on `signIn.submit` and auth fields where present |

### 14.2 Sign In (`SignInView`) — end-to-end

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-UI-10 | Layout & copy | Land on sign-in | Logo, “Welcome back”, subtitle about shield visible |
| TC-UI-11 | Username field | Enter a username, leave password empty | **Sign In** stays disabled (`PrimaryCTAButton` disabled state visually muted) |
| TC-UI-12 | Both fields required | Fill only one of username/password | Sign In disabled until both username and password are non-empty |
| TC-UI-13 | Password visibility | Use secure field affordance if shown | Toggles mask/unmask without losing text |
| TC-UI-14 | Sign In — loading | Valid credentials, tap **Sign In** | Loading indicator on CTA; double-tap does not duplicate requests |
| TC-UI-15 | Sign In — error | Wrong password / server error | **Single** red error line (friendly `lastAuthError` for iCloud issues, else `authError`); no duplicate raw error; user can retry; error clears on re-attempt and when leaving the screen |
| TC-UI-16 | Forgot Password — open | Tap **Forgot Password?** | `ForgotPasswordView` sheet opens; username prefilled from form; Apple-recovery note shown |
| TC-UI-16a | Reset — no local account | Enter username with no device account, valid new password, **Reset password** | Inline error: "No account with that username exists on this device…" (`PasswordResetError.noLocalAccount`) |
| TC-UI-16b | Reset — validation | New password `< 6` chars or mismatch | **Reset password** disabled; "Passwords don't match" label when applicable |
| TC-UI-16c | Reset — success | Existing device account, valid matching new password | Success state; **Back to sign in** dismisses and prefills username; signing in with new password works (old password rejected) |
| TC-UI-17 | Navigate back to Sign Up | Tap **Sign Up** on Sign In | Pops back to `SignUpView` (Sign Up is the nav root) |
| TC-UI-18 | Continue with Google | Tap **Continue with Google** | Alert “Google Sign-In…” explains SDK pending; dismiss OK returns to form |
| TC-UI-19 | Sign in with Apple — cancel | Start Apple sheet, cancel | Friendly cancel copy via `friendlyAuthError`; no crash |
| TC-UI-20 | Sign in with Apple — success | Complete Apple sign-in | Leaves unauthenticated UI per `authState`; dismiss triggers appropriately |
| TC-UI-21 | DEBUG tester shortcut | DEBUG build: tap tester credential chip | Fills `AppSession.devUsername` / password |

### 14.3 Sign Up (`SignUpView`) — end-to-end

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-UI-30 | Create Account disabled | Empty form | **Create Account** disabled |
| TC-UI-31 | Password rules | Password `< 6` chars | Create Account disabled |
| TC-UI-32 | Username rules | Username `< 3` chars | Create Account disabled |
| TC-UI-33 | Happy path form | Username ≥ 3 chars + password ≥ 6 chars | Create Account enables; success routes to onboarding/dashboard |
| TC-UI-34 | Sign Up — loading | Submit valid form | Loading on CTA; no duplicate submits |
| TC-UI-35 | Sign Up — Apple | Use Apple button on sign-up sheet | Same behavioral expectations as sign-in Apple path |
| TC-UI-36 | Sign Up — Google | Tap Google | Same placeholder alert as sign-in |
| TC-UI-37 | Go to Sign In | Tap **Sign In** from sign-up | `SignInView` pushes onto the nav stack |

### 14.4 Solo onboarding (`SoloOnboardingView`) — end-to-end

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-UI-40 | Progress dots | Advance steps 0→3 | Four dots; filled count matches step |
| TC-UI-41 | Step 0 — About you | Enter name, age | Continue advances |
| TC-UI-42 | Step 1 — Weight | Toggle lbs/kg; enter weight | Value respected in conversion |
| TC-UI-43 | Step 2 — Goal | Enter daily kcal | Caption about Mifflin visible |
| TC-UI-44 | Step 3 — optional partner | Read screen | Copy explains pairing from dashboard later |
| TC-UI-45 | Back navigation | From step 2 → Back | Returns to step 1; field values preserved |
| TC-UI-46 | Finish — invalid | Clear age or goal → Finish | “Check your numbers.” (`errorMessage`) |
| TC-UI-47 | Finish — success | Valid numbers → Finish | `completeSoloOnboarding` succeeds; navigates to solo dashboard; saving spinner clears |

### 14.5 PRD onboarding chain (screens in §4.2)

For **each** visible step (`OnboardingHealthView` → … → `OnboardingCompleteView`):

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-UI-50 | Progress strip accuracy | Walk full PRD path | Strip index/total matches `PostAuthOnboardingStep.progressIndicator` rules (optional steps don’t break counting) |
| TC-UI-51 | Health permissions UI | Complete health step | System permission + in-app copy coherent; denial path documented |
| TC-UI-52 | Manual body step | When branch shows `prdManual` | Fields validate; advance/back consistent |
| TC-UI-53 | Calorie goal step | Enter goal | Persisted and reflected on dashboard |
| TC-UI-54 | App blocking step | FamilyActivity picker | Selection persists; revisiting shows prior selection |
| TC-UI-55 | Pairing prompt | Solo skip vs pair paths | Navigation matches choice; no orphan state |
| TC-UI-56 | Role selection | After pair | All three roles selectable; subtitles match `PartnershipRole` |
| TC-UI-57 | Completion screen | `prdComplete` | Celebration/next action clear; lands on correct `authState` |

### 14.6 Mode selection & profile onboarding (`ModeSelectionView`, `UserOnboardingView`, `MonitorOnboardingView`)

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-UI-60 | Mode cards | Tap each mode | Visual selection + navigation to correct profile flow |
| TC-UI-61 | User profile — complete | Fill required fields | Advances to PRD or dashboard per routing |
| TC-UI-62 | Monitor profile — complete | Relationship label etc. | Advances correctly |
| TC-UI-63 | Mode switch from settings | If UI exposes mode change | Cloud + UI consistent; pair sheet flag if applicable |

### 14.7 Dashboards — solo / user / monitor

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-UI-70 | Solo dashboard elements | Load solo home | Progress/ring or primary metrics render; no indefinite loading |
| TC-UI-71 | User dashboard — unpaired | Pairing CTAs | Sheets/modals open; QR/code UI usable |
| TC-UI-72 | User dashboard — paired | Partner linked | Partner progress/labels; sync indicators |
| TC-UI-73 | Monitor dashboard | Paired & unpaired | Correct asymmetric UI vs product |
| TC-UI-74 | Pull to refresh | If implemented | Completes; errors non-silent |
| TC-UI-75 | Settings / overflow menus | Open each destination | Each row navigates; **Back** returns correctly |

### 14.8 Pairing UI (in-app + cross-device)

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-UI-80 | Show pairing code / QR | Generate invite | Code readable; QR scans on second device |
| TC-UI-81 | Enter code UI | Type code | Validation feedback live |
| TC-UI-82 | Success animation/copy | Complete pair | Success state; dashboards update `isPaired` |
| TC-UI-83 | Unpair — if exposed | Confirm destructive action | Both devices converge to unpaired UI |

### 14.9 Overrides / break-glass / OTP (if surfaced in UI)

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-UI-90 | Grant OTP | Controller/mutual grants | Code displays / channels correctly |
| TC-UI-91 | Redeem OTP | Controlled/mutual redeems | Unlock matches `canRedeemOverride` |
| TC-UI-92 | Expired OTP | Wait past validity | Clear failure copy |

### 14.10 Wellness / activity / policy UI (ViewModels injected in `Sweat2ScrollApp`)

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-UI-100 | Activity summaries | Open screens tied to `ActivityViewModel` | Data loads; errors surfaced |
| TC-UI-101 | Policy / unlock status | Screens tied to `PolicyViewModel` | Reflects goal + shield state |
| TC-UI-102 | Wellness metrics | `WellnessViewModel` surfaces | Charts/lists scroll; privacy-sensitive copy OK |

### 14.11 Errors, edge UI & resilience

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-UI-110 | Airplane mid-form | Toggle airplane during sign-up | Recoverable message; no corrupted navigation stack |
| TC-UI-111 | Low memory / slow network | Throttle network (Developer settings) | Spinners/timeouts; no blank white screens |
| TC-UI-112 | Rotate (if supported) | Rotate on key screens | Layout adapts or locks gracefully per design |

### 14.12 Subsystems exposed in the UI (auth-area scope today; expand per batch)

These rows pin behavior of services the user can perceive but that aren't a single SwiftUI screen. Add rows here as later batches (overrides, OPA, daily reset) are implemented and tested.

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-UI-120 | `EmailCredentialStore` persistence | Sign up via username → kill app → relaunch → sign in with same username/password | Same `appleUserID` resolved → same CloudKit account → no PRD re-trigger |
| TC-UI-121 | `EmailCredentialStore` wrong password | Sign in with the right username but wrong password | Specific error surfaces in `authError`; no session is started |
| TC-UI-122 | `AuthManager.signOut` UX | Trigger sign-out from wherever surfaced | UI returns to Sign In; cached account cleared from memory; no stale name shown anywhere |
| TC-UI-123 | `AppSession.isDevCredentialMatch` Release safety | In Release build, type `puji` / `1234` into Sign In | Submit runs the real path and fails with "no account" from `EmailCredentialStore` — the dev bypass is `#if DEBUG`-gated and unreachable |

### 14.13 Subsystems II — TOTP / CalorieEngine / DailyReset / Override / Pairing

These pin pure-logic services that drive partner OTPs, calorie goals, midnight rollover, override grants, and pair-code input. Each row has matching XCTest coverage in `Sweat2ScrollTests/`. Cloud-dependent rows are still manual on-device.

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-UI-130 | TOTP RFC 6238 conformance | Run `TOTPServiceTests.testRFC6238_SHA256_T1_sixDigitTrailing` | Code at counter=1 with the standard secret = "119246" (last 6 of RFC 8-digit value 46119246) |
| TC-UI-131 | TOTP determinism + format | `TOTPServiceTests.testHOTP_alwaysSixDigits` + `testHOTP_isDeterministic` | Same secret + counter → same code; output is always 6 digits zero-padded |
| TC-UI-132 | TOTP drift tolerance constant | `TOTPServiceTests.testDriftToleranceConstant` | `driftTolerance == 1` (±30s acceptable) |
| TC-UI-133 | CalorieEngine cohort boundaries | `CalorieEngineExtraTests.testAgeCohort_*` | 12y → pediatric, 13y → adolescent, 18y → adolescent, 19y → adult |
| TC-UI-134 | CalorieEngine hard caps | `CalorieEngineExtraTests.testHardCaps_pinnedValues` | 500 / 800 / 1000 kcal — silent change is a fail |
| TC-UI-135 | CalorieEngine .other sex branch | `CalorieEngineExtraTests.testComputeRMR_adult_otherSex_*` | RMR for `.other` lies between male and female; pediatric `.other` uses girls formula |
| TC-UI-136 | CalorieEngine validate(target:) | `testValidate_*` cases | High target → invalid w/ cap in reason; low → invalid; in-range → valid |
| TC-UI-137 | CalorieEngine stepsEquivalent zero-weight | `testStepsEquivalent_zeroWeight_doesNotCrash` | No crash; falls back to 70 kg reference (regression guard) |
| TC-UI-138 | CalorieEngine stepsEquivalent zero/negative kcal | `testStepsEquivalent_zeroCalories_returnsZero` + negative case | Returns 0 |
| TC-UI-139 | DailyReset midnight rollover | `DailyResetManagerTests.testReset_yesterdayLastReset_triggersReset` | Burned-calorie counter zeroed when last reset was a previous calendar day |
| TC-UI-140 | DailyReset 30-min free window | `testReset_freeWindowIs30MinutesFromMidnight` | `freeWindowEnd == startOfDay + 30 min` exactly |
| TC-UI-141 | DailyReset idempotent within day | `testReset_idempotentWithinSameDay` | Second call same day must not zero burned counter or shift window |
| TC-UI-142 | DailyReset grant-extension never shortens | `testGrantExtension_neverShortensExistingWindow` | Extending while a far-future window exists never moves end earlier |
| TC-UI-143 | EmergencyOverride partnershipID symmetry | `EmergencyOverrideTests.testPartnershipID_isSymmetric` | `partnershipID(a,b) == partnershipID(b,a)` |
| TC-UI-144 | EmergencyOverride duration clamping | `testClampedDuration_*` | <5 → 5, >240 → 240, in-range unchanged |
| TC-UI-145 | EmergencyOverride grant Codable | `testGrant_codableRoundTrip` | Encode → decode preserves all fields (within 1s for dates) |
| TC-UI-146 | Pairing code normalize valid | `PairingServiceTests.testNormalize_*` valid cases | Strips spaces / dashes / dots; accepts 6 digits including leading zeros |
| TC-UI-147 | Pairing code normalize reject | `testNormalize_tooShort` / `testNormalize_tooLong` / `testNormalize_lettersOnly` | Returns nil; `validateAndPair` short-circuits before CloudKit |
| TC-UI-148 | PairingResult equality + payload | `testPairingResult_*` | `.invalid != .expired`; `.success(monitorID:)` carries the linked id |

---

## 17. Release readiness checklist (App Store gate)

These are explicit, individually verifiable rows — replaces the single bullet under §13. Run before every TestFlight upload that's a release candidate.

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-REL-01 | Production aps-environment | Inspect entitlements of the **Release** archive | `aps-environment = production` for main app and any push-receiving extension |
| TC-REL-02 | Family Controls Distribution profile | Inspect provisioning profile in archive | Distribution Family Controls entitlement present (no Xcode "Development-only" yellow warning) |
| TC-REL-03 | Bundle IDs match App Store Connect | Compare archive bundle IDs vs App Store Connect listing | All match: main app + 3 extensions (`DeviceActivityMonitorExtension`, `ShieldConfigurationExtension`, `ShieldActionExtension`) |
| TC-REL-04 | DEBUG-only UI gone in Release | Build Release config; open Sign In | **No** "Tester login: …" chip visible; no other DEBUG affordances surface |
| TC-REL-05 | Privacy: no health data on disk | Run app, generate activity, then dump `Documents/`, `Library/Caches/`, `Library/Preferences/`, Keychain entries | No persisted HealthKit metric values (steps, kcal, HR, HRV, sleep). Per CLAUDE.md: in-memory only |
| TC-REL-06 | Info.plist usage strings | Check `NSHealthShareUsageDescription`, `NSHealthUpdateUsageDescription`, FamilyControls, push, Apple Sign-In strings | All present, accurate, user-readable; no placeholder text |
| TC-REL-07 | Privacy nutrition label accuracy | Cross-check App Store Connect privacy responses against actual data flows | Health data category truthfully declared; CloudKit data flows declared |
| TC-REL-08 | Required device capabilities | Inspect Info.plist / archive | iPhone-only declared correctly; min iOS 16+ matches CLAUDE.md |
| TC-REL-09 | Icons + launch assets | Open archive in Organizer | All required icon sizes present; launch screen renders without missing assets |
| TC-REL-10 | Crash-on-launch smoke (Release) | Install Release build via TestFlight on a fresh device | Reaches Sign In within 25s without crash (mirrors `testLaunch_reachesSignInChrome`) |
| TC-REL-11 | App Store screenshots up to date | Check Connect listing | Match current UI; no screenshots from removed/renamed flows |
| TC-REL-12 | Dev tester credentials not exploitable in Release | Per TC-UI-123, confirm Release does not accept `puji`/`1234` | Disabled CTA in Release; unreachable code path |
| TC-REL-13 | App Group provisioned at portal | Inspect the App ID at developer.apple.com → App Groups | `group.com.sweat2scroll.appblocker` is enabled on the App ID for the main app and all three extensions. On launch, console shows `[AppGroup] OK`. If `[AppGroup] FAIL` shows up, re-download the provisioning profile after enabling the capability. (Mitigates the cfprefsd `kCFPreferencesAnyUser` log warning observed in early builds.) |
| TC-REL-14 | HealthKit background delivery provisioned | Inspect the App ID at developer.apple.com → Capabilities | "HealthKit" is enabled with the **Background Delivery** sub-option checked. Entitlements file declares `com.apple.developer.healthkit.background-delivery`. Provisioning profile is re-downloaded after enabling. Verify by foreground-running the app, backgrounding for 10+ min while activity is logged, and confirming `HKObserverQuery` callbacks fire (no "Missing com.apple.developer.healthkit.background-delivery entitlement" log on launch). |

---

## 18. Build variants (DEBUG vs Release)

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-VAR-01 | DEBUG: tester chip visible | DEBUG build → Sign In | Chip visible per TC-UI-21 |
| TC-VAR-02 | Release: tester chip absent | Release build → Sign In | Chip is absent (per TC-REL-04 / TC-UI-123) |
| TC-VAR-03 | DEBUG: dev session skips CloudKit | DEBUG `devSignIn` flow | `isDevSession == true`; subsequent `complete*Onboarding` writes are guarded by `if !isDevSession` and not sent to CloudKit |
| TC-VAR-04 | Release: dev shortcut unreachable | Per TC-UI-123 | `isDevCredentialMatch` call site is `#if DEBUG`-gated in `signInUsername()`; verify by source diff before each release |

---

## 19. Permission revocation mid-session

| ID | Scenario | Steps | Expected |
|----|----------|-------|----------|
| TC-PERM-01 | Revoke HealthKit while running | Settings → Privacy → Health → revoke for Sweat2Scroll → return to app | UI handles missing data gracefully — no crash; clear "permissions needed" copy; relink path works |
| TC-PERM-02 | Revoke Family Controls while running | Settings → Screen Time → revoke Sweat2Scroll's authorization → return | `ScreenTimeService.refreshAuthorizationStatus` reflects new status; shield no longer enforced; app prompts to re-authorize |
| TC-PERM-03 | Disable Background App Refresh | Settings → General → Background App Refresh → disable for app | Background HealthKit/CK sync skipped silently; in-app refresh still works on foreground |
| TC-PERM-04 | iCloud signed out | Settings → sign out of iCloud while app foreground | CloudKit calls fail predictably; user sees actionable copy; pairing/sync paused; no blank-overwrite per TC-AUTH-13/14 |
| TC-PERM-05 | Re-grant after revoke | Re-grant any of the above in Settings → return to app | `scenePhase == .active` triggers refresh in `RootView`; previously-degraded UI restores |

---

## 15. Execution log (copy per cycle)

| TC ID | Pass / Fail / Blocked | Build | Device | Notes |
|-------|----------------------|-------|--------|-------|
| | | | | |

**Blocked** = external dependency (e.g. entitlement not approved, CK production schema).

Use **Fail** for any §2 violation — track fix + re-run until **Pass**.

---

## 16. Ownership

Update this document when:

- New `PostAuthOnboardingStep` or dashboard routes are added.
- Pairing protocol or `PartnershipRole` semantics change.
- New extensions or entitlements ship.
- New UI surfaces ship — add rows under §14 with new TC-UI IDs.
- New subsystem coverage lands — add rows under §14.12 (or open a new §14.X section per area: overrides, OPA, daily reset, tamper, deep links).
- Release-blocking infrastructure changes — update §17 (e.g., new entitlement, new privacy data category).

---

*Last aligned with in-repo routing: `RootView`, `AuthManager`, `AppAuthModels`, `CloudKitService`, `ScreenTimeService`, `SignInView`, `SignUpView`, `SoloOnboardingView`, `Sweat2ScrollApp`.*
