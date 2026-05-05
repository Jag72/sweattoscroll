# Policy/fitness_policy.rego
# Open Policy Agent (OPA) policy for Sweat2Scroll.
# Authored in Rego — compiled to WebAssembly via:
#   opa build -t wasm -e sweat2scroll/contract/allow \
#             -e sweat2scroll/contract/requires_grace_period \
#             policy/fitness_policy.rego
#
# Output: bundle.tar.gz → extract contract.wasm (~142 KB)
# Add contract.wasm to Xcode project under Resources/
#
# Static verification: run through Z3 SMT solver before deployment
# to detect unreachable states and contradictory rules.

package sweat2scroll.contract

import future.keywords.if
import future.keywords.in

# ─── DEFAULT STATES ──────────────────────────────────────────────────────────
# Fail-closed by default: deny access unless a rule explicitly grants it.

default allow             := false
default requires_grace    := false
default deny_reason       := "Daily fitness goal not yet reached."

# ─── PRIMARY RULE: CALORIE-BASED UNLOCK ─────────────────────────────────────
# Grant access when active calorie goal is met and no time drift detected.

allow if {
    input.goal_currency == "activeCalories"
    input.current_active_calories >= input.daily_calorie_goal
    not input.time_drift_detected
}

# ─── PRIMARY RULE: STEP-BASED UNLOCK ────────────────────────────────────────

allow if {
    input.goal_currency == "steps"
    input.current_steps >= input.daily_steps_goal
    not input.time_drift_detected
}

# ─── BREAK-GLASS OVERRIDE ───────────────────────────────────────────────────
# Grant access when a valid TOTP override is active and not expired.
# Clock drift check still applies — override is invalid if time is manipulated.

allow if {
    input.override_active == true
    input.current_time < input.override_expiration
    not input.time_drift_detected
}

# ─── FAIL-SOFT GRACE PERIOD ─────────────────────────────────────────────────
# Grant a 5-minute grace period when:
#   - Goal is not yet met (normal deny case)
#   - Data is demonstrably stale (>1 hour since last HealthKit sample)
#   - The UI sync timer has expired (user waited, no data arrived)
# This prevents false negatives from BLE sync lag penalizing honest users.

requires_grace if {
    input.current_active_calories < input.daily_calorie_goal
    input.data_staleness_seconds > 3600
    input.ui_timer_expired == true
    not input.time_drift_detected
}

# ─── SECURITY: TIME DRIFT LOCKOUT ───────────────────────────────────────────
# If the monotonic clock diverges from the wall clock, assume adversarial
# time manipulation. Fail-closed: deny all access regardless of goal state.

deny_reason := "Security lockout: system clock manipulation detected." if {
    input.time_drift_detected == true
}

# ─── DENY REASON: NORMAL GOAL INCOMPLETE ────────────────────────────────────

deny_reason := remaining_message if {
    not allow
    not input.time_drift_detected
    input.goal_currency == "activeCalories"
    remaining := input.daily_calorie_goal - input.current_active_calories
    remaining_message := sprintf("%.0f kcal remaining to unlock.", [remaining])
}

deny_reason := remaining_message if {
    not allow
    not input.time_drift_detected
    input.goal_currency == "steps"
    remaining := input.daily_steps_goal - input.current_steps
    remaining_message := sprintf("%d steps remaining to unlock.", [remaining])
}

# ─── SAFETY CAP VALIDATION ──────────────────────────────────────────────────
# Verifies the agreed goal does not exceed the age-appropriate hard cap.
# This is enforced in Swift (CalorieEngine) but double-checked in policy.

goal_within_safe_bounds if {
    input.daily_calorie_goal <= input.hard_cap
    input.daily_calorie_goal >= 50
}
