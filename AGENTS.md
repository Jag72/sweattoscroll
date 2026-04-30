# Sweat2Scroll — Codex Memory

## Project Overview
iOS app that gates social media access behind real physical activity.
User must hit a daily fitness goal (HealthKit) before designated apps unlock (FamilyControls).

## Research Foundation
- Paper: "Fitness-Contingent Screen Access Control Using OPA and WebAssembly on Mobile Edge Devices"
- Presented: IEEE SoutheastCon 2026, March 7, 2026
- Author: Jagadish Krishna Pilla

## Tech Stack
- **Language**: Swift / SwiftUI
- **Fitness data**: Apple HealthKit (steps, active calories, heart rate, workouts)
- **Policy engine**: Open Policy Agent (OPA) compiled to WebAssembly (WASM)
- **Enforcement**: FamilyControls API (Screen Time framework)
- **Policy language**: Rego (OPA's policy language)
- **Min iOS**: iOS 16+
- **Architecture**: MVVM

## Project Structure
```
SweatToScroll/
├── App/
│   └── SweatToScrollApp.swift       # App entry point, FamilyControls auth request
├── Models/
│   ├── ActivityGoal.swift           # User's daily target (steps/calories/minutes)
│   └── UnlockPolicy.swift           # OPA policy result model
├── ViewModels/
│   ├── ActivityViewModel.swift      # HealthKit data + goal progress
│   └── PolicyViewModel.swift        # OPA evaluation + FamilyControls enforcement
├── Views/
│   ├── HomeView.swift               # Main dashboard — progress ring + status
│   ├── GoalSetupView.swift          # Onboarding — set daily target
│   └── SettingsView.swift           # App selection, threshold config
├── Services/
│   ├── HealthKitService.swift       # HealthKit queries and authorization
│   ├── OPAService.swift             # Loads WASM bundle, evaluates Rego policy
│   └── ScreenTimeService.swift      # FamilyControls — lock/unlock apps
├── Policy/
│   └── fitness_policy.rego          # OPA policy definition
└── Resources/
    └── fitness_policy.wasm          # Compiled OPA policy bundle
```

## Core Logic Flow
1. App launches → request HealthKit + FamilyControls authorization
2. Background task queries HealthKit every 15 min
3. ActivityViewModel computes progress toward daily goal
4. OPAService evaluates fitness_policy.wasm with current activity data
5. If policy returns `allow = true` → ScreenTimeService unlocks apps
6. If policy returns `allow = false` → apps remain locked

## Key Entitlements Required
- `com.apple.developer.family-controls` (requires Apple entitlement approval)
- `com.apple.developer.healthkit`
- Background Modes: Background fetch, Background processing

## OPA Policy Logic (Rego)
```rego
package fitness

default allow = false

allow {
    input.active_calories >= input.goal_calories
}

allow {
    input.steps >= input.goal_steps
}

allow {
    input.workout_minutes >= input.goal_minutes
}
```

## GitHub Repo
- URL: https://github.com/Jag72/sweattoscroll
- Main branch: main
- Commit style: conventional commits (feat:, fix:, chore:)

## Important Constraints
- FamilyControls API requires physical device — cannot test on simulator
- HealthKit also requires physical device for real data (simulator has mock data)
- OPA WASM bundle must be compiled separately using `opa build`
- Never store health data to disk — keep in memory only (privacy)

## Current Status
- [x] Xcode project created
- [x] HealthKit integration (activity + biometrics + wellness metrics: HRV, RHR, sleep, respiratory rate)
- [x] OPA/WASM integration (WasmKit bridge fully written — add WasmKit via SPM to compile)
- [x] FamilyControls integration (Distribution entitlement approved 2026-03-20 for com.jagadish.sweat2scroll)
- [x] Home UI + full view hierarchy (Auth, Onboarding, Dashboards, Pairing, Wellness)
- [x] Onboarding flow (Solo, User, Monitor modes)
- [x] CloudKit schema bootstrap, tamper alert subscription, partner sync
- [ ] Add WasmKit package via Xcode SPM (File → Add Package Dependencies)
- [ ] Run on physical device to bootstrap CloudKit schema, then deploy to Production in Dashboard
- [ ] Change aps-environment in entitlements to "production" before archiving for App Store
- [ ] App Store submission
