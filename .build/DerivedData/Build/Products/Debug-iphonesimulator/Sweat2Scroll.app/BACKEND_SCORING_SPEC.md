# Backend Health Scoring Specification
# Sweat2Scroll — WHOOP-style Recovery / Strain / Sleep Engine

> Status: **Reference — not yet implemented**
> Saved: 2026-03-25

---

## Architecture Overview

The iOS app reads HealthKit data on-device, normalizes it, and sends it to the backend.
The backend computes Recovery, Strain, and Sleep scores, then sends results back to the app.

**Apple Health values used directly (no custom model needed):**
- Sleep stages (`sleepAnalysis` — awake, REM, core, deep)
- Resting heart rate
- Respiratory rate
- Active energy burned (`activeEnergyBurned`)
- Basal energy burned (`basalEnergyBurned`)
- Heart rate recovery
- Workouts (type, duration, avg HR)
- HRV SDNN (`heartRateVariabilitySDNN`)
- Heartbeat series (beat-to-beat intervals for custom RMSSD)

---

## Python Libraries

| Purpose | Library | License | Install |
|---|---|---|---|
| HRV features | `pyhrv` | BSD-3 | `pip install pyhrv` |
| HRV (alt) | `hrv-analysis` | GPLv3 | check license for commercial use |
| Activity classification | HART | MIT | via Keras model import |
| Phone-based calorie estimation | OpenMetabolics | MIT | `main.py` pipeline |
| Watch-based calorie estimation | WristBased-EE-Estimation | MIT | minute-by-minute MET from IMU |
| Sleep staging (custom) | WatchSleepNet / SleepStagePrediction | — | use only if skipping Apple stages |

---

## Algorithms

### 1. RMSSD / lnRMSSD from RR intervals

```python
import numpy as np

def rmssd(rr_ms):
    rr = np.asarray(rr_ms, dtype=float)
    diff = np.diff(rr)
    return np.sqrt(np.mean(diff ** 2))

def lnrmssd(rr_ms):
    return np.log(max(rmssd(rr_ms), 1e-6))
```

**Use:** Compute on backend from heartbeat series sent by the watch.
Apple already exposes `heartRateVariabilitySDNN`; if beat-to-beat intervals are available,
compute RMSSD / lnRMSSD yourself for a richer signal.

---

### 2. Recovery Score (0–100)

Inputs: today's values + rolling 14–28-day baselines.
Weights: lnRMSSD (40%), resting HR (25%), respiratory rate (10%), sleep score (25%),
yesterday's strain (10% negative).

```python
def z(x, mean, std):
    std = max(std, 1e-6)
    return (x - mean) / std

def recovery_score(lnrmssd_today, lnrmssd_base, lnrmssd_sd,
                   rhr_today, rhr_base, rhr_sd,
                   resp_today, resp_base, resp_sd,
                   sleep_score_0_100,
                   yday_strain, strain_base, strain_sd):
    score = (
        0.40 * z(lnrmssd_today, lnrmssd_base, lnrmssd_sd)
      - 0.25 * z(rhr_today, rhr_base, rhr_sd)
      - 0.10 * z(resp_today, resp_base, resp_sd)
      + 0.25 * (sleep_score_0_100 / 100.0)
      - 0.10 * z(yday_strain, strain_base, strain_sd)
    )
    # Squash to 0–100 via sigmoid
    return max(0, min(100, 100 / (1 + np.exp(-score))))
```

---

### 3. Strain Score (0–21, Banister TRIMP)

TRIMP = non-linear cardiovascular load per workout.
Strain = 0–21 log-scaled daily total across all workouts.

```python
import math

def trimp(duration_min, avg_hr, rest_hr, max_hr, k=1.8):
    hrr = (avg_hr - rest_hr) / max(max_hr - rest_hr, 1e-6)
    hrr = max(0.0, min(1.0, hrr))
    return duration_min * hrr * math.exp(k * hrr)

def day_strain(trimp_values, ref_load=300):
    total = sum(trimp_values)
    return min(21.0, 21.0 * math.log1p(total) / math.log1p(ref_load))
```

---

### 4. Sleep Score (0–100)

```python
def sleep_score(sleep_perf,      # hours_slept / hours_needed  (0–1)
                efficiency,       # time_asleep / time_in_bed   (0–1, scaled 0–100)
                consistency,      # regularity of sleep/wake times (0–100)
                stage_quality,    # REM + deep proportion (0–100)
                resp_stability):  # low respiratory disturbance (0–100)
    raw = (
        0.40 * sleep_perf * 100 +
        0.20 * efficiency +
        0.15 * consistency +
        0.15 * stage_quality +
        0.10 * resp_stability
    )
    return max(0, min(100, raw))
```

---

## Recommended Implementation Priority

### Phase 1 — Use Apple Health directly (ship fast)
- `activeEnergyBurned` and `basalEnergyBurned` for calorie goal gating (already done in app)
- `heartRateVariabilitySDNN` for Recovery inputs
- `sleepAnalysis` stages for Sleep score
- Resting HR and respiratory rate for Recovery

### Phase 2 — Backend scoring service
- POST `/api/v1/health-snapshot` — receive normalized HealthKit payload from iOS
- Compute Recovery, Strain, Sleep scores server-side
- Store rolling 28-day baseline per user
- Return scores to app for display on Dashboard

### Phase 3 — Custom ML (optional)
- HART for activity classification if workout type detection is needed
- WristBased-EE-Estimation if calorie override is needed
- Custom sleep staging only if Apple stages are insufficient

---

## API Payload Shape (draft)

```json
{
  "user_id": "uuid",
  "date": "2026-03-25",
  "hrv_sdnn": 52.3,
  "rr_intervals_ms": [820, 810, 835, ...],
  "resting_hr": 58,
  "respiratory_rate": 14.2,
  "active_calories": 420,
  "basal_calories": 1800,
  "workouts": [
    {
      "type": "running",
      "duration_min": 35,
      "avg_hr": 152,
      "max_hr": 174
    }
  ],
  "sleep": {
    "total_hours": 7.2,
    "efficiency": 0.89,
    "rem_hours": 1.8,
    "deep_hours": 1.2,
    "awake_hours": 0.5,
    "consistency_score": 78
  }
}
```

---

## Notes
- WHOOP's exact Recovery and Strain formulas are proprietary. The formulas above are
  well-supported public approximations (TRIMP is peer-reviewed; RMSSD is the field standard).
- Rolling baselines must be personalized — scores are relative to each user's own history,
  not population norms.
- Health data must never be stored to disk on-device (app constraint). The backend is the
  only persistent store for health snapshots.
