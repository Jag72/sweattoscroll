#!/usr/bin/env python3
"""End-to-end logic simulation for Sweat2Scroll — simulates both partner devices
and replicates the exact Swift code paths to verify suspected flaws."""

import hashlib, hmac, struct, random, math
from cryptography.hazmat.primitives.asymmetric.ec import (
    generate_private_key, SECP256R1, ECDH)
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes, serialization

print("=" * 72)
print("SIM 1 — ECDH pairing protocol (QR flow), exact replication of Swift")
print("=" * 72)
# Device A (initiator): OnboardingViewModel.generatePairingQRCode()
#   -> creates ephemeralPrivateKey A1, puts A1.public in QR. A1 stored in VM.
A1 = generate_private_key(SECP256R1())
qr_pubkey = A1.public_key()

# Device B (joiner): handleScannedQRCode -> TOTPService.performECDHExchange(A1.pub)
#   Swift: generates a FRESH private key B1 inside the function, derives secret,
#   returns B1.public
def perform_ecdh_exchange(partner_pub):
    priv = generate_private_key(SECP256R1())          # fresh ephemeral, always
    shared = priv.exchange(ECDH(), partner_pub)
    key = HKDF(algorithm=hashes.SHA256(), length=32,
               salt=b"sweat2scroll-v1", info=b"").derive(shared)
    return key, priv.public_key()

B_secret, B1_pub = perform_ecdh_exchange(qr_pubkey)   # B stores B_secret

# Device A: completePairingAsInitiator(B1.pub) -> performECDHExchange AGAIN
#   Swift generates ANOTHER fresh key A2 (A1 is never used for derivation!)
A_secret, A2_pub = perform_ecdh_exchange(B1_pub)      # A stores A_secret

print(f"Device A derived secret: {A_secret.hex()[:32]}…")
print(f"Device B derived secret: {B_secret.hex()[:32]}…")
print(f"SECRETS MATCH: {A_secret == B_secret}")

# What SHOULD happen (A reuses A1):
shared_correct_A = A1.exchange(ECDH(), B1_pub)
key_correct_A = HKDF(algorithm=hashes.SHA256(), length=32,
                     salt=b"sweat2scroll-v1", info=b"").derive(shared_correct_A)
print(f"(If A reused its QR key A1: match with B = {key_correct_A == B_secret})")

print()
print("=" * 72)
print("SIM 2 — TOTP break-glass with mismatched secrets (exact Swift HOTP)")
print("=" * 72)
def compute_hotp(secret: bytes, counter: int) -> str:
    mac = hmac.new(secret, struct.pack(">Q", counter), hashlib.sha256).digest()
    offset = mac[-1] & 0x0F
    val = (struct.unpack(">I", mac[offset:offset+4])[0] & 0x7FFFFFFF) % 10**6
    return f"{val:06d}"

import time
counter = int(time.time() // 30)
code_from_A = compute_hotp(A_secret, counter)   # monitor generates
# controlled user validates with THEIR secret, ±1 drift (Swift validateCode)
valid = any(compute_hotp(B_secret, counter + d) == code_from_A for d in (-1, 0, 1))
print(f"Monitor's TOTP code: {code_from_A}")
print(f"User-side validation result: {valid}  (expected on real devices: False)")

print()
print("=" * 72)
print("SIM 3 — CloudKit private-DB visibility model (6-digit pairing, both sides)")
print("=" * 72)
# Each iCloud account has its OWN private database. Model as separate dicts.
class PrivateDB(dict): pass
monitor_db, user_db = PrivateDB(), PrivateDB()   # two different iCloud accounts

# Monitor device: PairingService.generateCode -> savePairCodeRecord (privateDB)
code = f"{random.randint(100000, 999999):06d}"
monitor_db[f"pair-{code}"] = {"code": code, "monitorAppleUserID": "monitor_1",
                              "consumed": 0}
monitor_db["monitor_1"] = {"isPaired": False, "linkedPeer": None}
user_db["user_1"] = {"isPaired": False, "linkedPeer": None}

# User device: validateAndPair(code) -> cloud.fetchPairCodeRecord queries
# *the user's own* privateDB:
record = user_db.get(f"pair-{code}")
print(f"Monitor generated code {code}, saved to monitor's private DB")
print(f"User device queries its own private DB for the code -> {record}")
print(f"Pairing possible across two iCloud accounts: {record is not None}")

# Same model applies to: UserAccount fetch of the monitor, BypassGrant redemption,
# PartnerProgress ('myProgress'), tamper-alert CKQuerySubscription.
grant = {"code": "123456", "partnershipID": "a|b"}
monitor_db["grant-1"] = grant                      # granter saves to own private DB
print(f"BypassGrant redeem from user's DB -> {user_db.get('grant-1')}")

print()
print("=" * 72)
print("SIM 4 — Tamper 'time drift' false positive on device sleep / app suspend")
print("=" * 72)
# Swift: drift = |wallDelta - monotonicDelta|, threshold 120s.
# iOS ProcessInfo.systemUptime PAUSES during deep sleep; Task.sleep loop also
# suspends when app is backgrounded. Simulate phone asleep 10 min between checks.
last_wall, last_mono = 1000.0, 500.0
# ... 10 minutes pass; device asleep ~9.5 of them
now_wall = last_wall + 600.0
now_mono = last_mono + 30.0          # monotonic advanced only while awake
drift = abs((now_wall - last_wall) - (now_mono - last_mono))
print(f"wallDelta=600s monotonicDelta=30s -> drift={drift:.0f}s "
      f"(threshold 120s) -> TAMPER FLAGGED: {drift > 120}")
print("Result: policy denies with 'Security lockout: clock manipulation'.")

print()
print("=" * 72)
print("SIM 5 — Rego policy vs Swift native fallback parity fuzz")
print("=" * 72)
def rego_allow(i):
    if i["time_drift"]:
        return False
    if i["currency"] == "activeCalories" and i["cal"] >= i["cal_goal"]:
        return True
    if i["currency"] == "steps" and i["steps"] >= i["steps_goal"]:
        return True
    if i["override_active"] and i["now"] < i["override_exp"]:
        return True
    return False

def rego_grace(i):
    return (not i["time_drift"] and i["cal"] < i["cal_goal"]
            and i["staleness"] > 3600 and i["ui_timer_expired"])

def swift_fallback(i):
    if i["time_drift"]:
        return (False, False)
    if i["override_active"] and i["now"] < i["override_exp"]:
        return (True, False)
    if i["currency"] == "activeCalories":
        goal_met = i["cal"] >= i["cal_goal"]
    elif i["currency"] == "steps":
        goal_met = i["steps"] >= i["steps_goal"]
    else:
        goal_met = i["cal"] >= i["cal_goal"]
    if goal_met:
        return (True, False)
    grace = i["cal"] < i["cal_goal"] and i["staleness"] > 3600 and i["ui_timer_expired"]
    return (False, grace)

random.seed(7)
mismatches = []
for _ in range(200000):
    i = {"currency": random.choice(["activeCalories", "steps"]),
         "cal": random.uniform(0, 800), "cal_goal": random.uniform(50, 600),
         "steps": random.randint(0, 20000), "steps_goal": random.randint(1000, 15000),
         "override_active": random.random() < .3,
         "override_exp": random.uniform(0, 2000), "now": random.uniform(0, 2000),
         "staleness": random.uniform(0, 8000),
         "ui_timer_expired": random.random() < .5,
         "time_drift": random.random() < .1}
    r = (rego_allow(i), rego_grace(i) and not rego_allow(i))
    s = swift_fallback(i)
    s = (s[0], s[1] and not s[0])
    if r != s:
        mismatches.append((i, r, s))
print(f"Fuzz cases: 200000, semantic mismatches rego-vs-fallback: {len(mismatches)}")
if mismatches:
    i, r, s = mismatches[0]
    print("Example:", i, "rego:", r, "swift:", s)

# Parity caveat that fuzz can't see: rego grace can be TRUE while allow TRUE
# (steps met but cal not) -> requires_grace surfaced alongside allow. Check:
weird = {"currency": "steps", "cal": 10, "cal_goal": 300, "steps": 12000,
         "steps_goal": 8000, "override_active": False, "override_exp": 0,
         "now": 1, "staleness": 7200, "ui_timer_expired": True, "time_drift": False}
print(f"Steps user, goal met, cal stale: rego allow={rego_allow(weird)}, "
      f"rego requires_grace={rego_grace(weird)}  <- both true in WASM output")

print()
print("=" * 72)
print("SIM 6 — Release-build partner OTP flow (OTPRequestView)")
print("=" * 72)
# Swift: #if DEBUG valid = code.hasPrefix("1234") #else valid = false
DEBUG = False
def verify_release(code): return code.startswith("1234") if DEBUG else False
print(f"Any code in RELEASE build validates: {any(verify_release(f'{n:06d}') for n in range(0, 999999, 1111))}")
DEBUG = True
print(f"In DEBUG build, '123499' validates: {verify_release('123499')} "
      f"(any code starting 1234 works — 100 valid codes/attempt window)")

print()
print("=" * 72)
print("SIM 7 — PairingService edge cases")
print("=" * 72)
def normalize(raw):
    digits = "".join(c for c in raw if c.isdigit())
    return digits if len(digits) == 6 else None
print(f"normalize('12 34-56') = {normalize('12 34-56')}")
print(f"normalize('1234567') = {normalize('1234567')}")
# Code space: 900k codes, unauthenticated guessing? validateAndPair has no
# rate limit / attempt counter. 6-digit / 10-min TTL:
attempts_needed = 900000 / 2
print(f"No rate limiting on validateAndPair; median brute-force attempts: {attempts_needed:,.0f}")
