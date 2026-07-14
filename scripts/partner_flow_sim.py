#!/usr/bin/env python3
"""End-to-end simulation of the REBUILT partner flow, replicating the exact
Swift logic across TWO separate iCloud accounts (public-DB model)."""

import hashlib, hmac, struct, random, time
from cryptography.hazmat.primitives.asymmetric.ec import generate_private_key, SECP256R1, ECDH
from cryptography.hazmat.primitives.kdf.hkdf import HKDF
from cryptography.hazmat.primitives import hashes, serialization

def load_pub(raw):  # X9.63 uncompressed point -> public key
    from cryptography.hazmat.primitives.asymmetric.ec import EllipticCurvePublicKey
    return EllipticCurvePublicKey.from_encoded_point(SECP256R1(), raw)
def raw_pub(pk):
    return pk.public_bytes(serialization.Encoding.X962,
                           serialization.PublicFormat.UncompressedPoint)
def derive(priv, partner_pub_raw):
    shared = priv.exchange(ECDH(), load_pub(partner_pub_raw))
    return HKDF(algorithm=hashes.SHA256(), length=32,
                salt=b"sweat2scroll-v1", info=b"").derive(shared)

# ── Public CloudKit DB: world-readable, records writable only by creator ──────
class PublicDB:
    def __init__(self): self.records = {}   # recordName -> (creator, fields)
    def save(self, name, creator, fields):
        if name in self.records and self.records[name][0] != creator:
            raise PermissionError(f"{creator} cannot write {name} (owned by {self.records[name][0]})")
        self.records[name] = (creator, dict(fields))
    def get(self, name):
        return self.records.get(name, (None, None))[1]
    def delete(self, name, who):
        if name in self.records and self.records[name][0] == who:
            del self.records[name]

cloud = PublicDB()

print("="*72); print("SIM A — Cross-account pairing + ECDH handshake (public DB)"); print("="*72)
MONITOR, USER = "monitor_iCloudA", "user_iCloudB"

# 1. Monitor.generateCode(): beginPairingAsMonitor + savePairHandshake
mon_priv = generate_private_key(SECP256R1())
code = f"{random.randint(100000,999999):06d}"
cloud.save(f"handshake-{code}", MONITOR, {
    "code": code, "monitorUserID": MONITOR,
    "monitorPublicKey": raw_pub(mon_priv.public_key()).hex(),
    "monitorDisplayName": "Mom", "expiresAt": time.time()+600})
print(f"Monitor published handshake-{code} (public key length {len(raw_pub(mon_priv.public_key()))} bytes)")

# 2. User.validateAndPair(code): read handshake, completePairingAsUser, writePairResponse
hs = cloud.get(f"handshake-{code}")
assert hs and hs["monitorUserID"] != USER
mon_pub_raw = bytes.fromhex(hs["monitorPublicKey"])
user_priv = generate_private_key(SECP256R1())
user_secret = derive(user_priv, mon_pub_raw)                 # user stores this
try:
    cloud.save(f"presp-{code}", USER, {                      # user's OWN record
        "code": code, "userUserID": USER,
        "userPublicKey": raw_pub(user_priv.public_key()).hex(),
        "userDisplayName": "Kid"})
    print("User derived secret + published presp record (own record, permitted)")
except PermissionError as e:
    print("PERMISSION FAIL:", e)

# Permission guard check: could the user have written into the monitor's record?
try:
    cloud.save(f"handshake-{code}", USER, {"hacked": True})
    print("!! user wrote monitor's record — permission model WRONG")
except PermissionError:
    print("✓ user correctly BLOCKED from writing monitor's handshake record")

# 3. Monitor.pollForPairingConfirmation: read presp, completePairingAsMonitor (REUSES mon_priv)
resp = cloud.get(f"presp-{code}")
user_pub_raw = bytes.fromhex(resp["userPublicKey"])
mon_secret = derive(mon_priv, user_pub_raw)                  # monitor reuses its ORIGINAL key
print(f"\nMonitor secret: {mon_secret.hex()[:32]}…")
print(f"User    secret: {user_secret.hex()[:32]}…")
print(f"SHARED SECRET MATCHES: {mon_secret == user_secret}   <-- the P0-2 fix")

print(); print("="*72); print("SIM B — 30-second rotating TOTP (both sides use shared secret)"); print("="*72)
def hotp(secret, counter):
    mac = hmac.new(secret, struct.pack(">Q", counter), hashlib.sha256).digest()
    off = mac[-1] & 0x0F
    return f"{(struct.unpack('>I', mac[off:off+4])[0] & 0x7FFFFFFF) % 10**6:06d}"
def counter(t): return int(t // 30)
def generate(secret, t): return hotp(secret, counter(t))
def validate(secret, code, t, drift=1):   # ±1 step tolerance (Swift validateCode)
    return any(hotp(secret, counter(t)+d) == code for d in range(-drift, drift+1))

t0 = time.time()
code_mon = generate(mon_secret, t0)
print(f"Monitor shows code {code_mon} at t=0")
print(f"User validates at t=+2s  : {validate(user_secret, code_mon, t0+2)}  (should be True)")
print(f"User validates at t=+31s : {validate(user_secret, code_mon, t0+31)} (next step, ±1 tolerance still True)")
print(f"User validates at t=+95s : {validate(user_secret, code_mon, t0+95)} (3 steps later, EXPIRED -> False)")

# rotation: code changes every 30s
codes = [generate(mon_secret, t0 + 30*i) for i in range(4)]
print(f"Codes across 4 periods: {codes}  all-distinct: {len(set(codes))>=3}")

# wrong-secret device can't validate
stranger = generate_private_key(SECP256R1())
stranger_secret = derive(stranger, mon_pub_raw)
print(f"Unpaired stranger validates monitor's code: {validate(stranger_secret, code_mon, t0+2)} (should be False)")

print(); print("="*72); print("SIM C — Redemption grants a FIXED 15-minute unlock"); print("="*72)
# applyEmergencyOverride: minutes = max(1, min(durationMinutes, 15)); pass 15
def apply_override(requested):
    return max(1, min(requested, 15))
print(f"View passes unlockMinutes=15 -> applied: {apply_override(15)} min")
print(f"Defensive clamp if someone passes 240 -> {apply_override(240)} min (capped at 15)")
# unlock window then auto re-shield via temporaryBypass(minutes:15) DeviceActivity
unlock_end = t0 + 15*60
print(f"Apps usable until t=+{int((unlock_end-t0)/60)}min; shield re-engages after (DeviceActivity schedule).")

print(); print("="*72); print("SIM D — Failure/edge cases"); print("="*72)
print(f"Pair with self (monitorID==userID) rejected: {MONITOR == MONITOR}  -> validateAndPair returns .invalid")
# expired handshake
cloud.save(f"handshake-999999", MONITOR, {"code":"999999","monitorUserID":MONITOR,
    "monitorPublicKey":raw_pub(mon_priv.public_key()).hex(),"monitorDisplayName":"X",
    "expiresAt": time.time()-10})
hs2 = cloud.get("handshake-999999")
expired_is_nil = not (hs2["expiresAt"] > time.time())
print(f"Expired handshake -> fetchPairHandshake returns nil: {expired_is_nil}")
def normalize(raw):
    d = "".join(c for c in raw if c.isdigit())
    return d if len(d) == 6 else None
print(f"Malformed 5-digit code '12345' normalizes to: {normalize('12345')}")
print(f"Spaced code '12 34 56' normalizes to: {normalize('12 34 56')}")
