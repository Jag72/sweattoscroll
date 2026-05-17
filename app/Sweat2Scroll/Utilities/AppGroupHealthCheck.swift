// Utilities/AppGroupHealthCheck.swift
// One-shot diagnostic that confirms the App Group container is actually
// readable/writable from this process.
//
// Why this exists: iOS's `cfprefsd` daemon emits a warning at app launch when
// it probes the AnyUser scope of a non-system container before falling back to
// CurrentUser. The warning looks alarming —
//
//   Couldn't read values in CFPrefsPlistSource<...> (Domain:
//   group.com.sweat2scroll.appblocker, User: kCFPreferencesAnyUser, ByHost:
//   Yes, Container: (null), Contents Need Refresh: Yes): Using
//   kCFPreferencesAnyUser with a container is only allowed for System
//   Containers, detaching from cfprefsd
//
// — but is **typically benign** and does not mean the App Group is broken.
//
// The only way to know for sure is to write a value, read it back, and check
// equality. That's what this helper does. On first launch you should see a
// single `[AppGroup] OK` line in the console, after which the cfprefsd
// warning above can be safely ignored.
//
// If the read/write fails, the App Group capability is not actually being
// honored — almost always because the App ID at developer.apple.com does not
// have the App Group enabled, even though the entitlements file declares it.
// Re-check `app/BUILD_GUIDE.md` § App Groups and re-download the provisioning
// profile.

import Foundation

enum AppGroupHealthCheck {

    /// Suite identifier we share with the three Family Controls extensions.
    private static let appGroupID = "group.com.sweat2scroll.appblocker"

    /// Defaults key used only by this self-check. Namespaced so it cannot
    /// collide with real preference keys.
    private static let probeKey = "_appGroupHealthCheck.probe"

    /// Writes a UUID-tagged probe value to the App Group's `UserDefaults`,
    /// reads it back, and logs success or a loud failure.
    ///
    /// Cheap (≤ 1ms) and idempotent — safe to call from `Sweat2ScrollApp.init`.
    static func run() {
        guard let suite = UserDefaults(suiteName: appGroupID) else {
            AppLogger.app.error(
                "[AppGroup] FAIL: UserDefaults(suiteName:) returned nil. Suite: \(appGroupID, privacy: .public). Verify the App Group capability is added to the App ID at developer.apple.com and the provisioning profile is current."
            )
            return
        }

        let token = "probe-\(UUID().uuidString)"
        suite.set(token, forKey: probeKey)
        let readBack = suite.string(forKey: probeKey)

        if readBack == token {
            AppLogger.app.info(
                "[AppGroup] OK — \(appGroupID, privacy: .public) is read/write. Any cfprefsd 'kCFPreferencesAnyUser ... detaching' warning at launch is cosmetic."
            )
        } else {
            AppLogger.app.error(
                "[AppGroup] FAIL: probe write+read did not round-trip. Suite: \(appGroupID, privacy: .public). Wrote '\(token, privacy: .public)', read '\(readBack ?? "<nil>", privacy: .public)'. The App Group entitlement is declared but not honored — fix at developer.apple.com (see app/BUILD_GUIDE.md)."
            )
        }

        // Clean up the probe so a stale token can't accidentally be picked up
        // by other code that scans defaults keys.
        suite.removeObject(forKey: probeKey)
    }
}
