# Sweat2Scroll — Developer Build Guide

Complete end-to-end guide for building, configuring, and deploying the Sweat2Scroll iOS app.

---

## Project Structure

```
sweattoscroll/
├── index.html              ← Marketing landing page (GitHub Pages)
├── README.md
├── CNAME
├── CLAUDE.md               ← Claude Code memory (read at every session start)
└── app/
    └── Sweat2Scroll/
        ├── App/
        │   └── Sweat2ScrollApp.swift       ← Entry point, FamilyControls auth
        ├── Models/
        │   ├── UserProfile.swift           ← Biometric model (HealthKit data)
        │   ├── ActivityGoal.swift          ← Daily fitness contract
        │   ├── UnlockPolicy.swift          ← OPA input/output models
        │   ├── GovernanceContract.swift    ← Peer-to-peer pairing contract
        │   └── AuditEvent.swift            ← W3C PROV-DM audit log model
        ├── Services/
        │   ├── CalorieEngine.swift         ← Mifflin-St Jeor + IOM EER + CDC caps
        │   ├── HealthKitService.swift      ← HealthKit queries + background delivery
        │   ├── OPAService.swift            ← WasmKit + OPA policy evaluation
        │   ├── ScreenTimeService.swift     ← FamilyControls + ManagedSettings
        │   ├── TOTPService.swift           ← CryptoKit TOTP + ECDH pairing
        │   ├── CloudKitService.swift       ← CKShare + encrypted audit sync
        │   └── TamperDetectionService.swift ← Watchdog + clock drift detection
        ├── ViewModels/
        │   ├── ActivityViewModel.swift     ← Main coordinator (HealthKit → OPA → ScreenTime)
        │   └── ViewModels.swift            ← Onboarding, Policy, Partner VMs
        ├── Views/
        │   ├── HomeView.swift              ← Main dashboard
        │   ├── AllViews.swift              ← Onboarding, Settings, BreakGlass, AuditLog
        │   └── Components/
        │       └── Components.swift        ← ProgressRing, ShieldToggle
        ├── Extensions/
        │   ├── DeviceActivityMonitorExtension.swift  ← Background enforcement (separate target)
        │   ├── ShieldConfigurationExtension.swift    ← Gamified shield UI (separate target)
        │   ├── ShieldActionExtension.swift           ← Shield buttons (separate target)
        │   └── SwiftExtensions.swift                 ← Utilities
        ├── Policy/
        │   └── fitness_policy.rego         ← OPA Rego policy source
        └── Resources/
            ├── Info-Requirements.plist     ← Required Info.plist keys + setup checklist
            └── contract.wasm              ← Compiled OPA bundle (ADD AFTER COMPILING)
```

---

## Phase 1: Xcode Project Setup

### Step 1 — Xcode Capabilities
In your main app target → **Signing & Capabilities** → add:

| Capability | Notes |
|---|---|
| HealthKit | Enables HKHealthStore |
| iCloud | Enable CloudKit container: `iCloud.com.sweat2scroll` |
| Push Notifications | Required for CloudKit silent push |
| App Groups | Add: `group.com.sweat2scroll.appblocker` |
| Background Modes | Check: Fetch, Remote notifications, Background processing |
| Family Controls | **Requires Apple approval** (see below) |

### Step 2 — Request Family Controls Entitlement
Apply at: https://developer.apple.com/contact/request/family-controls-entitlement
Select: **Individual** (not parental). Takes 1–3 business days.

During development, you can test with `.individual` authorization mode (already set in `Sweat2ScrollApp.swift`).

### Step 3 — Create Extension Targets
**File → New → Target** for each:

| Extension | Class to use | Target Name |
|---|---|---|
| Device Activity Monitor | `Sweat2ScrollActivityMonitor` | `DeviceActivityMonitorExtension` |
| Shield Configuration | `Sweat2ScrollShieldConfiguration` | `ShieldConfigurationExtension` |
| Shield Action | `Sweat2ScrollShieldAction` | `ShieldActionExtension` |

For each extension, add App Group: `group.com.sweat2scroll.appblocker`

### Step 4 — Add WasmKit via Swift Package Manager
**File → Add Package Dependencies**
```
https://github.com/swiftwasm/WasmKit
```
Add to main app target only (not extensions).

---

## Phase 2: Compile the OPA Policy to WebAssembly

### Install OPA CLI
```bash
brew install opa
```

### Compile Rego → Wasm
```bash
cd app/Sweat2Scroll/Policy/

opa build \
  -t wasm \
  -e sweat2scroll/contract/allow \
  -e sweat2scroll/contract/requires_grace \
  fitness_policy.rego \
  -o bundle.tar.gz

# Extract the Wasm module
tar -xzf bundle.tar.gz
mv /policy.wasm ../Resources/contract.wasm
```

### Add to Xcode
Drag `contract.wasm` into Xcode under `Resources/`.
Check: **Target Membership → Sweat2Scroll** ✅

### Verify size (~142 KB expected)
```bash
ls -lh app/Sweat2Scroll/Resources/contract.wasm
```

---

## Phase 3: CloudKit Schema Setup

In **CloudKit Dashboard** (https://icloud.developer.apple.com):

### Record Types to Create

**AuditEvent**
| Field | Type | Encrypted |
|---|---|---|
| eventType | String | No |
| timestamp | Date/Time | No |
| agentDisplayName | String | No |
| caloriesAtEvent | Double | Yes |
| goalAtEvent | Double | Yes |
| overrideActive | Int(64) | Yes |
| jsonLDPayload | Bytes | Yes |
| notes | String | Yes |

**PartnerProgress**
| Field | Type | Encrypted |
|---|---|---|
| calories | Double | No |
| steps | Int(64) | No |
| goal | Double | No |
| currency | String | No |
| lastUpdated | Date/Time | No |

---

## Phase 4: WasmKit Integration (Complete OPAService.swift)

After adding WasmKit via SPM, complete `OPAService.swift`:

```swift
import WasmKit

// In loadModule():
let wasmBytes = try Array(Data(contentsOf: wasmURL))
let engine = Engine()
let store = Store(engine: engine)
let module = try parseWasm(bytes: wasmBytes)
instance = try module.instantiate(store: store, imports: [:])
isModuleLoaded = true

// In evaluate():
// 1. Write JSON input to Wasm linear memory
// 2. Call OPA entrypoint function via instance.export("opa_eval")
// 3. Read JSON output from memory pointer
// 4. Decode PolicyResult
```

Refer to: https://github.com/swiftwasm/WasmKit/blob/main/README.md

---

## Phase 5: Testing Strategy

### Simulator (what works)
- HealthKit with mock data (use Health app on simulator)
- CloudKit (use development environment)
- OPA policy evaluation
- CalorieEngine computation
- UI flows end-to-end

### Physical Device Required For
- FamilyControls / ManagedSettings (will crash on simulator)
- DeviceActivityMonitor extension
- Shield overlays
- Real HealthKit data from Apple Watch

### Test Checklist
- [ ] HealthKit authorization flow
- [ ] Calorie goal computed from biometrics (check against CalorieEngine formulas)
- [ ] OPA policy: allow when calories >= goal
- [ ] OPA policy: deny when calories < goal
- [ ] OPA policy: grace period when data stale + timer expired
- [ ] OPA policy: break-glass override
- [ ] Shield engages on toggle
- [ ] Shield disengages when goal met
- [ ] TOTP: generate code on Partner B device, validate on Partner A
- [ ] CloudKit: audit event saved and fetched
- [ ] Tamper detection: revoke HealthKit permission → CloudKit alert fires
- [ ] Clock drift: change system clock → policy returns drift error

---

## Phase 6: Build Order for Claude Code

When running `claude` from the repo root, implement in this order:

1. `HealthKitService.swift` — complete all TODOs
2. `CalorieEngine.swift` — verify formulas against unit tests
3. `OPAService.swift` — integrate WasmKit (after SPM package added)
4. `ScreenTimeService.swift` — complete DeviceActivity scheduling
5. `TOTPService.swift` — complete ECDH exchange
6. `CloudKitService.swift` — complete CKShare setup
7. `ActivityViewModel.swift` — wire all services together
8. UI views — complete all placeholder TODOs
9. Extensions — each needs its own Xcode target

---

## Key Constraints (Never Violate)

| Constraint | Why |
|---|---|
| Never store health data to disk | Privacy — keep in memory only |
| Hard cap: 1000 kcal adult, 800 teen, 500 child | Safety — enforced in CalorieEngine + Rego |
| Max 10 restricted apps | UX + FamilyActivityPicker recommendation |
| FamilyControls runs on physical device only | Apple sandbox restriction |
| Background HealthKit delivery: hourly max | Apple OS throttling — cannot override |
| Wasm module must pass hash pinning | Security — prevents policy tampering |
| All CloudKit sensitive fields use encryptedValues | End-to-end encryption guarantee |
| TOTP drift tolerance: ±1 period (30s) | Clock desync between paired devices |

---

## App Store Submission Notes

- **Age Rating**: 4+ (no objectionable content)
- **Privacy Nutrition Label**: Health & Fitness data (on-device only)
- **Review Notes**: Mention Family Controls entitlement is approved
- **TestFlight**: Use internal testing first (FamilyControls requires real device)
- **Entitlement**: Include Apple's approval email in App Review notes
