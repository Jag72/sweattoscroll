// Extensions/SwiftExtensions.swift
// Utility extensions used throughout the app.

import Foundation
import SwiftUI

// MARK: - Date Extensions
extension Date {
    /// Returns true if this date is today
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    /// Start of the current day (midnight)
    static var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    /// Formatted relative string (e.g., "2 minutes ago")
    var relativeFormatted: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

// MARK: - Double Extensions
extension Double {
    /// Formats a calorie value for display (e.g., 312 → "312 kcal")
    var kcalFormatted: String { "\(Int(self)) kcal" }

    /// Formats steps for display
    var stepsFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return (formatter.string(from: NSNumber(value: Int(self))) ?? "\(Int(self))") + " steps"
    }

    /// Clamps to a range
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

// MARK: - Legacy Color Aliases (remapped to sscrollBestUI palette)
extension Color {
    /// Legacy alias — now maps to electricOrange
    static let limeAccent = Color.electricOrange
    /// Legacy alias — now maps to paper background
    static let darkBg     = Color.paper
    /// Legacy alias — now maps to glass card fill
    static let cardBg     = Color.white.opacity(0.8)
}

// MARK: - View Extensions
extension View {
    /// Applies a glass card style background
    func cardStyle() -> some View {
        self
            .padding()
            .background(.thinMaterial)
            .cornerRadius(16)
            .padding(.horizontal)
    }

    /// Conditionally applies a modifier
    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition { transform(self) } else { self }
    }
}

// MARK: - UserDefaults Extension (App Group helpers)
extension UserDefaults {
    static let appGroup = UserDefaults(suiteName: "group.com.sweat2scroll.appblocker")

    func setCalorieProgress(_ calories: Double, goal: Double) {
        set(calories, forKey: "currentCalories")
        set(goal, forKey: "currentGoal")
    }

    func calorieProgress() -> (calories: Double, goal: Double) {
        (double(forKey: "currentCalories"), double(forKey: "currentGoal"))
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let shieldEngaged          = Notification.Name("sweat2scroll.shieldEngaged")
    static let shieldDisengaged       = Notification.Name("sweat2scroll.shieldDisengaged")
    static let syncTimerRequested     = Notification.Name("sweat2scroll.syncTimerRequested")
    static let tamperDetected         = Notification.Name("sweat2scroll.tamperDetected")
    static let breakGlassActivated    = Notification.Name("sweat2scroll.breakGlassActivated")
    static let partnerProgressUpdated = Notification.Name("sweat2scroll.partnerProgressUpdated")
}

// MARK: - Haptic Feedback Helper
struct HapticEngine {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func error()   { UINotificationFeedbackGenerator().notificationOccurred(.error) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
