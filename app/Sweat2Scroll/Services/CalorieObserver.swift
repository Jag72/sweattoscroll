// CalorieObserver.swift — PRD §5D hook (posts when HealthKit signals new active energy samples)

import Foundation
import HealthKit

final class CalorieObserver {
    static let shared = CalorieObserver()
    static let goalMetNotification = Notification.Name("s2sCalorieGoalMet")

    private let store = HKHealthStore()
    private var query: HKObserverQuery?

    private init() {}

    /// Start observer; full “unlock when goal met” still enforced in `ActivityViewModel` + OPA.
    func startObserving() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let type = HKQuantityType(.activeEnergyBurned)
        query = HKObserverQuery(sampleType: type, predicate: nil) { _, _, error in
            if error != nil { return }
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.goalMetNotification, object: nil)
            }
        }
        if let query { store.execute(query) }
    }
}
