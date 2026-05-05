// Utilities/AppLogger.swift
// Unified os_log categories for production debugging and QA (Console / Instruments).

import Foundation
import os.log

enum AppLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "app.sweat2scroll"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let healthKit = Logger(subsystem: subsystem, category: "healthkit")
    static let screenTime = Logger(subsystem: subsystem, category: "screentime")
    static let cloudKit = Logger(subsystem: subsystem, category: "cloudkit")
    static let blocking = Logger(subsystem: subsystem, category: "blocking")
    static let deepLink = Logger(subsystem: subsystem, category: "deeplink")
}
